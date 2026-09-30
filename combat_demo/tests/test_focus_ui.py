from pathlib import Path
import os
import sys
import unittest

os.environ['SDL_VIDEODRIVER']='dummy'
os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView


class FocusUiTests(unittest.TestCase):
    def setUp(self):
        self.v=PygameView(size=(1280,720));self.v.start_mission();self.v.hints=False

    def tearDown(self):pg.key.set_mods(0);pg.quit()

    def click(self,pos,button=1):
        self.v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=pos,button=button),pg.event.Event(pg.MOUSEBUTTONUP,pos=pos,button=button)])

    def key(self,key,mod=0):self.v.events([pg.event.Event(pg.KEYDOWN,key=key,mod=mod)])

    def buttons(self):
        labels={};original=self.v.button
        def record(rect,label,action,*args,**kwargs):
            labels[label]=pg.Rect(rect);return original(rect,label,action,*args,**kwargs)
        self.v.button=record
        try:self.v.draw()
        finally:self.v.button=original
        return labels

    def test_room_label_is_ground_and_plain_right_click_moves(self):
        self.v.draw();rect=next(r for r,room in self.v.room_labels if room=='S')
        pos=(rect.x+4,rect.y+4)
        self.assertEqual(self.v.hit_object(pos)[0],'ground')
        self.click(pos,3)
        self.assertIsNone(self.v.room_inspect);self.assertIsNone(self.v.menu)
        self.assertTrue(all(a.queue and a.queue[0].kind=='move' for a in self.v.world.actors[:4]))

    def test_ctrl_right_click_over_actor_focuses_room_without_orders(self):
        pg.key.set_mods(pg.KMOD_CTRL)
        self.click(self.v.pos(self.v.world.actor(1).position),3)
        self.assertEqual(self.v.room_inspect,'S');self.assertEqual(self.v.selected,[1,2,3,4])
        self.assertFalse(any(a.queue for a in self.v.world.actors[:4]))
        pg.key.set_mods(0)
        labels=self.buttons();self.assertIn('突入  ›',labels);self.assertNotIn('警戒 Q',labels)
        self.key(pg.K_ESCAPE);self.assertIsNone(self.v.room_inspect)
        self.assertIn('警戒 Q',self.buttons())

    def test_no_selection_only_shows_global_entries(self):
        self.v.select([]);labels=self.buttons()
        self.assertIn('近期事件',labels);self.assertIn('待分配 0 · L',labels)
        self.assertNotIn('警戒 Q',labels);self.assertNotIn('伤势与携带详情',labels)
        self.assertNotIn('携带物品 I',labels)
        self.key(pg.K_a,pg.KMOD_CTRL)
        self.assertIn('警戒 Q',self.buttons())

    def test_hover_does_not_change_focus_and_selection_resets_room(self):
        self.v.door_menu(room='R');self.v.mouse=self.v.pos(self.v.world.actor(2).position);self.v.update(0);self.v.draw()
        self.assertEqual(self.v.room_inspect,'R')
        self.v.select([2]);self.assertIsNone(self.v.room_inspect)
        self.assertIn('警戒 Q',self.buttons())

    def test_personal_sidebar_stop_only_targets_menu_actor(self):
        for i in (1,2):self.v.world.planner.submit([i],'face',angle=1)
        self.v.personal_menu(2,(400,300));labels=self.buttons()
        self.click(labels['取消计划 X'].center)
        self.assertTrue(self.v.world.actor(1).queue);self.assertFalse(self.v.world.actor(2).queue)
        self.assertEqual(self.v.selected,[1,2,3,4])

    def test_events_return_restores_room_focus_and_pause(self):
        self.v.world.set_paused(False);self.v.door_menu(room='R');labels=self.buttons()
        self.click(labels['近期事件'].center);self.assertEqual(self.v.overlay,'events')
        self.v.draw();self.key(pg.K_ESCAPE)
        self.assertEqual(self.v.room_inspect,'R');self.assertFalse(self.v.world.paused)

    def test_popup_over_sidebar_remains_clickable(self):
        self.v.personal_menu(4,(1260,650));self.v.draw()
        menu=self.v.menu
        self.assertGreaterEqual(menu.root.left,self.v.viewport.right)
        index=next(i for i,e in enumerate(menu.entries) if e.label=='取消此人计划')
        self.v.world.planner.submit([4],'face',angle=1)
        self.click((menu.root.x+15,menu.root.y+56+32*index+12))
        self.assertFalse(self.v.world.actor(4).queue)
        self.assertEqual(self.v.selected,[1,2,3,4])

    def test_room_search_sidebar_reuses_macro_action(self):
        self.v.door_menu(room='S');labels=self.buttons()
        self.click(labels['搜索区域物资  ›'].center)
        self.v.choose_action(self.v.action_focus['entries'][0])
        self.assertIsNone(self.v.room_inspect)
        self.assertEqual(next(iter(self.v.world.planner.tasks.values())).draft.actors,[1,2,3,4])

    def test_draft_global_entries_do_not_overlap_submit_at_both_sizes(self):
        for size in ((1280,720),(1440,900)):
            self.v.resize(size);self.v.new_draft([1,2,3,4],'door_S_R',None,'direct');labels=self.buttons()
            submit=next(rect for rect,action,_,_ in self.v.buttons if action==self.v.commit_draft)
            self.assertFalse(submit.colliderect(labels['近期事件']))
            self.assertFalse(submit.colliderect(labels['待分配 0 · L']))
            self.click(labels['近期事件'].center);self.key(pg.K_ESCAPE)
            self.assertIsNotNone(self.v.draft)


if __name__=='__main__':unittest.main()
