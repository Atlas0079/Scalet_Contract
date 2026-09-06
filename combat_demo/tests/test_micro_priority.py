from pathlib import Path
import sys
import unittest
from math import pi

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from simulation.actor import ActionType, FireMode, Team
from simulation.combat import ShotEvent
from simulation.geometry import Vec2, angle_difference
from simulation.mission import create_mission
from simulation.movement import stop_actor_at_cell


class MicroPriorityTests(unittest.TestCase):
    def setUp(self):
        self.w=create_mission();self.p=self.w.planner;self.a=self.w.actor(1);self.enemy=self.w.actors[4]
        for a in self.w.actors:a.ai_enabled=False;a.fire_mode=FireMode.HOLD_FIRE
        for i,cell in [(1,(31,32)),(2,(30,33)),(3,(31,33)),(4,(32,33)),(self.enemy.id,(37,32))]:
            stop_actor_at_cell(self.w.actor(i),self.w.grid,cell)
        self.a.facing=self.a.guard_angle=0;self.a.fire_mode=FireMode.AIMED_SHOT
        self.w.perception.refresh(self.w,.3);self.w.paused=False

    def advance(self,seconds):
        for _ in range(round(seconds*60)):self.w.update(1/60)

    def test_move_takes_over_actual_firing_and_resumes_only_after_arrival(self):
        for _ in range(120):
            self.w.update(1/60)
            if self.w.stats['rounds']:break
        self.assertGreater(self.w.stats['rounds'],0);self.assertTrue(self.enemy.alive)
        ammo=self.a.weapon.ammo;start=self.a.position
        self.assertIsNone(self.p.submit([1],'move',cell=(33,32),angle=0))
        self.advance(.25)
        self.assertGreater(self.a.position.x,start.x)
        self.assertIn(self.enemy.id,self.a.visible)
        self.assertEqual(self.a.weapon.ammo,ammo)
        while self.a.queue:
            self.w.update(1/60)
            self.assertEqual(self.a.weapon.ammo,ammo)
            self.assertLess(self.w.time,5)
        self.assertEqual(self.a.occupied_cell,(33,32))
        self.advance(1)
        self.assertLess(self.a.weapon.ammo,ammo)

    def test_ordinary_move_and_waypoints_ignore_visible_threat(self):
        self.p.submit([1],'move',cell=(32,32))
        self.p.submit([1],'move',cell=(33,32),append=True)
        self.advance(.8)
        self.assertGreater(self.a.position.x,32.5)
        self.assertEqual(self.a.weapon.ammo,30)
        self.assertTrue(self.a.queue)

    def test_empty_weapon_does_not_auto_reload_during_move(self):
        self.a.weapon.ammo=0
        self.p.submit([1],'move',cell=(33,32),angle=0)
        self.advance(.8)
        self.assertIsNone(self.a.current_action)
        self.assertGreater(self.a.position.x,32.5)
        self.advance(1)
        self.assertIsNotNone(self.a.current_action)
        self.assertEqual(self.a.current_action.type,ActionType.RELOAD)

    def test_replacement_move_interrupts_existing_automatic_reload(self):
        self.a.weapon.ammo=0
        self.w.start_action(self.a,ActionType.RELOAD,2,'auto:1:test',item='rifle')
        self.p.submit([1],'move',cell=(33,32),angle=0)
        self.advance(.5)
        self.assertIsNone(self.a.current_action)
        self.assertGreater(self.a.position.x,31.5)
        self.assertEqual(self.a.weapon.ammo,0)

    def test_unknown_fire_reports_but_does_not_interrupt_active_micro(self):
        self.p.submit([1],'move',cell=(33,32),angle=0)
        self.w.perception.player_visible.clear()
        shot=ShotEvent(self.a.position-Vec2(3,0),self.a.position,Team.BLUE.value)
        self.w.receive_attack(self.a,shot,self.enemy,hit=True)
        self.assertNotEqual(self.a.queue[0].status,'blocked')
        self.advance(.2)
        self.assertGreater(self.a.position.x,31.5)
        self.assertAlmostEqual(self.a.facing,0)
        self.assertIn('受袭',self.a.response)

    def test_shift_move_with_no_predecessor_takes_over_automatic_reload(self):
        self.a.weapon.ammo=0
        self.w.start_action(self.a,ActionType.RELOAD,2,'auto:1:test',item='rifle')
        self.p.submit([1],'move',cell=(33,32),append=True)
        self.advance(.2)
        self.assertIsNone(self.a.current_action)
        self.assertGreater(self.a.position.x,31.5)

    def test_micro_face_prevents_automatic_aim_stealing_turn_budget(self):
        self.p.submit([1],'face',angle=pi/2)
        self.advance(.2)
        self.assertAlmostEqual(self.a.facing,self.a.turn_speed*.2)
        self.assertEqual(self.a.weapon.ammo,30)
        self.advance(.3)
        self.assertFalse(self.a.queue)
        self.assertLess(abs(angle_difference(self.a.facing,pi/2)),.0873)

    def test_guard_reaches_position_then_allows_defensive_fire(self):
        self.p.submit([1],'guard',cell=(33,32),angle=0)
        self.advance(.5);self.assertGreater(self.a.position.x,31.5)
        self.assertEqual(self.a.weapon.ammo,30)
        self.advance(1.5)
        self.assertEqual(self.a.occupied_cell,(33,32))
        self.assertTrue(self.a.queue[0].started)
        self.assertLess(self.a.weapon.ammo,30)

    def test_macro_keeps_automatic_combat_stopping_rule(self):
        draft=self.p.choose_entrance([1,2],door='door_S_R')
        self.assertIsNone(self.p.submit_task(draft))
        start=self.a.position
        self.advance(.5)
        self.assertEqual(self.a.position,start)
        self.assertTrue(self.w.has_threat(self.a))
        self.assertFalse(self.p.micro_controls_motion(self.a))


if __name__=='__main__':unittest.main(verbosity=2)
