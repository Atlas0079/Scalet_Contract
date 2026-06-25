from __future__ import annotations

from .actor import Actor, PeekDirection
from .geometry import Vec2
from .map import GridMap, WallKind


PEEK_OFFSETS: dict[PeekDirection, Vec2] = {
    PeekDirection.N: Vec2(0.0, -0.28),
    PeekDirection.E: Vec2(0.28, 0.0),
    PeekDirection.S: Vec2(0.0, 0.28),
    PeekDirection.W: Vec2(-0.28, 0.0),
}

CORNER_OFFSETS: dict[tuple[PeekDirection, PeekDirection], Vec2] = {
    (PeekDirection.N, PeekDirection.E): Vec2(0.52, -0.52),
    (PeekDirection.N, PeekDirection.W): Vec2(-0.52, -0.52),
    (PeekDirection.S, PeekDirection.E): Vec2(0.52, 0.52),
    (PeekDirection.S, PeekDirection.W): Vec2(-0.52, 0.52),
    (PeekDirection.E, PeekDirection.N): Vec2(0.52, -0.52),
    (PeekDirection.E, PeekDirection.S): Vec2(0.52, 0.52),
    (PeekDirection.W, PeekDirection.N): Vec2(-0.52, -0.52),
    (PeekDirection.W, PeekDirection.S): Vec2(-0.52, 0.52),
}

PEEK_DIRECTIONS = tuple(PeekDirection)


def actor_combat_position(actor: Actor) -> Vec2:
    if actor.peek_direction is None:
        return actor.position
    if actor.peek_cover_direction is not None:
        offset = CORNER_OFFSETS.get((actor.peek_cover_direction, actor.peek_direction))
        if offset is not None:
            return actor.position + offset
    return actor.position + PEEK_OFFSETS[actor.peek_direction]


def combat_position_for(
    actor: Actor,
    peek_direction: PeekDirection | None,
    cover_direction: PeekDirection | None = None,
) -> Vec2:
    if peek_direction is None:
        return actor.position
    if cover_direction is not None:
        offset = CORNER_OFFSETS.get((cover_direction, peek_direction))
        if offset is not None:
            return actor.position + offset
    return actor.position + PEEK_OFFSETS[peek_direction]


def hard_cover_directions(grid: GridMap, cell: tuple[int, int]) -> set[PeekDirection]:
    result: set[PeekDirection] = set()
    for direction in PEEK_DIRECTIONS:
        wall = grid.wall_at(cell, direction.value)
        if wall in (WallKind.FULL, WallKind.DOOR_CLOSED):
            result.add(direction)
    return result


def can_peek_from_cell(grid: GridMap, cell: tuple[int, int], direction: PeekDirection) -> bool:
    covers = hard_cover_directions(grid, cell)
    if direction in (PeekDirection.N, PeekDirection.S):
        return PeekDirection.E in covers or PeekDirection.W in covers
    return PeekDirection.N in covers or PeekDirection.S in covers


def cover_directions_for_peek(
    grid: GridMap,
    cell: tuple[int, int],
    direction: PeekDirection,
) -> list[PeekDirection]:
    covers = hard_cover_directions(grid, cell)
    if direction in (PeekDirection.N, PeekDirection.S):
        return [cover for cover in (PeekDirection.E, PeekDirection.W) if cover in covers]
    return [cover for cover in (PeekDirection.N, PeekDirection.S) if cover in covers]


def clear_actor_peek(actor: Actor) -> None:
    actor.peek_direction = None
    actor.peek_cover_direction = None
