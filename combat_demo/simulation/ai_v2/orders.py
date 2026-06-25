from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from ..geometry import Vec2


class AISystem(Enum):
    LEGACY = "legacy"
    BREACH = "breach"


class BreachStage(Enum):
    STACK = "stack"
    OPEN_DOOR = "open_door"
    BREACH = "breach"
    CLEAR = "clear"
    STABILIZE = "stabilize"


class OrderType(Enum):
    STACK = "stack"
    OPEN_DOOR = "open_door"
    COVER_OPENING = "cover_opening"
    ENTER_ROOM = "enter_room"
    MOVE_TO_COVER = "move_to_cover"
    ENGAGE = "engage"
    SELF_PRESERVE = "self_preserve"
    HOLD = "hold"


@dataclass(frozen=True)
class BreachPlan:
    team: str
    stack_cells: tuple[tuple[int, int], ...]
    door_outside: tuple[int, int]
    door_inside: tuple[int, int]
    window_outside: tuple[int, int]
    window_inside: tuple[int, int]
    entry_cells: tuple[tuple[int, int], ...]
    room_cover_cells: tuple[tuple[int, int], ...]
    room_cells: tuple[tuple[int, int], ...]
    focus: Vec2


@dataclass
class BreachMemory:
    plan: BreachPlan
    stage: BreachStage = BreachStage.STACK
    stage_timer: float = 0.0


@dataclass(frozen=True)
class SquadOrder:
    actor_id: int
    type: OrderType
    reason: str
    target_cell: tuple[int, int] | None = None
    target_position: Vec2 | None = None
    target_actor_id: int | None = None
