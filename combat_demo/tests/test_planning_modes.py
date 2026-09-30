from pathlib import Path
import os
import sys
import unittest
from math import pi
os.environ['SDL_VIDEODRIVER']='dummy'
os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView
from simulation.mission import create_mission
from simulation.actor import FireMode
from simulation.geometry import angle_difference
from simulation.movement import stop_actor_at_cell


class PlannedExecutionTests(unittest.TestCase):
    def setUp(self):
        self.w=create_mission();self.p=self.w.planner
        for a in self.w.actors:a.ai_enabled=False;a.fire_mode=FireMode.HOLD_FIRE

    def custom(self,after='hold'):
        d,error=self.p.preview_task([1,2],'door_S_R','R','direct',after_entry=after,
            stack_overrides={1:(34,31),2:(36,31)},entry_overrides={1:(37,28),2:(33,28)},
            stack_angles={1:pi,2:0},entry_angles={1:0,2:pi})
        self.assertIsNone(error);return d

    def test_custom_positions_survive_submit_and_hold_at_requested_points(self):
        d=self.custom();self.assertIsNone(self.p.submit_task(d))
        task=next(iter(self.p.tasks.values()))
        self.assertEqual(task.draft.stacks,d.stacks);self.assertEqual(task.draft.entries,d.entries)
        for _ in range(60*45):
            self.w.set_paused(False);self.w.update(1/60)
            if not self.p.tasks:break
        self.assertFalse(self.p.tasks)
        for i,cell in d.entries.items():
            self.assertEqual(self.w.actor(i).occupied_cell,cell)
            self.assertLess(abs(angle_difference(self.w.actor(i).facing,d.entry_angles[i])),.1)
        self.assertNotIn('R',self.w.mission.room_checked)
        for _ in range(120):self.w.update(1/60)
        self.assertEqual({i:self.w.actor(i).occupied_cell for i in d.actors},d.entries)

    def test_search_mode_continues_after_entry_and_records_threat_check(self):
        d=self.custom('search');self.assertIsNone(self.p.submit_task(d))
        phases=set()
        for _ in range(60*90):
            self.w.set_paused(False);self.w.update(1/60)
            phases.update(t.phase for t in self.p.tasks.values())
            if not self.p.tasks:break
        self.assertIn('search',phases);self.assertIn('R',self.w.mission.room_checked)

    def test_invalid_custom_position_does_not_cancel_existing_plan(self):
        self.p.submit([1],'face',angle=1)
        old=self.w.actor(1).queue[0]
        d=self.custom();d.entry_overrides[1]=(0,0)
        self.assertIsNotNone(self.p.submit_task(d))
        self.assertIs(self.w.actor(1).queue[0],old);self.assertFalse(self.p.tasks)

    def test_same_stage_overlap_and_doorway_are_rejected(self):
        for slots in ({1:(35,29)},{1:(37,28),2:(37,28)}):
            _,error=self.p.preview_task([1,2],'door_S_R','R','direct',entry_overrides=slots)
            self.assertIsNotNone(error)

    def test_occupied_custom_entry_stays_fixed_and_suspends(self):
        d=self.custom();self.assertIsNone(self.p.submit_task(d));task=next(iter(self.p.tasks.values()))
        stop_actor_at_cell(self.w.actor(3),self.w.grid,d.entries[1])
        for _ in range(60*40):
            self.w.set_paused(False);self.w.update(1/60)
            if task.phase=='blocked':break
        self.assertEqual(task.draft.entries[1],d.entries[1])
        self.assertEqual(task.phase,'blocked')

    def test_flash_range_uses_custom_thrower_stack(self):
        _,error=self.p.preview_task([1,2],'door_S_R','R','flash',item='flashbang',landing=(35,28),stack_overrides={1:(14,32)})
        self.assertIsNotNone(error)


class PlanningUiTests(unittest.TestCase):
    def setUp(self):
        self.v=PygameView(size=(1280,720));self.v.start_mission();self.v.hints=False
    def tearDown(self):pg.key.set_mods(0);pg.quit()
    def mouse(self,kind,pos,button=1):self.v.events([pg.event.Event(kind,pos=pos,button=button)])
    def click(self,pos,button=1):
        self.mouse(pg.MOUSEBUTTONDOWN,pos,button);self.mouse(pg.MOUSEBUTTONUP,pos,button)

    def test_quick_mode_submits_without_draft(self):
        self.v.door_menu(door='door_S_R')
        self.v.choose_action(self.v.action_focus['entries'][2]);self.v.choose_action(self.v.action_focus['entries'][0])
        self.v.new_draft(*self.v.action_focus['choice'],quick=True)
        self.assertIsNone(self.v.draft)
        self.assertEqual(next(iter(self.v.world.planner.tasks.values())).draft.after_entry,'hold')

    def test_staged_mode_keeps_orders_untouched_until_commit(self):
        self.v.door_menu(door='door_S_R')
        self.v.choose_action(self.v.action_focus['entries'][2]);self.v.choose_action(self.v.action_focus['entries'][0])
        self.v.new_draft(*self.v.action_focus['choice'])
        self.assertIsNotNone(self.v.draft);self.assertFalse(self.v.world.planner.tasks)
        self.v.edit_draft(stack_overrides={1:(34,31)},entry_overrides={1:(37,28)},entry_angles={1:pi})
        self.assertFalse(self.v.draft_error)
        self.v.commit_draft();d=next(iter(self.v.world.planner.tasks.values())).draft
        self.assertEqual(d.entries[1],(37,28));self.assertEqual(d.entry_angles[1],pi)

    def test_quick_flash_click_submits_and_consumption_waits_for_execution(self):
        self.v.new_draft([1,2],'door_S_R','R','flash','flashbang',quick=True)
        self.assertFalse(self.v.world.planner.tasks)
        self.v.draw();self.click(self.v.pos((35.5,28.5)))
        self.assertIsNone(self.v.draft);self.assertTrue(self.v.world.planner.tasks)
        self.assertEqual(self.v.world.actor(1).inventory.quantities['flashbang'],1)

    def test_nonparticipant_click_preserves_draft_during_landing_tool(self):
        self.v.new_draft([1,2],'door_S_R','R','flash','flashbang');self.v.draw()
        self.click(self.v.pos(self.v.world.actor(3).position))
        self.assertEqual(self.v.selected,[1,2,3,4]);self.assertIsNotNone(self.v.draft)
        self.assertFalse(self.v.world.planner.tasks)

    def test_quick_flash_survives_event_inspection_and_cancels_cleanly(self):
        self.v.new_draft([1,2],'door_S_R','R','flash','flashbang',quick=True)
        self.v.show_overlay('events');self.v.close_overlay()
        self.assertTrue(self.v.quick_pending);self.assertEqual(self.v.tool['kind'],'landing')
        self.v.cancel_tool()
        self.assertIsNone(self.v.draft);self.assertFalse(self.v.quick_pending)
        self.assertFalse(self.v.world.planner.tasks)

    def test_dragged_slot_and_angle_are_world_space_at_three_zooms(self):
        for scale in (12,32,64):
            self.v.clear_tools();self.v.new_draft([1,2],'door_S_R','R','direct')
            self.v.set_plan_stage('entry');self.v.scale=scale;self.v.offset=[480-35*scale,300-30*scale];self.v.draw()
            start=self.v.pos((37.5,28.5))
            self.click(start,3)
            self.assertEqual(self.v.draft.entries[1],(37,28));self.v.draw()
            start=self.v.pos((37.5,28.5));end=self.v.pos((38.5,28.5))
            self.mouse(pg.MOUSEBUTTONDOWN,start,3);self.mouse(pg.MOUSEBUTTONUP,end,3)
            self.assertAlmostEqual(self.v.draft.entry_angles[1],0)

    def test_invalid_drag_keeps_valid_plan_and_does_not_issue_orders(self):
        self.v.new_draft([1,2],'door_S_R','R','direct');self.v.set_plan_stage('entry');self.v.draw()
        old=dict(self.v.draft.entries)
        self.click(self.v.pos((34.5,31.5)),3)
        self.assertEqual(self.v.draft.entries,old);self.assertIn('修改未生效',self.v.plan_feedback);self.assertFalse(self.v.draft_error)
        self.assertFalse(self.v.world.planner.tasks)

    def test_room_guard_requests_location_instead_of_using_center(self):
        self.v.door_menu(room='S');self.v.action_focus['entries'][1].action()
        self.assertNotIn('cell',self.v.tool)
        self.click(self.v.pos((34.5,32.5)))
        self.assertEqual(self.v.tool['cell'],(34,32))
        self.assertFalse(any(a.queue for a in self.v.world.actors[:4]))

    def test_changing_method_preserves_custom_stations(self):
        self.v.new_draft([1,2],'door_S_R','R','direct')
        self.v.edit_draft(entry_overrides={1:(37,28)},entry_angles={1:pi})
        self.v.change_method('breach')
        self.assertFalse(self.v.draft_error)
        self.assertEqual(self.v.draft.entries[1],(37,28));self.assertEqual(self.v.draft.entry_angles[1],pi)

    def test_arrow_has_same_world_length_at_all_zooms(self):
        from unittest.mock import patch
        origin=self.v.world.actor(1).position
        for scale in (12,32,64):
            self.v.scale=scale
            with patch.object(self.v,'line') as line:
                self.v.direction_arrow(origin,0,'white')
            start,end=line.call_args_list[0].args[:2]
            self.assertAlmostEqual(start.distance_to(end),1)

    def test_map_entrance_rejects_unrelated_door_and_keeps_same_entrance_edits(self):
        self.v.new_draft([1,2],'door_S_R','R','direct')
        self.v.edit_draft(entry_overrides={1:(37,28)})
        self.v.tool={'kind':'entrance','ids':[1,2]};self.v.draw()
        other=self.v.world.mission.entrances['door_S_L']
        self.click(self.v.pos(other.center(self.v.world.grid)))
        self.assertEqual(self.v.draft.door,'door_S_R');self.assertIsNotNone(self.v.tool)
        self.click(self.v.pos(self.v.world.mission.entrances['door_S_R'].center(self.v.world.grid)))
        self.assertIsNone(self.v.tool);self.assertEqual(self.v.draft.entries[1],(37,28))
