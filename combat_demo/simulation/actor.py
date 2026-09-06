from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from math import radians

from .body import BodyInstance, create_human_body
from .geometry import Vec2
from .weapon import RIFLE, WeaponState
from .items import Inventory


class Team(Enum):
    RED = "red"
    BLUE = "blue"


class ActorState(Enum):
    IDLE = "idle"
    INVESTIGATE = "investigate"
    ENGAGE = "engage"
    CHASE = "chase"
    DEAD = "dead"


class ActorMode(Enum):
    STANDING = "standing"
    MOVING = "moving"
    ACTING = "acting"
    DEAD = "dead"


class ActorRole(Enum):
    POINTMAN = "pointman"
    RIFLEMAN = "rifleman"
    SUPPORT = "support"


class AggressionPolicy(Enum):
    CONSERVATIVE = "conservative"
    STANDARD = "standard"
    AGGRESSIVE = "aggressive"


class AmmoPolicy(Enum):
    CONSERVE = "conserve"
    STANDARD = "standard"
    SUPPRESS = "suppress"


class CoverPolicy(Enum):
    COVER_FIRST = "cover_first"
    BALANCED = "balanced"
    CHASE = "chase"


class GrenadePolicy(Enum):
    DISABLED = "disabled"
    CAREFUL = "careful"
    AGGRESSIVE = "aggressive"


class MedicalPolicy(Enum):
    SELF_PRESERVE = "self_preserve"
    IGNORE_LIGHT = "ignore_light"


class FireMode(Enum):
    AIMED_SHOT = "aimed_shot"
    RAPID_FIRE = "rapid_fire"
    SUPPRESS = "suppress"
    HOLD_FIRE = "hold_fire"


class PeekDirection(Enum):
    N = "N"
    E = "E"
    S = "S"
    W = "W"


class IntentType(Enum):
    SEARCH = "search"
    MOVE_TO = "move_to"
    FACE = "face"
    ENGAGE = "engage"
    RELOAD = "reload"
    INVESTIGATE = "investigate"
    REGROUP = "regroup"
    SEEK_COVER = "seek_cover"
    SUPPRESS = "suppress"
    HOLD_POSITION = "hold_position"
    ACTION = "action"


class ActionType(Enum):
    RELOAD = "reload"
    THROW_GRENADE = "throw_grenade"
    BANDAGE = "bandage"
    VAULT_LOW_WALL = "vault_low_wall"
    OPEN_DOOR = "open_door"
    KICK_DOOR = "kick_door"


class InterruptPolicy(Enum):
    NONE = "none"
    THREAT = "threat"
    HIT = "hit"


@dataclass
class ActorAction:
    type: ActionType
    duration: float
    timer: float = 0.0
    target_position: Vec2 | None = None
    target_actor_id: int | None = None
    interrupt_policy: InterruptPolicy = InterruptPolicy.THREAT
    interrupted_reason: str | None = None
    door_id: str | None = None
    item_id: str | None = None
    part_id: str | None = None
    owner_token: str | None = None
    refill: int = 0

    @property
    def progress(self) -> float:
        if self.duration <= 0.0:
            return 1.0
        return min(1.0, self.timer / self.duration)


@dataclass
class ActorIntent:
    type: IntentType
    reason: str
    target_cell: tuple[int, int] | None = None
    target_position: Vec2 | None = None
    target_actor_id: int | None = None

    @property
    def label(self) -> str:
        return f"{self.type.value}: {self.reason}"


@dataclass(frozen=True)
class TacticProfile:
    aggression: AggressionPolicy = AggressionPolicy.STANDARD
    ammo: AmmoPolicy = AmmoPolicy.STANDARD
    cover: CoverPolicy = CoverPolicy.BALANCED
    grenade: GrenadePolicy = GrenadePolicy.CAREFUL
    medical: MedicalPolicy = MedicalPolicy.SELF_PRESERVE


@dataclass
class Actor:
    id: int
    name: str
    team: Team
    position: Vec2
    facing: float
    role: ActorRole = ActorRole.RIFLEMAN
    tactics: TacticProfile = field(default_factory=TacticProfile)
    weapon: WeaponState = field(default_factory=lambda: WeaponState.create(RIFLE))
    body: BodyInstance = field(default_factory=create_human_body)
    mode: ActorMode = ActorMode.STANDING
    occupied_cell: tuple[int, int] | None = None
    reserved_cell: tuple[int, int] | None = None
    route: list[tuple[int, int]] = field(default_factory=list)
    move_from: tuple[int, int] | None = None
    move_to: tuple[int, int] | None = None
    move_progress: float = 0.0
    state: ActorState = ActorState.IDLE
    target_id: int | None = None
    target_cell: tuple[int, int] | None = None
    path: list[tuple[int, int]] = field(default_factory=list)
    last_known_enemy: Vec2 | None = None
    last_known_timer: float = 0.0
    heard_position: Vec2 | None = None
    heard_timer: float = 0.0
    under_fire_position: Vec2 | None = None
    under_fire_timer: float = 0.0
    under_fire_angle: float | None = None
    response: str = ""
    suppression: float = 0.0
    inventory: Inventory = field(default_factory=Inventory)
    current_action: ActorAction | None = None
    aim_target_id: int | None = None
    aim_error_degrees: float = 8.0
    fire_mode: FireMode = FireMode.AIMED_SHOT
    fire_reason: str = "no target"
    peek_direction: PeekDirection | None = None
    peek_cover_direction: PeekDirection | None = None
    intent: ActorIntent = field(default_factory=lambda: ActorIntent(IntentType.SEARCH, "searching"))
    intent_reason: str = "searching"
    cover_score: float = 0.0
    cover_reason: str = "none"
    radius: float = 0.32
    height: float = 1.8
    eye_height: float = 1.65
    speed: float = 2.0
    turn_speed: float = radians(240.0)
    view_distance: float = 12.0
    view_angle: float = radians(120.0)
    max_aim_error_degrees: float = 8.0
    aim_settle_degrees_per_second: float = 10.0
    move_aim_penalty_degrees_per_second: float = 12.0
    stunned: float = 0.0
    guard_angle: float | None = None
    guard_explicit: bool = False
    visible: set[int] = field(default_factory=set)
    recognized: set[int] = field(default_factory=set)
    identification: dict[int, float] = field(default_factory=dict)
    memory: dict[int, tuple[Vec2, float]] = field(default_factory=dict)
    reaction: float = 0.0
    recent_attackers: dict[int, float] = field(default_factory=dict)
    ai_state: str = "guard"
    ai_enabled: bool = False
    home_cell: tuple[int, int] | None = None
    home_angle: float = 0.0
    patrol: tuple[tuple[int, int], ...] = ()
    patrol_index: int = 0
    ai_goal: tuple[int, int] | None = None
    ai_until: float = 0.0
    ai_wait: float = 0.0
    report_time: float = -1.0
    queue: list = field(default_factory=list)
    task_id: int | None = None
    blocked_reason: str = ""
    hit_flash: float = 0.0

    @property
    def alive(self) -> bool:
        return not self.body.dead and self.state != ActorState.DEAD and self.mode != ActorMode.DEAD

    def mark_dead_if_needed(self) -> None:
        if self.body.dead:
            self.state = ActorState.DEAD
            self.mode = ActorMode.DEAD
            self.occupied_cell = None
            self.reserved_cell = None
            self.route.clear()
            self.move_from = None
            self.move_to = None
            self.move_progress = 0.0
            self.target_id = None
            self.target_cell = None
            self.path.clear()
            self.current_action = None
            self.intent = ActorIntent(IntentType.HOLD_POSITION, "dead")
            self.intent_reason = "dead"
