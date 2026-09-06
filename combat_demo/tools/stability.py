"""Offscreen desktop-rendering soak; wall-clock duration is recorded verbatim."""
import ctypes
from ctypes import wintypes
import gc
import json
import os
from pathlib import Path
import sys
import time
os.environ['SDL_VIDEODRIVER']='dummy';os.environ['SDL_AUDIODRIVER']='dummy'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pygame as pg
from rendering.pygame_view import PygameView


class Counters(ctypes.Structure):
    _fields_=[('cb',wintypes.DWORD),('PageFaultCount',wintypes.DWORD)]+[(name,ctypes.c_size_t) for name in
        ('PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage')]


def memory():
    c=Counters();c.cb=ctypes.sizeof(c)
    kernel=ctypes.WinDLL('kernel32');kernel.GetCurrentProcess.restype=wintypes.HANDLE
    psapi=ctypes.WinDLL('psapi');psapi.GetProcessMemoryInfo.argtypes=[wintypes.HANDLE,ctypes.POINTER(Counters),wintypes.DWORD]
    if not psapi.GetProcessMemoryInfo(kernel.GetCurrentProcess(),ctypes.byref(c),c.cb):raise ctypes.WinError()
    return c.WorkingSetSize/1048576


def main():
    duration=float(sys.argv[1]) if len(sys.argv)>1 else 1200
    app=PygameView();start=time.perf_counter();count=0
    while time.perf_counter()-start<duration:
        app.events(pg.event.get());app.update(1/60);app.draw();pg.display.flip();app.clock.tick(60);count+=1
    readings=[]
    for _ in range(6):
        app.start_mission();app.draw();gc.collect();readings.append(memory())
        assert len(app.world.actors)==14 and not app.world.planner.tasks and not app.world.shots
        app.back_title()
    result={'title_wall_seconds':time.perf_counter()-start,'frames':count,'renderer':'SDL dummy / real Pygame draws',
            'working_set_mib':readings,'growth_mib':readings[-1]-readings[0],'pass':readings[-1]-readings[0]<=10}
    path=Path(__file__).resolve().parents[1]/'artifacts'/'stability.json';path.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result),flush=True);pg.quit()


if __name__=='__main__':main()
