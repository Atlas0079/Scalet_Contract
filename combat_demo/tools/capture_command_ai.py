"""Reproduce v1.4 input previews and a controlled real-ballistics regression scene."""
from pathlib import Path
import os
import sys
os.environ['SDL_VIDEODRIVER']='dummy';os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView
from simulation.actor import FireMode
from simulation.movement import stop_actor_at_cell


def main():
    folder=Path(__file__).resolve().parents[1]/'artifacts'
    app=PygameView();app.start_mission();app.hints=False
    app.scale=26;app.offset=[app.viewport.centerx-33*26,app.viewport.centery-26*26]
    w=app.world
    w.planner.submit_task(w.planner.choose_entrance([1,2,3,4],door='door_S_R'))
    app.select([1]);app.draw();point=app.pos((30.5,32.5))
    app.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=point,button=3),
                pg.event.Event(pg.MOUSEMOTION,pos=(point[0]+70,point[1]),rel=(70,0),buttons=(0,0,1))])
    app.draw();pg.image.save(app.screen,str(folder/'v14-drag.png'))
    app.clear_tools()
    # This is a test fixture, not a staged mission victory. The enemy fires
    # through World._combat and normal hit / near-miss resolution.
    enemy=w.actors[4];a=w.actor(1)
    for x in w.actors:x.ai_enabled=False;x.fire_mode=FireMode.HOLD_FIRE;x.view_distance=0
    stop_actor_at_cell(enemy,w.grid,(29,32))
    enemy.facing=enemy.guard_angle=0;enemy.view_distance=12;enemy.fire_mode=FireMode.AIMED_SHOT
    a.facing=a.guard_angle=0;a.view_distance=12
    w.paused=False
    for _ in range(180):
        w.update(1/60)
        if a.under_fire_timer>w.time:break
    assert a.under_fire_timer>w.time,'fixture did not receive incoming fire'
    for _ in range(20):w.update(1/60)
    w.set_paused(True);app.selected=[1,2,3,4];app.draw()
    pg.image.save(app.screen,str(folder/'v14-suspended.png'))
    print('captured',w.time,a.alive,a.response)
    pg.quit()


if __name__=='__main__':main()
