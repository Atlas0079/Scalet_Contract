from __future__ import annotations

from dataclasses import dataclass
from math import fabs

from .actor import (
    ActionType,
    Actor,
    ActorMode,
    ActorRole,
    ActorState,
    AmmoPolicy,
    CoverPolicy,
    IntentType,
    InterruptPolicy,
    MedicalPolicy,
    PeekDirection,
)
from .commands import ActorCommand, CommandType
from .geometry import Vec2, angle_difference, angle_to, rotate_toward
from .map import GridMap
from .movement import (
    find_available_target,
    is_moving_between_cells,
    reachable_cells_within,
)
from .pose import PEEK_DIRECTIONS, actor_combat_position, clear_actor_peek, combat_position_for, cover_directions_for_peek
from .squad import SquadAssignment, SquadMemory, SquadPhase, SquadPosture
from .world_commands import set_intent


TEAM_FORWARD = {
    "red": (1, 0),
    "blue": (-1, 0),
}

SEARCH_ROLE_OFFSETS = {
    ActorRole.POINTMAN: (0, 0),
    ActorRole.RIFLEMAN: (-1, -1),
    ActorRole.SUPPORT: (-2, 1),
}

CONTACT_ROLE_OFFSETS = {
    ActorRole.POINTMAN: (-2, 0),
    ActorRole.RIFLEMAN: (-3, -1),
    ActorRole.SUPPORT: (-4, 1),
}

FLANK_ROLE_OFFSETS = {
    ActorRole.POINTMAN: (-1, -2),
    ActorRole.RIFLEMAN: (-2, 2),
    ActorRole.SUPPORT: (-4, 2),
}

REGROUP_ROLE_OFFSETS = {
    ActorRole.POINTMAN: (1, 0),
    ActorRole.RIFLEMAN: (0, -1),
    ActorRole.SUPPORT: (-1, 1),
}


@dataclass(frozen=True)
class PositionChoice:
    cell: tuple[int, int]
    score: float
    reason: str


def can_see(observer: Actor, target: Actor, grid: GridMap) -> bool:
    if not observer.alive or not target.alive or observer.team == target.team:
        return False
    distance = observer.position.distance_to(target.position)
    if distance > observer.view_distance:
        return False
    target_angle = angle_to(observer.position, target.position)
    if fabs(angle_difference(observer.facing, target_angle)) > observer.view_angle / 2.0:
        return False
    target_position = actor_combat_position(target)
    wall_height = grid.ray_wall_height(observer.position, target_position)
    if wall_height < 2.0:
        return True
    if observer.mode != ActorMode.STANDING or not is_at_cell_center(observer, grid):
        return False
    cell = observer.occupied_cell or grid.cell_of(observer.position)
    for direction in PEEK_DIRECTIONS:
        for cover_direction in cover_directions_for_peek(grid, cell, direction):
            peek_start = combat_position_for(observer, direction, cover_direction)
            if grid.ray_wall_height(peek_start, target_position) < 2.0:
                return True
    return False


def nearest_visible_enemy(actor: Actor, actors: list[Actor], grid: GridMap) -> Actor | None:
    visible = [other for other in actors if can_see(actor, other, grid)]
    if not visible:
        return None
    return min(visible, key=lambda other: actor.position.distance_to(other.position))


def is_at_cell_center(actor: Actor, grid: GridMap, tolerance: float = 0.04) -> bool:
    if actor.occupied_cell is None:
        return actor.position.distance_to(grid.cell_center(grid.cell_of(actor.position))) <= tolerance
    return actor.position.distance_to(grid.cell_center(actor.occupied_cell)) <= tolerance


def remember_visible_contact(
    actor: Actor,
    visible: Actor | None,
    squad: SquadMemory,
    now: float,
) -> None:
    if visible is None:
        return
    squad.add_contact(
        visible.position,
        source="visual",
        confidence=1.0,
        now=now,
        enemy_id=visible.id,
        expires_after=5.0,
    )
    actor.target_id = visible.id
    actor.last_known_enemy = visible.position
    actor.last_known_timer = 5.0


def nearest_standing_cell(actor: Actor, grid: GridMap, actors: list[Actor]) -> tuple[int, int]:
    base = actor.move_to or actor.occupied_cell or grid.cell_of(actor.position)
    return find_available_target(actor, grid, actors, base)


def rotated_offset(forward: tuple[int, int], offset: tuple[int, int]) -> tuple[int, int]:
    along, side_amount = offset
    side = (-forward[1], forward[0])
    return (
        forward[0] * along + side[0] * side_amount,
        forward[1] * along + side[1] * side_amount,
    )


def clamp_cell(grid: GridMap, cell: tuple[int, int]) -> tuple[int, int]:
    return (
        max(0, min(grid.width - 1, cell[0])),
        max(0, min(grid.height - 1, cell[1])),
    )


def dominant_direction(origin: Vec2, target: Vec2, fallback: tuple[int, int]) -> tuple[int, int]:
    dx = target.x - origin.x
    dy = target.y - origin.y
    if abs(dx) < 0.2 and abs(dy) < 0.2:
        return fallback
    if abs(dx) >= abs(dy):
        return (1 if dx >= 0 else -1, 0)
    return (0, 1 if dy >= 0 else -1)


def team_centroid(actor: Actor, actors: list[Actor]) -> Vec2:
    allies = [other for other in actors if other.alive and other.team == actor.team]
    if not allies:
        return actor.position
    return Vec2(
        sum(other.position.x for other in allies) / len(allies),
        sum(other.position.y for other in allies) / len(allies),
    )


def formation_cell_for_search(actor: Actor, squad: SquadMemory, grid: GridMap) -> tuple[int, int]:
    forward = TEAM_FORWARD[actor.team.value]
    offset = rotated_offset(forward, SEARCH_ROLE_OFFSETS[actor.role])
    return clamp_cell(
        grid,
        (squad.objective_cell[0] + offset[0], squad.objective_cell[1] + offset[1]),
    )


def formation_cell_for_contact(
    actor: Actor,
    actors: list[Actor],
    squad: SquadMemory,
    grid: GridMap,
) -> tuple[int, int]:
    contact = squad.best_contact()
    if contact is None:
        return formation_cell_for_search(actor, squad, grid)
    fallback = TEAM_FORWARD[actor.team.value]
    forward = dominant_direction(team_centroid(actor, actors), contact.position, fallback)
    offset = rotated_offset(forward, CONTACT_ROLE_OFFSETS[actor.role])
    contact_cell = grid.cell_of(contact.position)
    return clamp_cell(
        grid,
        (contact_cell[0] + offset[0], contact_cell[1] + offset[1]),
    )


def formation_cell_for_flank(
    actor: Actor,
    actors: list[Actor],
    squad: SquadMemory,
    grid: GridMap,
) -> tuple[int, int]:
    contact = squad.best_contact()
    if contact is None:
        return formation_cell_for_search(actor, squad, grid)
    fallback = TEAM_FORWARD[actor.team.value]
    forward = dominant_direction(team_centroid(actor, actors), contact.position, fallback)
    offset = rotated_offset(forward, FLANK_ROLE_OFFSETS[actor.role])
    contact_cell = grid.cell_of(contact.position)
    return clamp_cell(
        grid,
        (contact_cell[0] + offset[0], contact_cell[1] + offset[1]),
    )


def formation_cell_for_regroup(actor: Actor, squad: SquadMemory, grid: GridMap) -> tuple[int, int]:
    forward = TEAM_FORWARD[actor.team.value]
    offset = rotated_offset(forward, REGROUP_ROLE_OFFSETS[actor.role])
    return clamp_cell(
        grid,
        (squad.rally_cell[0] + offset[0], squad.rally_cell[1] + offset[1]),
    )


def has_line_to_contact(grid: GridMap, cell: tuple[int, int], contact_position: Vec2) -> bool:
    wall_height = grid.ray_wall_height(grid.cell_center(cell), contact_position)
    return wall_height < 2.0


def choose_peek_direction(actor: Actor, grid: GridMap, target_position: Vec2) -> tuple[PeekDirection, PeekDirection] | None:
    if actor.mode != ActorMode.STANDING or not is_at_cell_center(actor, grid):
        return None
    cell = actor.occupied_cell or grid.cell_of(actor.position)
    best_direction: tuple[PeekDirection, PeekDirection] | None = None
    best_wall_height = 999.0
    for direction in PEEK_DIRECTIONS:
        for cover_direction in cover_directions_for_peek(grid, cell, direction):
            start = combat_position_for(actor, direction, cover_direction)
            wall_height = grid.ray_wall_height(start, target_position)
            if wall_height < 2.0 and wall_height < best_wall_height:
                best_direction = (direction, cover_direction)
                best_wall_height = wall_height
    return best_direction


def has_low_wall_protection(grid: GridMap, cell: tuple[int, int], contact_position: Vec2) -> bool:
    wall_height = grid.ray_wall_height(grid.cell_center(cell), contact_position)
    return 0.75 <= wall_height < 2.0


def contact_distance_score(cell_center: Vec2, contact_position: Vec2) -> float:
    distance = cell_center.distance_to(contact_position)
    if distance < 2.0:
        return -3.0
    if distance <= 9.0:
        return 2.0
    if distance <= 14.0:
        return 0.5
    return -1.5


def choose_cover_position(
    actor: Actor,
    actors: list[Actor],
    grid: GridMap,
    squad: SquadMemory,
    contact_position: Vec2,
    allow_hiding: bool,
) -> PositionChoice | None:
    anchor = team_centroid(actor, actors)
    candidates = reachable_cells_within(actor, grid, actors, radius=3)
    best: PositionChoice | None = None
    current_cell = grid.cell_of(actor.position)
    for cell in candidates:
        center = grid.cell_center(cell)
        line = has_line_to_contact(grid, cell, contact_position)
        low_cover = has_low_wall_protection(grid, cell, contact_position)
        wall_height = grid.ray_wall_height(center, contact_position)

        score = 0.0
        reasons: list[str] = []
        if line:
            score += 4.0
            reasons.append("line")
        else:
            score -= 3.0
        if low_cover:
            score += 5.0
            reasons.append("low-wall")
        elif allow_hiding and wall_height >= 2.0:
            score += 3.0
            reasons.append("hide")
        score += contact_distance_score(center, contact_position)
        squad_distance = center.distance_to(anchor)
        score -= max(0.0, squad_distance - 4.0) * 0.5
        move_cost = abs(cell[0] - current_cell[0]) + abs(cell[1] - current_cell[1])
        score -= move_cost * 0.25
        if actor.role == ActorRole.SUPPORT and center.distance_to(contact_position) < 5.0:
            score -= 1.5
        if actor.role == ActorRole.POINTMAN and line:
            score += 0.5

        if not line and not allow_hiding:
            continue
        if best is None or score > best.score:
            reason = " ".join(reasons) if reasons else "nearby"
            best = PositionChoice(cell=cell, score=score, reason=reason)
    return best


def update_ai(
    actor: Actor,
    actors: list[Actor],
    grid: GridMap,
    squad: SquadMemory,
    dt: float,
    tick_index: int,
    now: float,
) -> ActorCommand | None:
    if not actor.alive:
        actor.state = ActorState.DEAD
        set_intent(actor, IntentType.HOLD_POSITION, "dead")
        return

    actor.weapon.update(dt)
    actor.recoil_error_degrees = max(
        0.0,
        actor.recoil_error_degrees - actor.recoil_recovery_degrees_per_second * dt,
    )
    actor.suppression = max(0.0, actor.suppression - 8.0 * dt)
    actor.last_known_timer = max(0.0, actor.last_known_timer - dt)
    actor.heard_timer = max(0.0, actor.heard_timer - dt)
    actor.under_fire_timer = max(0.0, actor.under_fire_timer - dt)
    clear_actor_peek(actor)

    visible = nearest_visible_enemy(actor, actors, grid)
    remember_visible_contact(actor, visible, squad, now)

    if is_moving_between_cells(actor, grid):
        if actor.under_fire_timer > 0.0 and actor.under_fire_position is not None:
            actor.state = ActorState.INVESTIGATE
            target_cell = nearest_standing_cell(actor, grid, actors)
            set_intent(actor, IntentType.MOVE_TO, "reroute before reacting", target_cell=target_cell)
            actor.facing = rotate_toward(
                actor.facing,
                angle_to(actor.position, actor.under_fire_position),
                actor.turn_speed * dt,
            )
            return ActorCommand(
                actor.id,
                CommandType.MOVE_TO,
                "reroute before reacting",
                target_cell=target_cell,
            )
        elif visible is not None:
            actor.state = ActorState.CHASE
            target_cell = nearest_standing_cell(actor, grid, actors)
            set_intent(
                actor,
                IntentType.MOVE_TO,
                "reroute before engaging",
                target_cell=target_cell,
                target_position=visible.position,
                target_actor_id=visible.id,
            )
            return ActorCommand(
                actor.id,
                CommandType.MOVE_TO,
                "reroute before engaging",
                target_cell=target_cell,
                target_position=visible.position,
                target_actor_id=visible.id,
            )
        else:
            set_intent(actor, IntentType.MOVE_TO, "moving", target_cell=actor.target_cell)
        return

    if actor.current_action is not None:
        if (
            actor.current_action.interrupt_policy == InterruptPolicy.THREAT
            and (visible is not None or actor.under_fire_timer > 0.0)
        ):
            interrupted = actor.current_action.type.value
            actor.current_action = None
            set_intent(actor, IntentType.ACTION, f"{interrupted} interrupted: threat")
        else:
            set_intent(actor, IntentType.ACTION, f"continuing {actor.current_action.type.value}")
            return

    wound_threshold = 28.0 if actor.tactics.medical == MedicalPolicy.IGNORE_LIGHT else 18.0
    if actor.bandages > 0 and visible is None and actor.under_fire_timer <= 0.0 and squad.posture != SquadPosture.ENGAGED:
        wounded = most_wounded_treatable_part(actor)
        if wounded is not None and wounded[1] >= wound_threshold:
            return ActorCommand(
                actor.id,
                CommandType.START_ACTION,
                f"bandage {wounded[0]} wounded",
                target_actor_id=actor.id,
                action_type=ActionType.BANDAGE,
                duration=3.5,
            )

    if actor.current_action is not None:
        set_intent(actor, IntentType.ACTION, f"continuing {actor.current_action.type.value}")
        return

    actor.cover_score = 0.0
    actor.cover_reason = "none"
    actor.fire_reason = "no target"

    if visible:
        peek = choose_peek_direction(actor, grid, actor_combat_position(visible))
        if peek is not None:
            actor.peek_direction, actor.peek_cover_direction = peek
        assignment = squad.assignment_for(actor)
        if assignment == SquadAssignment.BASE_OF_FIRE and actor.role != ActorRole.POINTMAN:
            actor.state = ActorState.CHASE
            if squad.phase != SquadPhase.SET_FIRE_BASE:
                set_intent(
                    actor,
                    IntentType.SUPPRESS,
                    f"{assignment.value} covering bound",
                    target_position=visible.position,
                    target_actor_id=visible.id,
                )
                return ActorCommand(
                    actor.id,
                    CommandType.SUPPRESS,
                    f"{assignment.value} covering bound",
                    target_position=visible.position,
                    target_actor_id=visible.id,
                )
            target_cell = formation_cell_for_contact(actor, actors, squad, grid)
            choice = choose_cover_position(
                actor,
                actors,
                grid,
                squad,
                visible.position,
                allow_hiding=actor.suppression > 35.0,
            )
            if choice is not None and choice.score > 2.5:
                target_cell = choice.cell
                actor.cover_score = choice.score
                actor.cover_reason = choice.reason
            set_intent(
                actor,
                IntentType.SUPPRESS,
                f"{assignment.value} hold contact",
                target_cell=target_cell,
                target_position=visible.position,
                target_actor_id=visible.id,
            )
            return ActorCommand(
                actor.id,
                CommandType.SUPPRESS,
                f"{assignment.value} hold contact",
                target_cell=target_cell,
                target_position=visible.position,
                target_actor_id=visible.id,
            )
        if assignment == SquadAssignment.FLANK:
            if not squad.actor_can_bound(actor):
                actor.state = ActorState.ENGAGE
                set_intent(
                    actor,
                    IntentType.SUPPRESS,
                    f"{assignment.value} covering bound",
                    target_position=visible.position,
                    target_actor_id=visible.id,
                )
                return ActorCommand(
                    actor.id,
                    CommandType.SUPPRESS,
                    f"{assignment.value} covering bound",
                    target_position=visible.position,
                    target_actor_id=visible.id,
                )
            actor.state = ActorState.CHASE
            target_cell = formation_cell_for_flank(actor, actors, squad, grid)
            set_intent(
                actor,
                IntentType.INVESTIGATE,
                f"{assignment.value} angle on visual",
                target_cell=target_cell,
                target_position=visible.position,
                target_actor_id=visible.id,
            )
            actor.facing = rotate_toward(
                actor.facing,
                angle_to(actor.position, visible.position),
                actor.turn_speed * dt,
            )
            return
        if assignment == SquadAssignment.CONTACT_LEAD and not squad.actor_can_bound(actor):
            actor.state = ActorState.ENGAGE
            set_intent(
                actor,
                IntentType.ENGAGE,
                f"{assignment.value} hold for cover",
                target_position=visible.position,
                target_actor_id=visible.id,
            )
            return ActorCommand(
                actor.id,
                CommandType.ENGAGE,
                f"{assignment.value} hold for cover",
                target_position=visible.position,
                target_actor_id=visible.id,
            )
        actor.state = ActorState.ENGAGE
        reason = f"peek {actor.peek_direction.value} visual contact" if actor.peek_direction else "visual contact"
        set_intent(actor, IntentType.ENGAGE, reason, target_position=visible.position, target_actor_id=visible.id)
        return ActorCommand(
            actor.id,
            CommandType.ENGAGE,
            reason,
            target_position=visible.position,
            target_actor_id=visible.id,
        )

    if squad.posture == SquadPosture.REGROUP:
        target_cell = formation_cell_for_regroup(actor, squad, grid)
        actor.state = ActorState.IDLE
        set_intent(actor, IntentType.REGROUP, squad.regroup_reason or "rally", target_cell=target_cell)
        actor.target_id = None
        return ActorCommand(
            actor.id,
            CommandType.MOVE_TO,
            squad.regroup_reason or "rally",
            target_cell=target_cell,
            intent_type=IntentType.REGROUP,
        )

    if actor.under_fire_timer > 0.0 and actor.under_fire_position is not None:
        actor.state = ActorState.INVESTIGATE
        actor.target_id = None
        actor.last_known_enemy = actor.under_fire_position
        actor.last_known_timer = max(actor.last_known_timer, actor.under_fire_timer)
        set_intent(actor, IntentType.INVESTIGATE, "hit reaction", target_position=actor.under_fire_position)
        actor.facing = rotate_toward(
            actor.facing,
            angle_to(actor.position, actor.under_fire_position),
            actor.turn_speed * dt,
        )
        choice = choose_cover_position(
            actor,
            actors,
            grid,
            squad,
            actor.under_fire_position,
            allow_hiding=True,
        )
        threshold = 1.0 if actor.tactics.cover == CoverPolicy.COVER_FIRST else 3.0
        if choice is not None and choice.score > threshold:
            actor.cover_score = choice.score
            actor.cover_reason = choice.reason
            set_intent(actor, IntentType.SEEK_COVER, f"fallback under fire ({choice.reason})", target_cell=choice.cell)
            return ActorCommand(
                actor.id,
                CommandType.MOVE_TO,
                f"fallback under fire ({choice.reason})",
                target_cell=choice.cell,
                target_position=actor.under_fire_position,
                intent_type=IntentType.SEEK_COVER,
            )
        else:
            return ActorCommand(
                actor.id,
                CommandType.MOVE_TO,
                "hit reaction",
                target_cell=grid.cell_of(actor.under_fire_position),
                target_position=actor.under_fire_position,
                intent_type=IntentType.INVESTIGATE,
            )

    if actor.target_id is not None:
        target = next((other for other in actors if other.id == actor.target_id), None)
        if target is None or not target.alive:
            actor.target_id = None
            actor.state = ActorState.IDLE
            set_intent(actor, IntentType.SEARCH, "target lost")
        elif actor.last_known_timer > 0.0 and actor.last_known_enemy is not None:
            actor.state = ActorState.CHASE
            set_intent(actor, IntentType.INVESTIGATE, "chase last known target", target_position=actor.last_known_enemy)
            return ActorCommand(
                actor.id,
                CommandType.MOVE_TO,
                "chase last known target",
                target_cell=grid.cell_of(actor.last_known_enemy),
                target_position=actor.last_known_enemy,
                intent_type=IntentType.INVESTIGATE,
            )
        else:
            actor.target_id = None
            actor.state = ActorState.IDLE
            set_intent(actor, IntentType.SEARCH, "target memory expired")

    contact = squad.best_contact()
    if contact is not None and squad.posture in (SquadPosture.CONTACT, SquadPosture.ENGAGED):
        actor.state = ActorState.CHASE if contact.confidence >= 0.6 else ActorState.INVESTIGATE
        actor.target_id = contact.enemy_id
        actor.last_known_enemy = contact.position
        actor.last_known_timer = 4.0
        assignment = squad.assignment_for(actor)
        can_bound = squad.actor_can_bound(actor)
        target_cell = (
            formation_cell_for_flank(actor, actors, squad, grid)
            if assignment == SquadAssignment.FLANK
            else formation_cell_for_contact(actor, actors, squad, grid)
        )
        choice = choose_cover_position(
            actor,
            actors,
            grid,
            squad,
            contact.position,
            allow_hiding=actor.suppression > 35.0,
        )
        cover_threshold = {
            CoverPolicy.COVER_FIRST: 2.5,
            CoverPolicy.BALANCED: 4.0,
            CoverPolicy.CHASE: 6.0,
        }[actor.tactics.cover]
        if assignment == SquadAssignment.BASE_OF_FIRE:
            cover_threshold -= 1.0
        elif assignment == SquadAssignment.CONTACT_LEAD:
            cover_threshold += 1.0
        elif assignment == SquadAssignment.FLANK:
            cover_threshold += 0.5
        elif assignment == SquadAssignment.RECOVER:
            cover_threshold = 0.5

        if assignment == SquadAssignment.RECOVER:
            if choice is not None:
                target_cell = choice.cell
                actor.cover_score = choice.score
                actor.cover_reason = choice.reason
                set_intent(
                    actor,
                    IntentType.SEEK_COVER,
                    f"{assignment.value} break contact ({choice.reason})",
                    target_cell=target_cell,
                    target_position=contact.position,
                    target_actor_id=contact.enemy_id,
                )
            else:
                target_cell = formation_cell_for_regroup(actor, squad, grid)
                set_intent(
                    actor,
                    IntentType.REGROUP,
                    f"{assignment.value} recover",
                    target_cell=target_cell,
                    target_position=contact.position,
                    target_actor_id=contact.enemy_id,
                )
            actor.facing = rotate_toward(
                actor.facing,
                angle_to(actor.position, contact.position),
                actor.turn_speed * dt,
            )
            return ActorCommand(
                actor.id,
                CommandType.MOVE_TO,
                actor.intent.reason,
                target_cell=target_cell,
                target_position=contact.position,
                target_actor_id=contact.enemy_id,
                intent_type=actor.intent.type,
            )

        if assignment == SquadAssignment.BASE_OF_FIRE and squad.phase != SquadPhase.SET_FIRE_BASE:
            actor.state = ActorState.INVESTIGATE
            set_intent(
                actor,
                IntentType.SUPPRESS,
                f"{assignment.value} covering bound",
                target_position=contact.position,
                target_actor_id=contact.enemy_id,
            )
            actor.facing = rotate_toward(
                actor.facing,
                angle_to(actor.position, contact.position),
                actor.turn_speed * dt,
            )
            return ActorCommand(
                actor.id,
                CommandType.SUPPRESS,
                f"{assignment.value} covering bound",
                target_position=contact.position,
                target_actor_id=contact.enemy_id,
            )

        wants_suppress = (
            assignment == SquadAssignment.BASE_OF_FIRE
            or (assignment == SquadAssignment.FLANK and not can_bound)
            or (
                actor.role == ActorRole.SUPPORT
                and actor.suppression < 55.0
                and actor.tactics.ammo != AmmoPolicy.CONSERVE
            )
            or actor.tactics.ammo == AmmoPolicy.SUPPRESS
        )
        peek = choose_peek_direction(actor, grid, contact.position)
        if peek is not None and not can_bound:
            peek_direction, cover_direction = peek
            actor.peek_direction = peek_direction
            actor.peek_cover_direction = cover_direction
            actor.cover_score = max(actor.cover_score, 7.0)
            actor.cover_reason = f"peek-{peek_direction.value}"
            intent_type = IntentType.SUPPRESS if wants_suppress or contact.enemy_id is None else IntentType.ENGAGE
            reason = f"{assignment.value if assignment else actor.role.value} peek {peek_direction.value}"
            set_intent(
                actor,
                intent_type,
                reason,
                target_position=contact.position,
                target_actor_id=contact.enemy_id,
            )
            actor.facing = rotate_toward(
                actor.facing,
                angle_to(combat_position_for(actor, peek_direction, cover_direction), contact.position),
                actor.turn_speed * dt,
            )
            if intent_type == IntentType.SUPPRESS:
                return ActorCommand(
                    actor.id,
                    CommandType.SUPPRESS,
                    reason,
                    target_position=contact.position,
                    target_actor_id=contact.enemy_id,
                )
            return ActorCommand(
                actor.id,
                CommandType.ENGAGE,
                reason,
                target_position=contact.position,
                target_actor_id=contact.enemy_id,
            )
        if assignment in (SquadAssignment.CONTACT_LEAD, SquadAssignment.FLANK) and not can_bound:
            actor.state = ActorState.ENGAGE if contact.confidence >= 0.9 else ActorState.INVESTIGATE
            intent_type = IntentType.SUPPRESS if wants_suppress else IntentType.HOLD_POSITION
            reason = f"{assignment.value} wait for bound ({squad.phase.value})"
            set_intent(
                actor,
                intent_type,
                reason,
                target_position=contact.position,
                target_actor_id=contact.enemy_id,
            )
            actor.facing = rotate_toward(
                actor.facing,
                angle_to(actor.position, contact.position),
                actor.turn_speed * dt,
            )
            return
        if choice is not None and choice.score > cover_threshold:
            target_cell = choice.cell
            actor.cover_score = choice.score
            actor.cover_reason = choice.reason
            if wants_suppress:
                set_intent(
                    actor,
                    IntentType.SUPPRESS,
                    f"{assignment.value if assignment else actor.role.value} suppress from cover ({choice.reason})",
                    target_cell=target_cell,
                    target_position=contact.position,
                    target_actor_id=contact.enemy_id,
                )
            else:
                intent_type = IntentType.INVESTIGATE if assignment == SquadAssignment.FLANK else IntentType.SEEK_COVER
                set_intent(
                    actor,
                    intent_type,
                    f"{assignment.value if assignment else actor.role.value} cover ({choice.reason})",
                    target_cell=target_cell,
                    target_position=contact.position,
                    target_actor_id=contact.enemy_id,
                )
        else:
            if wants_suppress:
                set_intent(
                    actor,
                    IntentType.SUPPRESS,
                    f"{assignment.value if assignment else actor.role.value} suppress {contact.source} contact",
                    target_cell=target_cell,
                    target_position=contact.position,
                    target_actor_id=contact.enemy_id,
                )
            else:
                reason = (
                    f"{assignment.value} angle on {contact.source} contact"
                    if assignment == SquadAssignment.FLANK
                    else f"{assignment.value if assignment else actor.role.value} to {contact.source} contact"
                )
                set_intent(
                    actor,
                    IntentType.INVESTIGATE,
                    reason,
                    target_cell=target_cell,
                    target_position=contact.position,
                    target_actor_id=contact.enemy_id,
                )
        actor.facing = rotate_toward(
            actor.facing,
            angle_to(actor.position, contact.position),
            actor.turn_speed * dt,
        )
        command_type = CommandType.SUPPRESS if actor.intent.type == IntentType.SUPPRESS else CommandType.MOVE_TO
        return ActorCommand(
            actor.id,
            command_type,
            actor.intent.reason,
            target_cell=target_cell if actor.intent.target_cell is not None else None,
            target_position=contact.position,
            target_actor_id=contact.enemy_id,
            intent_type=actor.intent.type if command_type == CommandType.MOVE_TO else None,
        )

    if actor.heard_timer > 0.0 and actor.heard_position is not None:
        actor.state = ActorState.INVESTIGATE
        set_intent(actor, IntentType.INVESTIGATE, "heard gunshot", target_position=actor.heard_position)
        return ActorCommand(
            actor.id,
            CommandType.MOVE_TO,
            "heard gunshot",
            target_cell=grid.cell_of(actor.heard_position),
            target_position=actor.heard_position,
            intent_type=IntentType.INVESTIGATE,
        )

    if actor.state in (ActorState.IDLE, ActorState.INVESTIGATE, ActorState.CHASE) and actor.mode == ActorMode.STANDING and not actor.route:
        target_cell = formation_cell_for_search(actor, squad, grid)
        actor.state = ActorState.IDLE
        set_intent(actor, IntentType.SEARCH, f"{actor.role.value} formation slot", target_cell=target_cell)
        return ActorCommand(
            actor.id,
            CommandType.MOVE_TO,
            f"{actor.role.value} formation slot",
            target_cell=target_cell,
            intent_type=IntentType.SEARCH,
        )
    return None


def most_wounded_treatable_part(actor: Actor) -> tuple[str, float] | None:
    max_hp = {
        "stomach": 70.0,
        "leftArm": 60.0,
        "rightArm": 60.0,
        "leftLeg": 65.0,
        "rightLeg": 65.0,
    }
    missing = [(part, value - actor.body.hp[part]) for part, value in max_hp.items()]
    part, amount = max(missing, key=lambda item: item[1])
    if amount <= 0.0:
        return None
    return part, amount


def share_team_contact(source: Actor, actors: list[Actor], position: Vec2) -> None:
    for ally in actors:
        if ally.alive and ally.team == source.team and ally.id != source.id:
            if ally.last_known_timer <= 0.3:
                ally.last_known_enemy = position
                ally.last_known_timer = 4.5
