from pathlib import Path
import os
import sys
os.environ['SDL_VIDEODRIVER']='dummy'
os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView

folder=Path(__file__).resolve().parents[1]/'artifacts'/'focus-v154'
folder.mkdir(parents=True,exist_ok=True)
for size in ((1280,720),(1440,900)):
    v=PygameView(size=size);v.start_mission();v.hints=False
    def save(name):v.draw();pg.image.save(v.screen,str(folder/f'{name}-{size[0]}.png'))
    v.select([]);save('overview')
    v.select([1,2,3,4]);save('squad')
    v.door_menu(room='S');save('room')
    v.mouse=v.pos((35,32));pg.key.set_mods(pg.KMOD_CTRL);save('ctrl-room');pg.key.set_mods(0)
    v.personal_menu(2,(450,200));save('personal')
    v.new_draft([1,2,3,4],'door_S_R',None,'direct');save('draft')
    v.clear_tools();v.object_menu('case:S',(450,200));save('container')
    obj=v.world.loot.objects['case:S'];obj.opened=obj.searched=obj.discovered=True
    v.world.loot.remember(obj);v.world.loot.open_result(obj,v.world.actor(1))
    v.show_loot(obj.id);save('allocation')
    v.show_overlay('events');save('events');v.close_overlay()
    assert v.loot_panel==obj.id and v.world.paused
    pg.quit()
print('Focus screenshots captured:',folder)
