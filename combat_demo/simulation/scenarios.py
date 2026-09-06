from __future__ import annotations

from dataclasses import dataclass
from random import Random

from .actor import ActionType, Actor, ActorMode, ActorState, Team
from .body import create_human_body
from .commands import ActorCommand, CommandType
from .combat import resolve_shot
from .geometry import Vec2
from .map import create_full_cover, create_wall
from .movement import set_path_to, update_actor_movement
from .weapon import RIFLE, WeaponState
from .world import World, create_breach_world, create_maze_world, create_world


@dataclass(frozen=True)
class ScenarioResult:
    name: str
    passed: bool
    detail: str


def run_ai_scenarios() -> list[ScenarioResult]:
    return [
        demo_world_initializes(),
        breach_world_initializes(),
        maze_world_initializes(),
        path_can_cross_occupied_cell(),
        final_target_avoids_stationary_overlap(),
        crowding_slows_movement(),
        manual_move_command_moves_actor(),
        manual_open_door_action_opens_door(),
        shot_respects_full_wall(),
        projectile_respects_actual_wall_height(),
        cell_cover_blocks_movement_and_projectiles(),
        shot_hits_clear_target(),
        human_region_hit_resolves_to_seeded_subpart(),
        human_critical_part_damage_kills(),
        human_limb_damage_affects_derived_stats(),
        weapon_shot_angle_has_separate_error_sources(),
        weapon_fire_consumes_ammo_and_adds_recoil(),
        maze_map_has_large_rooms_and_wide_corridors(),
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


def demo_world_initializes() -> ScenarioResult:
    world = create_world()
    passed = len(world.actors) == 6 and world.scenario_name == "demo"
    detail = f"actors={len(world.actors)} scenario={world.scenario_name}"
    return ScenarioResult("demo_world_initializes", passed, detail)


def breach_world_initializes() -> ScenarioResult:
    world = create_breach_world()
    door = world.grid.wall_between((5, 5), (6, 5))
    window = world.grid.wall_between((5, 7), (6, 7))
    passed = (
        len(world.actors) == 6
        and door.kind == "door"
        and door.interactive_id is not None
        and door.blocks_movement
        and window.kind == "window"
        and 1.0 <= window.height <= 1.3
    )
    detail = f"actors={len(world.actors)} door={door.kind}/{door.height:g} window={window.kind}/{window.height:g}"
    return ScenarioResult("breach_world_initializes", passed, detail)


def maze_world_initializes() -> ScenarioResult:
    world = create_maze_world()
    data = world.grid.maze_data
    passed = (
        len(world.actors) >= 7
        and world.scenario_name == "maze"
        and data is not None
        and len(data.rooms) == 9
        and len(data.corridors) >= 8
        and sum(1 for actor in world.actors if actor.team == Team.BLUE) >= 4
    )
    detail = f"actors={len(world.actors)} rooms={len(data.rooms) if data else 0} corridors={len(data.corridors) if data else 0}"
    return ScenarioResult("maze_world_initializes", passed, detail)


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


def manual_move_command_moves_actor() -> ScenarioResult:
    world = create_world()
    actor = world.actors[0]
    place_actor(world, actor, (1, 1))

    world.apply_command(ActorCommand(actor.id, CommandType.MOVE_TO, "manual move", target_cell=(2, 1)))
    for _ in range(40):
        world.update(1.0 / 30.0)

    passed = actor.occupied_cell == (2, 1) and actor.mode == ActorMode.STANDING
    detail = f"occupied={actor.occupied_cell} mode={actor.mode.value}"
    return ScenarioResult("manual_move_command_moves_actor", passed, detail)


def manual_open_door_action_opens_door() -> ScenarioResult:
    world = create_breach_world()
    actor = world.actors[0]
    place_actor(world, actor, (5, 5))

    world.apply_command(
        ActorCommand(
            actor.id,
            CommandType.START_ACTION,
            "manual open door",
            target_position=world.grid.cell_center((6, 5)),
            action_type=ActionType.OPEN_DOOR,
            duration=0.1,
        )
    )
    for _ in range(12):
        world.update(1.0 / 60.0)

    wall = world.grid.wall_between((5, 5), (6, 5))
    passed = wall.kind == "door" and not wall.blocks_movement and wall.height == 0.0
    detail = f"kind={wall.kind} height={wall.height:g} blocks_move={wall.blocks_movement}"
    return ScenarioResult("manual_open_door_action_opens_door", passed, detail)


def shot_respects_full_wall() -> ScenarioResult:
    world = create_world()
    shooter = world.actors[0]
    target = world.actors[3]
    place_actor(world, shooter, (5, 2))
    place_actor(world, target, (8, 2))

    shot = resolve_shot(shooter, target.position, world.grid, world.actors, world.rng, 0.0)

    passed = shot.blocked and shot.hit_actor_id is None
    detail = f"blocked={shot.blocked} hit={shot.hit_actor_id}"
    return ScenarioResult("shot_respects_full_wall", passed, detail)


def projectile_respects_actual_wall_height() -> ScenarioResult:
    world = create_world()
    shooter = world.actors[0]
    target = world.actors[3]
    place_actor(world, shooter, (8, 4))
    place_actor(world, target, (8, 8))
    world.grid.set_edge_feature((8, 5), "S", create_wall(1.6, kind="test_cover"))

    shot = resolve_shot(shooter, target.position, world.grid, world.actors, world.rng, 0.0)
    feature = world.grid.wall_between((8, 5), (8, 6))

    passed = shot.blocked and shot.hit_actor_id is None and feature.height == 1.6
    detail = f"height={feature.height:g} blocked={shot.blocked} hit={shot.hit_actor_id}"
    return ScenarioResult("projectile_respects_actual_wall_height", passed, detail)


def cell_cover_blocks_movement_and_projectiles() -> ScenarioResult:
    world = create_world()
    shooter = world.actors[0]
    target = world.actors[3]
    place_actor(world, shooter, (9, 6))
    place_actor(world, target, (12, 6))
    world.grid.set_cell_feature((10, 6), create_full_cover(1.9))

    can_move_into_cover = world.grid.can_move((9, 6), (10, 6))
    shot = resolve_shot(shooter, target.position, world.grid, world.actors, world.rng, 0.0)

    passed = not can_move_into_cover and shot.blocked and shot.hit_actor_id is None
    detail = f"can_move={can_move_into_cover} blocked={shot.blocked} feature={world.grid.cell_feature_at((10, 6)).kind}"
    return ScenarioResult("cell_cover_blocks_movement_and_projectiles", passed, detail)


def shot_hits_clear_target() -> ScenarioResult:
    world = create_world()
    shooter = world.actors[0]
    target = world.actors[3]
    place_actor(world, shooter, (8, 2))
    place_actor(world, target, (10, 2))

    shot = resolve_shot(shooter, target.position, world.grid, world.actors, world.rng, 0.0)

    passed = shot.hit_actor_id == target.id and shot.damage > 0.0
    detail = f"hit={shot.hit_actor_id} damage={shot.damage:.1f} blocked={shot.blocked}"
    return ScenarioResult("shot_hits_clear_target", passed, detail)


def human_region_hit_resolves_to_seeded_subpart() -> ScenarioResult:
    body = create_human_body()
    hit = body.resolve_hit("left_arm", 10.0, "ballistic", Random(7))

    passed = hit.region_id == "left_arm" and hit.part_id == "left_upper_arm" and hit.damage == 10.0
    detail = f"region={hit.region_id} part={hit.part_id} damage={hit.damage:g}"
    return ScenarioResult("human_region_hit_resolves_to_seeded_subpart", passed, detail)


def human_critical_part_damage_kills() -> ScenarioResult:
    body = create_human_body()
    hit = body.damage_part("brain", 999.0, "ballistic")

    passed = hit.killed and body.dead
    detail = f"part={hit.part_id} killed={hit.killed} brain_hp={body.hp('brain'):.1f}"
    return ScenarioResult("human_critical_part_damage_kills", passed, detail)


def human_limb_damage_affects_derived_stats() -> ScenarioResult:
    body = create_human_body()
    before = body.derived_stats().movement_efficiency
    body.damage_part("left_thigh", 999.0, "ballistic")
    after = body.derived_stats().movement_efficiency

    passed = 0.15 <= after < before
    detail = f"movement_before={before:.2f} movement_after={after:.2f}"
    return ScenarioResult("human_limb_damage_affects_derived_stats", passed, detail)


def weapon_shot_angle_has_separate_error_sources() -> ScenarioResult:
    weapon = WeaponState.create(RIFLE)
    weapon.recoil_error_degrees = 3.0

    angle = weapon.sample_shot_angle(0.0, 4.0, Random(7))

    passed = angle.aim_offset != 0.0 and angle.weapon_offset != 0.0 and angle.recoil_offset != 0.0
    detail = (
        f"aim={angle.aim_offset:.4f} weapon={angle.weapon_offset:.4f} "
        f"recoil={angle.recoil_offset:.4f} final={angle.final_angle:.4f}"
    )
    return ScenarioResult("weapon_shot_angle_has_separate_error_sources", passed, detail)


def weapon_fire_consumes_ammo_and_adds_recoil() -> ScenarioResult:
    weapon = WeaponState.create(RIFLE)

    weapon.consume_round()

    passed = weapon.ammo == RIFLE.magazine_size - 1 and weapon.cooldown == RIFLE.fire_interval and weapon.recoil_error_degrees > 0.0
    detail = f"ammo={weapon.ammo} cooldown={weapon.cooldown:.2f} recoil={weapon.recoil_error_degrees:.1f}"
    return ScenarioResult("weapon_fire_consumes_ammo_and_adds_recoil", passed, detail)


def maze_map_has_large_rooms_and_wide_corridors() -> ScenarioResult:
    world = create_maze_world()
    data = world.grid.maze_data
    room_sizes = [len(room.cells) for room in data.rooms]
    corridor_widths = [min(corridor_span_width(corridor.cells)) for corridor in data.corridors]
    passed = (
        world.grid.width >= 39
        and world.grid.height >= 33
        and min(room_sizes) >= 60
        and min(corridor_widths) >= 3
        and max(corridor_widths) <= 5
    )
    detail = (
        f"size={world.grid.width}x{world.grid.height} "
        f"rooms={min(room_sizes)}-{max(room_sizes)} corridor_widths={corridor_widths}"
    )
    return ScenarioResult("maze_map_has_large_rooms_and_wide_corridors", passed, detail)


def corridor_span_width(cells: tuple[tuple[int, int], ...]) -> tuple[int, int]:
    xs = {cell[0] for cell in cells}
    ys = {cell[1] for cell in cells}
    return len(xs), len(ys)


def standing_cells_do_not_overlap_after_simulation() -> ScenarioResult:
    world = create_world()
    for _ in range(60):
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
