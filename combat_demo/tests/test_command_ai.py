from pathlib import Path
import os
import sys
import unittest
from math import pi
from unittest.mock import patch

os.environ['SDL_VIDEODRIVER']='dummy'
os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from simulation.actor import Team, FireMode, ActorMode, ActionType
from simulation.combat import ShotEvent, NearMissEvent
from simulation.geometry import Vec2, angle_difference
from simulation.mission import create_mission
from simulation.movement import stop_actor_at_cell
from rendering.pygame_view import PygameView


def advance(w,seconds):
    w.paused=False
    for _ in range(round(seconds*60)):w.update(1/60)


class CommandAITests(unittest.TestCase):
    def setUp(self):
        self.w=create_mission();self.p=self.w.planner
        for a in self.w.actors:
            a.fire_mode=FireMode.HOLD_FIRE;a.ai_enabled=False

    def task(self,ids=(1,2,3,4),method='direct'):
        d=self.p.choose_entrance(list(ids),door='door_S_R',method=method)
        if method=='flash':d.landing=(34,25)
        self.assertIsNone(self.p.submit_task(d))
        return next(t for t in self.p.tasks.values() if t.draft.actors==list(ids))

    def shot(self,actor=None):
        actor=actor or self.w.actor(1)
        return ShotEvent(actor.position-Vec2(4,0),actor.position,Team.BLUE.value)

    def test_shift_takeover_cancels_group_and_releases_reservation(self):
        task=self.task(method='flash');thrower=self.w.actor(task.draft.thrower)
        self.assertEqual(thrower.inventory.reserved('flashbang'),1)
        self.assertIsNone(self.p.submit([3],'move',cell=(40,32),append=True))
        self.assertFalse(self.p.tasks)
        self.assertEqual(thrower.inventory.reserved('flashbang'),0)
        self.assertEqual(len(self.w.actor(3).queue),1)
        self.assertTrue(all(not self.w.actor(i).queue for i in (1,2,4)))

    def test_shift_takeover_validates_from_current_position(self):
        task=self.task(method='flash');a=self.w.actor(task.draft.thrower)
        self.w.perception.explored.add((33,30))
        self.assertIsNone(self.p.submit([a.id],'throw',item='flashbang',cell=(33,30),append=True))
        self.assertFalse(self.p.tasks);self.assertEqual(len(a.queue),1)
        self.assertEqual(a.inventory.reserved('flashbang'),1)

    def test_invalid_takeover_preserves_group_and_resources(self):
        task=self.task(method='flash');tokens=[a.queue[0].token for a in self.w.actors[:4]]
        self.assertIsNotNone(self.p.submit([3],'move',cell=(5,5),append=True))
        self.assertEqual(tokens,[a.queue[0].token for a in self.w.actors[:4]])
        self.assertIn(task.id,self.p.tasks)

    def test_cancel_is_scoped_and_successors_cannot_run(self):
        t=self.task((1,2))
        other=self.p.choose_entrance([3,4],door='door_S_L');self.p.submit_task(other)
        other_id=max(self.p.tasks)
        # A queued personal successor can exist after an imported plan or an
        # earlier shared action: removing its predecessor must not execute it.
        from simulation.orders import Node
        self.w.actor(2).queue.append(Node('future','move',cell=(35,32)))
        self.p.submit([1],'move',cell=(30,32))
        self.assertNotIn(t.id,self.p.tasks);self.assertIn(other_id,self.p.tasks)
        self.assertEqual(self.w.actor(2).queue[0].status,'blocked')

    def test_removing_future_macro_does_not_stop_its_predecessor(self):
        first=self.task((1,2));a=self.w.actor(1)
        self.w.grid.open_interactable_between(first.draft.outside,first.draft.inside)
        self.w.perception.doors[first.draft.door]='open'
        d=self.p.choose_entrance([1,2],door='door_S_L',append=True)
        self.assertIsNotNone(d)
        self.assertIsNone(self.p.submit_task(d,append=True))
        future=max(self.p.tasks)
        advance(self.w,.2);route=list(a.route)
        self.p.cancel_task(future)
        self.assertEqual(first.phase,'stack');self.assertEqual(a.route,route)

    def test_unknown_attack_suspends_group_without_revealing_source(self):
        t=self.task();a=self.w.actor(1);enemy=self.w.actors[4]
        for hit in (False,True):
            self.w.receive_attack(a,self.shot(),enemy,hit=hit)
            self.assertEqual(t.phase,'blocked')
            self.assertNotIn(enemy.id,self.w.perception.player_visible)
            self.assertNotIn(enemy.id,a.recognized)
        self.assertEqual(a.under_fire_angle,pi)
        self.assertIsNotNone(self.p.retry_task(t.id))
        advance(self.w,2.2)
        self.assertEqual(t.phase,'blocked')
        self.assertIsNone(self.p.retry_task(t.id))
        self.assertNotEqual(t.phase,'blocked')

    def test_known_attack_is_plan_internal(self):
        t=self.task();enemy=self.w.actors[4]
        self.w.perception.player_visible.add(enemy.id)
        self.w.receive_attack(self.w.actor(1),self.shot(),enemy,hit=True)
        self.assertNotEqual(t.phase,'blocked')
        self.assertGreater(self.w.actor(1).under_fire_timer,0)
        self.assertNotIn(enemy.id,self.w.actor(1).visible)

    def test_invalid_batch_item_keeps_macro_intact(self):
        t=self.task();self.w.actor(3).weapon.ammo=5
        self.assertIsNotNone(self.p.submit([3,4],'reload',item='rifle'))
        self.assertIn(t.id,self.p.tasks)
        self.assertEqual(self.w.actor(3).queue[0].task_id,t.id)

    def test_interrupted_automatic_reload_does_not_suspend_known_combat(self):
        t=self.task();a=self.w.actor(1);enemy=self.w.actors[4]
        a.weapon.ammo=0
        self.w.start_action(a,ActionType.RELOAD,2,'auto:1:0',item='rifle')
        self.w.perception.player_visible.add(enemy.id)
        self.w.receive_attack(a,self.shot(),enemy,hit=True)
        self.assertIsNone(a.current_action)
        self.assertNotEqual(t.phase,'blocked')
        self.assertEqual(a.queue[0].task_id,t.id)

    def test_hit_and_near_miss_are_wired_from_shooting(self):
        a=self.w.actor(1);enemy=self.w.actors[4]
        stop_actor_at_cell(enemy,self.w.grid,(29,32));enemy.facing=0
        enemy.fire_mode=FireMode.AIMED_SHOT;enemy.visible={1};enemy.recognized={1}
        enemy.aim_target_id=1;enemy.reaction=2;enemy.aim_error_degrees=0
        self.p.submit([1],'wait',sync='A')
        event=self.shot();event.hit_actor_id=1;event.near_misses=[NearMissEvent(2,.4,.2)]
        with patch('simulation.world.resolve_shot',return_value=event):self.w._combat(enemy,1/60)
        self.assertEqual(a.queue[0].status,'blocked')
        self.assertGreater(self.w.actor(2).under_fire_timer,0)

    def test_real_unseen_shot_triggers_turn_before_visual_identification(self):
        a=self.w.actor(1);enemy=self.w.actors[4]
        for x in self.w.actors:x.view_distance=0
        stop_actor_at_cell(enemy,self.w.grid,(29,32))
        enemy.facing=enemy.guard_angle=0;enemy.view_distance=12;enemy.fire_mode=FireMode.AIMED_SHOT
        a.facing=a.guard_angle=0;a.view_distance=12
        self.p.submit([1],'face',angle=0)
        for _ in range(180):
            advance(self.w,1/60)
            if a.under_fire_timer>self.w.time:break
        self.assertGreater(a.under_fire_timer,self.w.time)
        self.assertNotIn(enemy.id,self.w.perception.player_visible)
        advance(self.w,.5)
        self.assertTrue(a.alive)
        self.assertGreater(abs(angle_difference(a.facing,0)),1)
        self.assertEqual(a.weapon.ammo,30)

    def test_sound_does_not_change_macro_assignment_or_route(self):
        t=self.task();a=self.w.actor(1)
        advance(self.w,.2);goals=dict(t.draft.stacks)
        self.w.emit_sound(a.position-Vec2(4,0),Team.BLUE,14,'rifle')
        advance(self.w,.1)
        self.assertEqual(t.phase,'stack');self.assertEqual(t.draft.stacks,goals)
        self.assertNotEqual(a.response,'听声观察')

    def test_sync_suspension_revokes_pending_release(self):
        d=self.p.choose_entrance([1,2],door='door_S_R');d.sync='A';self.p.submit_task(d)
        t=next(iter(self.p.tasks.values()));t.phase='wait';t.ready=True
        self.assertIsNone(self.p.release('A'))
        self.p.suspend_actor(self.w.actor(1),'未知来弹')
        self.assertNotIn('A',self.p.release_requests)
        self.assertFalse(t.released);self.assertFalse(t.ready)
        self.assertIsNone(self.p.retry_task(t.id));self.assertEqual(t.phase,'stack')

    def test_hold_fire_turns_to_unseen_attack_and_stays_suspended(self):
        a=self.w.actor(1);a.facing=0;a.guard_angle=0
        self.p.submit([1],'wait',sync='A')
        before=a.position;ammo=a.weapon.ammo
        self.w.receive_attack(a,self.shot(),self.w.actors[4])
        advance(self.w,1)
        self.assertLess(abs(angle_difference(a.facing,pi)),.01)
        self.assertEqual(a.position,before);self.assertEqual(a.weapon.ammo,ammo)
        advance(self.w,2)
        self.assertEqual(a.queue[0].status,'blocked')
        self.assertIsNone(self.p.retry_node(a,a.queue[0]))

    def test_sound_turns_idle_but_not_explicit_guard(self):
        a=self.w.actor(1);a.facing=0;a.guard_angle=0
        self.w.emit_sound(a.position-Vec2(3,0),Team.BLUE,14,'rifle')
        advance(self.w,.5);self.assertNotEqual(a.facing,0)
        self.p.submit([1],'face',angle=0);advance(self.w,1)
        self.assertFalse(a.queue)
        self.w.emit_sound(a.position-Vec2(3,0),Team.BLUE,14,'rifle')
        advance(self.w,.4);self.assertAlmostEqual(a.facing,0)

    def test_same_sound_refreshes_both_sides_and_preserves_enemy_path(self):
        a=self.w.actor(1);enemy=self.w.actors[4];enemy.ai_enabled=True
        stop_actor_at_cell(enemy,self.w.grid,(30,32))
        self.w.emit_sound(Vec2(31,32),Team.BLUE,14,'rifle');red_expiry=a.heard_timer
        self.w.emit_sound(Vec2(31,32),Team.RED,14,'rifle');blue_expiry=enemy.heard_timer
        enemy.ai_goal=(29,32)
        self.w.time+=.5
        self.w.emit_sound(Vec2(31,32),Team.BLUE,14,'rifle')
        self.w.emit_sound(Vec2(31,32),Team.RED,14,'rifle')
        self.assertGreater(a.heard_timer,red_expiry);self.assertGreater(enemy.heard_timer,blue_expiry)
        self.assertEqual(enemy.ai_goal,(29,32))

    def test_enemy_turns_from_unknown_attack(self):
        enemy=self.w.actors[4];enemy.ai_enabled=True;enemy.facing=0;enemy.guard_angle=0
        stop_actor_at_cell(enemy,self.w.grid,(30,32))
        self.w.receive_attack(enemy,self.shot(enemy),self.w.actor(1))
        advance(self.w,.6)
        self.assertGreater(abs(angle_difference(enemy.facing,0)),1)

    def test_ordinary_arrival_does_not_reset_north(self):
        a=self.w.actor(1);self.p.submit([1],'move',cell=(30,32))
        advance(self.w,3)
        self.assertFalse(a.queue);self.assertLess(abs(angle_difference(a.facing,pi)),.01)
        advance(self.w,1);self.assertLess(abs(angle_difference(a.facing,pi)),.01)

    def test_segment_angles_apply_during_each_move_and_share_turn_budget(self):
        a=self.w.actor(1)
        self.p.submit([1],'move',cell=(31,32),angle=0)
        self.p.submit([1],'move',cell=(29,32),angle=pi/2,append=True)
        self.p.submit([1],'move',cell=(28,32),append=True)
        advance(self.w,.6)
        self.assertGreater(a.position.x,31.5);self.assertAlmostEqual(a.facing,0)
        for _ in range(180):
            before=a.facing;advance(self.w,1/60)
            self.assertLessEqual(abs(angle_difference(a.facing,before)),a.turn_speed/60+1e-8)
            if len(a.queue)==2 and a.position.x<31:break
        self.assertEqual(len(a.queue),2)
        self.assertGreater(a.facing,0)
        advance(self.w,3)
        self.assertFalse(a.queue);self.assertLess(abs(angle_difference(a.facing,pi)),.01)

    def test_flash_release_survives_suspend_and_retry_without_duplicate(self):
        t=self.task((1,2),method='flash');a=self.w.actor(t.draft.thrower)
        self.w.grid.open_interactable_between(t.draft.outside,t.draft.inside)
        stop_actor_at_cell(a,self.w.grid,t.draft.stacks[a.id])
        t.phase='throw'
        self.assertIsNone(self.w.start_action(a,ActionType.THROW_GRENADE,.01,t.token,item=t.draft.item,cell=t.draft.landing))
        self.w.time=.02;self.w._update_action(a,.02)
        self.assertTrue(t.flash_released);self.assertEqual(len(self.w.projectiles),1)
        self.p.suspend_task(t,'测试意外')
        self.assertIsNone(self.p.retry_task(t.id));self.p.tick(1/60)
        self.assertEqual(t.phase,'blast');self.assertEqual(len(self.w.projectiles),1)
        self.assertEqual(a.inventory.quantities[t.draft.item],0)

    def test_suspension_stops_all_unfinished_actions_and_keeps_reservation(self):
        t=self.task((1,2),method='flash');a=self.w.actor(t.draft.thrower)
        self.w.grid.open_interactable_between(t.draft.outside,t.draft.inside)
        stop_actor_at_cell(a,self.w.grid,t.draft.stacks[a.id]);t.phase='throw'
        self.w.start_action(a,ActionType.THROW_GRENADE,.6,t.token,item=t.draft.item,cell=t.draft.landing)
        self.p.suspend_actor(self.w.actor(2),'未知来弹')
        self.assertIsNone(a.current_action);self.assertEqual(a.inventory.reserved(t.draft.item),1)
        self.assertEqual(t.phase,'blocked')


class DragInterfaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.app=PygameView()
    @classmethod
    def tearDownClass(cls):pg.quit()
    def setUp(self):
        self.app.start_mission();self.app.select([1]);self.app.draw();pg.key.set_mods(0)

    def down(self,point):self.app.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=point,button=3)])
    def up(self,point):self.app.events([pg.event.Event(pg.MOUSEBUTTONUP,pos=point,button=3)])

    def test_threshold_and_commit_only_on_release(self):
        a=self.app;point=a.pos((30.5,32.5))
        for distance,expect in ((a.scale*.49,None),(a.scale*.51,0)):
            a.world.planner.stop([1]);self.down(point)
            self.assertFalse(a.world.actor(1).queue)
            self.up((point[0]+distance,point[1]))
            self.assertEqual(a.world.actor(1).queue[0].angle,expect)

    def test_shift_is_captured_on_press(self):
        a=self.app;a.world.planner.submit([1],'move',cell=(31,32),angle=0)
        pg.key.set_mods(pg.KMOD_SHIFT);point=a.pos((30.5,32.5));self.down(point)
        pg.key.set_mods(0);self.up((point[0],point[1]-32))
        q=a.world.actor(1).queue;self.assertEqual(len(q),2)
        self.assertAlmostEqual(q[1].angle,-pi/2)

    def test_drag_cancel_outside_escape_and_resize(self):
        a=self.app;point=a.pos((30.5,32.5))
        self.down(point);self.up((a.width-1,100));self.assertFalse(a.world.actor(1).queue)
        self.down(point);a.events([pg.event.Event(pg.KEYDOWN,key=pg.K_ESCAPE,mod=0)])
        self.up((point[0]+30,point[1]));self.assertFalse(a.world.actor(1).queue)
        self.down(point);a.resize((1280,720));self.assertIsNone(a.move_drag)
        a.resize((1440,900))

    def test_crossing_object_and_dragging_back_do_not_change_target(self):
        a=self.app;point=a.pos((30.5,32.5));self.down(point)
        door=a.pos(a.world.mission.entrances['door_S_R'].center(a.world.grid))
        a.events([pg.event.Event(pg.MOUSEMOTION,pos=door,rel=(100,0),buttons=(0,0,1))])
        a.draw();self.assertIsNone(a.menu)
        self.up((point[0]+2,point[1]));n=a.world.actor(1).queue[0]
        self.assertEqual(n.cell,(30,32));self.assertIsNone(n.angle)


if __name__=='__main__':unittest.main(verbosity=2)
