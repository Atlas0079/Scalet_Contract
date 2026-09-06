from pathlib import Path
import copy
import os
import sys
import unittest
from math import pi
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
os.environ['SDL_VIDEODRIVER']='dummy';os.environ['SDL_AUDIODRIVER']='dummy'
from simulation.actor import ActorMode,ActionType,Team,FireMode
from simulation.geometry import Vec2
from simulation.items import ITEMS,SupplyDefinition,UseDefinition
from simulation.weapon import ItemDefinition
from simulation.mission import create_mission,RECTS
from simulation.movement import stop_actor_at_cell


def quiet(w):
    for a in w.actors:
        a.fire_mode=FireMode.HOLD_FIRE;a.ai_enabled=False


def advance(w,seconds):
    w.paused=False
    for _ in range(round(seconds*60)):
        w.update(1/60)


def kill(a):a.body.damage_part('brain',999);a.mark_dead_if_needed()


class TacticalTests(unittest.TestCase):
    def setUp(self):self.w=create_mission();self.p=self.w.planner

    def test_T01_pause_freezes_physics_and_resources(self):
        self.p.submit([1],'move',cell=(30,32));a=self.w.actor(1)
        snapshot=copy.deepcopy((a.position,a.facing,a.body,a.weapon,a.inventory.quantities,self.w.time))
        self.w.update(3)
        self.assertEqual(snapshot,(a.position,a.facing,a.body,a.weapon,a.inventory.quantities,self.w.time))

    def test_facing_plan_uses_one_turn_budget_per_step(self):
        from simulation.geometry import angle_difference
        quiet(self.w);a=self.w.actor(1);start=a.facing
        self.p.submit([1],'face',angle=pi/2);advance(self.w,1/60)
        self.assertLessEqual(abs(angle_difference(start,a.facing)),a.turn_speed/60+1e-9)

    def test_T02_four_move_destinations_are_unique(self):
        quiet(self.w);self.assertIsNone(self.p.submit([1,2,3,4],'move',cell=(29,32)))
        advance(self.w,12)
        self.assertEqual(len({a.occupied_cell for a in self.w.actors[:4]}),4)
        self.assertTrue(all(not a.queue for a in self.w.actors[:4]))

    def test_T03_rejection_preserves_existing_plan(self):
        self.p.submit([1],'move',cell=(30,32));token=self.w.actor(1).queue[0].token
        self.assertIsNotNone(self.p.submit([1],'move',cell=(5,5)))
        self.assertEqual(token,self.w.actor(1).queue[0].token)

    def test_T04_abstract_search_two_and_four(self):
        for ids in ([1,2],[1,2,3,4]):
            w=create_mission();quiet(w);p=w.planner
            stop_actor_at_cell(w.actors[4],w.grid,(5,5))
            self.assertIsNone(p.submit_task(p.choose_entrance(ids,door='door_S_R')))
            advance(w,65)
            self.assertIn('R',w.mission.room_checked)
            self.assertFalse(p.tasks)

    def test_T05_locked_door_requires_explicit_kick(self):
        self.w.grid.interactables['door_S_R'].properties['locked']=True
        self.w.perception.doors['door_S_R']='locked'
        d,error=self.p.preview_task([1,2],'door_S_R','R','direct');self.assertIn('门已锁',error)
        quiet(self.w);d,error=self.p.preview_task([1,2],'door_S_R','R','breach')
        self.assertIsNone(error);self.p.submit_task(d);advance(self.w,9)
        self.assertEqual(self.w.door_state('door_S_R'),'broken')

    def test_T06_two_entries_release_same_step(self):
        quiet(self.w)
        for ids,door in [([1,2],'door_S_R'),([3,4],'door_S_L')]:
            d=self.p.choose_entrance(ids,door=door);d.sync='A';self.p.submit_task(d)
        self.assertIsNotNone(self.p.release('A'));advance(self.w,25)
        self.assertTrue(all(ready for _,ready in self.p.sync_status('A')))
        self.assertIsNone(self.p.release('A'));advance(self.w,1/60)
        self.assertTrue(all(t.released for t in self.p.tasks.values()))
        self.assertEqual(sum(a.current_action is not None for a in self.w.actors[:4]),2)

    def test_T07_cancel_unregisters_sync(self):
        self.p.submit([1],'wait',sync='A');self.p.stop([1]);self.assertEqual(self.p.sync_status('A'),[])

    def test_T08_micro_override_cancels_whole_team(self):
        self.p.submit_task(self.p.choose_entrance([1,2,3,4],door='door_S_R'))
        self.p.submit([3],'move',cell=(40,32))
        self.assertFalse(self.p.tasks)
        self.assertTrue(all(not self.w.actor(i).queue for i in (1,2,4)))
        self.assertEqual(self.w.actor(3).queue[0].kind,'move')

    def test_T07_entry_member_death_can_resume_remaining_team(self):
        w=self.w;quiet(w);stop_actor_at_cell(w.actors[4],w.grid,(5,5))
        self.p.submit_task(self.p.choose_entrance([1,2,3,4],door='door_S_R'))
        w.paused=False
        for _ in range(1200):
            w.update(1/60)
            task=next(iter(self.p.tasks.values()))
            if 1 in task.entered:break
        self.assertIn(1,task.entered);kill(w.actor(1));w.update(1/60)
        self.assertEqual(task.phase,'blocked');self.assertIsNone(self.p.retry_task(task.id))
        advance(w,60);self.assertIn('R',w.mission.room_checked)

    def test_T09_queue_limit_and_segment_cancel(self):
        for i in range(8):self.assertIsNone(self.p.submit([1],'face',angle=i*.1,append=True))
        self.assertIsNotNone(self.p.submit([1],'face',angle=2,append=True))
        quiet(self.w);self.p.submit([1],'move',cell=(30,32));advance(self.w,.2)
        a=self.w.actor(1);position=a.position;destination=a.move_to;self.p.stop([1])
        self.assertEqual(a.position,position);advance(self.w,1)
        self.assertEqual(a.occupied_cell,destination)

    def test_T10_stationary_block_becomes_recoverable(self):
        quiet(self.w);self.p.submit([1],'move',cell=(30,32));stop_actor_at_cell(self.w.actor(2),self.w.grid,(30,32))
        advance(self.w,12);self.assertEqual(self.w.actor(1).queue[0].status,'blocked')
        self.assertIn('5 秒',self.w.actor(1).blocked_reason)

    def test_T11_memory_stays_at_last_seen_position(self):
        w=self.w;a=w.actor(1);enemy=w.actors[4]
        stop_actor_at_cell(a,w.grid,(39,28));a.facing=-pi/2
        w.perception.refresh(w,.3);old=enemy.position;self.assertIn(enemy.id,w.perception.player_visible)
        stop_actor_at_cell(enemy,w.grid,(5,5));w.perception.refresh(w,.1)
        self.assertNotIn(enemy.id,w.perception.player_visible);self.assertEqual(w.perception.last_seen[enemy.id][0],old)

    def test_T12_sound_is_quantized_and_cannot_identify(self):
        w=self.w;w.emit_sound(Vec2(35.7,29.5),Team.BLUE,14,'rifle')
        sound=w.sounds[-1];self.assertEqual(sound.area,(33,27));self.assertTrue(sound.audible)
        self.assertFalse(w.perception.player_visible)

    def test_T14_friendly_center_line_prevents_fire(self):
        w=self.w;quiet(w);a=w.actor(1);friend=w.actor(2);enemy=w.actors[4]
        for actor,cell in [(a,(32,32)),(friend,(34,32)),(enemy,(37,32))]:stop_actor_at_cell(actor,w.grid,cell)
        a.facing=0;a.fire_mode=FireMode.AIMED_SHOT;advance(w,2)
        self.assertEqual(a.weapon.ammo,30);self.assertEqual(a.fire_reason,'友军挡线')

    def test_T15_flash_respects_walls_and_facing(self):
        w=self.w;quiet(w)
        for a,cell,face in [(w.actor(1),(34,32),0),(w.actor(2),(36,32),0),(w.actor(3),(35,29),pi/2)]:
            stop_actor_at_cell(a,w.grid,cell);a.facing=face
        w._flash({'end':Vec2(35.5,32.5),'radius':4,'team':Team.RED})
        self.assertEqual(w.actor(1).stunned,2.5);self.assertEqual(w.actor(2).stunned,.8);self.assertEqual(w.actor(3).stunned,0)

    def test_T16_cancel_reload_and_throw_do_not_consume(self):
        w=self.w;quiet(w);a=w.actor(1);a.weapon.ammo=5
        self.p.submit([1],'reload',item='rifle');advance(w,.2);self.p.stop([1]);self.assertEqual((a.weapon.ammo,a.weapon.reserve_ammo),(5,90))
        w.perception.explored.add((33,30));self.p.submit([1],'throw',item='flashbang',cell=(33,30));advance(w,.2)
        self.p.stop([1]);self.assertEqual(a.inventory.quantities['flashbang'],1);self.assertEqual(a.inventory.reserved('flashbang'),0)

    def test_T17_single_survivor_can_open_and_fight(self):
        w=self.w;quiet(w)
        for a in w.actors[1:4]:kill(a)
        d,e=self.p.preview_task([1],'door_S_R','R','open');self.assertIsNone(e);self.p.submit_task(d)
        advance(w,8)
        if w.paused:advance(w,8)
        self.assertEqual(w.door_state('door_S_R'),'open')

    def test_T18_success_immediate(self):
        for a in self.w.actors[4:]:kill(a)
        advance(self.w,1/60);self.assertEqual(self.w.winner,Team.RED)

    def test_T19_mutual_wipe_fails_and_freezes(self):
        for a in self.w.actors:kill(a)
        advance(self.w,1/60);self.assertEqual(self.w.winner,Team.BLUE)
        before=self.w.time;self.w.update(1);self.assertEqual(before,self.w.time)

    def test_T20_same_inputs_same_result(self):
        snapshots=[]
        for _ in range(2):
            w=create_mission();w.planner.submit_task(w.planner.choose_entrance([1,2],door='door_S_R'));advance(w,12)
            snapshots.append([(a.position,a.facing,a.weapon.ammo,[(p.hp) for p in a.body.parts.values()]) for a in w.actors])
        self.assertEqual(*snapshots)

    def test_T24_reservations_release(self):
        self.w.perception.explored.add((33,30));a=self.w.actor(1)
        self.assertIsNone(self.p.submit([1],'throw',item='flashbang',cell=(33,30)))
        self.assertIsNotNone(self.p.submit([1],'throw',item='flashbang',cell=(33,30),append=True))
        self.p.stop([1]);self.assertEqual(a.inventory.available('flashbang'),1)

    def test_T26_additional_item_uses_same_execution(self):
        item=SupplyDefinition(ItemDefinition('training_flash','验证闪光','consumable'),25,(UseDefinition('throw','投掷…','ground',.1,1,8,2,True,'flash'),))
        ITEMS[item.id]=item
        try:
            w=self.w;quiet(w);a=w.actor(1);a.inventory.quantities[item.id]=1;w.perception.explored.add((33,30))
            self.assertIsNone(self.p.submit([1],'throw',item=item.id,cell=(33,30)));advance(w,.2)
            self.assertEqual(a.inventory.quantities[item.id],0);self.assertEqual(w.projectiles[0]['radius'],2)
        finally:ITEMS.pop(item.id)

    def test_T27_invalid_replacement_retains_reservation(self):
        w=self.w;w.perception.explored.add((33,30));a=w.actor(1)
        self.p.submit([1],'throw',item='flashbang',cell=(33,30));token=a.queue[0].token
        self.assertIsNotNone(self.p.submit([1],'throw',item='flashbang',cell=(1,1)))
        self.assertIn(token,a.inventory.reservations);self.assertEqual(token,a.queue[0].token)
        self.assertIsNone(self.p.submit([1],'throw',item='flashbang',cell=(33,30)))
        self.assertEqual(a.inventory.reserved('flashbang'),1)

    def test_T28_full_member_rejects_whole_group(self):
        for _ in range(8):self.p.submit([2],'face',angle=0,append=True)
        d=self.p.choose_entrance([1,2],door='door_S_R')
        self.assertIsNotNone(self.p.submit_task(d,append=True));self.assertFalse(self.w.actor(1).queue)

    def test_T31_map_configurations_and_observations(self):
        for config in 'ABC':
            w=create_mission(config);self.assertEqual(len(w.actors),14);self.assertEqual(sum(bool(a.patrol) for a in w.actors),3)
            self.assertEqual(len(w.grid.zone_cells),sum(len(z.cells) for z in w.grid.zones.values()))
            for a in w.actors:self.assertTrue(w.grid.walkable(a.occupied_cell))
            for room in w.mission.rooms:
                points=w.planner.observations(room)
                for point in points:self.assertTrue(w.grid.find_path(points[0],point,allowed_cells=set(w.grid.zones[room].cells)))


if __name__=='__main__':unittest.main(verbosity=2)
