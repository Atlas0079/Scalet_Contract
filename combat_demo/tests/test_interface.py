from pathlib import Path
import os
import sys
import unittest
os.environ['SDL_VIDEODRIVER']='dummy';os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView
from simulation.items import ITEMS,SupplyDefinition,UseDefinition
from simulation.weapon import ItemDefinition


class InterfaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.app=PygameView()
    @classmethod
    def tearDownClass(cls):pg.quit()
    def setUp(self):self.app.start_mission();self.app.draw()

    def click(self,pos,button=1):
        self.app.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=pos,button=button),pg.event.Event(pg.MOUSEBUTTONUP,pos=pos,button=button)])

    def test_T21_door_actions_stay_in_sidebar_without_issuing_orders(self):
        a=self.app;a.door_menu(door='door_S_R',anchor=(1390,800))
        self.assertIsNone(a.menu)
        a.choose_action(a.action_focus['entries'][2]);a.choose_action(a.action_focus['entries'][0])
        a.draw();self.assertIsNone(a.draft);self.assertFalse(a.world.planner.tasks)
        a.new_draft(*a.action_focus['choice']);self.assertIsNotNone(a.draft)
        self.assertFalse(a.world.planner.tasks)

    def test_T22_personal_inventory_keeps_selection(self):
        a=self.app;a.world.actor(3).weapon.ammo=7
        for i in [1,2,4]:a.world.planner.submit([i],'face',angle=0)
        tokens=[a.world.actor(i).queue[0].token for i in [1,2,4]]
        self.click(a.cards[2][0].center,3)
        a.menu.activate((0,0));a.menu.activate((1,0))
        self.assertEqual(a.selected,[1,2,3,4]);self.assertEqual(a.world.actor(3).queue[0].kind,'reload')
        self.assertEqual(tokens,[a.world.actor(i).queue[0].token for i in [1,2,4]])

    def test_T23_outside_click_does_not_issue_move(self):
        a=self.app;a.door_menu(door='door_S_R',anchor=(500,450))
        self.click((100,700));self.assertIsNone(a.menu);self.assertFalse(any(actor.queue for actor in a.world.actors[:4]))
        a.use_item(3,'flashbang','throw');self.click(a.pos((5.5,5.5)))
        self.assertIsNotNone(a.tool);self.assertFalse(a.world.actor(3).inventory.reservations)

    def test_T25_selection_change_cancels_targeting(self):
        a=self.app;a.use_item(3,'flashbang','throw')
        a.events([pg.event.Event(pg.KEYDOWN,key=pg.K_1,mod=0)])
        self.assertIsNone(a.tool);self.assertEqual(a.selected,[1]);self.assertFalse(a.world.actor(3).queue)

    def test_T26_inventory_and_breach_menus_are_capability_driven(self):
        a=self.app;item=SupplyDefinition(ItemDefinition('test_flash','测试闪光','consumable'),21,(UseDefinition('throw','投掷…','ground',.3,1,9,3,True,'flash'),))
        ITEMS[item.id]=item;a.world.actor(3).inventory.quantities[item.id]=1
        try:
            a.personal_menu(3,(600,400));self.assertTrue(any('测试闪光' in e.label for e in a.menu.entries))
            a.door_menu(door='door_S_R',anchor=(600,400));entries=a.action_focus['entries'][2].children
            self.assertTrue(any('测试闪光' in e.label for e in entries));entries[-1].action();a.new_draft(*a.action_focus['choice'])
            self.assertEqual(a.draft.item,item.id)
        finally:ITEMS.pop(item.id)

    def test_T29_effects_do_not_change_visibility(self):
        a=self.app;before=set(a.world.perception.player_visible)
        for effect in range(3):a.fx=effect;a.draw();self.assertEqual(before,a.world.perception.player_visible)

    def test_T30_paused_fx_freezes_but_tool_works(self):
        a=self.app;before=a.fx_time;a.update(.5);self.assertEqual(before,a.fx_time)
        a.use_item(3,'flashbang','throw');a.world.perception.explored.add((37,30))
        self.click(a.pos((37.5,30.5)))
        self.assertEqual(a.world.actor(3).queue[0].kind,'throw');self.assertEqual(a.world.time,0)

    def test_T32_minimum_resolution_commit_button_visible(self):
        a=self.app;a.resize((1280,720));a.new_draft([1,2,3,4],'door_S_R',None,'flash','flashbang');a.draw()
        button=next(r for r,fn,en,reason in a.buttons if fn==a.commit_draft)
        self.assertLessEqual(button.bottom,608);self.assertGreaterEqual(button.top,48)
        a.resize((1440,900))


if __name__=='__main__':unittest.main(verbosity=2)
