"""Render reproducible loot interactions with the real Pygame interface."""
from pathlib import Path
import os
import sys

os.environ['SDL_VIDEODRIVER']='dummy'
os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView
from simulation.actor import FireMode
from simulation.movement import stop_actor_at_cell


def capture(size,folder):
    view=PygameView(size=size);view.start_mission();view.hints=False
    w=view.world
    for a in w.actors:a.ai_enabled=False;a.fire_mode=FireMode.HOLD_FIRE
    view.selected=[1];view.scale=38
    view.offset=[view.viewport.centerx-36*view.scale,view.viewport.centery-30*view.scale]
    stop_actor_at_cell(w.actor(2),w.grid,(42,33))
    view.submit([1],'loot_search',object_id='case:S')
    w.set_paused(False)
    for _ in range(600):
        view.update(1/60)
        if view.loot_panel:break
    assert view.loot_panel=='case:S'
    obj=w.loot.objects['case:S'];gun=next(i for i in obj.items.values() if i.weapon)
    view.pickup(gun.id,1)
    view.draw()
    view.pickup_menu(gun.id,view.loot_rows[0][0].center)
    view.draw();pg.image.save(view.screen,str(folder/f'allocation-{size[0]}.png'))
    view.menu.activate((0,1));view.draw();pg.image.save(view.screen,str(folder/f'assigned-{size[0]}.png'))
    assert gun.id in obj.items and gun.id not in w.actor(2).inventory.cargo
    view.close_loot();w.set_paused(False)
    for _ in range(600):
        view.update(1/60)
        if gun.id in w.actor(2).inventory.cargo:break
    assert gun.id in w.actor(2).inventory.cargo and gun.id not in obj.items
    w.set_paused(True);view.selected=[2];view.mouse=(500,250);view.inventory_menu(2)
    view.draw();pg.image.save(view.screen,str(folder/f'carried-{size[0]}.png'))
    pg.quit()


if __name__=='__main__':
    folder=Path(__file__).resolve().parents[1]/'artifacts'/'loot-reassign'
    folder.mkdir(parents=True,exist_ok=True)
    for size in ((1440,900),(1280,720)):capture(size,folder)
    print('Real interface captures and physical pickup checks passed:',folder)
