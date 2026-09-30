"""Player plans and deterministic room tasks. Only World executes physical actions."""
from __future__ import annotations

from dataclasses import dataclass, field
from math import atan2, hypot
from typing import TYPE_CHECKING

from .actor import ActionType, Actor, ActorMode, FireMode, Team
from .commands import ActorCommand, CommandType
from .geometry import Vec2, angle_difference
from .items import ITEMS, use_for
from .mission import RECTS
from .movement import clear_movement

if TYPE_CHECKING:
    from .world import World

LABELS = {"move":"移动", "guard":"定点警戒", "face":"调整朝向", "attack":"指定攻击",
          "reload":"换弹", "bandage":"自行包扎", "throw":"投掷", "wait":"等待信号", "task":"房间行动", "move_face":"定向移动",
          "loot_search":"搜索物品", "loot_take":"到场拿取", "loot_drop":"放下物品", "loot_equip":"装备武器"}
STAGES = {"queued":"排队", "stack":"门外集结", "wait":"等待信号", "door":"操作门",
          "throw":"使用物品", "blast":"等待起爆", "enter":"依次进入", "search":"检查威胁",
          "blocked":"已挂起", "done":"完成", "cancelled":"已取消", "loot":"搜索物资", "allocation":"等待物资分配"}


@dataclass
class Node:
    token: str
    kind: str
    cell: tuple[int,int] | None = None
    angle: float | None = None
    target_id: int | None = None
    item: str | None = None
    sync: str | None = None
    task_id: int | None = None
    status: str = "queued"
    reason: str = ""
    elapsed: float = 0.0
    started: bool = False
    object_id: str | None = None
    cargo_id: str | None = None


@dataclass
class TaskDraft:
    actors: list[int]
    door: str | None
    room: str
    method: str
    outside: tuple[int,int]
    inside: tuple[int,int]
    stacks: dict[int,tuple[int,int]]
    entries: dict[int,tuple[int,int]]
    angle: float
    item: str | None = None
    thrower: int | None = None
    landing: tuple[int,int] | None = None
    sync: str | None = None
    opening: str = "open"
    after_entry: str = "search"
    stack_overrides: dict[int,tuple[int,int]] = field(default_factory=dict)
    entry_overrides: dict[int,tuple[int,int]] = field(default_factory=dict)
    stack_angles: dict[int,float] = field(default_factory=dict)
    entry_angles: dict[int,float] = field(default_factory=dict)


@dataclass
class SquadTask:
    id: int
    draft: TaskDraft
    phase: str = "queued"
    resume_phase: str = "stack"
    reason: str = ""
    ready: bool = False
    released: bool = False
    enter_index: int = 0
    entered: set[int] = field(default_factory=set)
    released_at: float = -100.0
    searches: dict[int,list[tuple[int,int]]] = field(default_factory=dict)
    observations: dict[int,float] = field(default_factory=dict)
    finals: dict[int,tuple[int,int]] = field(default_factory=dict)
    action_started: bool = False
    flash_released: bool = False
    blast_at: float = 0.0
    jobs: dict[int, Node] = field(default_factory=dict)
    pickups: dict[int, list[Node]] = field(default_factory=dict)
    guards: set[int] = field(default_factory=set)
    seen_loot: set[str] = field(default_factory=set)
    loot_idle: float = 0.0

    @property
    def token(self):
        return f"task:{self.id}"


class Planner:
    def __init__(self, world: World):
        self.world = world
        self.tasks: dict[int,SquadTask] = {}
        self.next_id = 1
        self.release_requests: set[str] = set()
        self.stalls: dict[int,tuple[Vec2,float,bool]] = {}

    def actor(self, id_: int) -> Actor:
        return self.world.actor(id_)

    def position_cell(self, actor: Actor):
        return actor.move_to or actor.occupied_cell or self.world.grid.cell_of(actor.position)

    def origin(self, actor: Actor, append=False):
        cell = self.position_cell(actor)
        if append:
            for node in actor.queue:
                if node.cell is not None and node.kind in {"move","guard","move_face"}:
                    cell = node.cell
                if node.task_id in self.tasks:
                    cell = self.tasks[node.task_id].draft.entries.get(actor.id, cell)
        return cell

    def path(self, actor: Actor, goal, *, start=None, zone=None, exclude=None, known=True):
        grid = self.world.grid
        allowed = None
        if zone:
            allowed = set(grid.zones[zone].cells)
        elif exclude:
            allowed = set(grid.zone_cells) - set(grid.zones[exclude].cells)
        start = start or self.position_cell(actor)
        if allowed is not None and start not in allowed:
            return []
        return grid.find_path(start, goal, allowed_cells=allowed,
                              known_doors=self.world.perception.doors if known and actor.team == Team.RED else None)

    def _releasing(self, actor: Actor):
        tokens = {node.token for node in actor.queue}
        tokens.update(self.tasks[n.task_id].token for n in actor.queue if n.task_id in self.tasks)
        return tokens

    def available(self, actor: Actor, item: str, append: bool):
        return actor.inventory.available(item, set() if append else self._releasing(actor))

    def item_error(self, actor: Actor, item: str, kind: str, append=False, cell=None):
        append=self.micro_append(actor,append)
        if not actor.alive:
            return "执行者死亡"
        if item not in ITEMS:
            return "未知物品"
        if kind == "reload":
            if actor.weapon.ammo >= actor.weapon.definition.magazine_size:
                return "弹匣已满"
            return "储备弹药耗尽" if actor.weapon.reserve_ammo <= 0 else None
        if self.available(actor,item,append) < 1:
            return "物品不足（可能已预约）"
        if kind == "bandage" and not self.world.treatment_part(actor):
            return "没有可治疗伤口"
        if kind == "throw" and cell is not None:
            return self.throw_error(actor,item,cell,self.origin(actor,append))
        return None

    def throw_error(self, actor, item, cell, origin=None, room=None, opening_door=None):
        grid=self.world.grid
        if not grid.walkable(cell):
            return "落点被家具或墙占用"
        if room is None and actor.team == Team.RED and cell not in self.world.perception.explored:
            return "区域未探索"
        if room is not None and grid.zone_id(cell) != room:
            return "落点必须在目标房间"
        use=use_for(item)
        start=grid.cell_center(origin) if origin is not None else actor.position
        end=grid.cell_center(cell)
        if start.distance_to(end) > use.range + 1e-6:
            return f"超出 {use.range:g} 格"
        for _,feature in grid.ray_features(start,end):
            if feature.interactive_id == opening_door:
                continue
            if feature.blocks_projectile and feature.height >= 2:
                return "被墙阻挡"
        return None

    def submit(self, ids, kind, *, cell=None, angle=None, target_id=None, item=None, sync=None, append=False, object_id=None, cargo_id=None):
        actors=[self.actor(i) for i in dict.fromkeys(ids)]
        if not actors or any(a is None or not a.alive for a in actors):
            return "先选择存活队员"
        appends={a.id:self.micro_append(a,append) for a in actors}
        if kind in {'loot_search','loot_drop','loot_equip'}:
            if len(actors)!=1:return '请选择一名执行者'
            a=actors[0]
            if kind=='loot_search':
                error=self.world.loot.search_error(a,object_id,start=self.origin(a,appends[a.id]))
            else:
                from .actor import ActionType
                error=self.world.loot.action_error(a,ActionType.DROP_ITEM if kind=='loot_drop' else ActionType.EQUIP_ITEM,'',cargo_id=cargo_id)
            if error:return error
        if any(appends[a.id] and len(a.queue)>=8 for a in actors):
            return "队列已满（最多 8 项）"
        if kind == "wait" and sync not in {"A","B"}:
            return "请选择同步 A 或 B"
        if sync and any(self.has_sync(a, appends[a.id]) for a in actors):
            return "该队员已有同步等待"
        assigned={}
        if kind in {"move","guard","move_face"}:
            assigned,error=self.movement_targets(ids,cell,append)
            if error:return error
        for actor in actors:
            if kind in {"reload","bandage","throw"}:
                error=self.item_error(actor,item or {"reload":"rifle","bandage":"bandage","throw":"flashbang"}[kind],kind,appends[actor.id],cell)
                if error:return error
            if kind=="attack" and target_id not in self.world.perception.player_visible:
                return "目标已失去视野"
        self.cancel_related([a.id for a in actors])
        for actor in actors:
            if not appends[actor.id]:self.cancel_actor(actor)
            elif actor.queue and actor.queue[-1].kind=="guard":actor.queue[-1].kind="move_face"
            token=f"node:{self.next_id}"
            self.next_id+=1
            chosen_item=item or {"reload":"rifle","bandage":"bandage","throw":"flashbang"}.get(kind)
            node=Node(token,kind,assigned.get(actor.id,cell),angle,target_id,chosen_item,sync,object_id=object_id,cargo_id=cargo_id)
            if chosen_item and kind!="reload":actor.inventory.reserve(token,chosen_item)
            actor.queue.append(node)
            actor.blocked_reason=""
        self.world.message(f"{' '.join(str(a.id) for a in actors)}：{LABELS.get(kind,kind)}"+(f" · {sync}" if sync else ""))
        return None

    def movement_targets(self,ids,cell,append=False):
        """One allocation rule for both the cursor preview and the submitted plan."""
        grid=self.world.grid
        actors=[self.actor(i) for i in dict.fromkeys(ids)]
        if not actors or any(a is None or not a.alive for a in actors):return {},'先选择存活队员'
        if cell is None or not grid.walkable(cell):return {},'目标不可通行'
        occupied={a.occupied_cell for a in self.world.actors if a.alive and a.id not in ids}
        assigned={}
        for actor in sorted(actors,key=lambda a:a.id):
            candidates=[cell] if len(actors)==1 else [c for c in grid.zone_cells
                if grid.zone_id(c)==grid.zone_id(cell) and hypot(c[0]-cell[0],c[1]-cell[1])<=2 and grid.walkable(c)]
            origin=self.origin(actor,self.micro_append(actor,append))
            paths=[(c,self.path(actor,c,start=origin)) for c in candidates if c not in occupied]
            paths=[(c,p) for c,p in paths if p]
            paths.sort(key=lambda cp: ((cp[0][0]-cell[0])**2+(cp[0][1]-cell[1])**2,grid.path_cost(cp[1]),cp[0][1],cp[0][0]))
            if not paths:return {},'路径被占位或关闭的门阻断'
            assigned[actor.id]=paths[0][0];occupied.add(paths[0][0])
        return assigned,None

    def has_sync(self,actor,append):
        return append and any(n.sync or n.task_id in self.tasks and self.tasks[n.task_id].draft.sync for n in actor.queue)

    def slots(self, outside, inside, room):
        grid=self.world.grid
        nx,ny=inside[0]-outside[0],inside[1]-outside[1]
        tx,ty=-ny,nx
        def offset(base,dn,dt):return base[0]+dn*nx+dt*tx,base[1]+dn*ny+dt*ty
        def fill(candidates,base,zone,radius,count):
            result=[]
            allowed=set(grid.zones[zone].cells)
            pool=sorted((c for c in allowed if grid.walkable(c)),key=lambda c:((c[0]-base[0])**2+(c[1]-base[1])**2,c[1],c[0]))
            for candidate in candidates:
                options=[candidate]+sorted((c for c in pool if hypot(c[0]-candidate[0],c[1]-candidate[1])<=radius),
                                           key=lambda c:((c[0]-candidate[0])**2+(c[1]-candidate[1])**2,c[1],c[0]))
                found=next((c for c in options if c not in result and c in allowed and grid.walkable(c)
                            and grid.find_path(base,c,allowed_cells=allowed)),None)
                if found is not None:result.append(found)
            for c in pool:
                if len(result)>=count:break
                if c not in result and hypot(c[0]-base[0],c[1]-base[1])<=3:result.append(c)
            return result[:count]
        stacks=fill([offset(outside,n,t) for n,t in [(0,0),(0,1),(0,-1),(-1,0),(-1,1),(-1,-1)]],
                    outside,grid.zone_id(outside),0,4)
        entries=fill([offset(inside,n,t) for n,t in [(1,1),(1,-1),(2,1),(2,-1)]],inside,room,2,4)
        return stacks,entries,atan2(ny,nx)

    def preview_task(self,ids,door,room,method,*,item=None,thrower=None,landing=None,sync=None,opening=None,append=False,
                     after_entry='search',stack_overrides=None,entry_overrides=None,stack_angles=None,entry_angles=None):
        world=self.world
        actors=[self.actor(i) for i in dict.fromkeys(ids)]
        if not actors or any(a is None or not a.alive for a in actors):return None,"先选择存活队员"
        room_action=method in {"direct","breach","flash"}
        if room_action and len(actors)<2:return None,"需要至少两名队员"
        if room_action and room not in world.mission.rooms:return None,"目标不是房间"
        entrance=world.mission.entrances[door]
        outside,inside=entrance.side(room)
        stacks,entries,angle=self.slots(outside,inside,room)
        if len(stacks)<len(actors) or len(entries)<len(actors):return None,"入口没有足够槽位"
        if method in {"open","kick"}:
            reachable=[(world.grid.path_cost(p),a.id,a) for a in actors if (p:=self.path(a,outside,start=self.origin(a,append)))]
            if not reachable:return None,"无可达交互格"
            actors=[min(reachable,key=lambda value:value[:2])[2]]
            stacks=[outside]
        for a,c in zip(actors,stacks):
            if not self.path(a,c,start=self.origin(a,append),exclude=room if room_action else None):return None,"无可达集结侧，请切换入口方向"
        known=world.perception.doors.get(door,"unknown")
        if known=="locked" and method in {"open","direct"}:return None,"门已锁，请选破门方式"
        if known in {"open","broken"} and method in {"open","kick","breach"}:return None,"门已打开，请选直接突入"
        if append and any(len(a.queue)>=8 for a in actors):return None,"队列已满"
        if sync and any(self.has_sync(a,append) for a in actors):return None,"该队员已有同步等待"
        opening=opening or ("kick" if method in {"kick","breach"} or known=="locked" else "open")
        if method=="flash":
            item=item or "flashbang"
            candidates=[a for a in actors if self.available(a,item,append)>0]
            if not candidates:return None,"没有可用道具"
            thrower=thrower or candidates[0].id
            if thrower not in [a.id for a in candidates]:return None,"指定执行者没有可用道具"
        else:item=thrower=landing=None
        draft=TaskDraft([a.id for a in actors],door,room,method,outside,inside,
                        dict(zip([a.id for a in actors],stacks)),dict(zip([a.id for a in actors],entries)),
                        angle,item,thrower,landing,sync,opening)
        if after_entry not in {'hold','search'}:return None,'无效的突入后行动'
        draft.after_entry=after_entry
        draft.stack_overrides=dict(stack_overrides or {});draft.entry_overrides=dict(entry_overrides or {})
        draft.stack_angles=dict(stack_angles or {});draft.entry_angles=dict(entry_angles or {})
        for mapping in (draft.stack_overrides,draft.entry_overrides,draft.stack_angles,draft.entry_angles):
            if any(i not in draft.actors for i in mapping):return None,'站位或朝向包含未参与的队员'
        for overrides,slots,zone,is_entry in ((draft.stack_overrides,draft.stacks,world.grid.zone_id(outside),False),
                                               (draft.entry_overrides,draft.entries,room,True)):
            slots.update(overrides)
            if len(set(slots.values()))!=len(slots):return None,'同一阶段的队员站位不能重叠'
            for i,cell in overrides.items():
                if not world.grid.walkable(cell) or world.grid.zone_id(cell)!=zone:return None,'站位必须在对应房间的可行走格'
                if is_entry:
                    if cell==inside:return None,'进门后站位不能占住入口通道'
                    if not self.path(self.actor(i),cell,start=inside,zone=room):return None,'入口无法到达指定就位点'
                elif not self.path(self.actor(i),cell,start=self.origin(self.actor(i),append),exclude=room):return None,'无法到达指定集结点'
        from math import isfinite
        if any(not isfinite(a) for mapping in (draft.stack_angles,draft.entry_angles) for a in mapping.values()):return None,'无效朝向'
        if item and landing is not None:
            error=self.throw_error(self.actor(thrower),item,landing,draft.stacks[thrower],room,door)
            if error:return draft,error
        return draft,None

    def choose_entrance(self,ids,door=None,room=None,method="direct",append=False,item=None):
        choices=[];errors=[]
        for e in self.world.mission.entrances.values():
            if door and e.id!=door:continue
            for target in (e.zone_a,e.zone_b):
                if room and target!=room:continue
                draft,error=self.preview_task(ids,e.id,target,method,append=append,item=item)
                if error:errors.append(error)
                if draft is not None and not error:
                    cost=sum(self.world.grid.path_cost(self.path(self.actor(i),c,start=self.origin(self.actor(i),append))) for i,c in draft.stacks.items())
                    choices.append((cost,e.id,target,draft))
        self.entrance_error='；'.join(dict.fromkeys(errors)) or '没有通向该区域的入口'
        return min(choices,key=lambda v:v[:3])[3] if choices else None

    def submit_task(self,draft:TaskDraft,append=False):
        fresh,error=self.preview_task(draft.actors,draft.door,draft.room,draft.method,item=draft.item,thrower=draft.thrower,
                                     landing=draft.landing,sync=draft.sync,opening=draft.opening,append=append,
                                     after_entry=draft.after_entry,stack_overrides=draft.stack_overrides,entry_overrides=draft.entry_overrides,
                                     stack_angles=draft.stack_angles,entry_angles=draft.entry_angles)
        if error:return error
        if fresh.item and fresh.landing is None:return "请设置道具落点"
        id_=self.next_id
        self.next_id+=1
        if not append:self.cancel_related(fresh.actors)
        for i in fresh.actors:
            actor=self.actor(i)
            if not append:self.cancel_actor(actor)
            elif actor.queue and actor.queue[-1].kind=="guard":actor.queue[-1].kind="move_face"
        task=SquadTask(id_,fresh)
        self.tasks[id_]=task
        if fresh.item:self.actor(fresh.thrower).inventory.reserve(task.token,fresh.item)
        for i in fresh.actors:
            self.actor(i).queue.append(Node(task.token,"task",task_id=id_))
            self.actor(i).blocked_reason=""
        self.world.message(f"{' '.join(map(str,fresh.actors))}：{self.task_label(task)}")
        return None

    def task_label(self,task):
        d=task.draft
        if d.method=='loot':return f'搜索物资 · {self.world.grid.zones[d.room].label}'
        label={"direct":"直接突入","breach":"破门突入","flash":f"使用{ITEMS[d.item].name if d.item else '物品'}突入",
               "stack":"门外集结","guarddoor":"守住门口","open":"开门","kick":"踹开"}[d.method]
        if d.method in {'direct','breach','flash'}:label+='并就位' if d.after_entry=='hold' else '并检查威胁'
        return f"{label} · {self.world.grid.zones[d.room].label}"

    def related_tasks(self,ids):
        return sorted({n.task_id for i in ids for n in self.actor(i).queue if n.task_id in self.tasks})

    def micro_append(self,actor,append):
        return append and not any(n.task_id in self.tasks for n in actor.queue)

    def micro_controls_motion(self,actor):
        if not actor.alive or actor.team!=Team.RED or not actor.queue or actor.blocked_reason:return False
        node=actor.queue[0]
        if node.task_id is not None or node.status=="blocked":return False
        return node.kind in {"move","move_face","face"} or node.kind=="guard" and not node.started or (
            node.kind in {'loot_search','loot_take'} and not node.started and node.status!='allocation')

    def takeover_text(self,ids):
        tasks=[self.tasks[i] for i in self.related_tasks(ids)]
        if not tasks:return ""
        members=sorted({i for t in tasks for i in t.draft.actors})
        return "将取消 "+" / ".join(self.task_label(t) for t in tasks)+" · 影响 "+"/".join(map(str,members))+" 号"

    def cancel_related(self,ids):
        for id_ in self.related_tasks(ids):self.cancel_task(id_)

    def suspend_task(self,task,reason):
        if task.phase!="blocked":task.resume_phase=task.phase
        task.phase="blocked";task.reason=reason;task.ready=False
        task.action_started=False
        if task.draft.sync:
            task.released=False
            self.release_requests.discard(task.draft.sync)
        for i in task.draft.actors:
            a=self.actor(i)
            if a.queue and a.queue[0].task_id==task.id:clear_movement(a)
            if a.current_action and a.current_action.owner_token in {task.token, *(job.token for job in task.jobs.values())}:
                a.current_action=None
                if a.alive:a.mode=ActorMode.STANDING
            if i in task.jobs:task.jobs[i].started=False

    def suspend_actor(self,actor,reason):
        clear_movement(actor)
        if actor.queue and actor.queue[0].task_id in self.tasks:
            self.suspend_task(self.tasks[actor.queue[0].task_id],reason)
        elif actor.queue:
            n=actor.queue[0];n.status="blocked";n.reason=reason;n.started=False
            actor.blocked_reason=reason
        if actor.current_action:
            actor.current_action=None
            if actor.alive:actor.mode=ActorMode.STANDING

    def retry_node(self,actor,node):
        if not actor.alive:return "执行者死亡"
        if actor.stunned>0 or actor.under_fire_timer>self.world.time:return "等待震撼或受袭搜索结束"
        if node.cell is not None and node.kind in {"move","move_face","guard"} and not self.path(actor,node.cell):return "路径仍不可达"
        if node.kind in {"throw","bandage"} and node.token not in self.world.completed:
            if node.token not in actor.inventory.reservations:return "物品预约失效，请重新下达"
            if node.kind=="throw":
                error=self.throw_error(actor,node.item,node.cell)
                if error:return error
            elif not self.world.treatment_part(actor):return "没有可治疗伤口"
        node.status="queued";node.reason="";node.started=False
        actor.blocked_reason="";self.stalls.pop(actor.id,None)
        return None

    def cancel_actor(self,actor):
        tasks={n.task_id for n in actor.queue if n.task_id in self.tasks}
        for node in actor.queue:
            actor.inventory.release(node.token)
            self.world.loot.release(node.token)
        actor.queue.clear()
        actor.current_action=None
        if actor.mode==ActorMode.ACTING:actor.mode=ActorMode.STANDING
        clear_movement(actor)
        actor.blocked_reason=""
        actor.guard_angle=actor.facing
        actor.guard_explicit=False
        for id_ in tasks:
            task=self.tasks[id_]
            for job in [task.jobs.pop(actor.id,None), *task.pickups.pop(actor.id,[])]:
                if job:
                    self.world.loot.release(job.token)
                    if job.kind=='loot_search':task.seen_loot.discard(job.object_id)
            if actor.id in task.draft.actors:
                index=task.draft.actors.index(actor.id)
                if index<task.enter_index:task.enter_index-=1
                task.draft.actors.remove(actor.id)
            task.entered.discard(actor.id)
            task.draft.stacks.pop(actor.id,None);task.draft.entries.pop(actor.id,None)
            actor.inventory.release(task.token)
            if not task.draft.actors:
                self.tasks.pop(id_,None)
            elif task.phase not in {"done","cancelled"}:
                if task.draft.method=='loot' and any(i not in task.guards for i in task.draft.actors):
                    self.assign_search(task)
                self.suspend_task(task,"成员阵亡，请继续或取消")

    def stop(self,ids):
        self.cancel_related(ids)
        for i in ids:
            actor=self.actor(i)
            if actor:self.cancel_actor(actor)

    def cancel_task(self,id_):
        task=self.tasks.pop(id_,None)
        if not task:return
        for job in [*task.jobs.values(), *(n for nodes in task.pickups.values() for n in nodes)]:
            self.world.loot.release(job.token)
        self.world.completed.discard(task.token)
        for actor in self.world.actors:
            index=next((j for j,n in enumerate(actor.queue) if n.task_id==id_),None)
            actor.inventory.release(task.token)
            actor.queue[:]=[n for n in actor.queue if n.task_id!=id_]
            if index==0:
                actor.current_action=None
                if actor.mode==ActorMode.ACTING:actor.mode=ActorMode.STANDING
                clear_movement(actor)
                actor.blocked_reason=""
                actor.guard_angle=actor.facing
                actor.guard_explicit=False
                if actor.queue:self.suspend_actor(actor,"前置宏观已取消，请继续或重下")
            elif index is not None and index<len(actor.queue):
                successor=actor.queue[index]
                if successor.task_id in self.tasks:self.suspend_task(self.tasks[successor.task_id],"前置宏观已取消，请继续或重下")
                else:successor.status="blocked";successor.reason="前置宏观已取消，请继续或重下"
        self.world.message(f"行动 {id_} 已取消")

    def retry_task(self,id_):
        task=self.tasks[id_]
        if any(self.actor(i).stunned>0 or self.actor(i).under_fire_timer>self.world.time for i in task.draft.actors):return "等待震撼或受袭搜索结束"
        if task.draft.method=='loot':
            if not any(i not in task.guards for i in task.draft.actors):return '已无搜索者，请取消后重新分工'
            task.phase='loot';task.reason=''
            for i in task.draft.actors:self.actor(i).blocked_reason=''
            for job in task.jobs.values():job.started=False
            return None
        if task.draft.method in {"direct","breach","flash"} and len(task.draft.actors)<2:return "不足两人，请取消并使用单人指令"
        if task.draft.item and not task.flash_released and task.draft.thrower not in task.draft.actors:return "道具执行者已退出，请重新下达"
        if task.draft.item and not task.flash_released:
            thrower=self.actor(task.draft.thrower)
            if task.token not in thrower.inventory.reservations:return "物品预约失效，请重新下达"
            error=self.throw_error(thrower,task.draft.item,task.draft.landing,task.draft.stacks[thrower.id],task.draft.room,task.draft.door)
            if error:return error
        resume=task.resume_phase
        if self.world.perception.doors.get(task.draft.door)=="locked" and task.draft.opening!="kick":return "门已锁，请重新选择破门方式"
        goals=task.draft.entries if resume in {"enter","search"} and not task.draft.sync else task.draft.stacks
        if any(not self.path(self.actor(i),goals[i]) for i in task.draft.actors):return "执行位置不可达，请修改方案"
        task.phase=task.resume_phase if task.resume_phase not in {"blocked","queued"} else "stack"
        if task.draft.sync:
            task.phase="stack";task.enter_index=0;task.entered.clear()
        task.reason=""
        task.action_started=False
        for i in task.draft.actors:
            self.stalls.pop(i,None)
            self.actor(i).blocked_reason=""
        if task.phase=="search":self.assign_search(task)
        return None

    def delete_node(self,actor,index):
        if not 0<=index<len(actor.queue):return
        node=actor.queue[index]
        if node.task_id in self.tasks:self.cancel_task(node.task_id)
        else:
            actor.inventory.release(node.token)
            self.world.loot.release(node.token)
            actor.queue.pop(index)
            if index==0:
                actor.current_action=None
                if actor.mode==ActorMode.ACTING:actor.mode=ActorMode.STANDING
                clear_movement(actor)
                actor.blocked_reason=""

    def sync_status(self,label):
        registered=[]
        for task in self.tasks.values():
            if task.draft.sync==label and not task.released:
                registered.append((self.task_label(task),task.phase=="wait" and task.ready))
        for a in self.world.actors:
            for n in a.queue:
                if n.kind=="wait" and n.sync==label:registered.append((a.name,n is a.queue[0] and n.status=="waiting" and not self.world.has_threat(a)))
        return registered

    def release(self,label):
        entries=self.sync_status(label)
        if not entries or not all(ready for _,ready in entries):return "尚未全员就绪"
        self.release_requests.add(label)
        return None

    def drive(self,actor,cell,dt,*,angle=None,zone=None):
        if actor.stunned>0 or actor.current_action:return False
        if self.world.has_threat(actor) and not self.micro_controls_motion(actor):
            clear_movement(actor)
            self.stalls.pop(actor.id,None)
            return False
        if actor.mode==ActorMode.STANDING and actor.occupied_cell==cell:
            self.stalls.pop(actor.id,None)
            clear_movement(actor)
            if angle is not None:
                actor.guard_angle=angle
                actor.guard_explicit=True
                return abs(angle_difference(actor.facing,angle))<=.087267
            return True
        previous,elapsed,recalculated=self.stalls.get(actor.id,(actor.position,0.0,False))
        elapsed=elapsed+dt if previous.distance_to(actor.position)<1e-6 else 0.0
        if elapsed>=5:
            actor.blocked_reason="5 秒无移动进展"
            clear_movement(actor)
            return False
        if elapsed>=2 and not recalculated:
            clear_movement(actor)
            recalculated=True
        self.stalls[actor.id]=(actor.position,elapsed,recalculated)
        if actor.target_cell!=cell or not actor.route and actor.mode==ActorMode.STANDING:
            path=self.path(actor,cell,zone=zone)
            if path:
                self.world.apply_command(ActorCommand(actor.id,CommandType.MOVE_TO,"按计划移动",target_cell=cell,path=tuple(path)))
            else:actor.blocked_reason="路径暂不可达"
        return False

    def observations(self,room):
        grid=self.world.grid
        x1,y1,x2,y2=RECTS[room]
        seeds=[(x1+1,y1+1),(x2-1,y1+1),(x2-1,y2-1),(x1+1,y2-1),((x1+x2+1)//2,(y1+y2+1)//2)]
        cells=[c for c in grid.zones[room].cells if grid.walkable(c)]
        result=[]
        for p in seeds:
            c=min(cells,key=lambda c:((c[0]-p[0])**2+(c[1]-p[1])**2,c[1],c[0]))
            if c not in result:result.append(c)
        return result

    def assign_search(self,task):
        actors=[i for i in task.draft.actors if i not in task.guards]
        remaining=list(dict.fromkeys(c for points in task.searches.values() for c in points)) if task.searches else self.observations(task.draft.room)
        task.searches={i:[] for i in actors}
        costs={i:0 for i in actors}
        ends={i:self.position_cell(self.actor(i)) for i in actors}
        for point in remaining:
            i=min(actors,key=lambda i:(costs[i],actors.index(i)))
            costs[i]+=self.world.grid.path_cost(self.path(self.actor(i),point,start=ends[i],zone=task.draft.room))
            task.searches[i].append(point)
            ends[i]=point
        task.observations={i:0 for i in actors}

    def finish_task(self,task):
        for i in task.draft.actors:
            actor=self.actor(i)
            actor.inventory.release(task.token)
            actor.queue[:]=[n for n in actor.queue if n.task_id!=task.id]
            actor.blocked_reason=""
            clear_movement(actor)
        task.phase="done"
        self.world.message(self.task_label(task)+" · 完成")
        self.tasks.pop(task.id,None)

    def resolve_slot(self,task,actor,cell,assigned,zone=None):
        occupied={a.occupied_cell for a in self.world.actors if a.alive and a.id!=actor.id and a.occupied_cell is not None and not a.route}
        if cell not in occupied:return cell
        grid=self.world.grid;room=grid.zone_id(cell)
        taken=set(assigned)-{cell}
        candidates=[]
        for c in grid.zones[room].cells:
            if c in occupied or c in taken or not grid.walkable(c) or hypot(c[0]-cell[0],c[1]-cell[1])>2:continue
            path=self.path(actor,c,zone=zone,exclude=task.draft.room if task.phase in {"stack","wait"} else None)
            if path:candidates.append(((c[0]-cell[0])**2+(c[1]-cell[1])**2,grid.path_cost(path),c[1],c[0],c))
        return min(candidates)[-1] if candidates else cell

    def tick_task(self,task,dt):
        w=self.world;d=task.draft
        if d.method=='loot':
            w.loot.tick_task(task,dt)
            return
        if task.phase=="blocked":return
        actors=[self.actor(i) for i in d.actors]
        if not all(a.queue and a.queue[0].task_id==task.id for a in actors):return
        if task.phase=="queued":task.phase="stack"
        earlier=next((other for other in self.tasks.values() if other.id<task.id and other.draft.door==d.door
                      and other.phase not in {"search","done","cancelled"}),None)
        if earlier and task.phase in {"stack","wait","door"}:
            self.suspend_task(task,f"门被行动 {earlier.id} 占用");return
        if any(a.blocked_reason for a in actors):
            self.suspend_task(task,next(a.blocked_reason for a in actors if a.blocked_reason))
            return
        if task.phase in {"stack","wait"}:
            ready=True
            for index,a in enumerate(actors):
                if a.id not in d.stack_overrides:d.stacks[a.id]=self.resolve_slot(task,a,d.stacks[a.id],d.stacks.values())
                facing=d.stack_angles.get(a.id,d.angle if index<3 else d.angle+3.14159265)
                ready=self.drive(a,d.stacks[a.id],dt,angle=facing) and ready
            if ready and not task.ready and d.sync:
                w.message(f"行动 {task.id} · 同步 {d.sync} 就绪",sound="ready")
            task.ready=ready
            if not ready:return
            if d.method in {"stack","guarddoor"}:
                self.finish_task(task);return
            if d.sync and not task.released:task.phase="wait";return
            task.phase="door"
        if task.phase=="door":
            if w.door_state(d.door) in {"open","broken"}:
                w.completed.discard(task.token)
                if d.method in {"open","kick"}:self.finish_task(task);return
                task.phase="throw" if d.item and not task.flash_released else "enter"
                task.action_started=False
            else:
                a=actors[0]
                if not self.drive(a,d.outside,dt,angle=d.angle):return
                if w.door_state(d.door)=="locked" and d.opening!="kick":
                    self.suspend_task(task,"门已锁，重新选择破门方式");return
                if not task.action_started:
                    error=w.start_action(a,ActionType.KICK_DOOR if d.opening=="kick" else ActionType.OPEN_DOOR,
                                         1.4 if d.opening=="kick" else .8,task.token,door=d.door,cell=d.inside)
                    if error:self.suspend_task(task,error)
                    else:task.action_started=True
                return
        if task.phase=="throw":
            if task.flash_released:
                w.completed.discard(task.token);task.phase="blast"
                return
            a=self.actor(d.thrower)
            if a.stunned>0:return
            if a.mode!=ActorMode.STANDING or a.occupied_cell!=d.stacks[a.id]:
                if not self.drive(a,d.stacks[a.id],dt):return
            if not task.action_started:
                error=self.throw_error(a,d.item,d.landing,room=d.room)
                if error:self.suspend_task(task,error);return
                w.start_action(a,ActionType.THROW_GRENADE,use_for(d.item).duration,task.token,item=d.item,cell=d.landing)
                task.action_started=True
            if task.token in w.completed:
                w.completed.discard(task.token)
                task.flash_released=True;task.phase="blast";task.blast_at=w.time+1.15
            return
        if task.phase=="blast":
            if w.time<task.blast_at:return
            task.phase="enter"
        if task.phase=="enter":
            for a in actors[:task.enter_index]:
                if a.id not in d.entry_overrides:d.entries[a.id]=self.resolve_slot(task,a,d.entries[a.id],d.entries.values())
                if self.drive(a,d.entries[a.id],dt,angle=d.entry_angles.get(a.id,self.room_angle(d.room,d.entries[a.id]))):
                    task.entered.add(a.id)
            if task.enter_index<len(actors):
                a=actors[task.enter_index]
                previous=actors[task.enter_index-1] if task.enter_index else None
                clear=previous is None or (w.grid.zone_id(self.position_cell(previous))==d.room and
                    previous.occupied_cell!=d.inside and previous.move_to!=d.inside and previous.move_from!=d.inside)
                if clear and w.time-task.released_at>=.25:
                    self.drive(a,d.entries[a.id],dt,angle=d.entry_angles.get(a.id,self.room_angle(d.room,d.entries[a.id])))
                    task.enter_index+=1;task.released_at=w.time
            elif len(task.entered)==len(actors):
                if d.after_entry=='hold':self.finish_task(task)
                else:task.phase="search";self.assign_search(task)
            return
        if task.phase=="search":
            done=True
            for a in actors:
                points=task.searches.get(a.id,[])
                if not points:continue
                points[0]=self.resolve_slot(task,a,points[0],list(task.finals.values())+[p for values in task.searches.values() for p in values],d.room)
                done=False
                if self.drive(a,points[0],dt,angle=self.room_angle(d.room,points[0]),zone=d.room):
                    task.observations[a.id]=task.observations.get(a.id,0)+dt
                    if task.observations[a.id]>=.4:
                        task.finals[a.id]=points.pop(0);task.observations[a.id]=0
                else:task.observations[a.id]=0
            if done and not any(w.has_threat(a) for a in actors):
                memories=[(p,t) for a in actors for p,t in a.memory.values() if w.grid.zone_id(w.grid.cell_of(p))==d.room and w.time-t<5]
                if memories:return
                for index,a in enumerate(actors):
                    a.guard_angle=atan2(d.inside[1]+.5-a.position.y,d.inside[0]+.5-a.position.x) if index==len(actors)-1 else self.room_angle(d.room,self.position_cell(a))
                w.mission.room_checked[d.room]=w.time
                self.finish_task(task)

    def room_angle(self,room,cell):
        x1,y1,x2,y2=RECTS[room]
        dx,dy=(x1+x2+1)/2-(cell[0]+.5),(y1+y2+1)/2-(cell[1]+.5)
        return atan2(dy,dx) if dx or dy else -1.5707963

    def tick(self,dt):
        w=self.world
        for label in list(self.release_requests):
            entries=self.sync_status(label)
            if entries and all(ready for _,ready in entries):
                for task in self.tasks.values():
                    if task.draft.sync==label and not task.released:task.released=True
                for a in w.actors:
                    if a.queue and a.queue[0].kind=="wait" and a.queue[0].sync==label:a.queue.pop(0)
                w.message(f"同步 {label} · 已放行")
            else:w.message(f"同步 {label} · 就绪状态变化")
            self.release_requests.discard(label)
        for task in list(self.tasks.values()):self.tick_task(task,dt)
        for a in w.actors:
            if not a.alive or not a.queue:continue
            n=a.queue[0]
            if n.kind=="task" or n.status=="blocked":continue
            if a.blocked_reason:n.status="blocked";n.reason=a.blocked_reason;continue
            if n.status!='allocation':n.status="running"
            done=False
            if n.kind.startswith('loot_'):
                done=w.loot.tick_node(a,n,dt)
            elif n.kind in {"move","guard","move_face"}:
                a.guard_explicit=n.angle is not None
                arrived=self.drive(a,n.cell,dt,angle=n.angle)
                if arrived and n.kind=="guard":n.started=True
                done=arrived and n.kind!="guard"
            elif n.kind=="face":
                if a.mode==ActorMode.STANDING and a.stunned<=0 and not a.current_action:
                    a.guard_angle=n.angle
                    a.guard_explicit=True
                    done=abs(angle_difference(a.facing,n.angle))<=.087267
            elif n.kind=="attack":
                a.target_id=n.target_id
                if n.target_id in a.visible:n.elapsed=0
                else:n.elapsed+=dt
                target=w.actor(n.target_id)
                done=n.elapsed>=2 or target is not None and not target.alive and n.target_id in a.visible
            elif n.kind=="wait":
                clear_movement(a)
                if a.mode==ActorMode.STANDING and not a.current_action and a.stunned<=0 and not w.has_threat(a):n.status="waiting"
            elif n.kind in {"reload","bandage","throw"}:
                if n.token in w.completed:
                    w.completed.discard(n.token);done=True
                elif not n.started and a.mode==ActorMode.STANDING and a.stunned<=0 and not a.current_action:
                    if n.kind=="reload" and a.weapon.ammo>=30:done=True
                    else:
                        error=w.start_action(a,{"reload":ActionType.RELOAD,"bandage":ActionType.BANDAGE,"throw":ActionType.THROW_GRENADE}[n.kind],
                                             use_for(n.item).duration,n.token,item=n.item,cell=n.cell)
                        if error:n.status="blocked";n.reason=error
                        else:n.started=True
            if done:
                a.inventory.release(n.token)
                w.loot.release(n.token)
                a.queue.pop(0)
                a.blocked_reason=""

    def submit_loot_task(self,ids,room,guards=()):
        actors=[self.actor(i) for i in dict.fromkeys(ids)]
        if not actors or any(not a or not a.alive for a in actors):return '请选择存活队员'
        if room not in self.world.grid.zones:return '无效区域'
        if any(self.world.grid.zone_id(self.position_cell(a))!=room for a in actors):return '请先让参与者进入目标区域'
        guards=set(guards)&set(ids)
        if guards==set(ids):return '至少需要一名搜索者'
        self.cancel_related(ids)
        for a in actors:self.cancel_actor(a)
        id_=self.next_id;self.next_id+=1
        positions={a.id:self.position_cell(a) for a in actors}
        anchor=positions[actors[0].id]
        draft=TaskDraft(list(ids),None,room,'loot',anchor,anchor,dict(positions),dict(positions),0)
        task=SquadTask(id_,draft,guards=guards)
        self.assign_search(task)
        self.tasks[id_]=task
        for a in actors:a.queue.append(Node(task.token,'task',task_id=id_))
        self.world.message(self.task_label(task)+' · 已下达')
        return None
