from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from math import floor

from .geometry import Vec2


class WallKind(Enum):
    NONE = 0
    LOW = 1
    FULL = 2
    DOOR_CLOSED = 3
    DOOR_OPEN = 4

    @property
    def height(self) -> float:
        if self == WallKind.LOW:
            return 1.0
        if self in (WallKind.FULL, WallKind.DOOR_CLOSED):
            return 2.2
        return 0.0


DIRS: dict[str, tuple[int, int]] = {
    "N": (0, -1),
    "E": (1, 0),
    "S": (0, 1),
    "W": (-1, 0),
}
OPPOSITE = {"N": "S", "S": "N", "E": "W", "W": "E"}


@dataclass
class GridMap:
    width: int
    height: int
    walls: dict[tuple[int, int, str], WallKind] = field(default_factory=dict)

    def in_bounds(self, cell: tuple[int, int]) -> bool:
        x, y = cell
        return 0 <= x < self.width and 0 <= y < self.height

    def cell_center(self, cell: tuple[int, int]) -> Vec2:
        x, y = cell
        return Vec2(x + 0.5, y + 0.5)

    def cell_of(self, pos: Vec2) -> tuple[int, int]:
        return (int(floor(pos.x)), int(floor(pos.y)))

    def set_wall(self, cell: tuple[int, int], direction: str, kind: WallKind) -> None:
        if not self.in_bounds(cell):
            return
        self.walls[(cell[0], cell[1], direction)] = kind
        dx, dy = DIRS[direction]
        other = (cell[0] + dx, cell[1] + dy)
        if self.in_bounds(other):
            self.walls[(other[0], other[1], OPPOSITE[direction])] = kind

    def wall_at(self, cell: tuple[int, int], direction: str) -> WallKind:
        if not self.in_bounds(cell):
            return WallKind.FULL
        return self.walls.get((cell[0], cell[1], direction), WallKind.NONE)

    def can_move(self, a: tuple[int, int], b: tuple[int, int]) -> bool:
        return self.wall_between(a, b) in (WallKind.NONE, WallKind.DOOR_OPEN)

    def wall_between(self, a: tuple[int, int], b: tuple[int, int]) -> WallKind:
        if not self.in_bounds(a) or not self.in_bounds(b):
            return WallKind.FULL
        dx, dy = b[0] - a[0], b[1] - a[1]
        direction = None
        for name, delta in DIRS.items():
            if delta == (dx, dy):
                direction = name
                break
        if direction is None:
            return WallKind.FULL
        return self.wall_at(a, direction)

    def can_vault(self, a: tuple[int, int], b: tuple[int, int]) -> bool:
        return self.wall_between(a, b) == WallKind.LOW

    def can_open_door(self, a: tuple[int, int], b: tuple[int, int]) -> bool:
        return self.wall_between(a, b) == WallKind.DOOR_CLOSED

    def open_door_between(self, a: tuple[int, int], b: tuple[int, int]) -> None:
        if not self.in_bounds(a) or not self.in_bounds(b):
            return
        dx, dy = b[0] - a[0], b[1] - a[1]
        for direction, delta in DIRS.items():
            if delta == (dx, dy):
                self.set_wall(a, direction, WallKind.DOOR_OPEN)
                return

    def neighbors(
        self,
        cell: tuple[int, int],
        allow_vault: bool = False,
        allow_doors: bool = False,
    ) -> list[tuple[int, int]]:
        result = []
        for dx, dy in DIRS.values():
            other = (cell[0] + dx, cell[1] + dy)
            wall = self.wall_between(cell, other)
            if (
                wall in (WallKind.NONE, WallKind.DOOR_OPEN)
                or (allow_vault and wall == WallKind.LOW)
                or (allow_doors and wall == WallKind.DOOR_CLOSED)
            ):
                result.append(other)
        return result

    def find_path(
        self,
        start: tuple[int, int],
        goal: tuple[int, int],
        blocked: set[tuple[int, int]] | None = None,
        allow_vault: bool = False,
        allow_doors: bool = False,
    ) -> list[tuple[int, int]]:
        if start == goal:
            return [start]
        blocked = blocked or set()
        frontier: deque[tuple[int, int]] = deque([start])
        came_from: dict[tuple[int, int], tuple[int, int] | None] = {start: None}
        while frontier:
            current = frontier.popleft()
            for nxt in self.neighbors(current, allow_vault=allow_vault, allow_doors=allow_doors):
                if nxt in came_from or (nxt in blocked and nxt != goal):
                    continue
                came_from[nxt] = current
                if nxt == goal:
                    frontier.clear()
                    break
                frontier.append(nxt)
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
                max_height = max(max_height, self.wall_at(last_cell, direction).height)
            last_cell = cell
        return max_height


def create_demo_map() -> GridMap:
    grid = GridMap(20, 12)
    for x in range(grid.width):
        grid.set_wall((x, 0), "N", WallKind.FULL)
        grid.set_wall((x, grid.height - 1), "S", WallKind.FULL)
    for y in range(grid.height):
        grid.set_wall((0, y), "W", WallKind.FULL)
        grid.set_wall((grid.width - 1, y), "E", WallKind.FULL)

    for y in range(1, 5):
        grid.set_wall((6, y), "E", WallKind.FULL)
    for y in range(7, 11):
        grid.set_wall((13, y), "E", WallKind.FULL)
    for x in range(8, 12):
        grid.set_wall((x, 5), "S", WallKind.LOW)
    for x in range(8, 12):
        grid.set_wall((x, 7), "N", WallKind.LOW)
    for y in range(4, 8):
        grid.set_wall((3, y), "E", WallKind.FULL)
        grid.set_wall((16, y), "W", WallKind.FULL)
    return grid


def create_breach_map() -> GridMap:
    grid = GridMap(16, 12)
    for x in range(grid.width):
        grid.set_wall((x, 0), "N", WallKind.FULL)
        grid.set_wall((x, grid.height - 1), "S", WallKind.FULL)
    for y in range(grid.height):
        grid.set_wall((0, y), "W", WallKind.FULL)
        grid.set_wall((grid.width - 1, y), "E", WallKind.FULL)

    for y in range(2, 10):
        grid.set_wall((5, y), "E", WallKind.FULL)
    grid.set_wall((5, 5), "E", WallKind.DOOR_CLOSED)
    grid.set_wall((5, 7), "E", WallKind.LOW)

    for x in range(8, 11):
        grid.set_wall((x, 4), "S", WallKind.LOW)
    grid.set_wall((9, 7), "E", WallKind.LOW)
    grid.set_wall((11, 6), "S", WallKind.LOW)
    return grid
