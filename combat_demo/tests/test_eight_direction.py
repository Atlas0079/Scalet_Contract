from pathlib import Path
import sys
import unittest
from heapq import heappop, heappush
from math import hypot, inf, sqrt
from random import Random

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from simulation.actor import Actor, FireMode, Team
from simulation.map import (GridMap, create_wall, create_full_cover, create_door,
                            create_door_interactable)
from simulation.mission import create_mission
from simulation.movement import (set_path_to, stop_actor_at_cell,
                                 update_actor_movement, reachable_cells_within)
from simulation.perception import enemy_move


class EightDirectionTests(unittest.TestCase):
    def test_neighbors_and_open_ground_cost(self):
        grid = GridMap(8, 8)
        self.assertEqual(len(grid.neighbors((3, 3))), 8)
        self.assertEqual(len(grid.neighbors((0, 0))), 3)
        self.assertAlmostEqual(grid.path_cost(grid.find_path((0, 0), (5, 3))), 2 + 3 * sqrt(2))
        self.assertEqual(grid.path_cost([(2, 2)]), 0)
        self.assertEqual(grid.path_cost([]), inf)
        self.assertFalse(grid.can_move((1, 1), (3, 3)))
        self.assertFalse(grid.can_move((1, 1), (1, 1)))

    def test_one_side_allows_diagonal_but_two_sides_block_it(self):
        for dx, dy in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
            a, b = (2, 2), (2 + dx, 2 + dy)
            for side in [(b[0], a[1]), (a[0], b[1])]:
                with self.subTest(dx=dx, dy=dy, side=side):
                    grid = GridMap(5, 5)
                    grid.set_cell_feature(side, create_full_cover())
                    self.assertTrue(grid.can_move(a, b))
                    self.assertTrue(grid.can_move(b, a))
                    self.assertIn(b, grid.neighbors(a))
                    self.assertAlmostEqual(grid.path_cost(grid.find_path(a, b)), sqrt(2))
                    for other in [(b[0], a[1]), (a[0], b[1])]:
                        if other != side:
                            grid.set_cell_feature(other, create_full_cover())
                    self.assertFalse(grid.can_move(a, b))
                    self.assertFalse(grid.can_move(b, a))
                    self.assertGreater(grid.path_cost(grid.find_path(a, b)), sqrt(2))

    def test_edges_block_diagonal_only_when_both_side_routes_are_closed(self):
        for dx, dy in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
            a, b = (2, 2), (2 + dx, 2 + dy)
            h, v = (b[0], a[1]), (a[0], b[1])
            for p, q in [(a, h), (h, b)]:
                for r, s in [(a, v), (v, b)]:
                    grid = GridMap(5, 5)
                    grid.set_edge_feature(p, grid.edge_between(p, q)[0][2], create_wall(1))
                    self.assertTrue(grid.can_move(a, b))
                    self.assertTrue(grid.can_move(b, a))
                    grid.set_edge_feature(r, grid.edge_between(r, s)[0][2], create_wall(1))
                    self.assertFalse(grid.can_move(a, b))
                    self.assertFalse(grid.can_move(b, a))
                    self.assertNotIn(b, grid.neighbors(a, allow_vault=True, allow_doors=True))

    def test_door_opening_invalidates_path_and_respects_player_knowledge(self):
        grid = GridMap(3, 3)
        grid.set_edge_feature((0, 0), 'S', create_wall(3))
        feature = create_door()
        grid.set_edge_feature((0, 0), 'E', feature)
        door = create_door_interactable((0, 0), 'E', feature.id)
        feature.interactive_id = door.id
        grid.add_interactable(door)
        self.assertEqual(grid.find_path((0, 0), (1, 1)), [])
        grid.open_interactable_between((0, 0), (1, 0))
        self.assertAlmostEqual(grid.path_cost(grid.find_path((0, 0), (1, 1))), sqrt(2))
        for known in [{}, {door.id: 'closed'}]:
            self.assertFalse(grid.can_move((0, 0), (1, 1), known_doors=known))
            self.assertEqual(grid.find_path((0, 0), (1, 1), known_doors=known), [])
        self.assertTrue(grid.can_move((0, 0), (1, 1), known_doors={door.id: 'open'}))

    def test_diagonal_requires_one_consistently_clear_and_allowed_side(self):
        grid = GridMap(3, 3)
        allowed = {(0, 0), (0, 1), (1, 1)}
        self.assertEqual(grid.find_path((0, 0), (1, 1), allowed_cells=allowed), [(0, 0), (1, 1)])
        self.assertEqual(grid.find_path((0, 0), (1, 1), blocked={(1, 0)}), [(0, 0), (1, 1)])
        self.assertEqual(grid.find_path((0, 0), (1, 1), allowed_cells={(0, 0), (1, 1)}), [])
        self.assertEqual(grid.find_path((0, 0), (1, 1), blocked={(1, 0), (0, 1)}), [])
        grid.set_edge_feature((0, 0), 'S', create_wall(3))
        self.assertEqual(grid.find_path((0, 0), (1, 1), allowed_cells=allowed), [])
        self.assertEqual(grid.find_path((0, 0), (1, 1), blocked={(1, 0)}), [])

    def test_mixed_cell_and_edge_obstacles_and_occupied_destination(self):
        grid = GridMap(4, 4)
        grid.set_cell_feature((2, 1), create_full_cover())
        self.assertTrue(grid.can_move((1, 1), (2, 2)))
        grid.set_edge_feature((1, 2), 'E', create_wall(3))
        self.assertFalse(grid.can_move((1, 1), (2, 2)))
        grid = GridMap(4, 4)
        grid.set_cell_feature((2, 2), create_full_cover())
        self.assertFalse(grid.can_move((1, 1), (2, 2)))
        self.assertEqual(grid.find_path((1, 1), (2, 2)), [])

    def test_weighted_shortest_paths_match_independent_dijkstra(self):
        rng = Random(142)
        for _ in range(12):
            grid = GridMap(9, 9)
            for y in range(9):
                for x in range(9):
                    if (x, y) not in {(0, 0), (8, 8)} and rng.random() < .2:
                        grid.set_cell_feature((x, y), create_full_cover())
            costs, queue = {(0, 0): 0.0}, [(0.0, (0, 0))]
            while queue:
                cost, current = heappop(queue)
                if cost > costs[current]:
                    continue
                for nxt in grid.neighbors(current):
                    candidate = cost + hypot(nxt[0]-current[0], nxt[1]-current[1])
                    if candidate < costs.get(nxt, inf):
                        costs[nxt] = candidate
                        heappush(queue, (candidate, nxt))
            path = grid.find_path((0, 0), (8, 8))
            self.assertAlmostEqual(grid.path_cost(path), costs.get((8, 8), inf))
            self.assertTrue(all(grid.can_move(a, b) for a, b in zip(path, path[1:])))
            self.assertEqual(path, grid.find_path((0, 0), (8, 8)))

    def test_diagonal_duration_matches_physical_distance(self):
        grid = GridMap(4, 4)
        durations = []
        for target in [(2, 1), (2, 2)]:
            actor = Actor(1, 'test', Team.RED, grid.cell_center((1, 1)), .7)
            stop_actor_at_cell(actor, grid, (1, 1))
            set_path_to(actor, grid, [actor], target)
            ticks = 0
            while actor.occupied_cell != target and ticks < 3000:
                update_actor_movement(actor, grid, [actor], .001, rotate=False)
                ticks += 1
            duration = ticks * .001
            self.assertLess(abs(duration - hypot(target[0]-1, target[1]-1) / actor.speed), .0011)
            self.assertEqual(actor.facing, .7)
            durations.append(duration)
        self.assertLess(abs(durations[1] / durations[0] - sqrt(2)), .004)

    def test_reachable_radius_uses_distance_not_number_of_steps(self):
        grid = GridMap(7, 7)
        actor = Actor(1, 'test', Team.RED, grid.cell_center((3, 3)), 0)
        stop_actor_at_cell(actor, grid, (3, 3))
        cells = reachable_cells_within(actor, grid, [actor], 2)
        self.assertIn((4, 4), cells)
        self.assertIn((5, 3), cells)
        self.assertNotIn((5, 5), cells)
        self.assertNotIn((5, 4), cells)

    def test_player_waypoint_and_enemy_use_diagonal_paths(self):
        world = create_mission()
        for actor in world.actors:
            actor.ai_enabled = False
            actor.fire_mode = FireMode.HOLD_FIRE
        ally, enemy = world.actor(1), world.actors[4]
        stop_actor_at_cell(ally, world.grid, (31, 32))
        ally.facing = ally.guard_angle = .7
        self.assertIsNone(world.planner.submit([1], 'move', cell=(33, 34), angle=.7))
        path = world.planner.path(ally, (33, 34))
        self.assertAlmostEqual(world.grid.path_cost(path), 2 * sqrt(2))
        self.assertIsNone(world.planner.submit([1], 'move', cell=(34, 33), angle=1.2, append=True))
        world.paused = False
        for _ in range(300):
            world.update(1/60)
            if not ally.queue:
                break
        self.assertEqual(ally.occupied_cell, (34, 33))
        self.assertAlmostEqual(ally.guard_angle, 1.2)
        stop_actor_at_cell(enemy, world.grid, (31, 32))
        enemy_move(world, enemy, (33, 34))
        self.assertAlmostEqual(world.grid.path_cost(enemy.route), 2 * sqrt(2))


if __name__ == '__main__':
    unittest.main()
