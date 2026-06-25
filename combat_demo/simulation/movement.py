from __future__ import annotations

from .actor import ActionType, Actor, ActorAction, ActorMode, IntentType, InterruptPolicy
from .geometry import rotate_toward
from .map import GridMap
from .pose import clear_actor_peek


def is_moving_between_cells(actor: Actor, grid: GridMap) -> bool:
    return actor.mode == ActorMode.MOVING


def update_actor_movement(actor: Actor, grid: GridMap, actors: list[Actor], dt: float) -> None:
    if actor.mode == ActorMode.STANDING and actor.route:
        clear_actor_peek(actor)
        begin_next_move_step(actor, grid)
    if actor.mode != ActorMode.MOVING:
        if not actor.route:
            actor.target_cell = None
            actor.reserved_cell = None
        return

    if actor.move_from is None or actor.move_to is None:
        stop_actor_at_cell(actor, grid, actor.occupied_cell or grid.cell_of(actor.position))
        return

    if actor.move_to == actor.reserved_cell and actor.move_to in blocked_final_cells(actor, actors, grid):
        replacement = find_available_target(actor, grid, actors, actor.move_to)
        if replacement != actor.move_to:
            set_intent(actor, IntentType.MOVE_TO, "reroute", target_cell=replacement)
            set_path_to(actor, grid, actors, replacement)
        else:
            clear_movement(actor)
            actor.mode = ActorMode.STANDING
            actor.occupied_cell = actor.move_from
            actor.position = grid.cell_center(actor.occupied_cell)
        return

    if grid.can_vault(actor.move_from, actor.move_to):
        actor.current_action = ActorAction(
            ActionType.VAULT_LOW_WALL,
            duration=0.85,
            target_position=grid.cell_center(actor.move_to),
            interrupt_policy=InterruptPolicy.THREAT,
        )
        actor.mode = ActorMode.ACTING
        set_intent(actor, IntentType.ACTION, "vault low wall", target_position=grid.cell_center(actor.move_to))
        actor.aim_error_degrees = actor.max_aim_error_degrees
        return
    if grid.can_open_door(actor.move_from, actor.move_to):
        actor.current_action = ActorAction(
            ActionType.OPEN_DOOR,
            duration=0.65,
            target_position=grid.cell_center(actor.move_to),
            interrupt_policy=InterruptPolicy.THREAT,
        )
        actor.mode = ActorMode.ACTING
        set_intent(actor, IntentType.ACTION, "open door", target_position=grid.cell_center(actor.move_to))
        actor.aim_error_degrees = actor.max_aim_error_degrees
        return

    start = grid.cell_center(actor.move_from)
    end = grid.cell_center(actor.move_to)
    distance = max(0.0001, start.distance_to(end))
    actor.move_progress = min(
        1.0,
        actor.move_progress + actor.speed * crowd_speed_multiplier(actor, actors) * dt / distance,
    )
    actor.position = start + (end - start) * actor.move_progress
    actor.aim_error_degrees = min(
        actor.max_aim_error_degrees,
        actor.aim_error_degrees + actor.move_aim_penalty_degrees_per_second * dt,
    )
    actor.facing = rotate_toward(actor.facing, (end - start).angle(), actor.turn_speed * dt)

    if actor.move_progress < 1.0:
        return

    arrived = actor.move_to
    if actor.route and actor.route[0] == arrived:
        actor.route.pop(0)
    if actor.path and actor.path[0] == arrived:
        actor.path.pop(0)
    if actor.route:
        actor.occupied_cell = None
        actor.move_from = arrived
        actor.move_to = None
        actor.move_progress = 0.0
        begin_next_move_step(actor, grid)
        return
    stop_actor_at_cell(actor, grid, arrived)


def begin_next_move_step(actor: Actor, grid: GridMap) -> None:
    if not actor.route:
        actor.target_cell = None
        actor.reserved_cell = None
        return
    if actor.mode == ActorMode.MOVING and actor.move_to is not None:
        return
    start = actor.occupied_cell or actor.move_from or grid.cell_of(actor.position)
    if actor.route and actor.route[0] == start:
        actor.route.pop(0)
    if actor.path and actor.path[0] == start:
        actor.path.pop(0)
    if not actor.route:
        stop_actor_at_cell(actor, grid, start)
        return
    actor.mode = ActorMode.MOVING
    clear_actor_peek(actor)
    actor.occupied_cell = None
    actor.move_from = start
    actor.move_to = actor.route[0]
    actor.move_progress = 0.0
    actor.position = grid.cell_center(start)


def stop_actor_at_cell(actor: Actor, grid: GridMap, cell: tuple[int, int]) -> None:
    actor.mode = ActorMode.STANDING
    clear_actor_peek(actor)
    actor.occupied_cell = cell
    actor.position = grid.cell_center(cell)
    actor.move_from = None
    actor.move_to = None
    actor.move_progress = 0.0
    clear_movement(actor)


def clear_movement(actor: Actor) -> None:
    actor.route.clear()
    actor.path.clear()
    actor.reserved_cell = None
    actor.target_cell = None


def stationary_occupied_cells(actor: Actor, actors: list[Actor], grid: GridMap) -> set[tuple[int, int]]:
    return {
        other.occupied_cell
        for other in actors
        if other.alive
        and other.id != actor.id
        and other.mode in (ActorMode.STANDING, ActorMode.ACTING)
        and other.occupied_cell is not None
    }


def reserved_target_cells(actor: Actor, actors: list[Actor]) -> set[tuple[int, int]]:
    return {
        other.reserved_cell
        for other in actors
        if other.alive and other.id != actor.id and other.reserved_cell is not None
    }


def blocked_final_cells(actor: Actor, actors: list[Actor], grid: GridMap) -> set[tuple[int, int]]:
    cells = stationary_occupied_cells(actor, actors, grid)
    cells.update(reserved_target_cells(actor, actors))
    return cells


def crowd_speed_multiplier(actor: Actor, actors: list[Actor]) -> float:
    multiplier = 1.0
    for other in actors:
        if not other.alive or other.id == actor.id:
            continue
        distance = actor.position.distance_to(other.position)
        shoulder_room = actor.radius + other.radius + 0.18
        if distance < shoulder_room:
            multiplier = min(multiplier, 0.45)
    return multiplier


def find_available_target(
    actor: Actor,
    grid: GridMap,
    actors: list[Actor],
    desired: tuple[int, int],
) -> tuple[int, int]:
    blocked = blocked_final_cells(actor, actors, grid)
    if grid.in_bounds(desired) and desired not in blocked:
        return desired
    candidates: list[tuple[int, int]] = []
    for radius in range(1, 4):
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                if abs(dx) + abs(dy) != radius:
                    continue
                candidate = (desired[0] + dx, desired[1] + dy)
                if grid.in_bounds(candidate) and candidate not in blocked:
                    candidates.append(candidate)
        if candidates:
            current = grid.cell_of(actor.position)
            return min(candidates, key=lambda cell: abs(cell[0] - current[0]) + abs(cell[1] - current[1]))
    return desired


def reachable_cells_within(
    actor: Actor,
    grid: GridMap,
    actors: list[Actor],
    radius: int,
) -> list[tuple[int, int]]:
    start = actor.occupied_cell or actor.move_to or grid.cell_of(actor.position)
    blocked = blocked_final_cells(actor, actors, grid)
    visited = {start}
    frontier = [(start, 0)]
    result = [start]
    while frontier:
        current, distance = frontier.pop(0)
        if distance >= radius:
            continue
        for neighbor in grid.neighbors(current):
            if neighbor in visited:
                continue
            visited.add(neighbor)
            if neighbor not in blocked:
                result.append(neighbor)
            frontier.append((neighbor, distance + 1))
    return result


def set_path_to(actor: Actor, grid: GridMap, actors: list[Actor], target_cell: tuple[int, int]) -> None:
    current = actor.occupied_cell or actor.move_to or grid.cell_of(actor.position)
    target_cell = find_available_target(actor, grid, actors, target_cell)
    if target_cell in blocked_final_cells(actor, actors, grid):
        actor.route.clear()
        actor.target_cell = None
        actor.reserved_cell = None
        return
    path = grid.find_path(current, target_cell, set(), allow_vault=True, allow_doors=True)
    if path:
        actor.route = path
        actor.path = path.copy()
        actor.target_cell = target_cell
        actor.reserved_cell = target_cell


def set_intent(
    actor: Actor,
    intent_type: IntentType,
    reason: str,
    target_cell: tuple[int, int] | None = None,
    target_position=None,
    target_actor_id: int | None = None,
) -> None:
    from .actor import ActorIntent

    actor.intent = ActorIntent(
        intent_type,
        reason,
        target_cell=target_cell,
        target_position=target_position,
        target_actor_id=target_actor_id,
    )
    actor.intent_reason = actor.intent.label
