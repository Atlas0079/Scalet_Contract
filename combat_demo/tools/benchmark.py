"""Measure real elapsed Pygame frame intervals; preserve workload and samples."""
from pathlib import Path
import json
import os
import platform
import statistics
import sys
import time
os.environ['SDL_VIDEODRIVER']='dummy';os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView


def main():
    app=PygameView();app.start_mission();app.fx=2;app.hints=False;app.world.paused=False
    times=[];start=previous=time.perf_counter();next_order=0;rounds=0
    while time.perf_counter()-start<130:
        app.clock.tick(60)
        now=time.perf_counter();dt=now-previous;previous=now
        if now-start>=10:times.append(dt*1000)
        app.events(pg.event.get())
        if app.page=='ending':
            app.start_mission();app.world.paused=False;previous=time.perf_counter();continue
        if app.world.paused:app.world.paused=False
        if app.world.time>=next_order:
            # Broad outdoor movement keeps all four observers and plans active.
            target=(10,32) if rounds%2==0 else (39,32)
            app.world.planner.submit([a.id for a in app.world.actors[:4] if a.alive],'move',cell=target)
            next_order=app.world.time+18;rounds+=1
        app.update(dt);app.draw();pg.display.flip()
    ordered=sorted(times);p95=ordered[int(len(ordered)*.95)]
    result={'os':platform.platform(),'python':platform.python_version(),'pygame':pg.version.ver,'renderer':'SDL dummy, CPU rendering; display present latency excluded',
            'resolution':[1440,900],'effects':'standard','config':'A','speed':1,'warmup_seconds':10,
            'sample_seconds':sum(times)/1000,'frames':len(times),'mean_frame_ms':statistics.mean(times),'p95_frame_ms':p95,
            'discarded_simulation_seconds':app.world.discarded_time,'pass':statistics.mean(times)<=17 and p95<=20}
    path=Path(__file__).resolve().parents[1]/'artifacts'/'performance.json';path.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result),flush=True);pg.quit()


if __name__=='__main__':main()
