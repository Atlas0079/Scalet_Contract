from pathlib import Path
import os
import sys
import unittest

os.environ['SDL_VIDEODRIVER']='dummy'
os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView
from rendering.widgets import ContextMenu,Entry


class LootUiTests(unittest.TestCase):
    def setUp(self):
        self.view=PygameView(size=(1280,720));self.view.start_mission();self.w=self.view.world

    def tearDown(self):pg.quit()

    def key(self,key):self.view.events([pg.event.Event(pg.KEYDOWN,key=key,mod=0)])

    def click(self,pos,button=1):self.view.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=pos,button=button)])

    def test_personal_shortcut_uses_menu_actor_without_changing_selection(self):
        self.w.actor(1).weapon.ammo=10;self.w.actor(2).weapon.ammo=11
        self.view.personal_menu(2,(400,300));self.key(pg.K_r)
        self.assertEqual(self.view.selected,[1,2,3,4])
        self.assertFalse(self.w.actor(1).queue)
        self.assertEqual(self.w.actor(2).queue[0].kind,'reload')

    def test_group_reload_skips_full_magazines(self):
        self.w.actor(3).weapon.ammo=8
        self.key(pg.K_r)
        self.assertEqual([a.id for a in self.w.actors[:4] if a.queue],[3])

    def test_pause_button_remains_clickable_above_context_menu(self):
        self.view.personal_menu(2,(400,300));self.view.draw()
        self.click((680,22))
        self.assertFalse(self.w.paused)
        self.assertIsNotNone(self.view.menu)

    def test_mouse_and_keyboard_submenu_switch_does_not_activate_stale_entry(self):
        calls=[]
        menu=ContextMenu('test','',[Entry('branch',children=[Entry('child',lambda:calls.append('child'))]),Entry('root',lambda:calls.append('root'))],(100,100),(1280,720))
        menu.activate((0,0));self.assertEqual(menu.keyboard,(1,0))
        pos=(menu.root.x+20,menu.root.y+56+32+10)
        menu.update(pos,1000);menu.update(pos,1200)
        self.assertIsNone(menu.branch)
        self.assertIsNone(menu.activate((1,0)))
        menu.key(pg.K_DOWN);menu.key(pg.K_RETURN)
        self.assertEqual(calls,['root'])

    def open_container(self):
        obj=self.w.loot.objects['case:S'];obj.opened=obj.searched=True;obj.discovered=True
        self.w.loot.remember(obj);self.w.loot.open_result(obj,self.w.actor(1))
        self.view.show_loot(obj.id);self.view.draw()
        return obj

    def test_double_click_schedules_current_actor_without_transfer(self):
        obj=self.open_container();gun=next(i for i in obj.items.values() if i.weapon)
        pos=self.view.loot_rows[0][0].center
        self.click(pos);self.assertFalse(self.w.loot.reservations)
        self.click(pos)
        self.assertEqual(next(iter(self.w.loot.reservations.values())).actor_id,1)
        self.assertIn(gun.id,obj.items);self.assertNotIn(gun.id,self.w.actor(1).inventory.cargo)
        self.key(pg.K_SPACE);self.assertTrue(self.w.paused)
        self.assertEqual(self.view.selected,[1,2,3,4])
        self.key(pg.K_ESCAPE);self.assertIsNone(self.view.loot_panel)
        self.assertTrue(self.w.paused)

    def test_right_click_selects_other_actor_and_repeated_items_append(self):
        obj=self.open_container()
        for row,item_id in self.view.loot_rows[:2]:
            self.click(row.center,3)
            self.assertIsNotNone(self.view.menu)
            self.click((self.view.menu.root.x+20,self.view.menu.root.y+56+32+10))
        queue=self.w.actor(2).queue
        self.assertEqual(len(queue),2)
        self.assertEqual(len(self.w.loot.reservations),2)
        self.assertTrue(all(n.object_id==obj.id for n in queue))
        self.assertFalse(self.w.actor(1).queue)
        self.assertEqual(self.view.loot_actors[obj.id],1)

    def test_duplicate_and_overweight_pickup_leave_existing_plan_intact(self):
        obj=self.open_container();pos=self.view.loot_rows[0][0].center
        self.click(pos);self.click(pos)
        tokens=set(self.w.loot.reservations)
        self.click(pos);self.click(pos)
        self.assertEqual(tokens,set(self.w.loot.reservations))
        self.w.actor(2).inventory.capacity=0
        self.click(self.view.loot_rows[1][0].center,3)
        self.assertTrue(self.view.menu.entries[1].reason())
        self.click((self.view.menu.root.x+20,self.view.menu.root.y+56+32+10))
        self.assertEqual(tokens,set(self.w.loot.reservations))
        self.assertFalse(self.w.actor(2).queue)

    def test_right_click_reassign_and_double_click_restore_current_actor(self):
        obj=self.open_container();row,item_id=self.view.loot_rows[0]
        self.click(row.center);self.click(row.center)
        self.click(row.center,3)
        self.assertEqual(self.view.menu.title,'更换拿取者')
        self.assertIn('当前',self.view.menu.entries[0].label)
        self.assertIn('9.8/18',self.view.menu.entries[0].label)
        self.click((self.view.menu.root.x+20,self.view.menu.root.y+56+32+10))
        self.assertEqual(self.w.loot.pickup_reservation(obj.id,item_id)[1].actor_id,2)
        self.assertFalse(self.w.actor(1).queue)
        self.click(row.center);self.click(row.center)
        self.assertEqual(self.w.loot.pickup_reservation(obj.id,item_id)[1].actor_id,1)
        self.assertFalse(self.w.actor(2).queue)
        self.assertEqual(len(self.w.loot.reservations),1)

    def test_dead_current_actor_is_not_silently_replaced(self):
        self.open_container();a=self.w.actor(1)
        a.body.damage_part('brain',999);a.mark_dead_if_needed()
        pos=self.view.loot_rows[0][0].center
        self.click(pos);self.click(pos)
        self.assertFalse(self.w.loot.reservations)
        self.click(pos,3)
        self.assertTrue(self.view.menu.entries[0].reason())
        self.assertIsNone(self.view.menu.entries[1].reason())

    def test_close_releases_search_wait_but_keeps_pickups(self):
        obj=self.open_container();pos=self.view.loot_rows[0][0].center
        self.click(pos);self.click(pos);self.key(pg.K_ESCAPE)
        self.view.update(0)
        self.assertIsNone(self.view.loot_panel);self.assertNotIn(obj.id,self.w.loot.results)
        self.assertEqual(len(self.w.loot.reservations),1)

    def test_menu_escape_and_outside_click_do_not_issue_orders(self):
        self.open_container();self.click(self.view.loot_rows[0][0].center,3)
        self.key(pg.K_ESCAPE);self.assertIsNone(self.view.menu)
        self.assertIsNotNone(self.view.loot_panel)
        self.click((20,500),3);self.click((20,500))
        self.assertFalse(any(a.queue for a in self.w.actors[:4]))
        self.assertFalse(self.w.loot.reservations)

    def test_window_stays_inside_map_at_both_resolutions_and_edges(self):
        self.open_container()
        for size in ((1280,720),(1440,900)):
            self.view.resize(size)
            for offset in ((0,0),(-2000,-2000),(2000,2000)):
                self.view.offset=list(offset);self.view.draw()
                self.assertTrue(self.view.viewport.contains(self.view.loot_rect))
                self.assertLessEqual(self.view.loot_rect.width,430)
                self.assertEqual(len(self.view.loot_rows),3)

    def test_multiple_objects_at_same_position_remain_accessible(self):
        cell=self.w.actor(1).occupied_cell
        obj=self.w.loot.add('test-pile','散落物','ground',cell,[self.w.loot.item('parts')],discovered=True)
        self.view.draw();self.click(self.view.pos(self.w.grid.cell_center(cell)),3)
        self.assertEqual(self.view.menu.title,'选择交互对象')
        self.assertEqual(len(self.view.menu.entries),2)
        self.view.menu.activate((0,1))
        self.assertEqual(self.view.menu.title,obj.name)

    def test_finish_and_next_consumes_only_current_decision_and_keeps_reservations(self):
        obj=self.open_container();item_id=next(iter(obj.items))
        other=self.w.loot.add('other-result','另一个箱子','ground',(35,33),[self.w.loot.item('parts')],discovered=True)
        other.searched=True;self.w.loot.remember(other);self.w.loot.open_result(other,self.w.actor(2))
        self.view.pickup(item_id,1)
        tokens=set(self.w.loot.reservations)
        self.view.show_loot(other.id)
        self.assertIn(obj.id,self.w.loot.results)
        self.view.show_loot(obj.id)
        self.view.finish_loot_next()
        self.assertEqual(self.view.loot_panel,other.id)
        self.assertNotIn(obj.id,self.w.loot.results)
        self.assertEqual(tokens,set(self.w.loot.reservations))
        self.assertIn(item_id,obj.items)
        self.view.finish_loot_next()
        self.assertIsNone(self.view.loot_panel)
        self.assertFalse(self.w.loot.results)
        self.assertTrue(self.w.paused)

    def test_single_item_cancel_menu_preserves_other_pickups_and_source_wait(self):
        obj=self.open_container();items=list(obj.items)[:2]
        for item_id in items:self.view.pickup(item_id,1)
        kept=self.w.loot.pickup_reservation(obj.id,items[1])[0]
        self.view.pickup_menu(items[0],(500,300))
        self.view.menu.activate((0,4))
        self.assertIsNone(self.w.loot.pickup_reservation(obj.id,items[0])[1])
        self.assertIn(kept,self.w.loot.reservations)
        self.assertEqual([n.cargo_id for n in self.w.actor(1).queue],[items[1]])
        self.assertIn(obj.id,self.w.loot.results)
        self.assertTrue(all(i in obj.items for i in items))

    def test_inspect_candidate_does_not_change_selection_allocation_or_time(self):
        obj=self.open_container();item_id=next(iter(obj.items));self.view.pickup(item_id,1)
        tokens=set(self.w.loot.reservations);before=self.w.time
        self.view.pickup_menu(item_id,(500,300));self.view.menu.keyboard=(0,1);self.view.draw()
        self.click((self.view.width-150,self.view.height-230))
        self.assertEqual(self.view.overlay,'actor');self.assertEqual(self.view.detail_actor,2)
        self.view.draw();self.key(pg.K_SPACE);self.view.update(1)
        self.assertEqual(self.w.time,before)
        self.assertEqual(tokens,set(self.w.loot.reservations))
        self.key(pg.K_ESCAPE)
        self.assertIsNone(self.view.overlay);self.assertEqual(self.view.loot_panel,obj.id)
        self.assertEqual(self.view.selected,[1,2,3,4]);self.assertTrue(self.w.paused)
        self.view.draw();self.key(pg.K_ESCAPE)
        self.assertIsNone(self.view.loot_panel)

    def test_details_returns_to_previous_running_state_without_command_side_effects(self):
        self.w.set_paused(False);self.view.inspect_actor(3);self.view.draw()
        self.key(pg.K_r);self.key(pg.K_x);self.key(pg.K_SPACE)
        self.assertFalse(any(a.queue for a in self.w.actors[:4]))
        self.assertTrue(self.w.paused)
        self.key(pg.K_ESCAPE)
        self.assertFalse(self.w.paused)

    def test_long_queue_keeps_details_accessible_at_both_sizes(self):
        for size in ((1280,720),(1440,900)):
            self.view.resize(size);self.view.selected=[1]
            self.w.actor(1).queue.clear()
            for index in range(8):
                self.assertIsNone(self.w.planner.submit([1],'move',cell=(32+index%2,33),append=True))
            self.view.draw()
            self.click((self.view.width-150,self.view.height-224))
            self.assertEqual(self.view.overlay,'actor')
            self.view.draw();self.key(pg.K_ESCAPE)

    def test_movement_preview_matches_committed_targets(self):
        expected,error=self.w.planner.movement_targets([1,2,3,4],(33,32))
        self.assertIsNone(error);self.assertEqual(len(set(expected.values())),4)
        self.assertIsNone(self.w.planner.submit([1,2,3,4],'move',cell=(33,32)))
        self.assertEqual(expected,{a.id:a.queue[0].cell for a in self.w.actors[:4]})


if __name__=='__main__':unittest.main()
