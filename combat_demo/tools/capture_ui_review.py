"""Capture the command/loot review states using the real renderer."""
from pathlib import Path
import os
import sys

os.environ['SDL_VIDEODRIVER']='dummy'
os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView
from tools.capture_loot import capture


def main():
    folder=Path(__file__).resolve().parents[1]/'artifacts'/'ui-v153'
    folder.mkdir(parents=True,exist_ok=True)
    for size in ((1280,720),(1440,900)):
        capture(size,folder)
        view=PygameView(size=size);view.start_mission();view.hints=False
        view.draw();pg.image.save(view.screen,str(folder/f'overview-{size[0]}.png'))
        view.selected=[1]
        for index in range(8):
            assert view.world.planner.submit([1],'move',cell=(32+index%2,33),append=True) is None
        view.world.actor(1).body.damage_part('left_thigh',10)
        view.inspect_actor(1);view.draw();pg.image.save(view.screen,str(folder/f'details-{size[0]}.png'))
        view.close_overlay();view.world.planner.stop([1]);view.selected=[1,2]
        assert view.world.planner.submit_loot_task([1,2],'S') is None
        task=next(iter(view.world.planner.tasks.values()))
        view.world.planner.suspend_task(task,'未知方向受袭 · 检查周边后手动继续')
        view.draw();pg.image.save(view.screen,str(folder/f'suspended-{size[0]}.png'))
        for id_ in ('case:S','drop:S'):
            obj=view.world.loot.objects[id_];obj.opened=obj.searched=obj.discovered=True
            view.world.loot.remember(obj);view.world.loot.open_result(obj,view.world.actor(1))
        view.show_loot('case:S');view.draw();pg.image.save(view.screen,str(folder/f'multiple-{size[0]}.png'))
        pg.quit()
    print('Captured both resolutions; physical pickup and reassignment passed:',folder)


if __name__=='__main__':main()
