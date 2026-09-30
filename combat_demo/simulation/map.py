from __future__ import annotations

from heapq import heappop, heappush
from dataclasses import dataclass, field
from enum import Enum
from math import floor, hypot, inf
from random import Random

from .geometry import Vec2


class PlacementKind(Enum):
    CELL = "cell"
    EDGE = "edge"


class InteractableState(Enum):
    CLOSED = "closed"
    OPEN = "open"
    ON = "on"
    OFF = "off"
    BROKEN = "broken"


DIRS: dict[str, tuple[int, int]] = {
    "N": (0, -1),
    "E": (1, 0),
    "S": (0, 1),
    "W": (-1, 0),
}
OPPOSITE = {"N": "S", "S": "N", "E": "W", "W": "E"}
MOVE_DIRS = ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1))


@dataclass
class EdgePlacement:
    cell: tuple[int, int]
    direction: str

    @property
    def kind(self) -> PlacementKind:
        return PlacementKind.EDGE


@dataclass
class CellPlacement:
    cell: tuple[int, int]

    @property
    def kind(self) -> PlacementKind:
        return PlacementKind.CELL


Placement = EdgePlacement | CellPlacement


@dataclass
class EnvironmentFeature:
    id: str
    kind: str
    placement: Placement
    height: float
    blocks_movement: bool = False
    blocks_sight: bool = False
    blocks_projectile: bool = False
    cover_value: float = 0.0
    interactive_id: str | None = None
    tags: set[str] = field(default_factory=set)


@dataclass
class Interactable:
    id: str
    kind: str
    placement: Placement
    state: InteractableState
    actions: tuple[str, ...]
    target_feature_id: str | None = None
    properties: dict[str, object] = field(default_factory=dict)


@dataclass(frozen=True)
class MapZone:
    id: str
    kind: str
    cells: tuple[tuple[int, int], ...]
    label: str = ""

    @property
    def center_cell(self) -> tuple[int, int]:
        if not self.cells:
            return (0, 0)
        x = round(sum(cell[0] for cell in self.cells) / len(self.cells))
        y = round(sum(cell[1] for cell in self.cells) / len(self.cells))
        return (x, y)


@dataclass(frozen=True)
class MazeMapData:
    rooms: tuple[MapZone, ...]
    corridors: tuple[MapZone, ...]
    extraction_cell: tuple[int, int]

    def zone_for_cell(self, cell: tuple[int, int]) -> MapZone | None:
        for zone in self.rooms + self.corridors:
            if cell in zone.cells:
                return zone
        return None


@dataclass
class GridMap:
    width: int
    height: int
    edge_features: dict[tuple[int, int, str], EnvironmentFeature] = field(default_factory=dict)
    cell_features: dict[tuple[int, int], EnvironmentFeature] = field(default_factory=dict)
    interactables: dict[str, Interactable] = field(default_factory=dict)
    maze_data: MazeMapData | None = None
    _next_id: int = 0
    zones: dict[str, MapZone] = field(default_factory=dict)
    zone_cells: dict[tuple[int, int], str] = field(default_factory=dict)
    revision: int = 0
    _path_cache: dict = field(default_factory=dict)
    terrain_speed: dict[tuple[int, int], float] = field(default_factory=dict)

    def _make_id(self, prefix: str) -> str:
        self._next_id += 1
        return f"{prefix}_{self._next_id}"

    def in_bounds(self, cell: tuple[int, int]) -> bool:
        x, y = cell
        return 0 <= x < self.width and 0 <= y < self.height

    def cell_center(self, cell: tuple[int, int]) -> Vec2:
        x, y = cell
        return Vec2(x + 0.5, y + 0.5)

    def cell_of(self, pos: Vec2) -> tuple[int, int]:
        return (int(floor(pos.x)), int(floor(pos.y)))

    def _edge_key(self, cell: tuple[int, int], direction: str) -> tuple[int, int, str]:
        return (cell[0], cell[1], direction)

    def edge_between(self, a: tuple[int, int], b: tuple[int, int]) -> tuple[tuple[int, int, str], tuple[int, int, str]] | None:
        if not self.in_bounds(a) or not self.in_bounds(b):
            return None
        dx, dy = b[0] - a[0], b[1] - a[1]
        for direction, delta in DIRS.items():
            if delta == (dx, dy):
                return self._edge_key(a, direction), self._edge_key(b, OPPOSITE[direction])
        return None

    def set_edge_feature(
        self,
        cell: tuple[int, int],
        direction: str,
        feature: EnvironmentFeature,
    ) -> None:
        if not self.in_bounds(cell):
            return
        feature.id = f"{feature.kind}:{cell[0]}:{cell[1]}:{direction}"
        feature.placement = EdgePlacement(cell, direction)
        key = self._edge_key(cell, direction)
        self.edge_features[key] = feature
        self.revision += 1
        self._path_cache.clear()
        dx, dy = DIRS[direction]
        other = (cell[0] + dx, cell[1] + dy)
        if self.in_bounds(other):
            self.edge_features[self._edge_key(other, OPPOSITE[direction])] = feature

    def set_cell_feature(self, cell: tuple[int, int], feature: EnvironmentFeature) -> None:
        if not self.in_bounds(cell):
            return
        feature.id = f"{feature.kind}:{cell[0]}:{cell[1]}"
        feature.placement = CellPlacement(cell)
        self.cell_features[cell] = feature
        self.revision += 1
        self._path_cache.clear()

    def add_interactable(self, interactable: Interactable) -> None:
        self.interactables[interactable.id] = interactable

    def edge_feature_at(self, cell: tuple[int, int], direction: str) -> EnvironmentFeature | None:
        if not self.in_bounds(cell):
            return EnvironmentFeature(
                id="boundary",
                kind="boundary",
                placement=EdgePlacement(cell, direction),
                height=3.0,
                blocks_movement=True,
                blocks_sight=True,
                blocks_projectile=True,
                tags={"boundary"},
            )
        return self.edge_features.get(self._edge_key(cell, direction))

    def edge_feature_between(self, a: tuple[int, int], b: tuple[int, int]) -> EnvironmentFeature | None:
        edge = self.edge_between(a, b)
        if edge is None:
            return EnvironmentFeature(
                id="boundary",
                kind="boundary",
                placement=EdgePlacement(a, "N"),
                height=3.0,
                blocks_movement=True,
                blocks_sight=True,
                blocks_projectile=True,
                tags={"boundary"},
            )
        return self.edge_features.get(edge[0]) or self.edge_features.get(edge[1])

    def cell_feature_at(self, cell: tuple[int, int]) -> EnvironmentFeature | None:
        return self.cell_features.get(cell)

    def wall_at(self, cell: tuple[int, int], direction: str) -> EnvironmentFeature:
        return self.edge_feature_at(cell, direction) or EnvironmentFeature(
            id="empty",
            kind="empty",
            placement=EdgePlacement(cell, direction),
            height=0.0,
        )

    def wall_between(self, a: tuple[int, int], b: tuple[int, int]) -> EnvironmentFeature:
        return self.edge_feature_between(a, b) or EnvironmentFeature(
            id="empty",
            kind="empty",
            placement=CellPlacement(a),
            height=0.0,
        )

    def can_move(self, a: tuple[int, int], b: tuple[int, int], *,
                 allow_vault=False, allow_doors=False, known_doors=None) -> bool:
        dx, dy = b[0] - a[0], b[1] - a[1]
        if (dx, dy) not in MOVE_DIRS or not self.in_bounds(a) or not self.walkable(b):
            return False
        if dx and dy:
            horizontal, vertical = (b[0], a[1]), (a[0], b[1])
            # One clear side permits corner cutting; two blocked sides do not.
            # Vaulting/opening is a cardinal interaction, never a diagonal hop.
            return any(self.walkable(side)
                       and self.can_move(a, side, known_doors=known_doors)
                       and self.can_move(side, b, known_doors=known_doors)
                       for side in (horizontal, vertical))
        edge = self.edge_feature_between(a, b)
        if edge and edge.interactive_id and known_doors is not None:
            if known_doors.get(edge.interactive_id) not in {"open", "broken"}:
                return False
        return (edge is None or not edge.blocks_movement
                or (allow_vault and edge.height <= 1.25)
                or (allow_doors and edge.interactive_id is not None))

    def step_cost(self, a, b):
        return hypot(b[0]-a[0], b[1]-a[1]) * (.5/self.terrain_speed.get(a, 1.0) + .5/self.terrain_speed.get(b, 1.0))

    def path_cost(self, path: list[tuple[int, int]]) -> float:
        if not path:
            return inf
        return sum(self.step_cost(a, b) for a, b in zip(path, path[1:]))

    def can_vault(self, a: tuple[int, int], b: tuple[int, int]) -> bool:
        edge = self.edge_feature_between(a, b)
        return bool(edge is not None and edge.blocks_movement and edge.height <= 1.25)

    def can_open_interactable(self, a: tuple[int, int], b: tuple[int, int]) -> bool:
        edge = self.edge_feature_between(a, b)
        if edge is None or edge.interactive_id is None:
            return False
        interactable = self.interactables.get(edge.interactive_id)
        return bool(interactable is not None and interactable.kind == "door" and interactable.state == InteractableState.CLOSED)

    def open_interactable_between(self, a: tuple[int, int], b: tuple[int, int]) -> None:
        edge = self.edge_feature_between(a, b)
        if edge is None or edge.interactive_id is None:
            return
        interactable = self.interactables.get(edge.interactive_id)
        if interactable is None or interactable.kind != "door":
            return
        interactable.state = InteractableState.OPEN
        edge.blocks_movement = False
        edge.blocks_sight = False
        edge.blocks_projectile = False
        edge.height = 0.0
        edge.tags.add("open")
        self.revision += 1

    def zone_id(self, cell: tuple[int, int]) -> str | None:
        return self.zone_cells.get(cell)

    def walkable(self, cell: tuple[int, int]) -> bool:
        feature = self.cell_feature_at(cell)
        return self.in_bounds(cell) and not (feature and feature.blocks_movement)

    def ray_features(self, start: Vec2, end: Vec2):
        """Traverse crossed grid edges/cells, emitting exact normalized distances."""
        dx, dy = end.x - start.x, end.y - start.y
        x, y = self.cell_of(start)
        sx, sy = (1 if dx >= 0 else -1), (1 if dy >= 0 else -1)
        tx = ((x + 1 if sx > 0 else x) - start.x) / dx if dx else inf
        ty = ((y + 1 if sy > 0 else y) - start.y) / dy if dy else inf
        stepx, stepy = abs(1 / dx) if dx else inf, abs(1 / dy) if dy else inf
        seen: set[str] = set()
        feature = self.cell_features.get((x, y))
        if feature:
            seen.add(feature.id)
            yield 0.0, feature
        while min(tx, ty) <= 1.0:
            t = max(0.0, min(tx, ty))
            crossx, crossy = tx <= ty + 1e-10, ty <= tx + 1e-10
            directions = (["E" if sx > 0 else "W"] if crossx else []) + (["S" if sy > 0 else "N"] if crossy else [])
            for direction in directions:
                feature = self.edge_feature_at((x, y), direction)
                if feature and feature.id not in seen:
                    seen.add(feature.id)
                    yield t, feature
            if crossx:
                x += sx
                tx += stepx
            if crossy:
                y += sy
                ty += stepy
            if not self.in_bounds((x, y)):
                return
            feature = self.cell_features.get((x, y))
            if feature and feature.id not in seen:
                seen.add(feature.id)
                yield t, feature

    def raycast(self, start: Vec2, end: Vec2, start_height: float = 1.65,
                end_height: float = 1.65, kind: str = "sight") -> tuple[float, EnvironmentFeature | None]:
        for t, feature in self.ray_features(start, end):
            height = start_height + (end_height - start_height) * t
            flag = feature.blocks_sight if kind == "sight" else feature.blocks_projectile
            if kind == "flash":
                flag = feature.blocks_projectile and feature.height >= 2.0
            if flag and (kind == "flash" or height <= feature.height or feature.kind == "window" and height >= 2.2):
                return t, feature
        return 1.0, None

    def neighbors(
        self,
        cell: tuple[int, int],
        allow_vault: bool = False,
        allow_doors: bool = False,
        known_doors: dict[str, str] | None = None,
    ) -> list[tuple[int, int]]:
        result = []
        for dx, dy in MOVE_DIRS:
            other = (cell[0] + dx, cell[1] + dy)
            if self.can_move(cell, other, allow_vault=allow_vault,
                             allow_doors=allow_doors, known_doors=known_doors):
                result.append(other)
        return result

    def find_path(self, start, goal, blocked=None, allow_vault=False, allow_doors=False,
                  allowed_cells=None, known_doors=None):
        key=(self.revision,start,goal,frozenset(blocked or ()),allow_vault,allow_doors,
             None if allowed_cells is None else frozenset(allowed_cells),
             None if known_doors is None else tuple(sorted(known_doors.items())))
        if key not in self._path_cache:
            if len(self._path_cache)>=2048:self._path_cache.clear()
            self._path_cache[key]=tuple(self._find_path(start,goal,blocked,allow_vault,allow_doors,allowed_cells,known_doors))
        return list(self._path_cache[key])

    def _find_path(
        self,
        start: tuple[int, int],
        goal: tuple[int, int],
        blocked: set[tuple[int, int]] | None = None,
        allow_vault: bool = False,
        allow_doors: bool = False,
        allowed_cells: set[tuple[int, int]] | None = None,
        known_doors: dict[str, str] | None = None,
    ) -> list[tuple[int, int]]:
        if not self.in_bounds(start) or not self.walkable(goal):
            return []
        if allowed_cells is not None and (start not in allowed_cells or goal not in allowed_cells):
            return []
        if start == goal:
            return [start]
        blocked = blocked or set()
        frontier = [(hypot(goal[0]-start[0], goal[1]-start[1]), 0.0, start[1], start[0])]
        costs = {start: 0.0}
        came_from: dict[tuple[int, int], tuple[int, int] | None] = {start: None}
        while frontier:
            _, cost, y, x = heappop(frontier)
            current = (x, y)
            if cost > costs[current] + 1e-9:
                continue
            if current == goal:
                break
            for nxt in self.neighbors(current, allow_vault=allow_vault, allow_doors=allow_doors,
                                      known_doors=known_doors):
                if allowed_cells is not None and nxt not in allowed_cells:
                    continue
                if current[0] != nxt[0] and current[1] != nxt[1]:
                    sides = ((nxt[0], current[1]), (current[0], nxt[1]))
                    # The physically clear side must also satisfy the path's
                    # region/obstruction restrictions (not the opposite side).
                    if not any(c not in blocked and (allowed_cells is None or c in allowed_cells)
                               and self.walkable(c)
                               and self.can_move(current, c, known_doors=known_doors)
                               and self.can_move(c, nxt, known_doors=known_doors) for c in sides):
                        continue
                if nxt in blocked and nxt != goal:
                    continue
                new_cost = cost + self.step_cost(current, nxt)
                if new_cost >= costs.get(nxt, inf) - 1e-9:
                    continue
                costs[nxt] = new_cost
                came_from[nxt] = current
                heappush(frontier, (new_cost + hypot(goal[0]-nxt[0], goal[1]-nxt[1]),
                                    new_cost, nxt[1], nxt[0]))
        if goal not in came_from:
            return []
        path = [goal]
        current = goal
        while came_from[current] is not None:
            current = came_from[current]  # type: ignore[assignment]
            path.append(current)
        path.reverse()
        return path

    def ray_wall_height(self, start: Vec2, end: Vec2, step: float = 0.04) -> float:
        distance = start.distance_to(end)
        if distance <= 0.00001:
            return 0.0
        samples = max(1, int(distance / step))
        last_cell = self.cell_of(start)
        max_height = 0.0
        for i in range(1, samples + 1):
            t = i / samples
            pos = Vec2(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t)
            cell = self.cell_of(pos)
            if cell == last_cell:
                feature = self.cell_feature_at(cell)
                if feature is not None and feature.blocks_projectile:
                    max_height = max(max_height, feature.height)
                continue
            dx = cell[0] - last_cell[0]
            dy = cell[1] - last_cell[1]
            crossed = []
            if dx == 1:
                crossed.append("E")
            elif dx == -1:
                crossed.append("W")
            if dy == 1:
                crossed.append("S")
            elif dy == -1:
                crossed.append("N")
            for direction in crossed:
                feature = self.edge_feature_at(last_cell, direction)
                if feature is not None and feature.blocks_projectile:
                    max_height = max(max_height, feature.height)
            feature = self.cell_feature_at(cell)
            if feature is not None and feature.blocks_projectile:
                max_height = max(max_height, feature.height)
            last_cell = cell
        return max_height


def edge_feature(
    kind: str,
    height: float,
    blocks_movement: bool,
    blocks_sight: bool,
    blocks_projectile: bool,
    interactive_id: str | None = None,
    cover_value: float = 0.0,
) -> EnvironmentFeature:
    return EnvironmentFeature(
        id=kind,
        kind=kind,
        placement=EdgePlacement((0, 0), "N"),
        height=height,
        blocks_movement=blocks_movement,
        blocks_sight=blocks_sight,
        blocks_projectile=blocks_projectile,
        interactive_id=interactive_id,
        cover_value=cover_value,
    )


def cell_feature(
    kind: str,
    height: float,
    blocks_movement: bool,
    blocks_sight: bool,
    blocks_projectile: bool,
    cover_value: float = 0.0,
) -> EnvironmentFeature:
    return EnvironmentFeature(
        id=kind,
        kind=kind,
        placement=CellPlacement((0, 0)),
        height=height,
        blocks_movement=blocks_movement,
        blocks_sight=blocks_sight,
        blocks_projectile=blocks_projectile,
        cover_value=cover_value,
    )


def create_boundary_edge() -> EnvironmentFeature:
    return edge_feature("boundary", 3.0, True, True, True)


def create_wall(height: float, kind: str = "wall") -> EnvironmentFeature:
    return edge_feature(kind, height, True, True, True)


def create_window(height: float = 1.2) -> EnvironmentFeature:
    return edge_feature("window", height, True, False, False)


def create_low_cover(height: float = 1.0) -> EnvironmentFeature:
    return edge_feature("low_cover", height, True, False, True, cover_value=0.45)


def create_full_cover(height: float = 1.8) -> EnvironmentFeature:
    return cell_feature("full_cover", height, True, True, True, cover_value=0.95)


def create_door(interactable_id: str | None = None, height: float = 2.2) -> EnvironmentFeature:
    return edge_feature("door", height, True, True, True, interactive_id=interactable_id)


def create_switch(cell: tuple[int, int], target_feature_id: str | None = None) -> Interactable:
    return Interactable(
        id=f"switch_{cell[0]}_{cell[1]}",
        kind="switch",
        placement=CellPlacement(cell),
        state=InteractableState.OFF,
        actions=("toggle",),
        target_feature_id=target_feature_id,
    )


def create_door_interactable(cell: tuple[int, int], direction: str, target_feature_id: str) -> Interactable:
    return Interactable(
        id=f"door_{cell[0]}_{cell[1]}_{direction}",
        kind="door",
        placement=EdgePlacement(cell, direction),
        state=InteractableState.CLOSED,
        actions=("open", "close"),
        target_feature_id=target_feature_id,
    )


def create_demo_map() -> GridMap:
    grid = GridMap(20, 12)
    for x in range(grid.width):
        grid.set_edge_feature((x, 0), "N", create_boundary_edge())
        grid.set_edge_feature((x, grid.height - 1), "S", create_boundary_edge())
    for y in range(grid.height):
        grid.set_edge_feature((0, y), "W", create_boundary_edge())
        grid.set_edge_feature((grid.width - 1, y), "E", create_boundary_edge())

    for y in range(1, 5):
        grid.set_edge_feature((6, y), "E", create_wall(2.2))
    for y in range(7, 11):
        grid.set_edge_feature((13, y), "E", create_wall(2.2))
    for x in range(8, 12):
        grid.set_edge_feature((x, 5), "S", create_low_cover())
    for x in range(8, 12):
        grid.set_edge_feature((x, 7), "N", create_low_cover())
    for y in range(4, 8):
        grid.set_edge_feature((3, y), "E", create_wall(2.2))
        grid.set_edge_feature((16, y), "W", create_wall(2.2))

    grid.set_cell_feature((10, 6), create_full_cover(1.9))
    grid.set_cell_feature((11, 6), create_full_cover(1.9))
    return grid


def create_breach_map() -> GridMap:
    grid = GridMap(16, 12)
    for x in range(grid.width):
        grid.set_edge_feature((x, 0), "N", create_boundary_edge())
        grid.set_edge_feature((x, grid.height - 1), "S", create_boundary_edge())
    for y in range(grid.height):
        grid.set_edge_feature((0, y), "W", create_boundary_edge())
        grid.set_edge_feature((grid.width - 1, y), "E", create_boundary_edge())

    for y in range(2, 10):
        grid.set_edge_feature((5, y), "E", create_wall(2.2))
    door_edge = create_door(height=2.2)
    grid.set_edge_feature((5, 5), "E", door_edge)
    door_interactable = create_door_interactable((5, 5), "E", door_edge.id)
    door_edge.interactive_id = door_interactable.id
    grid.add_interactable(door_interactable)

    grid.set_edge_feature((5, 7), "E", create_window(1.15))

    for x in range(8, 11):
        grid.set_edge_feature((x, 4), "S", create_low_cover(1.0))
    grid.set_edge_feature((9, 7), "E", create_low_cover(1.0))
    grid.set_edge_feature((11, 6), "S", create_low_cover(1.0))

    grid.set_cell_feature((9, 5), create_full_cover(1.8))
    grid.set_cell_feature((10, 5), create_full_cover(1.8))
    return grid


def rect_cells(x1: int, y1: int, x2: int, y2: int) -> tuple[tuple[int, int], ...]:
    return tuple((x, y) for y in range(y1, y2 + 1) for x in range(x1, x2 + 1))


def create_maze_map() -> GridMap:
    rng = Random(23)
    room_w = 9
    room_h = 7
    gap_x = 5
    gap_y = 5
    margin = 1
    grid = GridMap(margin * 2 + room_w * 3 + gap_x * 2, margin * 2 + room_h * 3 + gap_y * 2)
    for x in range(grid.width):
        grid.set_edge_feature((x, 0), "N", create_boundary_edge())
        grid.set_edge_feature((x, grid.height - 1), "S", create_boundary_edge())
    for y in range(grid.height):
        grid.set_edge_feature((0, y), "W", create_boundary_edge())
        grid.set_edge_feature((grid.width - 1, y), "E", create_boundary_edge())

    rooms = tuple(
        MapZone(
            id=f"room_{row}_{col}",
            kind="room",
            cells=rect_cells(
                margin + col * (room_w + gap_x),
                margin + row * (room_h + gap_y),
                margin + col * (room_w + gap_x) + room_w - 1,
                margin + row * (room_h + gap_y) + room_h - 1,
            ),
            label=f"room {row + 1}-{col + 1}",
        )
        for row in range(3)
        for col in range(3)
    )
    room_by_grid = {(index // 3, index % 3): room for index, room in enumerate(rooms)}
    corridors: list[MapZone] = []
    connections = connected_room_edges(rng)
    for edge_index, (a, b) in enumerate(connections):
        corridor_width = rng.randint(3, 5)
        corridor_cells = corridor_between(room_by_grid[a], room_by_grid[b], corridor_width)
        corridors.append(MapZone(f"corridor_{edge_index}", "corridor", tuple(corridor_cells), f"corridor {edge_index}"))

    open_cells = set()
    for zone in rooms + tuple(corridors):
        open_cells.update(zone.cells)

    for x in range(grid.width):
        for y in range(grid.height):
            cell = (x, y)
            for direction, (dx, dy) in DIRS.items():
                other = (x + dx, y + dy)
                if not grid.in_bounds(other):
                    continue
                if cell in open_cells and other in open_cells:
                    continue
                if cell in open_cells or other in open_cells:
                    grid.set_edge_feature(cell, direction, create_wall(2.2))

    for room in rooms:
        cover_candidates = [cell for cell in room.cells if cell != room.center_cell]
        rng.shuffle(cover_candidates)
        for cell in cover_candidates[: rng.randint(3, 5)]:
            grid.set_cell_feature(cell, create_full_cover(rng.choice((1.35, 1.55, 1.75))))

    grid.maze_data = MazeMapData(
        rooms=rooms,
        corridors=tuple(corridors),
        extraction_cell=room_by_grid[(2, 2)].center_cell,
    )
    return grid


def connected_room_edges(rng: Random) -> list[tuple[tuple[int, int], tuple[int, int]]]:
    all_edges: list[tuple[tuple[int, int], tuple[int, int]]] = []
    for row in range(3):
        for col in range(3):
            if col < 2:
                all_edges.append(((row, col), (row, col + 1)))
            if row < 2:
                all_edges.append(((row, col), (row + 1, col)))
    remaining = all_edges.copy()
    rng.shuffle(remaining)
    parent = {(row, col): (row, col) for row in range(3) for col in range(3)}

    def find(cell: tuple[int, int]) -> tuple[int, int]:
        while parent[cell] != cell:
            parent[cell] = parent[parent[cell]]
            cell = parent[cell]
        return cell

    def union(a: tuple[int, int], b: tuple[int, int]) -> bool:
        root_a = find(a)
        root_b = find(b)
        if root_a == root_b:
            return False
        parent[root_b] = root_a
        return True

    selected: list[tuple[tuple[int, int], tuple[int, int]]] = []
    for a, b in remaining:
        if union(a, b):
            selected.append((a, b))
    extra_edges = [edge for edge in all_edges if edge not in selected and (edge[1], edge[0]) not in selected]
    rng.shuffle(extra_edges)
    selected.extend(extra_edges[: rng.randint(2, 4)])
    return selected


def corridor_between(a: MapZone, b: MapZone, width: int) -> list[tuple[int, int]]:
    ax, ay = a.center_cell
    bx, by = b.center_cell
    cells: set[tuple[int, int]] = set()
    half_low = (width - 1) // 2
    half_high = width // 2
    if ax != bx:
        start = min(ax, bx)
        end = max(ax, bx)
        for x in range(start, end + 1):
            for offset in range(-half_low, half_high + 1):
                cells.add((x, ay + offset))
    else:
        start = min(ay, by)
        end = max(ay, by)
        for y in range(start, end + 1):
            for offset in range(-half_low, half_high + 1):
                cells.add((ax + offset, y))
    return sorted(cells, key=lambda cell: (cell[1], cell[0]))
