"""Capture real world movement from a four-person overlapping start."""
from pathlib import Path
import json
import os
import sys

os.environ['SDL_VIDEODRIVER'] = 'dummy'
os.environ['SDL_AUDIODRIVER'] = 'dummy'
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView
from simulation.actor import FireMode
from simulation.movement import stop_actor_at_cell


def main():
    folder = Path(__file__).resolve().parents[1] / 'artifacts' / 'crowding-v174'
    folder.mkdir(parents=True, exist_ok=True)
    view = PygameView(size=(1280, 720))
    view.start_mission()
    view.hints = False
    view.scale = 48
    view.offset = [view.viewport.centerx-34.5*48, view.viewport.centery-32.5*48]
    world = view.world
    for a in world.actors:
        a.ai_enabled = False
        a.fire_mode = FireMode.HOLD_FIRE
    for i in (1, 2, 3, 4):
        stop_actor_at_cell(world.actor(i), world.grid, (30, 32))
        error = world.planner.submit([i], 'move', cell=(40+i, 32))
        assert error is None, error
    samples = []
    def capture(name):
        view.draw()
        pg.image.save(view.screen, str(folder / f'{name}.png'))
        samples.append({'seconds': round(world.time, 3), 'actors': [
            {'id': i, 'distance': round(world.actor(i).position.x-30.5, 4),
             'slow_remaining': round(world.actor(i).crowd_slow_remaining, 4),
             'response': world.actor(i).response, 'blocked': world.actor(i).blocked_reason}
            for i in (1, 2, 3, 4)]})
    capture('overlapping-start')
    world.set_paused(False)
    for frame in range(1, 241):
        world.update(1/60)
        if frame in (15, 90, 240):
            capture(f'after-{frame}-ticks')
    assert world.actor(1).position.x-30.5 > 7.9
    assert all(world.actor(i).position.x-world.actor(i+1).position.x >= .819 for i in (1, 2, 3))
    assert all(not world.actor(i).blocked_reason for i in (1, 2, 3, 4))
    (folder / 'movement.json').write_text(json.dumps(samples, ensure_ascii=False, indent=2), encoding='utf-8')
    pg.quit()
    print('Movement capture complete:', folder)


if __name__ == '__main__':
    main()
