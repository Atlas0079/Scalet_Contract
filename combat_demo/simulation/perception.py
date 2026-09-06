"""Per-observer perception. Rendering and planning consume only team knowledge."""
from __future__ import annotations

from dataclasses import dataclass, field
from math import atan2, ceil, floor

from .actor import Team
from .geometry import Vec2, angle_difference


@dataclass
class Perception:
    player_visible: set[int] = field(default_factory=set)
    player_raw: set[int] = field(default_factory=set)
    identified: set[int] = field(default_factory=set)
    visible_cells: set[tuple[int,int]] = field(default_factory=set)
    explored: set[tuple[int,int]] = field(default_factory=set)
    last_seen: dict[int,tuple[Vec2,float]] = field(default_factory=dict)
    doors: dict[str,str] = field(default_factory=dict)
    cells_by_actor: dict[int,set[tuple[int,int]]] = field(default_factory=dict)
    _cell_keys: dict[int,tuple] = field(default_factory=dict)
    first_contact: bool = False
    _vision: dict[int,float] = field(default_factory=dict)

    def point_visible(self,world,actor,point):
        if actor.stunned>0:return False
        delta=point-actor.position
        distance=delta.length()
        if distance>actor.view_distance*self._vision.get(actor.id,1.0):return False
        if distance>.01 and abs(angle_difference(actor.facing,delta.angle()))>actor.view_angle*.5:return False
        t,feature=world.grid.raycast(actor.position,point)
        return feature is None or t>=1-1e-7

    def refresh(self,world,dt,force=False):
        self._vision={a.id:a.body.derived_stats().vision_efficiency for a in world.actors if a.alive}
        self.player_raw.clear();self.player_visible.clear();self.visible_cells.clear()
        for actor in world.actors:
            actor.visible.clear()
            if not actor.alive:continue
            for target in world.actors:
                if target.team==actor.team:continue
                if self.point_visible(world,actor,target.position):
                    actor.visible.add(target.id)
                    actor.identification[target.id]=actor.identification.get(target.id,0)+dt
                    if actor.identification[target.id]>=.2:
                        actor.recognized.add(target.id)
                        if actor.team==Team.RED:self.identified.add(target.id)
                    if target.id in actor.recognized and target.alive:
                        actor.memory[target.id]=(target.position,world.time)
                    elif not target.alive:
                        actor.memory.pop(target.id,None)
                else:actor.identification.pop(target.id,None)
            actor.memory={id_:(p,t) for id_,(p,t) in actor.memory.items() if world.time-t<5}
            if actor.team!=Team.RED:continue
            self.player_raw.update(actor.visible)
            actor.recognized.update(self.identified)
            key=(actor.position,actor.facing,actor.stunned>0,world.grid.revision,actor.body.derived_stats().vision_efficiency)
            if force or self._cell_keys.get(actor.id)!=key:
                cells=set()
                if actor.stunned<=0:
                    radius=actor.view_distance*actor.body.derived_stats().vision_efficiency
                    for y in range(max(0,floor(actor.position.y-radius)),min(world.grid.height,ceil(actor.position.y+radius))):
                        for x in range(max(0,floor(actor.position.x-radius)),min(world.grid.width,ceil(actor.position.x+radius))):
                            cell=(x,y)
                            if self.point_visible(world,actor,world.grid.cell_center(cell)):cells.add(cell)
                self.cells_by_actor[actor.id]=cells
                self._cell_keys[actor.id]=key
            self.visible_cells.update(self.cells_by_actor.get(actor.id,set()))
            if world.mission:
                for id_,entrance in world.mission.entrances.items():
                    if self.point_visible(world,actor,entrance.center(world.grid)):
                        self.doors[id_]=world.door_state(id_)
        self.explored.update(self.visible_cells)
        self.player_visible=self.player_raw & self.identified
        for actor in world.actors:
            if actor.team==Team.RED:
                actor.recognized.update(self.identified)
            elif actor.id in self.player_visible:
                self.last_seen[actor.id]=(actor.position,world.time)
        self.last_seen={i:v for i,v in self.last_seen.items() if world.time-v[1]<5}
        if any(world.actor(i).alive for i in self.player_visible) and not self.first_contact:
            self.first_contact=True
            world.message("发现敌人 · 空格暂停，逐人调整行动",sound="ready")
            if world.auto_contact:world.pause_requested=True

    def hear(self,world,event):
        area=(3*floor(event.position.x/3),3*floor(event.position.y/3))
        event.area=area
        for actor in world.actors:
            if not actor.alive:continue
            distance=actor.position.distance_to(event.position)
            if distance>event.radius:continue
            penalty=sum(4 for _,feature in world.grid.ray_features(event.position,actor.position)
                        if feature.blocks_projectile and feature.height>=2 and feature.kind in {"wall","door","boundary"})
            if distance+penalty>event.radius:continue
            if actor.team==Team.RED:event.audible=True
            if actor.team.value!=event.team:
                center=Vec2(area[0]+1.5,area[1]+1.5)
                changed=actor.heard_position!=center
                actor.heard_position=center
                actor.heard_timer=world.time+(6 if actor.ai_enabled else 1)
                if changed and actor.ai_enabled:
                    if actor.ai_state not in {"combat","search"}:
                        actor.ai_goal=None
                        actor.ai_state="investigate"


def update_enemy(world,actor):
    """Small explicit state machine, using actor memory rather than hidden targets."""
    from .movement import clear_movement
    if not actor.alive or actor.stunned>0 or actor.current_action:return
    if actor.under_fire_timer>world.time:
        clear_movement(actor)
        return
    visible=[world.actor(i) for i in actor.visible & actor.recognized if world.actor(i).alive]
    grid=world.grid;planner=world.planner
    zone=grid.zone_id(planner.position_cell(actor))
    if visible:
        target=min(visible,key=lambda t:(actor.position.distance_to(t.position),t.id))
        if actor.ai_state!="combat":
            actor.ai_state="combat";actor.ai_goal=None
            if zone:
                choices=[]
                for cell in grid.zones[zone].cells:
                    if not grid.walkable(cell) or grid.cell_center(cell).distance_to(actor.position)>3:continue
                    if any(a.id!=actor.id and a.alive and a.occupied_cell==cell for a in world.actors):continue
                    if not any(grid.cell_feature_at((cell[0]+dx,cell[1]+dy)) for dx,dy in [(0,-1),(1,0),(0,1),(-1,0)]):continue
                    if grid.raycast(grid.cell_center(cell),target.position,1.65,1.25,"projectile")[1] is not None:continue
                    path=planner.path(actor,cell,zone=zone,known=False)
                    if path:choices.append((len(path),grid.cell_center(cell).distance_to(target.position),cell[1],cell[0],cell,path))
                if choices:
                    choice=min(choices)
                    actor.ai_goal=choice[-2]
                    actor.route=list(choice[-1]);actor.path=list(actor.route);actor.reserved_cell=actor.ai_goal;actor.target_cell=actor.ai_goal
        if world.time-actor.report_time>=.5:
            actor.report_time=world.time
            for other in world.actors:
                if other.ai_enabled and other.alive and other.id!=actor.id and grid.zone_id(planner.position_cell(other))==zone and other.position.distance_to(actor.position)<=8:
                    other.heard_position=target.position
                    other.heard_timer=world.time+6
        return
    if actor.ai_state=="combat":
        clear_movement(actor)
        actor.ai_state="search";actor.ai_until=world.time+6;actor.ai_goal=None
        if actor.memory:actor.heard_position=max(actor.memory.values(),key=lambda v:v[1])[0]
    if actor.ai_state in {"search","investigate"} or actor.heard_timer>world.time:
        if actor.ai_state not in {"search","investigate"}:
            actor.ai_state="investigate";actor.ai_until=actor.heard_timer;actor.ai_goal=None
        deadline=actor.ai_until if actor.ai_state=="search" else actor.heard_timer
        if deadline>world.time and actor.heard_position and zone:
            if actor.ai_goal is None:
                candidates=sorted((c for c in grid.zones[zone].cells if grid.walkable(c)),key=lambda c:(grid.cell_center(c).distance_to(actor.heard_position),c[1],c[0]))
                for cell in candidates:
                    if planner.path(actor,cell,zone=zone,known=False):actor.ai_goal=cell;break
            if actor.ai_goal and enemy_move(world,actor,actor.ai_goal):
                actor.guard_angle=atan2(actor.heard_position.y-actor.position.y,actor.heard_position.x-actor.position.x)
                actor.ai_wait+=.1
                if actor.ai_wait<1:return
            else:return
        actor.ai_state="return";actor.ai_goal=None;actor.ai_wait=0;actor.heard_timer=0
    if actor.patrol:
        target=actor.patrol[actor.patrol_index]
        if enemy_move(world,actor,target):
            actor.ai_wait+=.1
            next_cell=actor.patrol[(actor.patrol_index+1)%len(actor.patrol)]
            actor.guard_angle=atan2(next_cell[1]-target[1],next_cell[0]-target[0])
            if actor.ai_wait>=1:
                actor.patrol_index=(actor.patrol_index+1)%len(actor.patrol);actor.ai_wait=0
        actor.ai_state="patrol"
    elif actor.home_cell:
        if enemy_move(world,actor,actor.home_cell):actor.guard_angle=actor.home_angle
        actor.ai_state="guard"


def enemy_move(world,actor,cell):
    from .commands import ActorCommand,CommandType
    if actor.occupied_cell==cell:return True
    if actor.target_cell!=cell or not actor.route and actor.mode.value=="standing":
        path=world.planner.path(actor,cell,known=False,zone=world.grid.zone_id(world.planner.position_cell(actor)))
        if path:world.apply_command(ActorCommand(actor.id,CommandType.MOVE_TO,"敌方行动",target_cell=cell,path=tuple(path)))
    return False
