from __future__ import annotations

from heapq import heappop, heappush
from math import hypot, inf
from .actor import ActionType, Actor, ActorAction, ActorMode, IntentType, InterruptPolicy
from .geometry import rotate_toward
from .map import GridMap
from .pose import clear_actor_peek


def is_moving_between_cells(actor: Actor, grid: GridMap) -> bool:
    return actor.mode == ActorMode.MOVING


def update_actor_movement(actor: Actor, grid: GridMap, actors: list[Actor], dt: float, *, rotate: bool = True,
                          distance_budget: float | None = None) -> None:
    if not actor.alive or actor.stunned > 0:
        return
    if distance_budget is None:
        distance_budget = movement_allowances(actors, grid, dt)[actor.id]
    if actor.mode == ActorMode.STANDING and actor.route:
        next_cell = next((cell for cell in actor.route if cell != actor.occupied_cell), None)
        if next_cell is None:
            clear_movement(actor)
            return
        if not grid.can_move(actor.occupied_cell, next_cell):
            return
        if next_cell == actor.reserved_cell and next_cell in stationary_occupied_cells(actor, actors, grid):
            return
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

    start = grid.cell_center(actor.move_from)
    end = grid.cell_center(actor.move_to)
    distance = max(0.0001, start.distance_to(end))
    actor.move_progress = min(
        1.0,
        actor.move_progress + distance_budget / distance,
    )
    if actor.move_progress >= 1.0 - 1e-9:
        actor.move_progress = 1.0
    actor.position = start + (end - start) * actor.move_progress
    if distance_budget > 0:
        actor.aim_error_degrees = min(
            actor.max_aim_error_degrees,
            actor.aim_error_degrees + actor.move_aim_penalty_degrees_per_second * dt,
        )
    if rotate:
        actor.facing = rotate_toward(actor.facing, (end - start).angle(), actor.turn_speed * dt)

    if actor.move_progress < 1.0:
        return

    arrived = actor.move_to
    occupied=stationary_occupied_cells(actor,actors,grid)
    if arrived in occupied:
        onward=[c for c in actor.route if c!=arrived]
        if onward and grid.can_move(arrived,onward[0]):
            actor.route=onward;actor.path=list(onward)
            actor.mode=ActorMode.STANDING;actor.occupied_cell=arrived
            actor.move_from=actor.move_to=None;actor.move_progress=0
            begin_next_move_step(actor,grid)
            return
        # Passing through is permitted; a combat stop must never create two
        # stationary bodies at one center and permanently block both rifles.
        forward=(arrived[0]-actor.move_from[0],arrived[1]-actor.move_from[1])
        candidates=[c for c in grid.neighbors(arrived) if c not in occupied
                    and c not in reserved_target_cells(actor,actors)]
        candidates.sort(key=lambda c:(-((c[0]-arrived[0])*forward[0]+(c[1]-arrived[1])*forward[1]),c[1],c[0]))
        if candidates:
            actor.position=grid.cell_center(arrived)
            actor.move_from=arrived;actor.move_to=candidates[0];actor.move_progress=0
            clear_movement(actor)
            return
        actor.move_progress=.95
        actor.position=start+(end-start)*.95
        return
    if actor.route and actor.route[0] == arrived:
        actor.route.pop(0)
    if actor.path and actor.path[0] == arrived:
        actor.path.pop(0)
    actor.mode = ActorMode.STANDING
    actor.occupied_cell = arrived
    actor.position = grid.cell_center(arrived)
    actor.move_from = actor.move_to = None
    actor.move_progress = 0.0
    if not actor.route:
        clear_movement(actor)


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


def _movement_speed(actor: Actor, grid: GridMap, actors: list[Actor]) -> float:
    if not actor.alive or actor.stunned > 0 or actor.current_action is not None:
        return 0.0
    if actor.mode == ActorMode.MOVING:
        if actor.move_from is None or actor.move_to is None:
            return 0.0
    elif actor.mode == ActorMode.STANDING and actor.route:
        target = next((c for c in actor.route if c != actor.occupied_cell), None)
        if target is None or not grid.can_move(actor.occupied_cell, target):
            return 0.0
        if target == actor.reserved_cell and target in stationary_occupied_cells(actor, actors, grid):
            return 0.0
    else:
        return 0.0
    return max(0.0, actor.speed * actor.body.derived_stats().movement_efficiency
               * grid.terrain_speed.get(grid.cell_of(actor.position), 1.0))


def movement_allowances(actors: list[Actor], grid: GridMap, dt: float) -> dict[int, float]:
    """Each overlapping pair slows only its slower mover; ties use actor ID.

    Decide from one snapshot so iteration order cannot slow both members of
    a pair. The 0.45 multiplier lasts another 0.5 simulation seconds after
    overlap ends; repeated contact refreshes it, never stacks it.
    """
    speeds = {a.id: _movement_speed(a, grid, actors) for a in actors}
    slowed_ids = set()
    living = [a for a in actors if a.alive]
    for index, a in enumerate(living):
        for b in living[index+1:]:
            if a.position.distance_to(b.position) >= a.radius + b.radius + .18:
                continue
            cell_a, cell_b = grid.cell_of(a.position), grid.cell_of(b.position)
            if cell_a != cell_b and not grid.can_move(cell_a, cell_b):
                continue
            movers = [unit for unit in (a, b) if speeds[unit.id] > 0]
            if movers:
                # Comparing speed before crowding also separates unequal-speed
                # pairs instead of accidentally reducing the faster to a tie.
                slowed = min(movers, key=lambda unit: (speeds[unit.id], -unit.id))
                slowed_ids.add(slowed.id)
    distances = {}
    dt = max(0.0, dt)
    for a in actors:
        if not a.alive:
            a.crowd_slow_remaining = 0.0
        if a.id in slowed_ids:
            a.crowd_slow_remaining = .5
            slow_time = dt
        else:
            slow_time = min(dt, a.crowd_slow_remaining)
            a.crowd_slow_remaining = max(0.0, a.crowd_slow_remaining - dt)
            if a.crowd_slow_remaining < 1e-9:
                a.crowd_slow_remaining = 0.0
        # Split the final timer step so a large dt cannot prolong the effect.
        distance = speeds[a.id] * (.45 * slow_time + dt - slow_time)
        if a.mode == ActorMode.MOVING and a.move_to is not None:
            distance = min(distance, a.position.distance_to(grid.cell_center(a.move_to)))
        distances[a.id] = distance
    return distances


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
    costs = {start: 0.0}
    frontier = [(0.0, start)]
    result = []
    while frontier:
        distance, current = heappop(frontier)
        if distance > costs[current] + 1e-9:
            continue
        if current == start or current not in blocked:
            result.append(current)
        for neighbor in grid.neighbors(current):
            new_cost = distance + grid.step_cost(current, neighbor)
            if new_cost > radius + 1e-9 or new_cost >= costs.get(neighbor, inf) - 1e-9:
                continue
            costs[neighbor] = new_cost
            heappush(frontier, (new_cost, neighbor))
    return result


def set_path_to(actor: Actor, grid: GridMap, actors: list[Actor], target_cell: tuple[int, int]) -> None:
    current = actor.occupied_cell or actor.move_to or grid.cell_of(actor.position)
    target_cell = find_available_target(actor, grid, actors, target_cell)
    if target_cell in blocked_final_cells(actor, actors, grid):
        actor.route.clear()
        actor.target_cell = None
        actor.reserved_cell = None
        return
    path = grid.find_path(current, target_cell)
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
