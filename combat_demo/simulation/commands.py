from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .actor import ActionType, IntentType
from .geometry import Vec2


class CommandType(Enum):
    MOVE_TO = "move_to"
    FACE = "face"
    ENGAGE = "engage"
    SUPPRESS = "suppress"
    START_ACTION = "start_action"
    HOLD = "hold"


@dataclass(frozen=True)
class ActorCommand:
    actor_id: int
    type: CommandType
    reason: str
    target_cell: tuple[int, int] | None = None
    target_position: Vec2 | None = None
    target_actor_id: int | None = None
    action_type: ActionType | None = None
    duration: float | None = None
    intent_type: IntentType | None = None
    door_id: str | None = None
    item_id: str | None = None
    part_id: str | None = None
    owner_token: str | None = None
    path: tuple[tuple[int, int], ...] | None = None
