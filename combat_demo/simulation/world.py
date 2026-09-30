from __future__ import annotations

from dataclasses import dataclass, field
from math import pi
from random import Random

from .actor import (
    ActionType,
    Actor,
    ActorAction,
    ActorMode,
    ActorRole,
    ActorState,
    AggressionPolicy,
    AmmoPolicy,
    CoverPolicy,
    GrenadePolicy,
    FireMode,
    IntentType,
    InterruptPolicy,
    MedicalPolicy,
    TacticProfile,
    Team,
)
from .commands import ActorCommand, CommandType
from .combat import ExplosionEvent, FloatingText, ShotEvent, SoundEvent, resolve_shot, point_segment_distance
from .geometry import Vec2, angle_to, angle_difference, rotate_toward
from .map import GridMap, InteractableState, create_breach_map, create_demo_map, create_maze_map
from .movement import clear_movement, update_actor_movement, movement_allowances
from .weapon import RIFLE, WeaponState
from .world_commands import apply_actor_command, set_intent


@dataclass
class World:
    grid: GridMap
    actors: list[Actor]
    shots: list[ShotEvent] = field(default_factory=list)
    texts: list[FloatingText] = field(default_factory=list)
    sounds: list[SoundEvent] = field(default_factory=list)
    explosions: list[ExplosionEvent] = field(default_factory=list)
    time: float = 0.0
    tick_index: int = 0
    winner: Team | None = None
    combat_cleared: bool = False
    rng: Random = field(default_factory=lambda: Random(7))
    scenario_name: str = "demo"
    mission: object | None = None
    paused: bool = False
    pause_requested: bool = False
    auto_contact: bool = False
    pause_count: int = 0
    accumulator: float = 0.0
    completed: set[str] = field(default_factory=set)
    projectiles: list = field(default_factory=list)
    events: list = field(default_factory=list)
    audio_events: list = field(default_factory=list)
    deaths_processed: set[int] = field(default_factory=set)
    stats: dict = field(default_factory=lambda: {"rounds":0,"friendly_hits":0,"friendly_stuns":0,"items":{}})
    discarded_time: float = 0.0
    sound_index: int = 0
    _turn_used: dict = field(default_factory=dict)

    def __post_init__(self):
        from .orders import Planner
        from .perception import Perception
        self.planner=Planner(self)
        self.perception=Perception()
        from .loot import LootSystem
        self.loot=LootSystem(self)
        self._actors={actor.id:actor for actor in self.actors}
        for actor in self.actors:
            if actor.occupied_cell is None and actor.mode==ActorMode.STANDING:
                actor.occupied_cell=self.grid.cell_of(actor.position)
            if actor.guard_angle is None:actor.guard_angle=actor.facing

    def actor(self,id_):
        return self._actors.get(id_)

    def set_paused(self,paused):
        if paused and not self.paused:self.pause_count+=1
        self.paused=paused
        self.accumulator=0.0

    def message(self,text,sound="confirm"):
        self.events.append((self.time,text))
        del self.events[:-100]
        if sound:self.audio_events.append(sound)

    def door_state(self,id_):
        door=self.grid.interactables[id_]
        if door.state==InteractableState.CLOSED:
            return "locked" if door.properties.get("locked") else "closed"
        return door.state.value

    def update(self,dt:float):
        if self.paused or self.winner is not None:return
        step=1/60
        self.accumulator+=max(0.0,dt)
        count=0
        while self.accumulator+1e-9>=step and count<5 and not self.paused and self.winner is None:
            self.accumulator-=step
            self._tick(step)
            count+=1
        if self.accumulator>=step:
            remainder=self.accumulator%step
            self.discarded_time+=self.accumulator-remainder
            self.accumulator=remainder

    def _tick(self,dt):
        from .perception import update_enemy
        self.time+=dt
        self.tick_index+=1
        self._update_effects(dt)
        for a in self.actors:
            a.weapon.update(dt)
            a.stunned=max(0.0,a.stunned-dt)
            a.hit_flash=max(0.0,a.hit_flash-dt)
            if a.current_action:
                if self.planner.micro_controls_motion(a) and (a.current_action.owner_token or "").startswith("auto:"):
                    self.interrupt(a,"微操接管自动换弹")
                else:self._update_action(a,dt)
        for projectile in list(self.projectiles):
            if self.time>=projectile["explode_at"]:
                self._flash(projectile)
                self.projectiles.remove(projectile)
        self.perception.refresh(self,dt)
        self.loot.refresh()
        if self.tick_index%6==0:
            for a in self.actors:
                if a.ai_enabled:update_enemy(self,a)
        self.planner.tick(dt)
        for a in self.actors:
            if not a.alive:continue
            if a.team==Team.RED and self.has_threat(a) and not self.planner.micro_controls_motion(a):clear_movement(a)
        distances=movement_allowances(self.actors,self.grid,dt)
        for a in self.actors:
            if not a.alive:continue
            if a.current_action is None:
                before=a.position
                update_actor_movement(a,self.grid,self.actors,dt,rotate=False,distance_budget=distances[a.id])
                self.observe(a,dt,a.position-before)
        self.perception.refresh(self,0.0)
        for a in sorted(self.actors,key=lambda actor:actor.id):
            self._combat(a,dt)
        for a in self.actors:
            if not a.alive and a.id not in self.deaths_processed:
                self.deaths_processed.add(a.id)
                self.planner.cancel_actor(a)
                self.loot.corpse(a)
                if a.team==Team.RED:
                    self.message(f"{a.id} {a.name} 阵亡",sound="hit")
                    self.pause_requested=True
        self._check_winner()
        if self.pause_requested and self.winner is None:
            self.set_paused(True)
        self.pause_requested=False
        # UI sounds are transient outputs; headless callers need not consume them.
        del self.audio_events[:-64]

    def has_threat(self,a):
        if a.under_fire_timer>self.time:return True
        if a.fire_mode==FireMode.HOLD_FIRE and not (a.queue and a.queue[0].kind=="attack"):return False
        visible=any(self.actor(i) and self.actor(i).alive for i in a.visible & a.recognized)
        if visible:
            a.last_known_timer=self.time
            return True
        return a.last_known_timer>0 and self.time-a.last_known_timer<1

    def observe(self,a,dt,motion):
        """Choose one observation intent; combat shares the same turn budget."""
        a.response=""
        if a.stunned>0:return
        if self.planner.micro_controls_motion(a):
            n=a.queue[0]
            angle=n.angle if n.angle is not None else motion.angle() if motion.length()>.000001 else a.guard_angle
            self.face(a,angle,dt)
            if n.angle is None and motion.length()>.000001:a.guard_angle=a.facing
            a.response="执行微操 · 受袭" if a.under_fire_timer>self.time else "执行微操"
            return
        visible=[self.actor(i) for i in a.visible & a.recognized if self.actor(i) and self.actor(i).alive]
        if visible and (a.fire_mode!=FireMode.HOLD_FIRE or a.queue and a.queue[0].kind=="attack"):
            a.response="交战"
            return
        n=a.queue[0] if a.queue else None
        planned=n.angle if n and n.kind in {"move","move_face","guard","face"} else None
        macro=n is not None and n.task_id in self.planner.tasks
        if a.under_fire_timer>self.time:
            a.response="受袭搜索";angle=a.under_fire_angle
        elif planned is not None:
            angle=planned
        elif a.team==Team.RED and not macro and not a.guard_explicit and a.heard_timer>self.time and a.heard_position is not None:
            a.response="听声观察";angle=angle_to(a.position,a.heard_position)
        elif motion.length()>.000001:
            angle=motion.angle()
        else:angle=a.guard_angle
        self.face(a,angle,dt)
        if not a.response and planned is None and motion.length()>.000001:
            a.guard_angle=a.facing

    def receive_attack(self,actor,shot,attacker,*,hit=False):
        """Ballistics grants a bearing, never hidden shooter coordinates."""
        actor.recent_attackers[attacker.id]=self.time
        was_under_fire=actor.under_fire_timer>self.time
        known=self.perception.player_visible if actor.team==Team.RED else actor.visible & actor.recognized
        friendly_known=attacker.team==actor.team and (actor.team==Team.RED or self.perception.point_visible(self,actor,attacker.position))
        unknown=attacker.id not in known and not friendly_known
        if unknown or attacker.team!=actor.team and attacker.id not in actor.visible & actor.recognized:
            bearing=shot.start-shot.end
            actor.under_fire_angle=bearing.angle()
            actor.under_fire_timer=self.time+2
        if unknown:
            if self.planner.micro_controls_motion(actor):
                if not was_under_fire:self.message(f"{actor.id} 号受袭 · 继续执行微操",sound="hit")
                return
            already=(actor.queue and (actor.queue[0].status=="blocked" or
                     actor.queue[0].task_id in self.planner.tasks and self.planner.tasks[actor.queue[0].task_id].phase=="blocked"))
            self.planner.suspend_actor(actor,f"{actor.id} 号受到未确认方向来弹")
            if actor.team==Team.RED and not already:self.message(f"{actor.id} 号受袭搜索"+(" · 关联计划已挂起" if actor.queue else ""),sound="hit")
        elif hit:self.interrupt(actor,"受到攻击，动作中断")

    def face(self,a,angle,dt):
        if angle is not None and a.stunned<=0:
            tick,used=self._turn_used.get(a.id,(-1,0.0))
            if tick!=self.tick_index:used=0.0
            budget=max(0.0,a.turn_speed*dt-used)
            change=min(abs(angle_difference(a.facing,angle)),budget)
            a.facing=rotate_toward(a.facing,angle,budget)
            self._turn_used[a.id]=(self.tick_index,used+change)

    def _combat(self,a,dt):
        if not a.alive or a.stunned>0 or a.current_action:return
        if self.planner.micro_controls_motion(a):
            a.reaction=0;a.aim_target_id=None;a.fire_reason="微操优先"
            return
        explicit=a.queue[0].target_id if a.queue and a.queue[0].kind=="attack" else None
        if a.fire_mode==FireMode.HOLD_FIRE and explicit is None:return
        candidates=[self.actor(i) for i in a.visible & a.recognized if self.actor(i) and self.actor(i).alive]
        if explicit is not None:
            candidates=[target for target in candidates if target.id==explicit]
        if not candidates:
            a.reaction=0
            a.aim_target_id=None
            a.fire_reason="警戒"
            return
        target=min(candidates,key=lambda t:(not (self.time-a.recent_attackers.get(t.id,-100)<.5),a.position.distance_to(t.position),t.id))
        if a.aim_target_id!=target.id:
            a.aim_target_id=target.id;a.reaction=0;a.aim_error_degrees=8
        a.reaction+=dt
        if a.mode!=ActorMode.STANDING:return
        desired=angle_to(a.position,target.position)
        self.face(a,desired,dt)
        if abs(angle_difference(a.facing,desired))>.087267:return
        a.aim_error_degrees=max(0.0,a.aim_error_degrees-10*a.body.derived_stats().manipulation_efficiency*dt)
        if a.reaction<( .25 if a.team==Team.RED else .65) or a.aim_error_degrees>3:return
        if a.position.distance_to(target.position)>a.weapon.definition.range:return
        if a.weapon.ammo==0:
            if a.weapon.reserve_ammo>0:
                self.start_action(a,ActionType.RELOAD,a.weapon.definition.reload_time,f"auto:{a.id}:{self.tick_index}",item="rifle")
            else:a.fire_reason="弹药耗尽"
            return
        if not a.weapon.can_fire():return
        if self.grid.raycast(a.position,target.position,1.65,1.25,"projectile")[1] is not None:
            a.fire_reason="射线被遮挡";return
        for other in self.actors:
            if other.id==a.id or not other.alive or other.team!=a.team:continue
            distance,t=point_segment_distance(other.position,a.position,target.position)
            if 0<t<1 and distance<=other.radius+.1:
                a.fire_reason="友军挡线";return
        a.fire_reason="交战"
        event=resolve_shot(a,target.position,self.grid,self.actors,self.rng,a.aim_error_degrees)
        self.shots.append(event)
        self.emit_sound(a.position,a.team,14,"rifle")
        if a.team==Team.RED:self.stats["rounds"]+=1
        if event.hit_actor_id is not None:
            hit=self.actor(event.hit_actor_id)
            self.receive_attack(hit,event,a,hit=True)
            if hit.team==a.team and a.team==Team.RED:self.stats["friendly_hits"]+=1
            if hit.team==Team.RED or hit.id in self.perception.player_visible:self.audio_events.append("hit")
        for miss in event.near_misses:
            if miss.actor_id!=event.hit_actor_id:self.receive_attack(self.actor(miss.actor_id),event,a)

    def emit_sound(self,position,team,radius,kind):
        self.sound_index+=1
        event=SoundEvent(position,team.value,radius,2.0,kind,id=self.sound_index)
        self.perception.hear(self,event)
        self.sounds.append(event)
        if event.audible:self.audio_events.append(kind)

    def apply_command(self,command,dt=0.0):
        actor=self.actor(command.actor_id)
        if actor is None or not actor.alive:return "执行者死亡"
        return apply_actor_command(actor,self.actors,self.grid,command,dt)

    def treatment_part(self,a):
        parts=[p for p in a.body.wounded_parts("bleeds") if not p.destroyed]
        return min(parts,key=lambda p:(-p.missing_hp,p.definition.id)).definition.id if parts else None

    def start_action(self,a,kind,duration,token,*,item=None,cell=None,door=None,object_id=None,cargo_id=None):
        if not a.alive:return "执行者死亡"
        if a.stunned>0:return "等待震撼结束"
        if a.mode!=ActorMode.STANDING or a.current_action:return "执行者尚未站定"
        part=None
        if kind in {ActionType.SEARCH_LOOT,ActionType.TRANSFER_ITEM,ActionType.DROP_ITEM,ActionType.EQUIP_ITEM}:
            error=self.loot.action_error(a,kind,token,object_id,cargo_id)
            if error:return error
            duration/=a.body.derived_stats().manipulation_efficiency
        if kind==ActionType.RELOAD:
            if a.weapon.reserve_ammo<=0:return "储备弹药耗尽"
            duration=duration/a.body.derived_stats().manipulation_efficiency
        if kind==ActionType.BANDAGE:
            part=self.treatment_part(a)
            if not part:return "没有可治疗伤口"
        if kind in {ActionType.BANDAGE,ActionType.THROW_GRENADE}:
            if token not in a.inventory.reservations:return "物品未预约"
        if kind==ActionType.THROW_GRENADE:
            error=self.planner.throw_error(a,item,cell,room=self.grid.zone_id(cell))
            if error:return error
        error=self.apply_command(ActorCommand(a.id,CommandType.START_ACTION,"执行计划",target_position=self.grid.cell_center(cell) if cell else None,
                     action_type=kind,duration=duration,door_id=door,item_id=item,part_id=part,owner_token=token,
                     object_id=object_id,cargo_id=cargo_id))
        if not error and kind==ActionType.RELOAD:self.audio_events.append("reload")
        return error

    def interrupt(self,a,reason):
        action=a.current_action
        if action is None:return
        if action.owner_token and action.owner_token.startswith("auto:"):
            a.current_action=None
            if a.alive:a.mode=ActorMode.STANDING
            return
        self.planner.suspend_actor(a,reason)

    def _update_action(self,a,dt):
        action=a.current_action
        if not a.alive or a.stunned>0:return
        action.timer+=dt
        if action.timer+1e-9<action.duration:return
        token=action.owner_token
        kind=action.type
        if kind in {ActionType.SEARCH_LOOT,ActionType.TRANSFER_ITEM,ActionType.DROP_ITEM,ActionType.EQUIP_ITEM}:
            error=self.loot.complete_action(a,action)
            if error:self.interrupt(a,error);return
        elif kind==ActionType.RELOAD:
            refill=min(action.refill,a.weapon.reserve_ammo,a.weapon.definition.magazine_size-a.weapon.ammo)
            a.weapon.ammo+=refill;a.weapon.reserve_ammo-=refill
        elif kind==ActionType.BANDAGE:
            part=a.body.parts.get(action.part_id)
            if part is None or part.destroyed or not part.missing_hp:self.interrupt(a,"治疗部位失效");return
            if not a.inventory.consume(token):self.interrupt(a,"物品不足");return
            a.body.heal_part(action.part_id,min(22,part.missing_hp))
            self._item_used(a,action.item_id)
        elif kind==ActionType.THROW_GRENADE:
            from .items import use_for
            cell=self.grid.cell_of(action.target_position)
            error=self.planner.throw_error(a,action.item_id,cell,room=self.grid.zone_id(cell))
            if error:self.interrupt(a,error);return
            if not a.inventory.consume(token):self.interrupt(a,"物品不足");return
            use=use_for(action.item_id)
            self.projectiles.append({"start":a.position,"end":action.target_position,"release":self.time,"explode_at":self.time+1.0,
                                     "item":action.item_id,"radius":use.radius,"team":a.team,"actor":a.id})
            task=next((t for t in self.planner.tasks.values() if t.token==token),None)
            if task:
                task.flash_released=True;task.blast_at=self.time+1.15
            self._item_used(a,action.item_id)
        elif kind in {ActionType.OPEN_DOOR,ActionType.KICK_DOOR}:
            dest=self.grid.cell_of(action.target_position)
            feature=self.grid.edge_feature_between(a.occupied_cell,dest)
            if feature is None or not feature.interactive_id:self.interrupt(a,"门目标失效");return
            id_=feature.interactive_id
            if self.door_state(id_)=="locked" and kind!=ActionType.KICK_DOOR:self.interrupt(a,"门已锁");return
            self.grid.open_interactable_between(a.occupied_cell,dest)
            if kind==ActionType.KICK_DOOR:self.grid.interactables[id_].state=InteractableState.BROKEN
            if a.team==Team.RED:self.perception.doors[id_]=self.door_state(id_)
            self.emit_sound(a.position,a.team,8 if kind==ActionType.KICK_DOOR else 3,"kick" if kind==ActionType.KICK_DOOR else "door")
        a.current_action=None
        if a.alive:a.mode=ActorMode.STANDING
        if token and not token.startswith("auto:"):self.completed.add(token)

    def _item_used(self,a,item):
        if a.team==Team.RED:self.stats["items"][item]=self.stats["items"].get(item,0)+1

    def _flash(self,projectile):
        pos=projectile["end"];radius=projectile["radius"]
        self.explosions.append(ExplosionEvent(pos,radius))
        self.emit_sound(pos,projectile["team"],12,"flash")
        for a in self.actors:
            distance=a.position.distance_to(pos)
            if not a.alive or distance>radius:continue
            if self.grid.raycast(pos,a.position,kind="flash")[1] is not None:continue
            front=distance<1e-7 or abs(angle_difference(a.facing,angle_to(a.position,pos)))<=pi/3
            a.stunned=max(a.stunned,2.5 if front else .8)
            a.reaction=0;a.aim_error_degrees=8
            self.interrupt(a,"受到闪光震撼")
            if a.team==Team.RED and projectile["team"]==Team.RED:self.stats["friendly_stuns"]+=1

    def _update_effects(self,dt):
        for group in (self.shots,self.texts,self.sounds,self.explosions):
            for event in group:event.timer-=dt
            group[:]=[event for event in group if event.timer>0]

    def _check_winner(self):
        red_alive=any(a.alive and a.team==Team.RED for a in self.actors)
        blue_alive=any(a.alive and a.team==Team.BLUE for a in self.actors)
        if not red_alive:self.winner=Team.BLUE
        elif not blue_alive and not self.combat_cleared:self.winner=Team.RED
        if self.winner is not None:
            self.message("任务完成 · 全部敌人已消灭" if self.winner==Team.RED else "任务失败 · 小队全灭",
                         "ready" if self.winner==Team.RED else "reject")

    def continue_looting(self):
        if self.winner!=Team.RED:return
        self.combat_cleared=True;self.winner=None;self.set_paused(True)
        self.message('威胁清除 · 可以继续搜索和整理携带物品')


def create_world() -> World:
    grid = create_demo_map()
    actors = [
        Actor(
            0,
            "Red 1",
            Team.RED,
            Vec2(1.5, 4.5),
            0.0,
            role=ActorRole.POINTMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.AGGRESSIVE, cover=CoverPolicy.CHASE),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            1,
            "Red 2",
            Team.RED,
            Vec2(1.5, 6.5),
            0.0,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            2,
            "Red 3",
            Team.RED,
            Vec2(2.5, 8.5),
            0.0,
            role=ActorRole.SUPPORT,
            tactics=TacticProfile(ammo=AmmoPolicy.SUPPRESS, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            3,
            "Blue 1",
            Team.BLUE,
            Vec2(18.5, 4.5),
            pi,
            role=ActorRole.POINTMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.CONSERVATIVE, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            4,
            "Blue 2",
            Team.BLUE,
            Vec2(18.5, 6.5),
            pi,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(grenade=GrenadePolicy.AGGRESSIVE),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            5,
            "Blue 3",
            Team.BLUE,
            Vec2(17.5, 8.5),
            pi,
            role=ActorRole.SUPPORT,
            tactics=TacticProfile(ammo=AmmoPolicy.CONSERVE, medical=MedicalPolicy.IGNORE_LIGHT),
            weapon=WeaponState.create(RIFLE),
        ),
    ]
    initialize_actor_cells(grid, actors)
    return World(grid=grid, actors=actors, scenario_name="demo")


def create_breach_world() -> World:
    grid = create_breach_map()
    actors = [
        Actor(
            0,
            "Breach 1",
            Team.RED,
            Vec2(3.5, 5.5),
            0.0,
            role=ActorRole.POINTMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.AGGRESSIVE, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            1,
            "Breach 2",
            Team.RED,
            Vec2(2.5, 5.5),
            0.0,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            2,
            "Breach 3",
            Team.RED,
            Vec2(3.5, 7.5),
            0.0,
            role=ActorRole.SUPPORT,
            tactics=TacticProfile(ammo=AmmoPolicy.SUPPRESS, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            3,
            "Trainee 1",
            Team.BLUE,
            Vec2(9.5, 3.5),
            pi,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.CONSERVATIVE, cover=CoverPolicy.COVER_FIRST, grenade=GrenadePolicy.DISABLED),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            4,
            "Trainee 2",
            Team.BLUE,
            Vec2(12.5, 5.5),
            pi,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.CONSERVATIVE, cover=CoverPolicy.COVER_FIRST, grenade=GrenadePolicy.DISABLED),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            5,
            "Trainee 3",
            Team.BLUE,
            Vec2(10.5, 8.5),
            pi,
            role=ActorRole.SUPPORT,
            tactics=TacticProfile(aggression=AggressionPolicy.CONSERVATIVE, cover=CoverPolicy.COVER_FIRST, grenade=GrenadePolicy.DISABLED),
            weapon=WeaponState.create(RIFLE),
        ),
    ]
    initialize_actor_cells(grid, actors)
    return World(grid=grid, actors=actors, scenario_name="breach")


def create_maze_world() -> World:
    grid = create_maze_map()
    rng = Random(41)
    data = grid.maze_data
    if data is None:
        raise ValueError("maze map requires maze_data")
    start_room = data.rooms[6]
    enemy_rooms = [room for room in data.rooms if room.id not in {start_room.id, data.rooms[8].id}]
    red_cells = available_cells(grid, start_room.cells, rng, 3)
    enemy_cells = available_cells(
        grid,
        tuple(cell for room in enemy_rooms for cell in room.cells),
        rng,
        rng.randint(4, 6),
    )
    actors = [
        Actor(
            0,
            "Scout 1",
            Team.RED,
            grid.cell_center(red_cells[0]),
            0.0,
            role=ActorRole.POINTMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.STANDARD, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            1,
            "Scout 2",
            Team.RED,
            grid.cell_center(red_cells[1]),
            0.0,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            2,
            "Scout 3",
            Team.RED,
            grid.cell_center(red_cells[2]),
            0.0,
            role=ActorRole.SUPPORT,
            tactics=TacticProfile(ammo=AmmoPolicy.SUPPRESS, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
    ]
    for index, cell in enumerate(enemy_cells, start=3):
        role = ActorRole.SUPPORT if index % 3 == 2 else ActorRole.RIFLEMAN
        actors.append(
            Actor(
                index,
                f"Patrol {index - 2}",
                Team.BLUE,
                grid.cell_center(cell),
                pi,
                role=role,
                tactics=TacticProfile(
                    aggression=AggressionPolicy.CONSERVATIVE,
                    ammo=AmmoPolicy.CONSERVE if role == ActorRole.SUPPORT else AmmoPolicy.STANDARD,
                    cover=CoverPolicy.COVER_FIRST,
                ),
                weapon=WeaponState.create(RIFLE),
            )
        )
    initialize_actor_cells(grid, actors)
    return World(grid=grid, actors=actors, scenario_name="maze")


def initialize_actor_cells(grid: GridMap, actors: list[Actor]) -> None:
    for actor in actors:
        actor.occupied_cell = grid.cell_of(actor.position)
        actor.position = grid.cell_center(actor.occupied_cell)


def available_cells(
    grid: GridMap,
    cells: tuple[tuple[int, int], ...],
    rng: Random,
    count: int,
) -> list[tuple[int, int]]:
    candidates = [cell for cell in cells if grid.cell_feature_at(cell) is None]
    rng.shuffle(candidates)
    return candidates[:count]
