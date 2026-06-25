from __future__ import annotations

from dataclasses import dataclass

from .actor import ActionType, Actor, ActorMode, ActorRole, ActorState, FireMode, IntentType, PeekDirection, Team
from .ai import choose_peek_direction, update_ai
from .combat import ShotEvent, resolve_shot
from .geometry import Vec2
from .map import WallKind
from .movement import set_path_to, update_actor_movement
from .squad import SquadAssignment, SquadPhase, SquadPosture
from .world import World, create_breach_world, create_world


@dataclass(frozen=True)
class ScenarioResult:
    name: str
    passed: bool
    detail: str


def run_ai_scenarios() -> list[ScenarioResult]:
    return [
        hit_reaction_contact(),
        gunshot_contact(),
        squad_assigns_contact_roles(),
        squad_tempo_allows_one_bounder(),
        support_suppression(),
        friendly_fire_hold(),
        bandage_when_safe(),
        path_can_cross_occupied_cell(),
        final_target_avoids_stationary_overlap(),
        crowding_slows_movement(),
        moving_actor_delays_engagement(),
        standing_actor_can_engage_after_move(),
        actor_peeks_from_current_cover(),
        peek_shot_uses_offset_origin(),
        shot_hits_peeking_target_offset(),
        breach_ai_stacks_and_opens_door(),
        breach_ai_enters_room(),
        standing_cells_do_not_overlap_after_simulation(),
    ]


def place_actor(world: World, actor: Actor, cell: tuple[int, int]) -> None:
    actor.mode = ActorMode.STANDING
    actor.occupied_cell = cell
    actor.reserved_cell = None
    actor.route.clear()
    actor.path.clear()
    actor.move_from = None
    actor.move_to = None
    actor.move_progress = 0.0
    actor.target_cell = None
    actor.position = world.grid.cell_center(cell)


def start_actor_move(
    world: World,
    actor: Actor,
    from_cell: tuple[int, int],
    to_cell: tuple[int, int],
    progress: float = 0.0,
) -> None:
    actor.mode = ActorMode.MOVING
    actor.occupied_cell = None
    actor.reserved_cell = to_cell
    actor.route = [to_cell]
    actor.path = [to_cell]
    actor.move_from = from_cell
    actor.move_to = to_cell
    actor.move_progress = progress
    start = world.grid.cell_center(from_cell)
    end = world.grid.cell_center(to_cell)
    actor.position = start + (end - start) * progress
    actor.target_cell = to_cell


def issue_ai_command(world: World, actor: Actor) -> None:
    command = update_ai(actor, world.actors, world.grid, world.squads[actor.team], 0.1, 1, world.time)
    if command is not None:
        world.apply_command(command, 0.1)


def hit_reaction_contact() -> ScenarioResult:
    world = create_world()
    victim = world.actors[0]
    shooter = world.actors[3]
    victim.facing = 3.14
    shot = ShotEvent(shooter.position, victim.position, shooter.team.value, damage=24.0, hit_actor_id=victim.id, hit_part="stomach")

    world._apply_hit_reaction(victim, shooter, shot)
    world.update(0.1)

    squad = world.squads[victim.team]
    contact = squad.best_contact()
    passed = (
        contact is not None
        and contact.source == "hit_reaction"
        and contact.confidence >= 0.55
        and victim.intent.type in (IntentType.INVESTIGATE, IntentType.SEEK_COVER)
        and victim.suppression > 0.0
    )
    detail = f"contact={contact.source if contact else 'none'} intent={victim.intent.label} suppression={victim.suppression:.1f}"
    return ScenarioResult("hit_reaction_contact", passed, detail)


def gunshot_contact() -> ScenarioResult:
    world = create_world()
    shooter = world.actors[3]
    shooter.position = Vec2(12.5, 6.5)
    for actor in world.actors:
        if actor.team == Team.RED:
            actor.facing = 3.14

    world._notify_gunshot(shooter)
    world.update(0.1)

    squad = world.squads[Team.RED]
    contact = squad.best_contact()
    responders = [
        actor
        for actor in world.actors
        if actor.team == Team.RED
        and actor.intent.type in (IntentType.INVESTIGATE, IntentType.SUPPRESS, IntentType.HOLD_POSITION)
    ]
    passed = (
        contact is not None
        and contact.source == "gunshot"
        and squad.posture == SquadPosture.CONTACT
        and len(responders) >= 1
    )
    detail = f"posture={squad.posture.value} contact={contact.source if contact else 'none'} responders={len(responders)}"
    return ScenarioResult("gunshot_contact", passed, detail)


def squad_assigns_contact_roles() -> ScenarioResult:
    world = create_world()
    squad = world.squads[Team.RED]
    squad.add_contact(Vec2(10.5, 6.5), source="ally_report", confidence=0.8, now=world.time, enemy_id=3)
    squad.update(world.time, 0.0)
    squad.update_assignments([actor for actor in world.actors if actor.team == Team.RED])

    assignments = {actor.role: squad.assignment_for(actor) for actor in world.actors if actor.team == Team.RED}
    passed = (
        assignments.get(ActorRole.POINTMAN) == SquadAssignment.CONTACT_LEAD
        and assignments.get(ActorRole.SUPPORT) == SquadAssignment.BASE_OF_FIRE
        and assignments.get(ActorRole.RIFLEMAN) == SquadAssignment.FLANK
    )
    detail = " ".join(
        f"{role.value}={assignment.value if assignment else 'none'}"
        for role, assignment in assignments.items()
    )
    return ScenarioResult("squad_assigns_contact_roles", passed, detail)


def squad_tempo_allows_one_bounder() -> ScenarioResult:
    world = create_world()
    squad = world.squads[Team.RED]
    actors = [actor for actor in world.actors if actor.team == Team.RED]
    squad.add_contact(Vec2(10.5, 6.5), source="ally_report", confidence=0.8, now=world.time, enemy_id=3)
    squad.update(world.time, 0.0)
    squad.update_assignments(actors)
    squad.update_tempo(actors, 0.1)
    squad.update_tempo(actors, 1.0)

    for actor in actors:
        command = update_ai(actor, world.actors, world.grid, squad, 0.1, 1, world.time)
        if command is not None:
            world.apply_command(command, 0.1)

    bound = next((actor for actor in actors if actor.id == squad.bound_actor_id), None)
    movers = [
        actor
        for actor in actors
        if actor.intent.target_cell is not None
        and actor.intent.type in (IntentType.INVESTIGATE, IntentType.SEEK_COVER, IntentType.SUPPRESS)
    ]
    waiting = [
        actor
        for actor in actors
        if actor is not bound
        and actor.intent.type in (IntentType.HOLD_POSITION, IntentType.SUPPRESS)
        and "wait for bound" in actor.intent.reason
    ]
    passed = (
        squad.phase == SquadPhase.BOUNDING
        and bound is not None
        and len(movers) == 1
        and movers[0] is bound
        and len(waiting) >= 1
    )
    detail = (
        f"phase={squad.phase.value} bound={bound.name if bound else 'none'} "
        f"movers={[actor.name for actor in movers]} waiting={[actor.name for actor in waiting]}"
    )
    return ScenarioResult("squad_tempo_allows_one_bounder", passed, detail)


def support_suppression() -> ScenarioResult:
    world = create_world()
    support = world.actors[2]
    squad = world.squads[support.team]
    contact_position = Vec2(10.5, 8.5)

    squad.add_contact(contact_position, source="ally_report", confidence=0.8, now=world.time, enemy_id=3)
    squad.update(world.time, 0.0)
    issue_ai_command(world, support)

    passed = support.role == ActorRole.SUPPORT and support.intent.type == IntentType.SUPPRESS
    detail = f"role={support.role.value} intent={support.intent.label}"
    return ScenarioResult("support_suppression", passed, detail)


def friendly_fire_hold() -> ScenarioResult:
    world = create_world()
    shooter = world.actors[0]
    ally = world.actors[1]
    target = world.actors[3]
    shooter.position = Vec2(5.5, 5.5)
    ally.position = Vec2(7.5, 5.5)
    target.position = Vec2(9.5, 5.5)

    mode, reason = world._choose_fire_mode(shooter, target)

    passed = mode == FireMode.HOLD_FIRE
    detail = f"mode={mode.value} reason={reason}"
    return ScenarioResult("friendly_fire_hold", passed, detail)


def bandage_when_safe() -> ScenarioResult:
    world = create_world()
    actor = world.actors[1]
    actor.body.damage("leftArm", 30.0)

    issue_ai_command(world, actor)

    action = actor.current_action.type if actor.current_action is not None else None
    passed = action == ActionType.BANDAGE and actor.intent.type == IntentType.ACTION
    detail = f"action={action.value if action else 'none'} intent={actor.intent.label}"
    return ScenarioResult("bandage_when_safe", passed, detail)


def path_can_cross_occupied_cell() -> ScenarioResult:
    world = create_world()
    mover = world.actors[0]
    blocker = world.actors[1]
    place_actor(world, mover, (1, 1))
    place_actor(world, blocker, (2, 1))

    set_path_to(mover, world.grid, world.actors, (3, 1))

    passed = (2, 1) in mover.path and mover.target_cell == (3, 1)
    detail = f"path={mover.path} target={mover.target_cell}"
    return ScenarioResult("path_can_cross_occupied_cell", passed, detail)


def final_target_avoids_stationary_overlap() -> ScenarioResult:
    world = create_world()
    mover = world.actors[0]
    occupant = world.actors[1]
    place_actor(world, mover, (1, 1))
    place_actor(world, occupant, (3, 1))

    set_path_to(mover, world.grid, world.actors, (3, 1))

    passed = mover.target_cell is not None and mover.target_cell != (3, 1)
    detail = f"requested=(3, 1) target={mover.target_cell} path={mover.path}"
    return ScenarioResult("final_target_avoids_stationary_overlap", passed, detail)


def crowding_slows_movement() -> ScenarioResult:
    clear_world = create_world()
    clear_mover = clear_world.actors[0]
    start_actor_move(clear_world, clear_mover, (1, 1), (2, 1))
    clear_start_x = clear_mover.position.x
    update_actor_movement(clear_mover, clear_world.grid, clear_world.actors, 0.2)
    clear_delta = clear_mover.position.x - clear_start_x

    crowded_world = create_world()
    crowded_mover = crowded_world.actors[0]
    neighbor = crowded_world.actors[1]
    start_actor_move(crowded_world, crowded_mover, (1, 1), (2, 1))
    place_actor(crowded_world, neighbor, (1, 1))
    neighbor.position = Vec2(1.7, 1.5)
    crowded_start_x = crowded_mover.position.x
    update_actor_movement(crowded_mover, crowded_world.grid, crowded_world.actors, 0.2)
    crowded_delta = crowded_mover.position.x - crowded_start_x

    passed = 0.0 < crowded_delta < clear_delta
    detail = f"clear_delta={clear_delta:.3f} crowded_delta={crowded_delta:.3f}"
    return ScenarioResult("crowding_slows_movement", passed, detail)


def moving_actor_delays_engagement() -> ScenarioResult:
    world = create_world()
    mover = world.actors[0]
    enemy = world.actors[3]
    start_actor_move(world, mover, (5, 5), (6, 5), progress=0.2)
    mover.facing = 0.0
    mover.state = ActorState.ENGAGE
    mover.target_id = enemy.id
    place_actor(world, enemy, (8, 5))
    enemy.facing = 0.0

    world.update(0.1)

    passed = mover.intent.type == IntentType.MOVE_TO and len(world.shots) == 0 and mover.weapon.ammo == mover.weapon.spec.magazine_size
    detail = f"intent={mover.intent.label} shots={len(world.shots)} ammo={mover.weapon.ammo}"
    return ScenarioResult("moving_actor_delays_engagement", passed, detail)


def standing_actor_can_engage_after_move() -> ScenarioResult:
    world = create_world()
    actor = world.actors[0]
    enemy = world.actors[3]
    place_actor(world, actor, (5, 5))
    actor.facing = 0.0
    place_actor(world, enemy, (8, 5))

    issue_ai_command(world, actor)

    passed = actor.intent.type == IntentType.ENGAGE and actor.state == ActorState.ENGAGE
    detail = f"state={actor.state.value} intent={actor.intent.label}"
    return ScenarioResult("standing_actor_can_engage_after_move", passed, detail)


def actor_peeks_from_current_cover() -> ScenarioResult:
    world = create_world()
    actor = world.actors[0]
    enemy = world.actors[3]
    place_actor(world, actor, (5, 5))
    place_actor(world, enemy, (5, 3))
    actor.facing = -1.57
    enemy.facing = 1.57
    world.grid.set_wall((5, 5), "N", WallKind.FULL)

    issue_ai_command(world, actor)

    passed = (
        actor.intent.type == IntentType.ENGAGE
        and actor.peek_direction in (PeekDirection.E, PeekDirection.W)
        and actor.target_cell is None
        and not actor.route
    )
    detail = f"intent={actor.intent.label} peek={actor.peek_direction} route={actor.route}"
    return ScenarioResult("actor_peeks_from_current_cover", passed, detail)


def peek_shot_uses_offset_origin() -> ScenarioResult:
    world = create_world()
    actor = world.actors[0]
    enemy = world.actors[3]
    place_actor(world, actor, (5, 5))
    place_actor(world, enemy, (5, 3))
    world.grid.set_wall((5, 5), "N", WallKind.FULL)

    peek = choose_peek_direction(actor, world.grid, enemy.position)

    passed = peek is not None and peek[0] in (PeekDirection.E, PeekDirection.W) and peek[1] == PeekDirection.N
    detail = f"peek={peek}"
    return ScenarioResult("peek_shot_uses_offset_origin", passed, detail)


def shot_hits_peeking_target_offset() -> ScenarioResult:
    world = create_world()
    shooter = world.actors[0]
    target = world.actors[3]
    place_actor(world, shooter, (8, 2))
    place_actor(world, target, (10, 2))
    target.peek_direction = PeekDirection.N
    target.peek_cover_direction = PeekDirection.W

    shot = resolve_shot(shooter, target.position + Vec2(-0.52, -0.52), world.grid, world.actors, world.rng, 0.0)

    passed = shot.hit_actor_id == target.id and shot.end.y < target.position.y
    detail = f"hit={shot.hit_actor_id} end=({shot.end.x:.2f},{shot.end.y:.2f}) target_y={target.position.y:.2f}"
    return ScenarioResult("shot_hits_peeking_target_offset", passed, detail)


def breach_ai_stacks_and_opens_door() -> ScenarioResult:
    world = create_breach_world()
    for _ in range(160):
        world.update(1.0 / 30.0)

    memory = world.breach_memory
    door_open = world.grid.wall_between((5, 5), (6, 5)) == WallKind.DOOR_OPEN
    red_intents = [actor.intent.reason for actor in world.actors if actor.team == Team.RED]
    passed = memory is not None and door_open and memory.stage.value in ("breach", "clear", "stabilize")
    detail = f"stage={memory.stage.value if memory else 'none'} door_open={door_open} intents={red_intents}"
    return ScenarioResult("breach_ai_stacks_and_opens_door", passed, detail)


def breach_ai_enters_room() -> ScenarioResult:
    world = create_breach_world()
    for _ in range(260):
        world.update(1.0 / 30.0)

    memory = world.breach_memory
    assert memory is not None
    red_inside = [
        actor.name
        for actor in world.actors
        if actor.team == Team.RED and (actor.occupied_cell or world.grid.cell_of(actor.position)) in memory.plan.room_cells
    ]
    support = next(actor for actor in world.actors if actor.team == Team.RED and actor.role == ActorRole.SUPPORT)
    support_cell = support.occupied_cell or world.grid.cell_of(support.position)
    passed = memory.stage.value in ("clear", "stabilize") and (support_cell == memory.plan.window_outside or support_cell in memory.plan.room_cells)
    detail = f"stage={memory.stage.value} inside={red_inside} support={support.intent.label}"
    return ScenarioResult("breach_ai_enters_room", passed, detail)


def standing_cells_do_not_overlap_after_simulation() -> ScenarioResult:
    world = create_world()
    for _ in range(180):
        world.update(1.0 / 30.0)
        occupied: list[tuple[Team, tuple[int, int]]] = [
            (actor.team, actor.occupied_cell)
            for actor in world.actors
            if actor.alive and actor.mode in (ActorMode.STANDING, ActorMode.ACTING) and actor.occupied_cell is not None
        ]
        cells = [cell for _, cell in occupied]
        if len(cells) != len(set(cells)):
            return ScenarioResult("standing_cells_do_not_overlap_after_simulation", False, f"occupied={occupied}")
    final_cells = [
        actor.occupied_cell
        for actor in world.actors
        if actor.alive and actor.mode in (ActorMode.STANDING, ActorMode.ACTING)
    ]
    return ScenarioResult("standing_cells_do_not_overlap_after_simulation", True, f"final={final_cells}")
