from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from simulation.actor import Actor, ActorMode, FireMode, Team
from simulation.map import GridMap, create_wall, create_full_cover
from simulation.mission import create_mission
from simulation.movement import stop_actor_at_cell, update_actor_movement
from simulation.world import World


class LootTests(unittest.TestCase):
    def setUp(self):
        self.w=create_mission();self.p=self.w.planner;self.loot=self.w.loot
        for a in self.w.actors:a.ai_enabled=False;a.fire_mode=FireMode.HOLD_FIRE

    def advance(self,seconds,until_pause=False):
        self.w.paused=False
        for _ in range(round(seconds*60)):
            self.w.update(1/60)
            if until_pause and self.w.paused:break

    def search(self,i=1,objid='case:S'):
        self.assertIsNone(self.p.submit([i],'loot_search',object_id=objid))
        self.advance(12,True)
        self.assertTrue(self.w.paused)
        self.assertIn(objid,self.loot.results)
        return self.loot.objects[objid]

    def test_search_pause_assignment_and_physical_pickup(self):
        obj=self.search();gun=next(i for i in obj.items.values() if i.weapon)
        a,b=self.w.actor(1),self.w.actor(2)
        stop_actor_at_cell(b,self.w.grid,(42,33))
        before=self.loot.weight(b)
        self.assertIsNone(self.loot.allocate(obj.id,{gun.id:2}))
        self.assertIn(gun.id,obj.items);self.assertNotIn(gun.id,b.inventory.cargo)
        self.assertEqual(self.loot.weight(b),before)
        for _ in range(120):self.w.update(1/60)
        self.assertNotIn(gun.id,b.inventory.cargo)
        self.advance(.2)
        self.assertNotIn(gun.id,b.inventory.cargo)
        self.advance(8)
        self.assertIs(b.inventory.cargo[gun.id],gun)
        self.assertEqual(gun.weapon.ammo,17)
        self.assertEqual(b.weapon.ammo,30)
        self.assertNotIn(gun.id,obj.items)

    def test_carrier_death_before_pickup_keeps_item_in_source(self):
        obj=self.search();item=next(iter(obj.items))
        self.loot.allocate(obj.id,{item:2})
        b=self.w.actor(2);b.body.damage_part('brain',999);b.mark_dead_if_needed()
        self.advance(.1)
        self.assertIn(item,obj.items)
        self.assertFalse(self.loot.reservations)
        self.assertNotIn(item,self.loot.objects['corpse:2'].items)

    def test_death_after_pickup_transfers_same_gun_once(self):
        obj=self.search();gun=next(i for i in obj.items.values() if i.weapon)
        self.loot.allocate(obj.id,{gun.id:2});self.advance(5)
        b=self.w.actor(2);b.body.damage_part('brain',999);b.mark_dead_if_needed();self.advance(.1)
        self.assertIs(self.loot.objects['corpse:2'].items[gun.id],gun)
        self.assertFalse(b.inventory.cargo)
        self.assertNotIn(gun.id,obj.items)
        before=len(self.loot.objects);self.advance(.1);self.assertEqual(before,len(self.loot.objects))

    def test_capacity_and_duplicate_reservations_are_atomic(self):
        obj=self.search();gun=next(i for i in obj.items.values() if i.weapon)
        self.w.actor(2).inventory.capacity=self.loot.weight(self.w.actor(2))
        old=list(self.w.actor(1).queue)
        self.assertIn('上限',self.loot.allocate(obj.id,{gun.id:2}))
        self.assertEqual(old,self.w.actor(1).queue);self.assertFalse(self.loot.reservations)
        self.w.actor(2).inventory.capacity=18
        self.assertIsNone(self.loot.allocate(obj.id,{gun.id:2}))
        self.assertIsNone(self.loot.allocate(obj.id,{gun.id:3}))
        self.assertEqual(self.loot.pickup_reservation(obj.id,gun.id)[1].actor_id,3)
        self.assertFalse(self.w.actor(2).queue)

    def test_reassign_failed_capacity_preserves_old_action_and_other_items(self):
        obj=self.search();items=list(obj.items)[:2]
        self.loot.allocate(obj.id,{i:2 for i in items})
        old=list(self.w.actor(2).queue);tokens=set(self.loot.reservations)
        self.w.actor(3).inventory.capacity=0
        self.assertIsNotNone(self.loot.allocate(obj.id,{items[0]:3}))
        self.assertEqual(old,self.w.actor(2).queue);self.assertEqual(tokens,set(self.loot.reservations))
        self.w.actor(3).inventory.capacity=18
        self.assertIsNone(self.loot.allocate(obj.id,{items[0]:3}))
        self.assertEqual([n.cargo_id for n in self.w.actor(2).queue],[items[1]])
        self.assertEqual(len(self.loot.reservations),2)

    def test_same_carrier_keeps_running_action_then_reassign_cancels_transfer(self):
        obj=self.search();gun=next(i for i in obj.items.values() if i.weapon)
        self.loot.allocate(obj.id,{gun.id:1})
        self.w.set_paused(False)
        for _ in range(120):
            self.w.update(1/60)
            if self.w.actor(1).current_action:break
        a=self.w.actor(1);action=a.current_action;self.assertIsNotNone(action)
        token=action.owner_token;timer=action.timer
        a.inventory.capacity=self.loot.weight(a)+gun.weight
        self.assertIsNone(self.loot.allocate(obj.id,{gun.id:1}))
        self.assertIs(action,a.current_action);self.assertEqual(timer,action.timer)
        self.assertIn(token,self.loot.reservations)
        self.assertIsNone(self.loot.allocate(obj.id,{gun.id:2}))
        self.assertIsNone(a.current_action);self.assertNotIn(token,self.loot.reservations)
        self.advance(12)
        self.assertNotIn(gun.id,a.inventory.cargo)
        self.assertIs(self.w.actor(2).inventory.cargo[gun.id],gun)

    def test_reassign_macro_after_result_closed_keeps_task(self):
        self.p.submit_loot_task([1,2],'S')
        task=next(iter(self.p.tasks.values()));self.advance(12,True)
        result=next(iter(self.loot.results.values()));obj=self.loot.objects[result.object_id]
        item=next(iter(obj.items));self.loot.allocate(obj.id,{item:1})
        old=self.loot.pickup_reservation(obj.id,item)[0]
        self.assertNotIn(obj.id,self.loot.results)
        self.assertIsNone(self.loot.allocate(obj.id,{item:2}))
        self.assertIn(task.id,self.p.tasks)
        self.assertFalse(any(n.token==old for n in task.pickups.get(1,[])))
        self.assertEqual(task.pickups[2][-1].cargo_id,item)
        self.assertEqual(task.pickups[2][-1].task_id,task.id)

    def test_active_macro_pickup_reassign_removes_only_old_job(self):
        self.p.submit_loot_task([1,2],'S');task=next(iter(self.p.tasks.values()))
        self.advance(12,True)
        result=next(iter(self.loot.results.values()));obj=self.loot.objects[result.object_id]
        item=next(iter(obj.items));actor=self.w.actor(result.actor_id);other=2 if actor.id==1 else 1
        self.loot.allocate(obj.id,{item:actor.id})
        token=self.loot.pickup_reservation(obj.id,item)[0]
        for _ in range(120):
            self.w.set_paused(False);self.w.update(1/60)
            if actor.current_action and actor.current_action.owner_token==token:break
        self.assertIsNotNone(actor.current_action)
        self.assertEqual(actor.current_action.owner_token,token)
        self.assertIsNone(self.loot.allocate(obj.id,{item:other}))
        self.assertIsNone(actor.current_action);self.assertNotIn(token,self.loot.reservations)
        self.assertIn(task.id,self.p.tasks);self.assertNotIn(actor.id,task.jobs)
        self.assertEqual(task.pickups[other][-1].cargo_id,item)

    def test_unreachable_reassignment_keeps_original_reservation(self):
        obj=self.search();item=next(iter(obj.items));self.loot.allocate(obj.id,{item:1})
        actor=self.w.actor(2);cell=actor.occupied_cell
        for direction in ('N','E','S','W'):self.w.grid.set_edge_feature(cell,direction,create_wall(3))
        tokens=set(self.loot.reservations);queue=list(self.w.actor(1).queue)
        self.assertIsNotNone(self.loot.allocate(obj.id,{item:2}))
        self.assertEqual(tokens,set(self.loot.reservations));self.assertEqual(queue,self.w.actor(1).queue)

    def test_completed_pickup_cannot_be_reassigned_using_stale_knowledge(self):
        obj=self.search();gun=next(i for i in obj.items.values() if i.weapon)
        self.loot.allocate(obj.id,{gun.id:1});self.advance(2)
        self.assertIn(gun.id,self.w.actor(1).inventory.cargo)
        obj.known[gun.id]=gun
        self.assertIsNotNone(self.loot.allocate(obj.id,{gun.id:2}))
        self.assertFalse(self.loot.reservations)
        self.assertFalse(self.w.actor(2).queue)

    def test_cancel_releases_pickup_reservations(self):
        obj=self.search();item=next(iter(obj.items))
        self.loot.allocate(obj.id,{item:2});self.p.stop([2])
        self.assertFalse(self.loot.reservations)
        self.assertIn(item,obj.items)

    def test_searcher_pickup_keeps_source_decision_until_explicit_finish(self):
        obj=self.search();item=next(iter(obj.items))
        self.assertIsNone(self.loot.allocate(obj.id,{item:1},finish=False))
        self.assertIn(obj.id,self.loot.results)
        self.assertEqual(self.w.actor(1).queue[0].kind,'loot_take')
        self.assertIsNone(self.loot.allocate(obj.id,{}))
        self.assertNotIn(obj.id,self.loot.results)
        self.advance(3)
        self.assertNotIn(item,obj.items)

    def test_cancel_single_macro_pickup_keeps_task_and_other_pickup(self):
        self.assertIsNone(self.p.submit_loot_task([1,2],'S'))
        task=next(iter(self.p.tasks.values()));self.advance(12,True)
        result=next(iter(self.loot.results.values()));obj=self.loot.objects[result.object_id]
        # The first result can be a loose drop; add a second known item for the transfer scenario.
        extra=self.loot.item('bandage');obj.items[extra.id]=extra;self.loot.remember(obj)
        first,second=list(obj.items)[:2]
        for item in (first,second):self.assertIsNone(self.loot.allocate(obj.id,{item:1},finish=False))
        token=self.loot.pickup_reservation(obj.id,first)[0]
        kept=self.loot.pickup_reservation(obj.id,second)[0]
        self.loot.cancel_pickup(token)
        self.assertIn(task.id,self.p.tasks)
        self.assertIn(kept,self.loot.reservations)
        self.assertNotIn(token,self.loot.reservations)
        self.assertEqual([n.cargo_id for n in task.pickups[1]],[second])
        self.assertIn(first,obj.items)
        self.assertIn(obj.id,self.loot.results)

    def test_search_does_not_require_inventory_space(self):
        self.w.actor(1).inventory.capacity=0
        self.search()

    def test_blocked_edges_prevent_interaction_even_when_geometrically_close(self):
        grid=GridMap(5,5)
        actor=Actor(1,'A',Team.RED,grid.cell_center((1,2)),0,occupied_cell=(1,2))
        w=World(grid,[actor]);obj=w.loot.add('box','柜子','container',(2,2),discovered=True)
        grid.set_cell_feature((2,2),create_full_cover())
        grid.set_edge_feature((1,2),'E',create_wall(3))
        self.assertNotIn((1,2),w.loot.interaction_cells(obj))
        self.assertNotIn((1,1),w.loot.interaction_cells(obj))
        self.assertFalse(w.loot.at_object(actor,obj))

    def test_macro_allocation_retains_own_task(self):
        self.assertIsNone(self.p.submit_loot_task([1,2],'S'))
        task=next(iter(self.p.tasks.values()))
        self.advance(12,True)
        self.assertTrue(self.loot.results)
        result=next(iter(self.loot.results.values()));obj=self.loot.objects[result.object_id]
        item=next(iter(obj.items))
        self.assertEqual(result.task_id,task.id)
        self.assertIsNone(self.loot.allocate(obj.id,{item:2}))
        self.assertIn(task.id,self.p.tasks)
        self.assertTrue(task.pickups[2])

    def test_incremental_macro_allocation_keeps_ownership_until_close(self):
        self.assertIsNone(self.p.submit_loot_task([1,2],'S'))
        task=next(iter(self.p.tasks.values()))
        self.advance(12,True)
        result=next(iter(self.loot.results.values()));obj=self.loot.objects[result.object_id]
        for item_id in list(obj.items)[:2]:
            self.assertIsNone(self.loot.allocate(obj.id,{item_id:2},finish=False))
            self.assertIn(task.id,self.p.tasks)
            self.assertIn(obj.id,self.loot.results)
        self.assertEqual(len(task.pickups[2]),min(2,len(obj.items)))
        tokens=set(self.loot.reservations)
        self.assertIsNone(self.loot.allocate(obj.id,{}))
        self.assertNotIn(obj.id,self.loot.results)
        self.assertEqual(tokens,set(self.loot.reservations))
        self.assertIn(task.id,self.p.tasks)

    def test_incremental_pickups_enforce_queue_limit_without_losing_reservations(self):
        obj=self.search()
        obj.items={item.id:item for item in [self.loot.item('bandage') for _ in range(9)]}
        self.loot.remember(obj)
        for item_id in list(obj.items)[:8]:
            self.assertIsNone(self.loot.allocate(obj.id,{item_id:2},finish=False))
        tokens=set(self.loot.reservations)
        self.assertIsNotNone(self.loot.allocate(obj.id,{list(obj.items)[8]:2},finish=False))
        self.assertEqual(tokens,set(self.loot.reservations))
        self.assertEqual(len(self.w.actor(2).queue),8)

    def test_macro_takeover_cancels_whole_loot_task(self):
        self.p.submit_loot_task([1,2],'S')
        self.assertIsNone(self.p.submit([1],'move',cell=(32,33)))
        self.assertFalse(self.p.tasks)
        self.assertFalse(self.w.actor(2).queue)

    def test_interrupted_search_keeps_open_color_but_not_hidden_contents(self):
        self.p.submit([1],'loot_search',object_id='case:S')
        for _ in range(240):
            self.w.paused=False;self.w.update(1/60)
            if self.w.actor(1).current_action:break
        obj=self.loot.objects['case:S']
        self.assertTrue(obj.opened);self.assertFalse(obj.searched);self.assertFalse(obj.known)
        self.w.interrupt(self.w.actor(1),'受袭')
        self.advance(1)
        self.assertFalse(obj.searched);self.assertTrue(obj.opened)
        self.assertFalse(self.loot.results)

    def test_drop_then_pickup_and_equip_preserves_weapon(self):
        a=self.w.actor(1);gun=self.loot.item('rifle',ammo=9);a.inventory.cargo[gun.id]=gun
        self.assertIsNone(self.p.submit([1],'loot_drop',cargo_id=gun.id));self.advance(1)
        pile=next(o for o in self.loot.objects.values() if gun.id in o.items)
        self.assertEqual(pile.kind,'ground');self.assertTrue(pile.searched)
        self.loot.allocate(pile.id,{gun.id:2});self.advance(5)
        old_id=self.w.actor(2).inventory.equipped_id
        self.assertIsNone(self.p.submit([2],'loot_equip',cargo_id=gun.id));self.advance(1)
        self.assertEqual(self.w.actor(2).weapon.ammo,9)
        self.assertEqual(self.w.actor(2).inventory.equipped_id,gun.id)
        self.assertIn(old_id,self.w.actor(2).inventory.cargo)

    def test_corpse_placement_and_cost_slowdown_do_not_block(self):
        a=self.w.actor(1);cell=a.occupied_cell
        a.body.damage_part('brain',999);a.mark_dead_if_needed();self.advance(.1)
        corpse=self.loot.objects['corpse:1']
        self.assertEqual(corpse.cell,cell)
        self.assertTrue(self.w.grid.walkable(cell))
        self.assertAlmostEqual(self.w.grid.terrain_speed[cell],.6)
        self.assertGreater(self.w.grid.step_cost(cell,(cell[0]+1,cell[1])),1)

    def test_two_simultaneous_search_results_are_not_overwritten(self):
        self.loot.add('case:2','另一个箱子','case',(39,31),[self.loot.item('parts')],discovered=True)
        stop_actor_at_cell(self.w.actor(1),self.w.grid,(35,31))
        stop_actor_at_cell(self.w.actor(2),self.w.grid,(39,31))
        self.p.submit([1],'loot_search',object_id='case:S')
        self.p.submit([2],'loot_search',object_id='case:2')
        self.advance(5,True)
        self.assertEqual(set(self.loot.results),{'case:S','case:2'})
        self.assertEqual(self.w.pause_count,1)

    def test_nonweapon_cargo_cannot_be_equipped(self):
        item=self.loot.item('parts');self.w.actor(1).inventory.cargo[item.id]=item
        self.assertIn('只能装备',self.p.submit([1],'loot_equip',cargo_id=item.id))
        self.assertIn(item.id,self.w.actor(1).inventory.cargo)

    def test_corpse_speed_affects_travel_time_only_inside_its_cell(self):
        def travel(slow):
            grid=GridMap(5,5)
            if slow:grid.terrain_speed[(2,2)]=.6
            actor=Actor(1,'A',Team.RED,grid.cell_center((1,2)),0,occupied_cell=(1,2))
            actor.route=[(2,2),(3,2)];actor.target_cell=(3,2)
            for tick in range(6000):
                update_actor_movement(actor,grid,[actor],1/600)
                if actor.occupied_cell==(3,2) and actor.mode==ActorMode.STANDING:return (tick+1)/600
            self.fail('movement did not finish')
        self.assertAlmostEqual(travel(True)/travel(False),4/3,delta=.025)

    def test_corpse_spread_does_not_cross_closed_boundary(self):
        grid=GridMap(5,5)
        actors=[Actor(i,str(i),Team.RED,grid.cell_center((2,2)),0,occupied_cell=(2,2)) for i in (1,2)]
        w=World(grid,actors)
        grid.set_edge_feature((2,2),'N',create_wall(3))
        for actor in actors:actor.body.damage_part('brain',999);actor.mark_dead_if_needed();w.loot.corpse(actor)
        self.assertEqual(w.loot.objects['corpse:1'].cell,(2,2))
        self.assertEqual(w.loot.objects['corpse:2'].cell,(1,2))

    def test_full_macro_finishes_after_declining_results_and_keeps_guard_stationary(self):
        guard_cell=self.w.actor(4).occupied_cell
        self.assertIsNone(self.p.submit_loot_task([1,2,4],'S',guards=[4]))
        sources=set()
        for _ in range(60*90):
            for id_ in list(self.loot.results):
                sources.add(id_);self.assertIsNone(self.loot.allocate(id_,{}))
            self.w.paused=False;self.w.update(1/60)
            if not self.p.tasks:break
        self.assertFalse(self.p.tasks)
        self.assertIn('case:S',sources);self.assertIn('drop:S',sources)
        self.assertEqual(self.w.actor(4).occupied_cell,guard_cell)

    def test_last_enemy_corpse_can_be_searched_after_victory(self):
        for a in self.w.actors:
            if a.team==Team.BLUE:a.body.damage_part('brain',999);a.mark_dead_if_needed()
        self.advance(.1)
        self.assertEqual(self.w.winner,Team.RED)
        self.w.continue_looting();self.assertTrue(self.w.paused)
        self.assertTrue(self.w.combat_cleared);self.assertIsNone(self.w.winner)
        self.search()

    def test_searcher_death_allows_macro_survivor_to_finish_same_container(self):
        self.p.submit_loot_task([1,2],'S');task=next(iter(self.p.tasks.values()))
        for _ in range(120):
            self.w.paused=False;self.w.update(1/60)
            if self.w.actor(1).current_action:break
        self.assertEqual(task.jobs[1].object_id,'case:S')
        a=self.w.actor(1);a.body.damage_part('brain',999);a.mark_dead_if_needed();self.advance(.1)
        self.assertEqual(task.phase,'blocked')
        self.assertIsNone(self.p.retry_task(task.id))
        found=False
        for _ in range(60*20):
            for id_ in list(self.loot.results):
                if id_=='case:S':found=True;break
                self.loot.allocate(id_,{})
            if found:break
            self.w.paused=False;self.w.update(1/60)
        self.assertTrue(found)
        self.assertEqual(self.loot.results['case:S'].actor_id,2)

    def test_slow_but_continuous_movement_is_not_treated_as_blocked(self):
        a=self.w.actor(1);a.speed=.8
        for cell in self.w.grid.zones['S'].cells:self.w.grid.terrain_speed[cell]=.6
        self.w.grid.revision+=1;self.w.grid._path_cache.clear()
        self.assertIsNone(self.p.submit([1],'move',cell=(42,33)))
        self.advance(12)
        self.assertFalse(a.blocked_reason)
        self.assertGreater(a.position.x,33.5)
        self.advance(40)
        self.assertFalse(a.queue);self.assertEqual(a.occupied_cell,(42,33))


if __name__=='__main__':unittest.main()
