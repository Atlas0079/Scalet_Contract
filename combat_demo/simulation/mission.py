"""The authored Greyport mission, shared by simulation, planner and map rendering."""
from __future__ import annotations

from dataclasses import dataclass, field
from math import pi

from .actor import Actor, Team
from .map import (GridMap, MapZone, Interactable, InteractableState, EdgePlacement,
                  create_wall, create_window, create_full_cover, create_door, rect_cells)

RECTS = {
    "S": (1,30,46,34), "R": (25,25,46,29), "C": (25,10,30,24),
    "O": (31,17,46,24), "A": (31,10,46,16), "M": (25,1,30,9),
    "W": (9,10,24,24), "L": (1,25,24,29), "U": (1,10,8,24), "N": (1,1,24,9),
}
LABELS = {"S":"南侧安全区", "R":"接待室", "C":"主走廊", "O":"办公室", "A":"档案室",
          "M":"监控室", "W":"仓库", "L":"装卸间", "U":"维修间", "N":"北侧控制室"}
FURNITURE = {
    "R": ([(33,27,36,27)], []),
    "C": ([], [(25,15,27,15),(28,19,30,19)]),
    "O": ([(37,20,40,20)],[(35,18,35,20)]),
    "A": ([],[(35,11,35,14),(41,12,41,15)]),
    "M": ([(26,3,28,3)],[]),
    "W": ([(12,19,14,19),(20,13,22,13)],[(13,12,14,16),(19,18,20,22)]),
    "L": ([],[(8,27,9,28)]), "U": ([(3,15,4,16)],[]),
    "N": ([(17,5,19,5)],[(10,4,11,7)]),
}
DOORS = [
    ("S_R",(35,30),"N",False), ("S_L",(12,30),"N",False),
    ("L_W",(17,25),"N",False), ("L_U",(4,25),"N",False),
    ("W_C",(24,18),"E",False), ("U_N",(4,10),"N",True),
    ("C_O",(30,21),"E",False), ("O_A",(39,17),"N",False),
    ("A_C",(30,13),"E",True), ("C_M",(27,10),"N",False),
    ("M_N",(24,5),"E",False),
]
SPAWNS = {
    "R": [((39,26),-pi/2)], "C":[((28,12),pi/2),((26,22),-pi/2)],
    "O":[((43,19),pi)], "A":[((39,12),pi/2),((44,15),pi)],
    "M":[((28,6),pi/2)], "W":[((17,14),pi/2),((22,21),pi)],
    "L":[((19,27),-pi/2)], "U":[((5,13),pi/2)], "N":[((7,4),pi/2),((19,7),pi)],
}
COUNTS = {"A":(1,1,1,1,1,2,0,1,2), "B":(0,1,1,1,1,2,1,1,2), "C":(1,2,1,2,1,1,0,0,2)}
PATROLS = {"C":((28,12),(29,17)), "W":((17,14),(17,21)), "N":((7,4),(7,7))}
SEEDS = {"A":7,"B":17,"C":27}


@dataclass(frozen=True)
class Entrance:
    id: str
    a: tuple[int,int]
    b: tuple[int,int]
    zone_a: str
    zone_b: str

    def side(self, target: str):
        return (self.b, self.a) if self.zone_a == target else (self.a, self.b)

    def center(self, grid: GridMap):
        return (grid.cell_center(self.a) + grid.cell_center(self.b)) * .5


@dataclass
class Mission:
    config: str
    entrances: dict[str, Entrance] = field(default_factory=dict)
    room_checked: dict[str, float] = field(default_factory=dict)

    @property
    def rooms(self):
        return [r for r in RECTS if r not in {"S", "C"}]


def create_mission(config: str = "A"):
    from random import Random
    from .world import World
    if config not in COUNTS:
        raise ValueError("配置必须为 A、B 或 C")
    grid = GridMap(48,36)
    for name, rect in RECTS.items():
        zone = MapZone(name, "room" if name not in {"S","C"} else "corridor", rect_cells(*rect), LABELS[name])
        grid.zones[name] = zone
        for cell in zone.cells:
            grid.zone_cells[cell] = name
    for y in range(36):
        for x in range(48):
            cell = (x,y)
            if cell not in grid.zone_cells:
                grid.set_cell_feature(cell, create_full_cover(2.2))
            for direction, delta in [("E",(1,0)),("S",(0,1))]:
                other = x+delta[0], y+delta[1]
                if grid.zone_id(cell) != grid.zone_id(other):
                    grid.set_edge_feature(cell, direction, create_wall(2.2))
    mission = Mission(config)
    for code, cell, direction, locked in DOORS:
        id_ = "door_" + code
        dx,dy = (0,-1) if direction == "N" else (1,0)
        other = cell[0]+dx,cell[1]+dy
        feature = create_door(id_,2.2)
        grid.set_edge_feature(cell,direction,feature)
        grid.add_interactable(Interactable(id_,"door",EdgePlacement(cell,direction), InteractableState.CLOSED,
                                           ("open","kick"),feature.id,{"locked":locked}))
        mission.entrances[id_] = Entrance(id_,cell,other,grid.zone_id(cell),grid.zone_id(other))
    for x in (26,27,28):
        for edge in grid.edge_between((x,25),(x,24)):
            grid.edge_features.pop(edge,None)
    for cell,direction in [((30,23),"E"),((29,10),"N")]:
        grid.set_edge_feature(cell,direction,create_window(1.2))
    for name,(low,high) in FURNITURE.items():
        for rect in low+high:
            for cell in rect_cells(*rect):
                feature = create_full_cover(1.0 if rect in low else 2.2)
                feature.kind = "low_cover" if rect in low else "full_cover"
                feature.blocks_sight = rect in high
                grid.set_cell_feature(cell,feature)
    actors=[]
    for index,(name,x) in enumerate(zip(("先锋","侧翼","支援","后卫"),(33,35,37,39)),1):
        actor=Actor(index,name,Team.RED,grid.cell_center((x,32)),-pi/2)
        actor.occupied_cell=(x,32)
        actor.guard_angle=actor.facing
        actors.append(actor)
    for (zone,spawns),count in zip(SPAWNS.items(),COUNTS[config]):
        for index,(cell,facing) in enumerate(spawns[:count]):
            actor=Actor(101+len(actors)-4,"敌人",Team.BLUE,grid.cell_center(cell),facing)
            actor.occupied_cell=actor.home_cell=cell
            actor.guard_angle=actor.home_angle=facing
            actor.inventory.quantities={}
            actor.weapon.reserve_ammo=60
            actor.ai_enabled=True
            actor.patrol=PATROLS.get(zone,()) if index==0 else ()
            actor.ai_state="patrol" if actor.patrol else "guard"
            actors.append(actor)
    world=World(grid,actors,rng=Random(SEEDS[config]),scenario_name="greyport",mission=mission)
    world.paused=True
    world.perception.refresh(world,0.0,force=True)
    # Containers reuse authored furniture; the briefing case is nonblocking.
    loot=world.loot
    loot.add('case:S','现场补给箱','case',(35,31),[loot.item('rifle',ammo=17),loot.item('bandage',2),loot.item('rifle_ammo',30)])
    for room,cell in [('R',(33,27)),('O',(37,20)),('A',(35,11)),('M',(26,3)),('W',(12,19)),('L',(8,27)),('U',(3,15)),('N',(17,5))]:
        loot.add('cache:'+room,LABELS[room]+'物资柜','container',cell,
                 [loot.item('intel' if room=='A' else 'parts'),loot.item('bandage'),loot.item('rifle_ammo',20)])
    loot.add('drop:S','地面物品','ground',(37,31),[loot.item('flashbang')])
    loot.refresh()
    return world
