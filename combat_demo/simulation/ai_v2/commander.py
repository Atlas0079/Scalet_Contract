from __future__ import annotations

from .orders import BreachMemory, BreachStage, OrderType, SquadOrder
from ..actor import ActionType, Actor, ActorMode, ActorRole, IntentType, Team
from ..ai import can_see
from ..commands import ActorCommand, CommandType
from ..geometry import Vec2, angle_to, rotate_toward
from ..map import GridMap, WallKind
from ..movement import blocked_final_cells
from ..world_commands import set_intent


def update_breach_ai(
    actor: Actor,
    actors: list[Actor],
    grid: GridMap,
    memory: BreachMemory,
    dt: float,
) -> ActorCommand | None:
    team = Team(memory.plan.team)
    if actor.team != team:
        return update_training_defender(actor, actors, grid, memory, dt)

    update_breach_stage(actors, grid, memory, dt)
    order = order_for_actor(actor, actors, grid, memory)
    return command_for_order(actor, actors, grid, memory, order, dt)


def update_breach_stage(actors: list[Actor], grid: GridMap, memory: BreachMemory, dt: float) -> None:
    memory.stage_timer += dt
    plan = memory.plan
    breachers = [actor for actor in actors if actor.alive and actor.team.value == plan.team]
    if not breachers:
        return
    inside_count = sum(1 for actor in breachers if cell_of_actor(actor, grid) in plan.room_cells)
    support_count = sum(
        1
        for actor in breachers
        if cell_of_actor(actor, grid) in plan.room_cells or cell_of_actor(actor, grid) == plan.window_outside
    )
    stacked_count = sum(1 for actor in breachers if cell_of_actor(actor, grid) in plan.stack_cells)
    door_open = grid.wall_between(plan.door_outside, plan.door_inside) == WallKind.DOOR_OPEN
    enemies_alive = any(actor.alive and actor.team.value != plan.team for actor in actors)

    next_stage = memory.stage
    if memory.stage == BreachStage.STACK and (stacked_count >= min(2, len(breachers)) or memory.stage_timer > 2.0):
        next_stage = BreachStage.OPEN_DOOR
    elif memory.stage == BreachStage.OPEN_DOOR and door_open:
        next_stage = BreachStage.BREACH
    elif memory.stage == BreachStage.BREACH and inside_count >= 1 and support_count >= min(2, len(breachers)):
        next_stage = BreachStage.CLEAR
    elif memory.stage == BreachStage.CLEAR and (inside_count >= len(breachers) or not enemies_alive):
        next_stage = BreachStage.STABILIZE

    if next_stage != memory.stage:
        memory.stage = next_stage
        memory.stage_timer = 0.0


def order_for_actor(
    actor: Actor,
    actors: list[Actor],
    grid: GridMap,
    memory: BreachMemory,
) -> SquadOrder:
    badly_wounded = actor.body.hp["head"] < 22.0 or actor.body.hp["thorax"] < 45.0
    if actor.suppression > 75.0 or badly_wounded:
        return self_preserve_order(actor, actors, grid, memory)

    plan = memory.plan
    breachers = sorted(
        [other for other in actors if other.alive and other.team == actor.team],
        key=lambda other: role_priority(other),
    )
    index = breachers.index(actor) if actor in breachers else 0
    visible_enemy = nearest_visible_enemy(actor, actors, grid)
    actor_cell = cell_of_actor(actor, grid)
    can_break_to_engage = (
        memory.stage in (BreachStage.CLEAR, BreachStage.STABILIZE)
        or (memory.stage == BreachStage.BREACH and actor.role == ActorRole.SUPPORT and actor_cell == plan.window_outside)
    )
    if visible_enemy is not None and can_break_to_engage:
        return SquadOrder(
            actor.id,
            OrderType.ENGAGE,
            f"v2 engage during {memory.stage.value}",
            target_position=visible_enemy.position,
            target_actor_id=visible_enemy.id,
        )

    if memory.stage == BreachStage.STACK:
        target = plan.stack_cells[min(index, len(plan.stack_cells) - 1)]
        return SquadOrder(actor.id, OrderType.STACK, f"v2 stack {index + 1}", target_cell=target, target_position=plan.focus)

    if memory.stage == BreachStage.OPEN_DOOR:
        if index == 0:
            return SquadOrder(
                actor.id,
                OrderType.OPEN_DOOR,
                "v2 open breach door",
                target_cell=plan.door_outside,
                target_position=grid.cell_center(plan.door_inside),
            )
        if index == 2:
            return SquadOrder(
                actor.id,
                OrderType.COVER_OPENING,
                "v2 cover window",
                target_cell=plan.window_outside,
                target_position=plan.focus,
            )
        return SquadOrder(actor.id, OrderType.COVER_OPENING, "v2 cover door", target_cell=plan.stack_cells[1], target_position=plan.focus)

    if memory.stage == BreachStage.BREACH:
        if index == 2:
            return SquadOrder(actor.id, OrderType.COVER_OPENING, "v2 window overwatch", target_cell=plan.window_outside, target_position=plan.focus)
        target_index = 0 if not breachers[0].alive and index == 1 else min(index, len(plan.entry_cells) - 1)
        target = plan.entry_cells[target_index]
        return SquadOrder(actor.id, OrderType.ENTER_ROOM, f"v2 enter room {index + 1}", target_cell=target, target_position=plan.focus)

    cover_index = min(index, len(plan.room_cover_cells) - 1)
    return SquadOrder(
        actor.id,
        OrderType.MOVE_TO_COVER,
        f"v2 clear to cover {cover_index + 1}",
        target_cell=plan.room_cover_cells[cover_index],
        target_position=plan.focus,
    )


def command_for_order(
    actor: Actor,
    actors: list[Actor],
    grid: GridMap,
    memory: BreachMemory,
    order: SquadOrder,
    dt: float,
) -> ActorCommand | None:
    if actor.current_action is not None:
        set_intent(actor, IntentType.ACTION, f"v2 continuing {actor.current_action.type.value}")
        return None

    if order.type == OrderType.ENGAGE and order.target_actor_id is not None:
        return ActorCommand(
            actor.id,
            CommandType.ENGAGE,
            order.reason,
            target_position=order.target_position,
            target_actor_id=order.target_actor_id,
        )

    if order.type == OrderType.OPEN_DOOR:
        if actor.mode != ActorMode.STANDING or actor.occupied_cell != order.target_cell:
            return move_order(actor, order)
        if grid.wall_between(memory.plan.door_outside, memory.plan.door_inside) == WallKind.DOOR_CLOSED:
            return ActorCommand(
                actor.id,
                CommandType.START_ACTION,
                order.reason,
                target_position=grid.cell_center(memory.plan.door_inside),
                action_type=ActionType.OPEN_DOOR,
                duration=0.65,
            )
        return hold_order(actor, order)

    if order.type in (OrderType.STACK, OrderType.ENTER_ROOM, OrderType.MOVE_TO_COVER):
        if order.target_cell is not None and not is_standing_at(actor, order.target_cell):
            return move_order(actor, order)
        return hold_order(actor, order)

    if order.type in (OrderType.COVER_OPENING, OrderType.HOLD, OrderType.SELF_PRESERVE):
        if order.target_cell is not None and not is_standing_at(actor, order.target_cell):
            blocked = blocked_final_cells(actor, actors, grid)
            if order.target_cell not in blocked:
                return move_order(actor, order)
        return hold_order(actor, order)

    return None


def update_training_defender(
    actor: Actor,
    actors: list[Actor],
    grid: GridMap,
    memory: BreachMemory,
    dt: float,
) -> ActorCommand | None:
    if (
        memory.stage in (BreachStage.STACK, BreachStage.OPEN_DOOR)
        and actor.under_fire_timer <= 0.0
        and grid.wall_between(memory.plan.door_outside, memory.plan.door_inside) != WallKind.DOOR_OPEN
    ):
        actor.facing = rotate_toward(actor.facing, angle_to(actor.position, grid.cell_center(memory.plan.door_inside)), actor.turn_speed * dt)
        set_intent(actor, IntentType.HOLD_POSITION, "v2 training idle", target_position=memory.plan.focus)
        return None
    if memory.stage == BreachStage.BREACH and memory.stage_timer < 1.2 and actor.under_fire_timer <= 0.0:
        actor.facing = rotate_toward(actor.facing, angle_to(actor.position, grid.cell_center(memory.plan.door_inside)), actor.turn_speed * dt)
        set_intent(actor, IntentType.HOLD_POSITION, "v2 defender startled", target_position=memory.plan.focus)
        return None

    visible = nearest_visible_enemy(actor, actors, grid)
    if visible is not None:
        return ActorCommand(
            actor.id,
            CommandType.ENGAGE,
            "v2 defender react",
            target_position=visible.position,
            target_actor_id=visible.id,
        )
    if actor.under_fire_timer > 0.0 and memory.plan.room_cover_cells:
        cell = nearest_cell(cell_of_actor(actor, grid), memory.plan.room_cover_cells)
        return ActorCommand(
            actor.id,
            CommandType.MOVE_TO,
            "v2 defender seek cover",
            target_cell=cell,
            target_position=memory.plan.focus,
            intent_type=IntentType.SEEK_COVER,
        )
    actor.facing = rotate_toward(actor.facing, angle_to(actor.position, grid.cell_center(memory.plan.door_inside)), actor.turn_speed * dt)
    set_intent(actor, IntentType.HOLD_POSITION, "v2 training idle", target_position=memory.plan.focus)
    return None


def self_preserve_order(actor: Actor, actors: list[Actor], grid: GridMap, memory: BreachMemory) -> SquadOrder:
    current = cell_of_actor(actor, grid)
    candidates = memory.plan.stack_cells + memory.plan.room_cover_cells
    target = nearest_cell(current, candidates)
    return SquadOrder(
        actor.id,
        OrderType.SELF_PRESERVE,
        "v2 self preserve",
        target_cell=target,
        target_position=actor.under_fire_position or memory.plan.focus,
    )


def move_order(actor: Actor, order: SquadOrder) -> ActorCommand:
    return ActorCommand(
        actor.id,
        CommandType.MOVE_TO,
        order.reason,
        target_cell=order.target_cell,
        target_position=order.target_position,
        target_actor_id=order.target_actor_id,
        intent_type=IntentType.MOVE_TO,
    )


def hold_order(actor: Actor, order: SquadOrder) -> ActorCommand:
    return ActorCommand(
        actor.id,
        CommandType.HOLD,
        order.reason,
        target_position=order.target_position,
        target_actor_id=order.target_actor_id,
    )


def nearest_visible_enemy(actor: Actor, actors: list[Actor], grid: GridMap) -> Actor | None:
    visible = [other for other in actors if other.team != actor.team and can_see(actor, other, grid)]
    if not visible:
        return None
    return min(visible, key=lambda other: actor.position.distance_to(other.position))


def role_priority(actor: Actor) -> int:
    if actor.role == ActorRole.POINTMAN:
        return 0
    if actor.role == ActorRole.RIFLEMAN:
        return 1
    return 2


def cell_of_actor(actor: Actor, grid: GridMap) -> tuple[int, int]:
    return actor.occupied_cell or actor.move_to or grid.cell_of(actor.position)


def is_standing_at(actor: Actor, cell: tuple[int, int]) -> bool:
    return actor.mode == ActorMode.STANDING and actor.occupied_cell == cell


def nearest_cell(origin: tuple[int, int], candidates: tuple[tuple[int, int], ...]) -> tuple[int, int]:
    return min(candidates, key=lambda cell: abs(cell[0] - origin[0]) + abs(cell[1] - origin[1]))
