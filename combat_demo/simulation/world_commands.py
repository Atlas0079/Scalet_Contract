from __future__ import annotations

from .actor import Actor, ActorAction, ActorIntent, ActorMode, ActorState, IntentType, InterruptPolicy
from .commands import ActorCommand, CommandType
from .geometry import angle_to, rotate_toward
from .map import GridMap
from .movement import clear_movement, set_path_to


def set_intent(
    actor: Actor,
    intent_type: IntentType,
    reason: str,
    target_cell: tuple[int, int] | None = None,
    target_position=None,
    target_actor_id: int | None = None,
) -> None:
    actor.intent = ActorIntent(
        intent_type,
        reason,
        target_cell=target_cell,
        target_position=target_position,
        target_actor_id=target_actor_id,
    )
    actor.intent_reason = actor.intent.label


def apply_actor_command(
    actor: Actor,
    actors: list[Actor],
    grid: GridMap,
    command: ActorCommand,
    dt: float = 0.0,
) -> None:
    if command.type == CommandType.MOVE_TO and command.target_cell is not None:
        actor.state = ActorState.CHASE
        set_intent(
            actor,
            command.intent_type or IntentType.MOVE_TO,
            command.reason,
            target_cell=command.target_cell,
            target_position=command.target_position,
            target_actor_id=command.target_actor_id,
        )
        set_path_to(actor, grid, actors, command.target_cell)
        return

    if command.type == CommandType.ENGAGE and command.target_actor_id is not None:
        actor.state = ActorState.ENGAGE
        actor.target_id = command.target_actor_id
        set_intent(
            actor,
            IntentType.ENGAGE,
            command.reason,
            target_position=command.target_position,
            target_actor_id=command.target_actor_id,
        )
        clear_movement(actor)
        return

    if command.type == CommandType.SUPPRESS and command.target_position is not None:
        actor.state = ActorState.INVESTIGATE
        set_intent(
            actor,
            IntentType.SUPPRESS,
            command.reason,
            target_cell=command.target_cell,
            target_position=command.target_position,
            target_actor_id=command.target_actor_id,
        )
        if command.target_cell is not None:
            set_path_to(actor, grid, actors, command.target_cell)
        else:
            clear_movement(actor)
        return

    if command.type == CommandType.START_ACTION and command.action_type is not None:
        actor.current_action = ActorAction(
            command.action_type,
            command.duration or 0.0,
            target_position=command.target_position,
            target_actor_id=command.target_actor_id,
            interrupt_policy=InterruptPolicy.THREAT,
        )
        actor.mode = ActorMode.ACTING
        clear_movement(actor)
        set_intent(
            actor,
            IntentType.ACTION,
            command.reason,
            target_position=command.target_position,
            target_actor_id=command.target_actor_id,
        )
        return

    if command.type == CommandType.FACE and command.target_position is not None:
        actor.facing = rotate_toward(
            actor.facing,
            angle_to(actor.position, command.target_position),
            actor.turn_speed * dt,
        )
        set_intent(actor, IntentType.FACE, command.reason, target_position=command.target_position)
        return

    if command.type == CommandType.HOLD:
        actor.state = ActorState.IDLE if actor.state == ActorState.IDLE else actor.state
        set_intent(
            actor,
            IntentType.HOLD_POSITION,
            command.reason,
            target_position=command.target_position,
            target_actor_id=command.target_actor_id,
        )
        clear_movement(actor)
        if command.target_position is not None and dt > 0.0:
            actor.facing = rotate_toward(
                actor.facing,
                angle_to(actor.position, command.target_position),
                actor.turn_speed * dt,
            )
