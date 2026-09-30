"""World objects, knowledge and transfers. Plans never teleport inventory."""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass, field
from math import hypot
from heapq import heappop, heappush

from .actor import ActionType, ActorMode, Team
from .items import CargoItem, LOOT_KINDS
from .map import CellPlacement, Interactable, InteractableState
from .weapon import RIFLE, WeaponState

LOOT_BRIGHT = '#FFE45C'
LOOT_OPENED = '#927A2C'
SEARCH_SECONDS = 3.0
CORPSE_SECONDS = 2.0
TRANSFER_SECONDS = .6
CORPSE_SPEED = .6


@dataclass
class LootObject:
    id: str
    name: str
    kind: str
    cell: tuple[int, int]
    items: dict[str, CargoItem] = field(default_factory=dict)
    discovered: bool = False
    visible: bool = False
    opened: bool = False
    searched: bool = False
    known: dict[str, CargoItem] = field(default_factory=dict)
    seen_at: float = 0.0

    @property
    def color(self):
        return LOOT_BRIGHT if self.kind == 'ground' or not self.opened else LOOT_OPENED


@dataclass
class SearchResult:
    object_id: str
    actor_id: int | None
    task_id: int | None
    token: str
    completed_at: float


@dataclass
class PickupReservation:
    object_id: str
    item_id: str
    actor_id: int
    weight: float


class LootSystem:
    def __init__(self, world):
        self.world = world
        self.objects: dict[str, LootObject] = {}
        self.reservations: dict[str, PickupReservation] = {}
        self.searchers: dict[str, str] = {}
        self.results: dict[str, SearchResult] = {}
        self.notifications: list[str] = []
        self.counter = 0
        for actor in world.actors:
            actor.inventory.equipped_id = f'weapon:{actor.id}'

    def item(self, kind, quantity=1, *, ammo=30):
        self.counter += 1
        weapon = WeaponState(RIFLE, ammo, reserve_ammo=0) if kind == 'rifle' else None
        return CargoItem(f'item:{self.counter}', kind, quantity, weapon)

    def add(self, id_, name, kind, cell, items=(), *, discovered=False):
        obj = LootObject(id_, name, kind, cell, {i.id: i for i in items}, discovered=discovered)
        if kind == 'ground':
            obj.searched = True
        self.objects[id_] = obj
        self.world.grid.add_interactable(Interactable(id_, kind, CellPlacement(cell),
            InteractableState.OPEN if kind=='ground' else InteractableState.CLOSED,
            ('take',) if kind=='ground' else ('search', 'take')))
        if discovered and obj.searched:
            self.remember(obj)
        return obj

    def remember(self, obj):
        obj.known = deepcopy(obj.items)
        obj.seen_at = self.world.time

    def refresh(self):
        w = self.world
        for obj in list(self.objects.values()):
            center = w.grid.cell_center(obj.cell)
            points = [center]
            if obj.kind == 'container':
                from .geometry import Vec2
                points += [center + Vec2(dx*.501, dy*.501) for dx, dy in ((0,1),(1,0),(0,-1),(-1,0))]
            obj.visible = any(w.perception.point_visible(w, a, point)
                              for a in w.actors if a.alive and a.team == Team.RED for point in points)
            if obj.visible:
                obj.discovered = True
                if obj.searched:
                    self.remember(obj)

    def weight(self, actor):
        inv = actor.inventory
        primary = actor.weapon.definition.item.mass + .012*(actor.weapon.ammo+actor.weapon.reserve_ammo)
        supplies = sum(LOOT_KINDS[k][1]*q for k,q in inv.quantities.items() if k in LOOT_KINDS)
        return primary + supplies + sum(item.weight for item in inv.cargo.values())

    def reserved_weight(self, actor_id, excluding=()):
        return sum(r.weight for token,r in self.reservations.items() if r.actor_id==actor_id and token not in excluding)

    def interaction_cells(self, obj):
        grid = self.world.grid
        x,y = obj.cell
        cells = [obj.cell] if obj.kind != 'container' and grid.walkable(obj.cell) else []
        for dx,dy in ((0,-1),(1,0),(0,1),(-1,0)):
            cell = x+dx,y+dy
            edge = grid.edge_feature_between(cell,obj.cell)
            if grid.walkable(cell) and not (edge and edge.blocks_movement):
                cells.append(cell)
        return cells

    def approach(self, actor, obj, *, start=None):
        w = self.world
        occupied = {a.occupied_cell for a in w.actors if a.alive and a.id!=actor.id and a.occupied_cell is not None}
        reserved = {a.reserved_cell for a in w.actors if a.alive and a.id!=actor.id and a.reserved_cell is not None}
        choices = []
        for cell in self.interaction_cells(obj):
            if cell in occupied or cell in reserved:
                continue
            path = w.planner.path(actor,cell,start=start)
            if path:
                choices.append((w.grid.path_cost(path),cell[1],cell[0],cell))
        return min(choices)[-1] if choices else None

    def at_object(self, actor, obj):
        return actor.mode in {ActorMode.STANDING,ActorMode.ACTING} and actor.occupied_cell in self.interaction_cells(obj)

    def search_error(self, actor, object_id, *, start=None):
        obj = self.objects.get(object_id)
        if not actor.alive:
            return '执行者已阵亡'
        if obj is None or not obj.discovered:
            return '尚未发现此对象'
        if self.approach(actor,obj,start=start) is None:
            return '没有可达的交互位置（不能隔墙操作）'
        return None

    def open_result(self, obj, actor=None, node=None):
        if obj.id not in self.results:
            self.results[obj.id] = SearchResult(obj.id, actor.id if actor else None,
                                                node.task_id if node else None, node.token if node else '',self.world.time)
            self.results=dict(sorted(self.results.items(),key=lambda pair:(pair[1].completed_at,pair[0])))
        if obj.id not in self.notifications:
            self.notifications.append(obj.id)
            self.notifications.sort(key=lambda id_:(self.results[id_].completed_at,id_))
        self.world.pause_requested = True

    def release(self, token):
        self.reservations.pop(token,None)
        self.searchers = {id_:owner for id_,owner in self.searchers.items() if owner!=token}
        self.results = {id_:r for id_,r in self.results.items() if r.token!=token}
        self.notifications = [id_ for id_ in self.notifications if id_ in self.results]

    def take_error(self, actor, token, *, onsite=False):
        r = self.reservations.get(token)
        if not r or r.actor_id!=actor.id:
            return '拿取预约已失效'
        obj = self.objects.get(r.object_id)
        if not obj or r.item_id not in obj.items:
            return '来源物品已不存在'
        if not actor.alive:
            return '执行者已阵亡'
        if onsite and not self.at_object(actor,obj):
            return '必须到达物品的交互位置'
        if self.weight(actor) + obj.items[r.item_id].weight > actor.inventory.capacity + 1e-9:
            return '携带容量不足'
        return None

    def pickup_reservation(self, object_id, item_id):
        return next(((token,r) for token,r in self.reservations.items()
                     if r.object_id==object_id and r.item_id==item_id),(None,None))

    def pickup_task(self, object_id, item_id):
        token,_=self.pickup_reservation(object_id,item_id)
        if token:
            for task in self.world.planner.tasks.values():
                if any(n.token==token for n in [*task.jobs.values(),
                        *(n for nodes in task.pickups.values() for n in nodes)]):return task
        result=self.results.get(object_id)
        task=self.world.planner.tasks.get(result.task_id) if result else None
        return task if task and task.draft.method=='loot' else None

    def cancel_pickup(self, token):
        """Remove only this transfer, including a running macro job."""
        from .movement import clear_movement
        w,p=self.world,self.world.planner
        for actor in w.actors:
            index=next((i for i,n in enumerate(actor.queue) if n.token==token),None)
            if index is not None:p.delete_node(actor,index)
        for task in p.tasks.values():
            for actor_id,job in list(task.jobs.items()):
                if job.token!=token:continue
                task.jobs.pop(actor_id)
                actor=w.actor(actor_id)
                if actor.queue and actor.queue[0].task_id==task.id:
                    if actor.current_action and actor.current_action.owner_token==token:
                        actor.current_action=None
                        if actor.mode==ActorMode.ACTING:actor.mode=ActorMode.STANDING
                    clear_movement(actor);actor.blocked_reason='';p.stalls.pop(actor.id,None)
            for nodes in task.pickups.values():nodes[:]=[n for n in nodes if n.token!=token]
        self.release(token);w.completed.discard(token)

    def allocation_error(self, object_id, assignments):
        w=self.world;obj=self.objects.get(object_id)
        if not obj or not obj.discovered or not obj.searched:return '物品尚未搜索'
        weights={};counts={};outgoing=set()
        for item_id,actor_id in assignments.items():
            if actor_id is None:continue
            actor=w.actor(actor_id);item=obj.known.get(item_id)
            if not actor or not actor.alive or actor.team!=Team.RED:return '请选择存活的在场队员'
            if not item:return '物品记录不存在'
            if item_id not in obj.items:return '物品已离开来源，不能改派'
            token,old=self.pickup_reservation(object_id,item_id)
            if old and old.actor_id==actor_id:continue
            if token:outgoing.add(token)
            error=self.search_error(actor,object_id)
            if error:return f'{actor.name}：{error}'
            weights[actor_id]=weights.get(actor_id,0)+item.weight
            counts[actor_id]=counts.get(actor_id,0)+1
        for actor_id,extra in weights.items():
            actor=w.actor(actor_id)
            if self.weight(actor)+self.reserved_weight(actor_id,outgoing)+extra>actor.inventory.capacity+1e-9:
                excess=self.weight(actor)+self.reserved_weight(actor_id,outgoing)+extra-actor.inventory.capacity
                return f'{actor.name} 超出 {actor.inventory.capacity:g} kg 携带上限，缺少 {excess:.2f} kg 空间 · 先完成放下再安排拿取；整堆不能拆分'
            if counts[actor_id]>8:return f'{actor.name} 一次最多安排 8 次拿取'
            task_internal=all((task:=self.pickup_task(object_id,item_id)) and actor_id in task.draft.actors
                              for item_id,i in assignments.items() if i==actor_id)
            remaining=[n for n in actor.queue if n.token not in outgoing]
            if not task_internal and remaining and all(n.kind=='loot_take' and n.object_id==object_id and n.task_id is None for n in remaining):
                if len(remaining)+counts[actor_id]>8:return f'{actor.name} 最多安排 8 次拿取'
        return None

    def allocate(self, object_id, assignments, *, finish=True):
        from .orders import Node
        error=self.allocation_error(object_id,assignments)
        if error:return error
        w,p=self.world,self.world.planner;obj=self.objects[object_id]
        source_result=self.results.get(object_id)
        changes={}
        for item_id,actor_id in assignments.items():
            if actor_id is None:continue
            token,old=self.pickup_reservation(object_id,item_id)
            if old and old.actor_id==actor_id:continue
            task=self.pickup_task(object_id,item_id)
            changes[item_id]=(actor_id,token,task if task and actor_id in task.draft.actors else None)
        external=sorted({i for i,_,task in changes.values() if task is None})
        replacing=[i for i in external if not w.actor(i).queue or
                   not all(n.kind=='loot_take' and n.object_id==object_id and n.task_id is None for n in w.actor(i).queue)]
        # All validation precedes any cancellation or reservation mutation.
        for _,token,_ in changes.values():
            if token:self.cancel_pickup(token)
        p.cancel_related(replacing)
        for i in replacing:p.cancel_actor(w.actor(i))
        for item_id,(actor_id,_,task) in changes.items():
            token=f'node:{p.next_id}';p.next_id+=1
            task_id=task.id if task and task.id in p.tasks else None
            node=Node(token,'loot_take',object_id=object_id,cargo_id=item_id,task_id=task_id)
            self.reservations[token]=PickupReservation(object_id,item_id,actor_id,obj.known[item_id].weight)
            if task_id is not None:task.pickups.setdefault(actor_id,[]).append(node)
            else:w.actor(actor_id).queue.append(node)
        if finish:self.results.pop(object_id,None)
        elif source_result is not None:
            # Replacing the searching actor's micro queue releases its old token.
            # The open source decision still belongs to the player until closed.
            self.results[object_id]=source_result
            self.results=dict(sorted(self.results.items(),key=lambda pair:(pair[1].completed_at,pair[0])))
        self.notifications=[id_ for id_ in self.notifications if id_!=object_id]
        if changes:w.message(f'{obj.name}：已安排／改派 {len(changes)} 件 · 到场后拿取')
        return None

    def action_error(self, actor, kind, token, object_id=None, cargo_id=None):
        obj = self.objects.get(object_id)
        if kind == ActionType.SEARCH_LOOT:
            if not obj or not self.at_object(actor,obj):
                return '必须到达搜索对象旁'
            if self.searchers.get(object_id) not in {None,token}:
                return '另一名队员正在搜索此对象'
        elif kind == ActionType.TRANSFER_ITEM:
            return self.take_error(actor,token,onsite=True)
        elif kind in {ActionType.DROP_ITEM,ActionType.EQUIP_ITEM}:
            if cargo_id not in self.carried(actor):
                return '物品已不在此人身上'
            if kind==ActionType.EQUIP_ITEM and not (cargo_id in actor.inventory.cargo and actor.inventory.cargo[cargo_id].weapon):
                return '只能装备携带中的武器'
        return None

    def complete_action(self, actor, action):
        error = self.action_error(actor,action.type,action.owner_token,action.object_id,action.cargo_id)
        if error:
            return error
        obj = self.objects.get(action.object_id)
        if action.type == ActionType.SEARCH_LOOT:
            obj.searched = True
            self.remember(obj)
            self.searchers.pop(obj.id,None)
        elif action.type == ActionType.TRANSFER_ITEM:
            item = obj.items.pop(action.cargo_id)
            if item.kind in {'flashbang','bandage'}:
                actor.inventory.quantities[item.kind] = actor.inventory.quantities.get(item.kind,0)+item.quantity
            elif item.kind == 'rifle_ammo':
                actor.weapon.reserve_ammo += item.quantity
            else:
                actor.inventory.cargo[item.id] = item
            self.reservations.pop(action.owner_token,None)
            self.remember(obj)
            self.world.message(f'{actor.name} 已拿取 {item.name} ×{item.quantity}')
            if obj.kind=='ground' and not obj.items:
                self.objects.pop(obj.id,None)
                self.world.grid.interactables.pop(obj.id,None)
        elif action.type == ActionType.DROP_ITEM:
            item = self.remove_carried(actor,action.cargo_id)
            cell = actor.occupied_cell
            pile = next((o for o in self.objects.values() if o.kind=='ground' and o.cell==cell),None)
            if pile is None:
                self.counter += 1
                pile = self.add(f'ground:{self.counter}','地面物品','ground',cell,discovered=True)
            pile.items[item.id] = item
            self.remember(pile)
            self.world.message(f'{actor.name} 已放下 {item.name}')
        elif action.type == ActionType.EQUIP_ITEM:
            item = actor.inventory.cargo.pop(action.cargo_id)
            old = CargoItem(actor.inventory.equipped_id,'rifle',weapon=actor.weapon)
            # Reserve ammo belongs to the soldier, not to the swapped magazine.
            reserve = old.weapon.reserve_ammo
            old.weapon.reserve_ammo = 0
            actor.weapon = item.weapon
            actor.weapon.reserve_ammo += reserve
            actor.inventory.equipped_id = item.id
            actor.inventory.cargo[old.id] = old
            self.world.message(f'{actor.name} 已装备 {item.name}')
        return None

    def carried(self, actor):
        items = dict(actor.inventory.cargo)
        for kind in ('flashbang','bandage'):
            count = actor.inventory.available(kind)
            if count>0:
                items[f'supply:{kind}'] = CargoItem(f'supply:{kind}',kind,count)
        if actor.weapon.reserve_ammo:
            items['supply:rifle_ammo'] = CargoItem('supply:rifle_ammo','rifle_ammo',actor.weapon.reserve_ammo)
        return items

    def remove_carried(self, actor, item_id):
        if item_id in actor.inventory.cargo:
            return actor.inventory.cargo.pop(item_id)
        kind = item_id.split(':',1)[1]
        if kind=='rifle_ammo':
            count = actor.weapon.reserve_ammo; actor.weapon.reserve_ammo = 0
        else:
            count = actor.inventory.available(kind)
            actor.inventory.quantities[kind] -= count
        return self.item(kind,count)

    def tick_node(self, actor, node, dt):
        w,p = self.world,self.world.planner
        obj = self.objects.get(node.object_id)
        if node.kind=='loot_search' and node.status=='allocation':
            return node.object_id not in self.results
        if node.token in w.completed:
            w.completed.discard(node.token)
            if node.kind=='loot_search' and obj:
                node.status='allocation'
                self.open_result(obj,actor,node)
                return False
            return True
        if node.started or actor.current_action or actor.stunned>0:
            return False
        if node.kind in {'loot_drop','loot_equip'}:
            if actor.mode!=ActorMode.STANDING:
                return False
            kind = ActionType.DROP_ITEM if node.kind=='loot_drop' else ActionType.EQUIP_ITEM
        else:
            if not obj:
                actor.blocked_reason='目标物品已不存在'; return False
            if node.kind=='loot_search' and obj.searched:
                node.status='allocation'; self.open_result(obj,actor,node); return False
            if node.kind=='loot_search' and self.searchers.get(obj.id) not in {None,node.token}:
                node.reason='等待另一名搜索者'; return False
            target = actor.occupied_cell if self.at_object(actor,obj) else self.approach(actor,obj)
            if target is None:
                actor.blocked_reason='没有可达且空闲的交互位置'; return False
            node.cell=target
            if not p.drive(actor,target,dt):
                return False
            kind = ActionType.SEARCH_LOOT if node.kind=='loot_search' else ActionType.TRANSFER_ITEM
        duration = (CORPSE_SECONDS if obj and obj.kind=='corpse' else SEARCH_SECONDS) if kind==ActionType.SEARCH_LOOT else TRANSFER_SECONDS
        error = w.start_action(actor,kind,duration,node.token,object_id=node.object_id,cargo_id=node.cargo_id)
        if error:
            actor.blocked_reason=error
        else:
            node.started=True
            if kind==ActionType.SEARCH_LOOT:
                obj.opened=True; self.searchers[obj.id]=node.token
                w.grid.interactables[obj.id].state=InteractableState.OPEN
        return False

    def tick_task(self, task, dt):
        w,p = self.world,self.world.planner
        actors = [w.actor(i) for i in task.draft.actors]
        if task.phase=='blocked' or not all(a.queue and a.queue[0].task_id==task.id for a in actors):
            return
        if any(a.blocked_reason for a in actors):
            p.suspend_task(task,next(a.blocked_reason for a in actors if a.blocked_reason)); return
        task.phase='loot'
        claimed = {job.object_id for other in p.tasks.values() for job in other.jobs.values()}
        from .orders import Node
        for actor in actors:
            job = task.jobs.get(actor.id)
            if job:
                if job.status=='blocked':
                    continue
                if self.tick_node(actor,job,dt):
                    self.release(job.token);task.jobs.pop(actor.id,None)
                continue
            pickups = task.pickups.get(actor.id,[])
            if pickups:
                task.jobs[actor.id]=pickups.pop(0);continue
            if actor.id in task.guards:
                continue
            choices=[]
            for obj in self.objects.values():
                if not obj.discovered or obj.id in task.seen_loot or obj.id in claimed or w.grid.zone_id(obj.cell)!=task.draft.room:
                    continue
                if obj.searched and not obj.known:continue
                cell=self.approach(actor,obj)
                if cell is not None:
                    choices.append((w.grid.path_cost(p.path(actor,cell)),obj.id))
            if choices:
                objid=min(choices)[1];token=f'node:{p.next_id}';p.next_id+=1
                task.jobs[actor.id]=Node(token,'loot_search',object_id=objid,task_id=task.id)
                task.seen_loot.add(objid)
                claimed.add(objid)
                continue
            points=task.searches.get(actor.id,[])
            if points:
                if p.drive(actor,points[0],dt,angle=p.room_angle(task.draft.room,points[0]),zone=task.draft.room):
                    task.observations[actor.id]=task.observations.get(actor.id,0)+dt
                    if task.observations[actor.id]>=.4:
                        points.pop(0);task.observations[actor.id]=0
        waiting = any(job.status=='allocation' for job in task.jobs.values())
        if waiting:
            task.phase='allocation'
        if not task.jobs and not any(task.pickups.values()) and not any(task.searches.values()):
            task.loot_idle+=dt
            if task.loot_idle>=.5:p.finish_task(task)
        else:task.loot_idle=0

    def corpse(self, actor):
        id_=f'corpse:{actor.id}'
        if id_ in self.objects:
            return
        w,grid=self.world,self.world.grid
        anchor=actor.death_anchor or grid.cell_of(actor.position)
        if not grid.walkable(anchor):
            anchor=min((c for c in grid.zone_cells if grid.walkable(c)),key=lambda c:(hypot(c[0]+.5-actor.position.x,c[1]+.5-actor.position.y),c[1],c[0]))
        occupied={o.cell for o in self.objects.values() if o.kind=='corpse'}
        # Placement uses geometric distance, independent of movement slowdown.
        frontier=[(0,anchor[1],anchor[0])];distances={anchor:0};choices=[]
        while frontier:
            cost,y,x=heappop(frontier);current=x,y
            if cost>distances[current]+1e-9:continue
            if current not in occupied:choices.append((cost,y,x,current))
            for nxt in grid.neighbors(current):
                distance=cost+hypot(nxt[0]-x,nxt[1]-y)
                if distance<=2+1e-9 and distance<distances.get(nxt,float('inf'))-1e-9:
                    distances[nxt]=distance;heappush(frontier,(distance,nxt[1],nxt[0]))
        cell=min(choices)[-1] if choices else anchor
        items=list(actor.inventory.cargo.values());actor.inventory.cargo.clear()
        gun=actor.weapon
        reserve=gun.reserve_ammo;gun.reserve_ammo=0
        items.append(CargoItem(actor.inventory.equipped_id,'rifle',weapon=gun))
        actor.inventory.equipped_id=''
        if reserve:items.append(self.item('rifle_ammo',reserve))
        for kind,count in actor.inventory.quantities.items():
            if count:items.append(self.item(kind,count))
        actor.inventory.quantities.clear();actor.inventory.reservations.clear()
        actor.weapon=WeaponState(RIFLE,0,reserve_ammo=0)
        actor.position=grid.cell_center(cell)
        self.add(id_,f'{actor.name}的尸体','corpse',cell,items,discovered=actor.team==Team.RED)
        grid.terrain_speed[cell]=CORPSE_SPEED;grid.revision+=1;grid._path_cache.clear()
