from pathlib import Path
import os
import sys
import unittest
from math import pi
os.environ['SDL_VIDEODRIVER']='dummy';os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView


class DraftInteractionTests(unittest.TestCase):
    def setUp(self):
        self.v=PygameView(size=(1280,720));self.v.start_mission();self.v.hints=False
    def tearDown(self):pg.key.set_mods(0);pg.quit()
    def click(self,pos,button=1):
        self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=pos,button=button),pg.event.Event(pg.MOUSEBUTTONUP,pos=pos,button=button)])
    def key(self,key,mod=0):self.v.events([pg.event.Event(pg.KEYDOWN,key=key,mod=mod)])
    def buttons(self):
        result=[];original=self.v.button
        def record(rect,label,action,*args,**kwargs):
            result.append((label,pg.Rect(rect)));return original(rect,label,action,*args,**kwargs)
        self.v.button=record
        try:self.v.draw()
        finally:self.v.button=original
        return result
    def press(self,label,index=0):
        rect=[r for text,r in self.buttons() if text==label][index];self.click(rect.center)
    def draft(self,item=None):
        self.v.new_draft([1,2,3,4],'door_S_R','R','flash' if item else 'direct',item)
        self.v.draw()

    def test_editor_pauses_world_and_both_resume_controls_require_leaving(self):
        self.v.world.planner.submit([1],'face',angle=1);old=self.v.world.actor(1).queue[0]
        self.v.world.set_paused(False);self.draft();self.assertTrue(self.v.world.paused)
        self.key(pg.K_SPACE);self.press('Ⅱ 暂停中');self.v.update(.2)
        self.assertEqual(self.v.world.time,0);self.assertIs(self.v.world.actor(1).queue[0],old)
        self.key(pg.K_x);self.assertIs(self.v.world.actor(1).queue[0],old)
        self.v.commit_draft();self.assertTrue(self.v.world.paused)
        self.key(pg.K_SPACE);self.assertFalse(self.v.world.paused)

    def test_ground_cards_numbers_and_ctrl_click_keep_custom_draft(self):
        self.draft();self.v.edit_draft(entry_overrides={1:(37,28)})
        for button in (1,3):self.click(self.v.pos((30,29)),button)
        self.click(self.v.cards[2][0].center);self.assertEqual(self.v.plan_actor,3)
        self.key(pg.K_2);self.assertEqual(self.v.plan_actor,2)
        self.click(self.v.pos(self.v.world.actor(4).position));self.assertEqual(self.v.plan_actor,4)
        pg.key.set_mods(pg.KMOD_CTRL);self.click(self.v.pos((30,29)),3)
        self.assertEqual(self.v.draft.entries[1],(37,28));self.assertEqual(self.v.selected,[1,2,3,4])
        self.assertFalse(self.v.world.planner.tasks)

    def test_row_selects_and_separate_arrow_changes_order(self):
        self.draft();self.press('02   2 号 · 侧翼')
        self.assertEqual(self.v.plan_actor,2);self.assertEqual(self.v.draft.actors,[1,2,3,4])
        self.press('↑',1);self.assertEqual(self.v.draft.actors,[2,1,3,4])
        self.key(pg.K_z,pg.KMOD_CTRL);self.assertEqual(self.v.draft.actors,[1,2,3,4])

    def test_undo_restores_positions_angles_sync_and_append_without_live_orders(self):
        self.draft();original=dict(self.v.draft.entries)
        self.v.edit_draft(entry_overrides={1:(37,28)},entry_angles={1:pi})
        self.v.edit_draft(sync='A');self.v.set_plan_append(True)
        self.v.undo_plan();self.assertFalse(self.v.draft_append);self.assertEqual(self.v.draft.sync,'A')
        self.v.undo_plan();self.assertIsNone(self.v.draft.sync);self.assertEqual(self.v.draft.entries[1],(37,28))
        self.v.undo_plan();self.assertEqual(self.v.draft.entries,original);self.assertFalse(self.v.draft.entry_angles)
        self.assertFalse(self.v.world.planner.tasks)

    def test_exit_restores_camera_and_recovers_edits_before_submission(self):
        camera=(self.v.scale,list(self.v.offset));self.draft()
        self.v.edit_draft(entry_overrides={1:(37,28)},entry_angles={1:pi});self.key(pg.K_ESCAPE)
        self.assertIsNone(self.v.draft);self.assertEqual((self.v.scale,self.v.offset),camera)
        self.press('恢复未下达草稿');self.assertEqual(self.v.draft.entries[1],(37,28))
        self.assertEqual(self.v.draft.entry_angles[1],pi)
        self.v.commit_draft();d=next(iter(self.v.world.planner.tasks.values())).draft
        self.assertEqual(d.entries[1],(37,28));self.assertEqual(d.entry_angles[1],pi)
        self.assertIsNone(self.v.saved_plan)

    def test_restore_revalidates_dead_participant_and_new_mission_clears_saved(self):
        self.draft();self.v.leave_plan();self.v.world.actor(2).body.damage_part('brain',999);self.v.world.actor(2).mark_dead_if_needed()
        self.v.restore_plan();self.assertIsNone(self.v.draft);self.assertIsNotNone(self.v.saved_plan)
        self.assertFalse(self.v.world.planner.tasks)
        self.v.start_mission();self.assertIsNone(self.v.saved_plan)

    def test_selecting_member_cancels_pending_move_without_committing(self):
        self.draft()
        self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=self.v.pos((34.5,31.5)),button=3)])
        self.click(self.v.pos(self.v.world.actor(2).position))
        self.assertEqual(self.v.plan_actor,2);self.assertIsNone(self.v.move_drag)
        self.v.events([pg.event.Event(pg.MOUSEBUTTONUP,pos=self.v.pos((34.5,31.5)),button=3)])
        self.assertFalse(self.v.draft.stack_overrides);self.assertFalse(self.v.world.planner.tasks)

    def test_illegal_position_preview_and_edit_keep_previous_valid_plan(self):
        self.draft();old=dict(self.v.draft.entries)
        self.assertIsNotNone(self.v.plan_position_error('entry',1,(0,0)))
        self.assertFalse(self.v.edit_draft(entry_overrides={1:(0,0)}))
        self.assertEqual(self.v.draft.entries,old);self.assertFalse(self.v.draft_error)
        self.assertIn('保留原设置',self.v.plan_feedback)
        self.v.commit_draft();self.assertEqual(next(iter(self.v.world.planner.tasks.values())).draft.entries,old)

    def test_flash_landing_undo_and_submit_reserve_without_consumption(self):
        self.draft('flashbang');self.click(self.v.pos((35.5,28.5)))
        self.assertEqual(self.v.draft.landing,(35,28));self.assertFalse(self.v.world.planner.tasks)
        self.v.undo_plan();self.assertIsNone(self.v.draft.landing)
        self.v.set_plan_stage('flash');self.click(self.v.pos((35.5,28.5)))
        self.v.commit_draft();self.assertEqual(self.v.world.actor(1).inventory.quantities['flashbang'],1)
        self.assertTrue(self.v.world.planner.tasks)

    def test_all_members_and_primary_controls_fit_without_scroll(self):
        for size in ((1280,720),(1440,900)):
            self.v.resize(size);self.draft('flashbang')
            labels=self.buttons()
            members=[rect for label,rect in labels if '号 ·' in label]
            self.assertEqual(len(members),4)
            for rect in members:self.assertTrue(pg.Rect(self.v.viewport.right,48,300,self.v.height-160).contains(rect))
            submit=next(rect for label,rect in labels if label=='下达计划')
            for label,rect in labels:
                if label in ('近期事件','待分配 0 · L','退出 · 留草稿'):self.assertFalse(submit.colliderect(rect))
            self.v.plan_settings=True;self.v.draw()
            self.assertTrue(self.v.viewport.contains(self.v.plan_settings_rect))

    def test_sidebar_decision_is_explicit_and_quick_order_keeps_running(self):
        self.v.world.set_paused(False);self.v.door_menu(door='door_S_R')
        self.press('突入  ›');self.press('直接突入')
        self.assertIsNone(self.v.menu);self.assertIsNone(self.v.draft);self.assertFalse(self.v.world.planner.tasks)
        self.press('立即下令 · 直接突入');self.assertTrue(self.v.world.planner.tasks)
        self.assertFalse(self.v.world.paused)

    def test_keyboard_navigation_requires_explicit_submit_choice(self):
        self.v.door_menu(door='door_S_R')
        self.key(pg.K_DOWN);self.key(pg.K_DOWN);self.key(pg.K_RETURN)
        self.key(pg.K_RETURN);self.assertIsNotNone(self.v.action_focus['choice'])
        self.assertFalse(self.v.world.planner.tasks)
        self.key(pg.K_RETURN);self.assertIsNone(self.v.draft)
        self.key(pg.K_RETURN);self.assertIsNotNone(self.v.draft)
        self.assertFalse(self.v.world.planner.tasks)

    def test_visible_room_tool_and_sidebar_search_reuse_existing_planner(self):
        self.press('房间操作…');self.click(self.v.pos((34.5,32.5)))
        self.assertEqual(self.v.room_inspect,'S');self.assertIsNone(self.v.menu)
        self.press('搜索区域物资  ›');self.press('全员搜索')
        task=next(iter(self.v.world.planner.tasks.values()))
        self.assertEqual(task.draft.method,'loot');self.assertEqual(task.draft.actors,[1,2,3,4])

    def test_settings_blank_click_and_outside_close_preserve_draft(self):
        self.draft();self.press('计划设置…')
        self.v.draw();self.click((self.v.plan_settings_rect.x+10,self.v.plan_settings_rect.bottom-5))
        self.assertTrue(self.v.plan_settings);self.assertIsNotNone(self.v.draft)
        self.click((30,250));self.assertFalse(self.v.plan_settings);self.assertIsNotNone(self.v.draft)

    def test_overlay_and_loot_notification_do_not_replace_editor(self):
        self.draft();self.v.edit_draft(entry_angles={1:pi})
        self.press('近期事件');self.key(pg.K_ESCAPE)
        self.assertEqual(self.v.draft.entry_angles[1],pi);self.assertTrue(self.v.world.paused)
        self.v.world.loot.notifications.append('case:S');self.v.update(0)
        self.assertIsNotNone(self.v.draft);self.assertIsNone(self.v.loot_panel)

    def test_shift_at_commit_does_not_override_explicit_replace_setting(self):
        self.v.world.planner.submit([1],'face',angle=1);self.draft()
        pg.key.set_mods(pg.KMOD_SHIFT);self.v.commit_draft()
        self.assertEqual(len(self.v.world.actor(1).queue),1)
        self.assertIsNotNone(self.v.world.actor(1).queue[0].task_id)

    def test_stage_filters_hit_targets_but_preserves_other_stage(self):
        self.draft();before=dict(self.v.draft.stacks);self.v.set_plan_stage('entry');self.v.draw()
        self.assertEqual({stage for _,stage,_ in self.v.plan_markers},{'entry'})
        self.click(self.v.pos(self.v.world.grid.cell_center(before[1])))
        self.assertEqual(self.v.draft.stacks,before)

    def test_replacement_summary_identifies_all_affected_members(self):
        self.draft();self.v.commit_draft();self.v.new_draft([1,2],'door_S_R','R','direct')
        self.assertIn('1/2/3/4',self.v.plan_impact([1,2],False))
        self.assertIn('保留',self.v.plan_impact([1,2],True))

    def test_right_click_places_each_stage_without_moving_live_actors(self):
        self.draft();positions={i:self.v.world.actor(i).position for i in (1,2,3,4)}
        for stage,cell in (('stack',(34,31)),('entry',(37,28))):
            self.v.set_plan_stage(stage);self.v.draw();self.click(self.v.pos((cell[0]+.5,cell[1]+.5)),3)
            self.assertEqual(getattr(self.v.draft,stage+'_overrides')[1],cell)
            self.assertNotIn(1,getattr(self.v.draft,stage+'_angles'))
        self.assertEqual(positions,{i:self.v.world.actor(i).position for i in (1,2,3,4)})
        self.assertFalse(self.v.world.planner.tasks)
        self.v.commit_draft();d=next(iter(self.v.world.planner.tasks.values())).draft
        self.assertEqual(d.stacks[1],(34,31));self.assertEqual(d.entries[1],(37,28))

    def test_right_drag_anchors_destination_at_press_and_undoes_both_changes(self):
        for stage,cell in (('stack',(34,31)),('entry',(37,28))):
            self.v.clear_tools();self.draft();self.v.set_plan_stage(stage)
            old=dict(getattr(self.v.draft,'stacks' if stage=='stack' else 'entries'))
            start=self.v.pos((cell[0]+.5,cell[1]+.5));end=(start[0]+round(self.v.scale*2),start[1])
            self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=start,button=3)])
            self.v.events([pg.event.Event(pg.MOUSEMOTION,pos=end,rel=(end[0]-start[0],0),buttons=(0,0,1))])
            self.v.draw();self.assertEqual(getattr(self.v.draft,'stacks' if stage=='stack' else 'entries'),old)
            self.v.events([pg.event.Event(pg.MOUSEBUTTONUP,pos=end,button=3)])
            self.assertEqual(getattr(self.v.draft,stage+'_overrides')[1],cell)
            self.assertAlmostEqual(getattr(self.v.draft,stage+'_angles')[1],0)
            self.assertEqual(len(self.v.plan_history),1)
            self.v.undo_plan();self.assertEqual(getattr(self.v.draft,'stacks' if stage=='stack' else 'entries'),old)
            self.assertFalse(getattr(self.v.draft,stage+'_angles'))

    def test_small_right_drag_uses_default_facing_at_all_zooms(self):
        for scale in (12,32,64):
            self.v.clear_tools();self.draft();self.v.set_plan_stage('entry')
            self.v.scale=scale;self.v.offset=[480-35*scale,300-30*scale]
            self.v.edit_draft(entry_angles={1:pi});start=self.v.pos((37.5,28.5))
            self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=start,button=3),
                           pg.event.Event(pg.MOUSEBUTTONUP,pos=(start[0]+round(.2*scale),start[1]),button=3)])
            self.assertEqual(self.v.draft.entries[1],(37,28));self.assertNotIn(1,self.v.draft.entry_angles)
            self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=start,button=3),
                           pg.event.Event(pg.MOUSEBUTTONUP,pos=(start[0],start[1]+scale),button=3)])
            self.assertAlmostEqual(self.v.draft.entry_angles[1],pi/2)

    def test_escape_outside_release_and_stage_switch_cancel_pending_move(self):
        for cancel in ('escape','outside','stage'):
            self.v.clear_tools();self.draft();self.v.set_plan_stage('entry')
            start=self.v.pos((37.5,28.5));end=(start[0]+50,start[1])
            self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=start,button=3)])
            if cancel=='escape':self.key(pg.K_ESCAPE)
            elif cancel=='stage':self.v.set_plan_stage('stack')
            else:end=(self.v.width-10,self.v.height//2)
            self.v.events([pg.event.Event(pg.MOUSEBUTTONUP,pos=end,button=3)])
            self.assertIsNotNone(self.v.draft);self.assertFalse(self.v.draft.entry_overrides)
            self.assertFalse(self.v.plan_history);self.assertIsNone(self.v.move_drag)

    def test_left_drag_only_selects_marker_and_position_buttons_are_removed(self):
        self.draft();self.v.set_plan_stage('entry');self.v.draw()
        old=dict(self.v.draft.entries);start=self.v.pos(self.v.world.grid.cell_center(old[2]));end=self.v.pos((37.5,28.5))
        self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=start,button=1),pg.event.Event(pg.MOUSEBUTTONUP,pos=end,button=1)])
        self.assertEqual(self.v.plan_actor,2);self.assertEqual(self.v.draft.entries,old)
        for stage in ('stack','entry'):
            self.v.set_plan_stage(stage)
            self.assertFalse(any('改位置' in label or '改朝向' in label for label,_ in self.buttons()))

    def test_ordinary_and_draft_moves_share_direction_and_press_destination(self):
        self.v.select([1]);self.v.scale=32;self.v.offset=[480-35*32,300-30*32]
        start=self.v.pos((34.5,31.5));end=(start[0]+32,start[1]-32)
        self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=start,button=3),pg.event.Event(pg.MOUSEBUTTONUP,pos=end,button=3)])
        normal=self.v.world.actor(1).queue[0]
        self.assertEqual(normal.cell,(34,31))
        self.draft();self.v.scale=32;self.v.offset=[480-35*32,300-30*32]
        self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=start,button=3),pg.event.Event(pg.MOUSEBUTTONUP,pos=end,button=3)])
        self.assertEqual(self.v.draft.stacks[1],normal.cell);self.assertEqual(self.v.draft.stack_angles[1],normal.angle)
        self.assertIs(self.v.world.actor(1).queue[0],normal)


if __name__=='__main__':unittest.main()
