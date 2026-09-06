"""Capture actual renderer states and a played mission outcome, without staged actors."""
import os
os.environ['SDL_VIDEODRIVER']='dummy';os.environ['SDL_AUDIODRIVER']='dummy'
from pathlib import Path
import json
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView
from playthrough import run


def main():
    root=Path(__file__).resolve().parents[1]/'artifacts';root.mkdir(exist_ok=True)
    app=PygameView();app.page='brief';app.draw();pg.image.save(app.screen,str(root/'01-briefing.png'))
    app.start_mission();app.hints=False
    app.new_draft([1,2],'door_S_R',None,'flash','flashbang')
    app.draft.landing=(38,26);app.tool=None;app.draw();pg.image.save(app.screen,str(root/'02-planning.png'))
    app.resize((1280,720));app.draw();pg.image.save(app.screen,str(root/'planning-1280.png'))
    app.resize((1440,900));app.clear_tools();saved=False
    def capture(w):
        nonlocal saved
        if not saved and w.shots and any(t.phase=='enter' and t.draft.room=='R' for t in w.planner.tasks.values()):
            saved=True;app.world=w;app.page='mission';app.scale=36
            app.offset=[app.viewport.centerx-35*36,app.viewport.centery-27*36]
            app.draw();pg.image.save(app.screen,str(root/'03-entry.png'))
    w,log=run('A',capture,variant=1);app.world=w;app.page='ending' if w.winner else 'mission';app.center_map();app.draw()
    pg.image.save(app.screen,str(root/'04-outcome.png'))
    (root/'playthrough-A.json').write_text(json.dumps({'A':log},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(log[-1],ensure_ascii=False),flush=True);pg.quit()


if __name__=='__main__':main()
