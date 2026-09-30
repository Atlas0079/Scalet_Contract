"""Capture plan editing at different window and map scales."""
from pathlib import Path
import os
import sys
os.environ['SDL_VIDEODRIVER']='dummy'
os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView


def main():
    folder=Path(__file__).resolve().parents[1]/'artifacts'/'planning-v171'
    folder.mkdir(parents=True,exist_ok=True)
    for size in ((1280,720),(1440,900)):
        v=PygameView(size=size);v.start_mission();v.hints=False
        def save(name):v.draw();pg.image.save(v.screen,str(folder/f'{name}-{size[0]}.png'))
        v.door_menu(room='R');save('room')
        v.door_menu(door='door_S_R');save('door')
        v.choose_action(v.action_focus['entries'][2]);v.choose_action(v.action_focus['entries'][0]);save('choice')
        v.new_draft([1,2,3,4],'door_S_R','R','direct');save('stack')
        v.set_plan_stage('entry');save('entry')
        start=v.pos((37.5,28.5));end=(start[0]+round(v.scale*2),start[1])
        v.events([pg.event.Event(pg.MOUSEBUTTONDOWN,pos=start,button=3),
                  pg.event.Event(pg.MOUSEMOTION,pos=end,rel=(end[0]-start[0],0),buttons=(0,0,1))])
        save('right-drag')
        v.events([pg.event.Event(pg.MOUSEBUTTONUP,pos=end,button=3)]);save('right-place')
        v.undo_plan();v.mouse=(0,0)

        v.plan_settings=True;save('settings');v.plan_settings=False
        v.new_draft([1,2,3,4],'door_S_R','R','direct')
        v.edit_draft(stack_overrides={1:(34,31)},entry_overrides={1:(37,28)},entry_angles={1:0})
        assert not v.draft_error
        v.set_plan_stage('entry')
        for scale in (12,32,64):
            v.scale=scale;v.offset=[v.viewport.centerx-35*scale,v.viewport.centery-29.5*scale]
            save(f'plan-zoom-{scale}')
        v.scale=32;v.offset=[v.viewport.centerx-35*32,v.viewport.centery-29.5*32]
        v.focus_plan();v.plan_settings=True;save('plan-controls')
        v.leave_plan();save('saved');v.restore_plan();save('restored')
        v.new_draft([1,2,3,4],'door_S_R','R','flash','flashbang');save('flash')
        v.plan_settings=True;save('flash-settings')
        v.new_draft([1,2],'door_S_R','R','flash','flashbang',quick=True);save('quick-flash')
        pg.quit()
    print('Planning capture complete:',folder)


if __name__=='__main__':main()
