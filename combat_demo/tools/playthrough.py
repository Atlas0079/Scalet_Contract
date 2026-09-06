"""Repeatable planner-driven integration run, not a substitute for human play."""
from pathlib import Path
import json
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from simulation.mission import create_mission
from simulation.actor import Team


def run(config,on_step=None,variant=0):
    w=create_mission(config);log=[];attempts={};active=None;prepared=set();single_seen=set();single_wait=0
    for tick in range(60*900):
        order=[(i+variant)%4+1 for i in range(4)]
        alive=[i for i in order if w.actor(i).alive]
        if w.winner:break
        if w.paused:w.set_paused(False)
        for a in w.actors[:4]:
            if a.alive and a.queue and a.queue[0].status=='blocked':
                if a.under_fire_timer>w.time or a.stunned>0:continue
                log.append({'time':round(w.time,2),'cancel_personal':a.id,'reason':a.queue[0].reason})
                if a.queue[0].cell:single_seen.add(a.queue[0].cell)
                w.planner.delete_node(a,0)
        if len(alive)==1:
            a=w.actor(alive[0])
            for task in list(w.planner.tasks.values()):
                if task.draft.method not in {'open','kick'}:w.planner.cancel_task(task.id)
            if a.queue and a.queue[0].kind=='guard' and a.occupied_cell==a.queue[0].cell and not w.has_threat(a):
                single_wait+=1/60
                if single_wait>=1:
                    single_seen.add(a.queue[0].cell);w.planner.stop(alive);single_wait=0
            else:single_wait=0
            if not a.queue:
                choices=[]
                for room in w.mission.rooms:
                    for point in w.planner.observations(room):
                        if point in single_seen:continue
                        path=w.planner.path(a,point)
                        if path:choices.append((len(path),room,point))
                if choices:
                    _,room,point=min(choices)
                    w.planner.submit(alive,'guard',cell=point,angle=w.planner.room_angle(room,point))
                else:
                    doors=[]
                    for entrance in w.mission.entrances.values():
                        if w.perception.doors.get(entrance.id) in {'open','broken'}:continue
                        for room in (entrance.zone_a,entrance.zone_b):
                            d,e=w.planner.preview_task(alive,entrance.id,room,'kick')
                            if not e:doors.append((len(w.planner.path(a,d.outside)),entrance.id,d))
                    if doors:w.planner.submit_task(min(doors,key=lambda c:c[:2])[2])
                    else:break
            w.update(1/60)
            if on_step:on_step(w)
            continue
        if not w.planner.tasks:
            if any(a.queue for a in w.actors[:4] if a.alive):
                w.update(1/60)
                if on_step:on_step(w)
                continue
            marker=tuple(w.mission.room_checked)
            if ((config=='C' and variant==0) or variant>=5) and marker and marker not in prepared:
                prepared.add(marker)
                for i in alive:
                    a=w.actor(i)
                    if w.treatment_part(a) and a.inventory.available('bandage')>0:w.planner.submit([i],'bandage',item='bandage')
                    if a.weapon.ammo<30 and a.weapon.reserve_ammo>0:w.planner.submit([i],'reload',item='rifle',append=True)
                if any(a.queue for a in w.actors[:4] if a.alive):continue
            candidates=[]
            for room in w.mission.rooms:
                if room in w.mission.room_checked:continue
                for method in ('direct','breach'):
                    draft=w.planner.choose_entrance(alive,room=room,method=method)
                    if draft:
                        cost=sum(len(w.planner.path(w.actor(i),c)) for i,c in draft.stacks.items())
                        priority={'B':'ROAWMNUL','C':'LUNMWROA'}[config].index(room)*10000 if config!='A' and variant==0 else 0
                        candidates.append((priority+cost,room,method,draft));break
            if not candidates:log.append({'time':round(w.time,2),'error':'no reachable unchecked room','alive':alive});break
            _,room,method,draft=min(candidates,key=lambda c:c[:3])
            if room not in ({'R','L','U','M'} if config!='A' else {'R','L','U'}) and any(w.planner.available(w.actor(i),'flashbang',False)>0 for i in alive):
                ordered=list(alive)
                if config!='A' and variant==0:
                    thrower=next(i for i in alive if w.planner.available(w.actor(i),'flashbang',False)>0)
                    ordered=[thrower]+[i for i in alive if i!=thrower]
                flash,error=w.planner.preview_task(ordered,draft.door,room,'flash')
                if not error:
                    cells=sorted((c for c in w.grid.zones[room].cells if w.grid.walkable(c)),
                                 key=lambda c:(w.grid.cell_center(c).distance_to(w.grid.cell_center(w.grid.zones[room].center_cell)),c))
                    for cell in cells:
                        if config!='A' and variant==0 and any(w.grid.cell_center(cell).distance_to(w.grid.cell_center(c))<=4 for c in flash.stacks.values()):continue
                        if not w.planner.throw_error(w.actor(flash.thrower),'flashbang',cell,flash.stacks[flash.thrower],room,flash.door):
                            flash.landing=cell;draft=flash;method='flash';break
            result=w.planner.submit_task(draft);active=room
            row={'time':round(w.time,2),'room':room,'method':method,'error':result};log.append(row);print(config,row,flush=True)
        for task in list(w.planner.tasks.values()):
            if task.phase=='blocked':
                if any(w.actor(i).under_fire_timer>w.time or w.actor(i).stunned>0 for i in task.draft.actors):continue
                row={'time':round(w.time,2),'blocked':task.reason,'room':task.draft.room};log.append(row);print(config,row,flush=True)
                attempts[task.draft.room]=attempts.get(task.draft.room,0)+1
                if attempts[task.draft.room]>4:return w,log
                if '门已锁' in task.reason:
                    d,e=w.planner.preview_task(alive,task.draft.door,task.draft.room,'breach')
                    if e:log.append({'error':e});return w,log
                    w.planner.submit_task(d)
                else:
                    error=w.planner.retry_task(task.id)
                    if error:
                        log.append({'error':error})
                        if len([a for a in w.actors[:4] if a.alive])<2:continue
                        if '执行者已退出' in error:
                            ids=[a.id for a in w.actors[:4] if a.alive]
                            method='breach' if w.perception.doors.get(task.draft.door)=='locked' else 'direct'
                            replacement,rejected=w.planner.preview_task(ids,task.draft.door,task.draft.room,method)
                            if not rejected:w.planner.submit_task(replacement);continue
                        return w,log
        w.update(1/60)
        if on_step:on_step(w)
    log.append({'time':round(w.time,2),'winner':w.winner.value if w.winner else None,'alive':[a.id for a in w.actors[:4] if a.alive],
                'enemies':sum(a.alive for a in w.actors[4:]),'stats':w.stats})
    return w,log


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('configs',nargs='*',default=['A','B','C']);parser.add_argument('--variant',type=int,default=0)
    args=parser.parse_args()
    output={}
    for config in args.configs:
        w,log=run(config,variant=args.variant);output[config]=log;print(json.dumps(log[-1],ensure_ascii=False),flush=True)
        if config=='A' and w.winner==Team.RED:
            import os
            os.environ['SDL_VIDEODRIVER']='dummy';os.environ['SDL_AUDIODRIVER']='dummy'
            import pygame as pg
            from rendering.pygame_view import PygameView
            app=PygameView();app.world=w;app.page='ending';app.selected=[a.id for a in w.actors[:4] if a.alive];app.draw()
            pg.image.save(app.screen,str(Path(__file__).resolve().parents[1]/'artifacts'/'04-outcome.png'));pg.quit()
    path=Path(__file__).resolve().parents[1]/'artifacts'/('playthrough-'+''.join(output)+f'-v{args.variant}.json')
    path.parent.mkdir(exist_ok=True);path.write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding='utf-8')
