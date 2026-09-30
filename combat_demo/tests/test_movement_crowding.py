from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from simulation.actor import Actor, FireMode, Team
from simulation.geometry import Vec2
from simulation.map import GridMap, create_wall
from simulation.mission import create_mission
from simulation.movement import (begin_next_move_step, movement_allowances,
                                 stop_actor_at_cell, update_actor_movement)
from simulation.world import World


def actor(grid, i, cell):
    a = Actor(i, str(i), Team.RED, grid.cell_center(cell), 0)
    a.fire_mode = FireMode.HOLD_FIRE
    stop_actor_at_cell(a, grid, cell)
    return a


def route(a, grid, goal, via=()):
    path = []
    start = a.occupied_cell
    for end in (*via, goal):
        part = grid.find_path(start, end)
        assert part, (start, end)
        path.extend(part if not path else part[1:])
        start = end
    a.route = path
    a.path = list(path)
    a.target_cell = a.reserved_cell = goal


def tick(grid, actors, dt=1/60):
    distances = movement_allowances(actors, grid, dt)
    for a in actors:
        update_actor_movement(a, grid, actors, dt, rotate=False, distance_budget=distances[a.id])


class MovementCrowdingTests(unittest.TestCase):
    def test_overlapping_pair_both_move_and_only_one_slows(self):
        grid = GridMap(20, 3)
        actors = [actor(grid, i, (1, 1)) for i in (1, 2)]
        for a in actors:
            route(a, grid, (15+a.id, 1))
        for _ in range(20):
            before = [a.position for a in actors]
            tick(grid, actors)
            distances = [a.position.distance_to(p) for a, p in zip(actors, before)]
            self.assertAlmostEqual(distances[0], 2/60)
            self.assertAlmostEqual(distances[1], 2*.45/60)

    def test_overlapping_pair_separates_and_leader_keeps_full_speed(self):
        grid = GridMap(30, 5)
        actors = [actor(grid, i, (1, 2)) for i in (1, 2)]
        for a in actors:
            route(a, grid, (20+a.id, 2))
        for _ in range(240):
            tick(grid, actors)
        self.assertAlmostEqual(actors[0].position.x-1.5, 8, delta=.04)
        self.assertGreater(actors[1].position.x-1.5, 6.5)
        self.assertAlmostEqual(actors[0].position.distance_to(actors[1].position), 1.37, delta=.06)

    def test_four_overlapping_movers_are_independent_of_update_order(self):
        results = []
        for reverse in (False, True):
            grid = GridMap(30, 5)
            actors = [actor(grid, i, (1, 2)) for i in (1, 2, 3, 4)]
            for a in actors:
                route(a, grid, (20+a.id, 2))
            if reverse:
                actors.reverse()
            for _ in range(240):
                tick(grid, actors)
            results.append({a.id: a.position for a in actors})
        self.assertEqual(*results)
        self.assertGreater(results[0][4].x-1.5, 3)
        for i in (1, 2, 3):
            self.assertGreaterEqual(results[0][i].x-results[0][i+1].x, .819)

    def test_equal_speed_priority_stays_fixed_while_positions_swap(self):
        grid = GridMap(20, 3)
        behind, front = [actor(grid, i, (1, 1)) for i in (1, 2)]
        for a in (behind, front):
            route(a, grid, (15+a.id, 1))
        begin_next_move_step(front, grid)
        front.move_progress = .4
        front.position = grid.cell_center((1, 1)) + Vec2(.4, 0)
        for _ in range(180):
            before = behind.position
            tick(grid, [behind, front])
            self.assertAlmostEqual(behind.position.x-before.x, 2/60)
        self.assertGreater(behind.position.x-front.position.x, .819)

    def test_different_speeds_separate_without_slowing_the_faster_mover(self):
        grid = GridMap(20, 3)
        front, behind = actor(grid, 2, (2, 1)), actor(grid, 1, (1, 1))
        front.speed = .6
        for a in (front, behind):
            route(a, grid, (15+a.id, 1))
        for _ in range(300):
            tick(grid, [behind, front])
        self.assertAlmostEqual(behind.position.x-1.5, 10, delta=.04)
        self.assertGreater(behind.position.x-front.position.x, .82)
        self.assertGreater(front.position.x-2.5, 2)

    def test_diagonal_routes_merge_into_a_moving_queue(self):
        grid = GridMap(20, 5)
        actors = [actor(grid, 1, (1, 1)), actor(grid, 2, (1, 3))]
        for a in actors:
            route(a, grid, (15+a.id, 2), via=((2, 2),))
        for _ in range(240):
            tick(grid, actors)
        self.assertGreater(min(a.position.x for a in actors), 6)
        self.assertGreaterEqual(actors[0].position.distance_to(actors[1].position), .819)

    def test_crossing_movers_continue_and_both_reach_exact_goals(self):
        grid = GridMap(10, 10)
        actors = [actor(grid, 1, (1, 4)), actor(grid, 2, (4, 1))]
        goals = {1: (8, 4), 2: (4, 8)}
        for a in actors:
            route(a, grid, goals[a.id])
        for _ in range(360):
            before = {a.id: a.position for a in actors}
            tick(grid, actors)
            for a in actors:
                if a.occupied_cell != goals[a.id]:
                    self.assertGreater(a.position.distance_to(before[a.id]), 1e-9)
        self.assertEqual({a.id: a.occupied_cell for a in actors}, goals)

    def test_head_on_in_single_cell_corridor_cannot_deadlock(self):
        grid = GridMap(12, 1)
        actors = [actor(grid, 1, (1, 0)), actor(grid, 2, (10, 0))]
        goals = {1: (10, 0), 2: (1, 0)}
        for a in actors:
            route(a, grid, goals[a.id])
        for _ in range(420):
            tick(grid, actors)
        self.assertEqual({a.id: a.occupied_cell for a in actors}, goals)

    def test_stationary_and_stunned_bodies_remain_passable(self):
        for stunned in (False, True):
            with self.subTest(stunned=stunned):
                grid = GridMap(12, 1)
                mover, occupant = actor(grid, 1, (1, 0)), actor(grid, 2, (3, 0))
                route(mover, grid, (8, 0))
                if stunned:
                    route(occupant, grid, (10, 0))
                    occupant.stunned = 20
                for _ in range(360):
                    tick(grid, [mover, occupant])
                self.assertEqual(mover.occupied_cell, (8, 0))
                self.assertEqual(occupant.position, grid.cell_center((3, 0)))

    def test_a_wall_prevents_body_crowding_across_it(self):
        grid = GridMap(4, 4)
        grid.set_edge_feature((1, 1), 'E', create_wall(3))
        mover, occupant = actor(grid, 1, (1, 1)), actor(grid, 2, (2, 1))
        route(mover, grid, (1, 2))
        mover.position, occupant.position = Vec2(1.9, 1.5), Vec2(2.1, 1.5)
        distances = movement_allowances([mover, occupant], grid, 1/60)
        self.assertAlmostEqual(distances[mover.id], mover.speed/60)

    def test_task_members_keep_moving_and_draft_order_is_unchanged(self):
        world = create_mission()
        for a in world.actors:
            a.ai_enabled = False
            a.fire_mode = FireMode.HOLD_FIRE
        for i in (1, 2):
            stop_actor_at_cell(world.actor(i), world.grid, (34, 33))
        draft, error = world.planner.preview_task([2, 1], 'door_S_R', 'R', 'direct',
            stack_overrides={2: (34, 31), 1: (34, 30)}, after_entry='hold')
        self.assertIsNone(error)
        self.assertIsNone(world.planner.submit_task(draft))
        world.set_paused(False)
        world.update(1/60)
        self.assertLess(world.actor(2).position.y, 33.5)
        self.assertLess(world.actor(1).position.y, 33.5)
        self.assertEqual(next(iter(world.planner.tasks.values())).draft.actors, [2, 1])

    def slow_world(self):
        grid = GridMap(40, 5)
        first, second = [actor(grid, i, (1, 2)) for i in (1, 2)]
        enemy = actor(grid, 9, (39, 4))
        enemy.team = Team.BLUE
        world = World(grid, [first, second, enemy])
        for a in (first, second):
            self.assertIsNone(world.planner.submit([a.id], 'move', cell=(20+a.id, 2)))
        first.speed = .1
        return world

    def test_slow_teammate_does_not_stop_or_suspend_other_mover(self):
        world = self.slow_world()
        for _ in range(360):
            world.update(1/60)
        follower = world.actor(2)
        self.assertGreater(follower.position.x, 13)
        self.assertFalse(follower.blocked_reason)
        self.assertEqual(follower.queue[0].status, 'running')
        self.assertEqual(follower.response, '执行微操')
        self.assertGreater(world.actor(1).position.x, 2)

    def test_real_stall_uses_normal_timeout(self):
        world = self.slow_world()
        follower = world.actor(2)
        world.planner.stalls[2] = (follower.position, 4.99, True)
        world.planner.drive(follower, (22, 2), .02)
        self.assertIn('5 秒', follower.blocked_reason)

    def test_dead_actor_does_not_refresh_remaining_slowdown(self):
        grid = GridMap(20, 3)
        actors = [actor(grid, i, (1, 1)) for i in (1, 2)]
        for a in actors:
            route(a, grid, (15+a.id, 1))
        tick(grid, actors)
        actors[0].body.damage_part('brain', 999)
        actors[0].mark_dead_if_needed()
        before = actors[1].position
        tick(grid, actors)
        self.assertAlmostEqual(actors[1].position.distance_to(before), 2*.45/60)
        for _ in range(30):
            tick(grid, actors)
        self.assertEqual(actors[1].crowd_slow_remaining, 0)
        before = actors[1].position
        tick(grid, actors)
        self.assertAlmostEqual(actors[1].position.distance_to(before), 2/60)

    def test_no_slowdown_before_overlap_and_separation_keeps_slowdown(self):
        grid = GridMap(20, 3)
        actors = [actor(grid, i, (1, 1)) for i in (1, 2)]
        for a in actors:
            route(a, grid, (15+a.id, 1))
        begin_next_move_step(actors[1], grid)
        for separation, expected in ((.84, 1), (.8, .45), (.84, .45)):
            actors[1].move_progress = separation
            actors[1].position = grid.cell_center((1, 1)) + Vec2(separation, 0)
            distances = movement_allowances(actors, grid, 1/60)
            self.assertAlmostEqual(distances[1], 2/60)
            self.assertAlmostEqual(distances[2], 2*expected/60)

    def separated_pair(self):
        grid = GridMap(20, 3)
        actors = [actor(grid, i, (1, 1)) for i in (1, 2)]
        for a in actors:
            route(a, grid, (15+a.id, 1))
        movement_allowances(actors, grid, 1/60)
        stop_actor_at_cell(actors[0], grid, (1, 2))
        return grid, actors

    def test_slowdown_expires_after_half_a_simulation_second(self):
        grid, actors = self.separated_pair()
        for dt in (.49, .009, .001):
            distances = movement_allowances(actors, grid, dt)
            self.assertAlmostEqual(distances[2], 2*.45*dt)
        self.assertEqual(actors[1].crowd_slow_remaining, 0)
        self.assertAlmostEqual(movement_allowances(actors, grid, .1)[2], .2)

    def test_timer_expiry_within_a_step_only_slows_remaining_duration(self):
        grid, actors = self.separated_pair()
        movement_allowances(actors, grid, .49)
        self.assertAlmostEqual(movement_allowances(actors, grid, .02)[2], 2*(.45*.01+.01))
        self.assertEqual(actors[1].crowd_slow_remaining, 0)

    def test_repeated_contact_refreshes_half_second_without_stacking(self):
        grid, actors = self.separated_pair()
        movement_allowances(actors, grid, .4)
        stop_actor_at_cell(actors[0], grid, (1, 1))
        route(actors[0], grid, (16, 1))
        distances = movement_allowances(actors, grid, .01)
        self.assertAlmostEqual(distances[2], 2*.45*.01)
        self.assertEqual(actors[1].crowd_slow_remaining, .5)
        stop_actor_at_cell(actors[0], grid, (1, 2))
        self.assertAlmostEqual(movement_allowances(actors, grid, .49)[2], 2*.45*.49)
        self.assertAlmostEqual(actors[1].crowd_slow_remaining, .01)

    def test_pause_freezes_timer_and_standing_does_not_clear_it(self):
        world = self.slow_world()
        a = world.actor(2)
        a.crowd_slow_remaining = .5
        stop_actor_at_cell(a, world.grid, (4, 2))
        world.planner.stop([a.id])
        self.assertEqual(a.crowd_slow_remaining, .5)
        world.set_paused(True)
        world.update(10)
        self.assertEqual(a.crowd_slow_remaining, .5)
        world.set_paused(False)
        for _ in range(30):
            world.update(1/60)
        self.assertEqual(a.crowd_slow_remaining, 0)

    def test_multiple_overlaps_do_not_stack_the_slowdown(self):
        grid = GridMap(20, 3)
        actors = [actor(grid, i, (1, 1)) for i in (1, 2, 3, 4)]
        for a in actors:
            route(a, grid, (12+a.id, 1))
        tick(grid, actors)
        self.assertAlmostEqual(actors[0].position.x-1.5, 2/60)
        for a in actors[1:]:
            self.assertAlmostEqual(a.position.x-1.5, 2*.45/60)


if __name__ == '__main__':
    unittest.main()
