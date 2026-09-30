"""A compact tactical terminal. Widgets edit plans; simulation owns the world."""
from __future__ import annotations

from collections import OrderedDict
from copy import deepcopy
from math import atan2, cos, sin, pi, hypot
from pathlib import Path
import random
import sys
import pygame as pg

from simulation.actor import Team, FireMode
from simulation.geometry import Vec2
from simulation.items import ITEMS, use_for
from simulation.mission import create_mission, RECTS
from simulation.orders import LABELS, STAGES
from .widgets import ContextMenu, Entry, BG, LINE, ACCENT, TEXT, WARN, ENEMY, DIM, PANEL
from .loot_view import LootViewMixin
from .planning_view import PlanningViewMixin

ASSETS=Path(getattr(sys,"_MEIPASS",Path(__file__).resolve().parents[1]))/"assets"


class PygameView(PlanningViewMixin,LootViewMixin):
    def __init__(self,config="A",size=(1440,900)):
        pg.mixer.pre_init(22050,-16,1,512);pg.init()
        self.screen=pg.display.set_mode(size,pg.RESIZABLE)
        pg.display.set_caption("SCARLET CONTRACT 1.7.4 · 单方重叠减速")
        self.fonts={s:pg.font.Font(str(ASSETS/"NotoSansSC-Regular.ttf"),s) for s in (12,14,16,20,28,48)}
        self.text_cache=OrderedDict();self.clock=pg.time.Clock();self.running=True
        self.config=config;self.page="title";self.world=create_mission(config)
        self.selected=[1,2,3,4];self.groups=[[1,2],[3,4]];self.speed=1
        self.init_loot_ui()
        self.init_planning()
        self.menu=None;self.draft=None;self.draft_append=False;self.draft_error="";self.tool=None
        self.buttons=[];self.cards=[];self.room_labels=[];self.tooltip="";self.notice="";self.notice_until=0
        self.drag=None;self.move_drag=None;self.panning=False;self.last_number=(None,0);self.overlay=None;self.return_pause=True
        self.fx=1;self.fx_time=0;self.volume=.5;self.auto_contact=False;self.hints=True;self.hint_index=0
        self.queue_offset=0;self.help_scroll=0;self.mouse=(0,0);self.room_inspect=None
        self.sounds={}
        if pg.mixer.get_init():
            for path in ASSETS.glob("*.wav"):self.sounds[path.stem]=pg.mixer.Sound(str(path))
        self.resize(size);self.center_map()

    def resize(self,size):
        self.move_drag=None
        old_view=getattr(self,"viewport",None)
        fitted=old_view is not None and hasattr(self,"scale") and abs(self.scale-min(old_view.width/48,old_view.height/36))<.01
        width,height=max(1280,size[0]),max(720,size[1])
        if self.screen.get_size()!=(width,height):self.screen=pg.display.set_mode((width,height),pg.RESIZABLE)
        self.width,self.height=width,height
        self.viewport=pg.Rect(0,48,width-300,height-160)
        self.noise=[];rng=random.Random(31)
        for _ in range(8):
            surf=pg.Surface(self.viewport.size,pg.SRCALPHA)
            for _ in range(int(self.viewport.width*self.viewport.height*.002)):
                surf.set_at((rng.randrange(surf.get_width()),rng.randrange(surf.get_height())),(157,255,227,255))
            self.noise.append(surf)
        self.menu=None
        if fitted:self.center_map()
        elif old_view is not None and hasattr(self,"offset"):
            self.offset[0]+=self.viewport.centerx-old_view.centerx;self.offset[1]+=self.viewport.centery-old_view.centery

    def center_map(self):
        self.scale=min(self.viewport.width/48,self.viewport.height/36)
        self.offset=[self.viewport.centerx-24*self.scale,self.viewport.centery-18*self.scale]

    def pos(self,point):
        x,y=(point.x,point.y) if isinstance(point,Vec2) else point
        return round(self.offset[0]+x*self.scale),round(self.offset[1]+y*self.scale)

    def map_point(self,pos):return Vec2((pos[0]-self.offset[0])/self.scale,(pos[1]-self.offset[1])/self.scale)
    def cell(self,pos):return self.world.grid.cell_of(self.map_point(pos))
    def shift(self):return bool(pg.key.get_mods()&pg.KMOD_SHIFT)
    def append(self):return self.draft_append if self.draft is not None else self.shift()

    def text(self,value,x,y,color=TEXT,size=16,width=None):
        value=str(value);font=self.fonts[size]
        if width is not None and font.size(value)[0]>width:
            while value and font.size(value+"…")[0]>width:value=value[:-1]
            value+="…"
        key=(value,str(color),size)
        if key not in self.text_cache:
            self.text_cache[key]=font.render(value,True,color)
            if len(self.text_cache)>1500:self.text_cache.popitem(last=False)
        self.screen.blit(self.text_cache[key],(round(x),round(y)))

    def button(self,rect,label,action,enabled=True,reason="",accent=False):
        rect=pg.Rect(rect);hover=rect.collidepoint(self.mouse)
        pg.draw.rect(self.screen,LINE if hover and enabled else PANEL,rect)
        pg.draw.rect(self.screen,ACCENT if accent and enabled else LINE,rect,1)
        size=14 if rect.width<110 else 16
        if len(label)==1:self.text(label,rect.centerx-self.fonts[size].size(label)[0]//2,rect.centery-11,TEXT if enabled else DIM,size)
        else:self.text(label,rect.x+10,rect.centery-11,TEXT if enabled else DIM,size,width=rect.width-20)
        self.buttons.append((rect,action,enabled,reason))
        if hover:self.tooltip=reason or label

    def notify(self,error):
        if error:self.notice=str(error);self.notice_until=pg.time.get_ticks()+3500;self.play("reject")

    def play(self,name):
        if name in self.sounds:
            sound=self.sounds[name];sound.set_volume(self.volume);sound.play()

    def clear_tools(self,*,remember=True):
        if remember and self.draft and not self.quick_pending:self.remember_plan()
        self.menu=None;self.draft=None;self.tool=None;self.move_drag=None;self.draft_error="";self.room_inspect=None
        self.plan_markers=[];self.quick_pending=False
        self.action_focus=None;self.plan_settings=False;self.plan_settings_rect=None;self.plan_feedback='';self.drag=None

    def ctrl_room(self,pos):
        if not self.viewport.collidepoint(pos) or not pg.key.get_mods()&pg.KMOD_CTRL:return False
        room=self.world.grid.zone_id(self.cell(pos))
        if room is None:return False
        self.door_menu(room=room,anchor=pos)
        return True

    def cancel_tool(self):
        if self.quick_pending:self.clear_tools();return
        tool=self.tool;self.tool=None
        if tool and tool.get("kind")=="throw":self.personal_menu(tool["ids"][0],self.mouse)

    def open_context_at(self,pos):
        actor=next((i for rect,i in self.cards if rect.collidepoint(pos)),None)
        if actor is not None:self.personal_menu(actor,pos);return
        if not self.viewport.collidepoint(pos):return
        if self.ctrl_room(pos):return
        if self.loot_context(pos):return
        kind,target=self.hit_object(pos)
        if kind in {"ally","dead"}:self.personal_menu(target,pos)
        elif kind=="door":self.door_menu(door=target,anchor=pos)
        elif kind=="room":self.door_menu(room=target,anchor=pos)

    def select(self,ids,toggle=False):
        if self.draft:
            if ids:self.choose_plan_actor(ids[0])
            return
        self.clear_tools();self.queue_offset=0;self.room_inspect=None
        ids=[i for i in ids if self.world.actor(i) and self.world.actor(i).alive]
        self.selected=sorted(set(self.selected)^set(ids)) if toggle else list(ids)

    def submit(self,ids,kind,**kwargs):
        append=kwargs.pop("append",self.append())
        error=self.world.planner.submit(ids,kind,append=append,**kwargs)
        if error:self.notify(error)
        else:self.clear_tools()
        return error

    def batch_item(self,kind,item):
        ids=self.command_ids()
        if not ids:self.notify("先选择队员");return
        ready=[i for i in ids if not self.world.planner.item_error(self.world.actor(i),item,kind,self.shift())]
        if not ready:self.notify('没有需要且能够执行此动作的队员');return
        self.notify(self.world.planner.submit(ready,kind,item=item,append=self.shift()))
        self.menu=None

    def command_ids(self):
        if self.menu and getattr(self.menu,'actor_id',None):return [self.menu.actor_id]
        if self.tool:return list(self.tool.get('ids',self.selected))
        return list(self.selected)

    def start_tool(self,kind,**kwargs):
        if kind!='room' and not kwargs.get("ids",self.selected):self.notify("先选择队员");return
        self.clear_tools();self.tool={"kind":kind,"ids":list(self.selected),**kwargs}

    def use_item(self,i,item,action):
        use=use_for(item,action)
        if use.target=="ground":self.start_tool("throw",ids=[i],item=item)
        else:self.submit([i],action,item=item)

    def personal_menu(self,i,anchor):
        self.action_focus=None
        self.room_inspect=None
        actor=self.world.actor(i);entries=[]
        for definition in actor.inventory.definitions():
            item=definition.id
            quantity="" if item=="rifle" else f" · 可用 {actor.inventory.available(item)} / 已安排 {actor.inventory.reserved(item)}"
            children=[Entry(use.label,lambda i=i,item=item,use=use:self.use_item(i,item,use.id),
                        error=lambda i=i,item=item,use=use:self.world.planner.item_error(self.world.actor(i),item,use.id,self.shift())) for use in definition.uses]
            entries.append(Entry(definition.name+quantity,children=children,label_fn=lambda definition=definition,item=item:
                definition.name+("" if item=="rifle" else f" · 可用 {actor.inventory.available(item)} / 已安排 {actor.inventory.reserved(item)}")))
        entries.extend([Entry('伤势与携带详情',lambda:self.inspect_actor(i)),Entry('携带物品 / 放下 / 装备',lambda:self.inventory_menu(i)),Entry("调整朝向…",lambda:self.start_tool("face",ids=[i])),
            Entry("开火规则",children=[Entry("自动开火",lambda:self.set_fire([i],False)),Entry("禁止开火",lambda:self.set_fire([i],True))]),
            Entry("等待信号",children=[Entry("同步 A",lambda:self.submit([i],"wait",sync="A")),Entry("同步 B",lambda:self.submit([i],"wait",sync="B"))]),
            Entry("取消此人计划",lambda:self.stop([i]))])
        subtitle=lambda:("已阵亡 · 装备只读" if not actor.alive else self.world.planner.takeover_text([i]) or ("追加微操队列" if self.shift() else "替换微操 · 保留原选择"))
        for entry in entries:
            for leaf in entry.children or [entry]:
                previous_error=leaf.error
                leaf.error=lambda previous_error=previous_error:("执行者死亡" if not actor.alive else previous_error() if callable(previous_error) else previous_error)
        self.menu=ContextMenu(f"{i} {actor.name} · 个人指令",subtitle,entries,anchor,(self.width,self.height))
        self.menu.actor_id=i
        self.draft=None;self.tool=None

    def set_fire(self,ids,hold):
        for i in ids:self.world.actor(i).fire_mode=FireMode.HOLD_FIRE if hold else FireMode.AIMED_SHOT
        self.menu=None

    def stop(self,ids=None):
        self.world.planner.stop(ids if ids is not None else self.selected);self.clear_tools()

    def flash_menu(self):
        ids=self.command_ids()
        if len(ids)==1:self.use_item(ids[0],"flashbang","throw");return
        entries=[Entry(f"{i} {self.world.actor(i).name} · 使用闪光弹",lambda i=i:self.use_item(i,"flashbang","throw"),
            error=lambda i=i:self.world.planner.item_error(self.world.actor(i),"flashbang","throw",self.shift())) for i in ids]
        if not entries:self.notify("先选择队员");return
        self.menu=ContextMenu("选择投掷者","仅向所选执行者下令",entries,self.mouse,(self.width,self.height))

    def door_menu(self,door=None,room=None,anchor=None):
        ids=list(self.selected);planner=self.world.planner
        def reason(method,item=None):
            if not ids:return "先选择队员"
            d=planner.choose_entrance(ids,door,room,method,self.shift(),item)
            return None if d else planner.entrance_error
        def leaf(label,method,item=None):
            return Entry(label,lambda:self.action_focus.update(choice=(ids,door,room,method,item)),error=lambda:reason(method,item))
        breach=[leaf("直接突入","direct"),leaf("破门突入","breach")]
        for definition in sorted(ITEMS.values(),key=lambda v:v.order):
            if any(u.breach for u in definition.uses) and any(definition.id in self.world.actor(i).inventory.quantities for i in ids):
                count=sum(planner.available(self.world.actor(i),definition.id,self.shift()) for i in ids)
                breach.append(leaf(f"使用{definition.name}突入 · 可用 {count}","flash",definition.id))
        entries=[leaf("门外集结","stack"),Entry("操作门",children=[leaf("开门","open"),leaf("踹开","kick")]),
                 Entry("突入",children=breach),leaf("守住门口","guarddoor")]
        if room:
            entries=[Entry("突入",children=breach),Entry("在房间内警戒…",lambda:self.start_tool("guard",ids=ids,room=room),error=None if ids else '先选择队员'),
                     self.loot_task_entries(room)]
        title=self.world.grid.zones[room].label if room else '门口行动 · '+door.replace("door_","").replace("_"," ↔ ")
        self.clear_tools()
        self.room_inspect=room
        self.action_focus={'title':title,'room':room,'entries':entries,'path':[],'choice':None,'keyboard':None}

    def inspect_room(self,room):self.door_menu(room=room)

    def method_menu(self):
        entries=[Entry("直接突入",lambda:self.change_method("direct")),Entry("破门突入",lambda:self.change_method("breach"))]
        for definition in sorted(ITEMS.values(),key=lambda value:value.order):
            if any(use.breach for use in definition.uses):entries.append(Entry(f"使用{definition.name}突入",lambda item=definition.id:self.change_method("flash",item)))
        self.menu=ContextMenu("突入方式","修改草稿 · 尚未提交",entries,(self.width-310,112),(self.width,self.height))

    def change_method(self,method,item=None):
        if not self.edit_draft(method=method,item=item,thrower=None,landing=None,opening=None):return
        self.menu=None;self.plan_settings=False;self.set_plan_stage('flash' if self.draft.item else 'stack')

    def new_draft(self,ids,door,room,method,item=None,*,quick=False):
        draft=self.world.planner.choose_entrance(ids,door,room,method,self.shift(),item)
        if not draft:self.notify(self.world.planner.entrance_error);return
        self.clear_tools()
        if item:draft.item=item
        self.draft=draft;self.draft_append=False;self.draft_error=""
        self.quick_pending=quick;self.plan_markers=[]
        draft.after_entry=self.plan_after
        self.draft_append=self.shift()
        self.plan_history=[];self.plan_actor=draft.actors[0];self.plan_stage='flash' if draft.item else 'stack'
        self.plan_candidate=None
        self.plan_camera=(self.scale,list(self.offset))
        if not quick:self.world.set_paused(True);self.focus_plan()
        if draft.item:
            self.tool={"kind":"landing","ids":draft.actors}
        elif quick:self.commit_draft()

    def edit_draft(self,**changes):
        fresh,error=self.preview_draft(**changes)
        if error:
            self.plan_feedback='修改未生效，保留原设置：'+error;self.notify(self.plan_feedback);return False
        if fresh!=self.draft:self.plan_history.append((deepcopy(self.draft),self.draft_append))
        self.draft=fresh;self.draft_error='';self.plan_feedback='';return True

    def commit_draft(self):
        error=self.world.planner.submit_task(self.draft,self.append())
        if error:
            if self.quick_pending and not self.draft.item:self.clear_tools()
            elif self.quick_pending:self.tool={'kind':'landing','ids':self.draft.actors}
            self.draft_error=error;self.notify(error)
        else:
            staged=not self.quick_pending
            self.clear_tools(remember=False)
            if staged:
                self.saved_plan=None;self.world.set_paused(True);self.world.message('计划已下达 · 按空格执行')

    def start_mission(self):
        self.world=create_mission(self.config);self.world.auto_contact=self.auto_contact
        self.selected=[1,2,3,4];self.groups=[[1,2],[3,4]];self.clear_tools(remember=False);self.overlay=None
        self.speed=1;self.page="mission";self.hint_index=0;self.fx_time=0;self.center_map()
        self.init_loot_ui()
        self.init_planning()

    def show_overlay(self,page):
        self.overlay_context=(self.menu,self.draft,self.tool,self.room_inspect,self.quick_pending,self.action_focus,self.plan_settings,self.plan_feedback) if not self.loot_panel else (None,None,None,None,False,None,False,'')
        self.return_pause=self.world.paused;self.world.set_paused(True);self.overlay=page;self.clear_tools(remember=False)
        self.drag=None;self.panning=False

    def close_overlay(self):
        self.overlay=None
        self.menu,self.draft,self.tool,self.room_inspect,self.quick_pending,self.action_focus,self.plan_settings,self.plan_feedback=self.overlay_context
        if self.page=="mission":self.world.set_paused(self.return_pause)

    def hit_object(self,pos):
        world=self.world
        def nearby(actors):
            found=[a for a in actors if hypot(self.pos(a.position)[0]-pos[0],self.pos(a.position)[1]-pos[1])<=max(6,self.world_px(a.radius))]
            return min(found,key=lambda a:(hypot(self.pos(a.position)[0]-pos[0],self.pos(a.position)[1]-pos[1]),a.id)) if found else None
        ally=nearby(a for a in world.actors if a.team==Team.RED and a.alive)
        if ally:return "ally",ally.id
        enemy=nearby(a for a in world.actors if a.team==Team.BLUE and a.alive and a.id in world.perception.player_visible)
        if enemy:return "enemy",enemy.id
        for id_,entrance in world.mission.entrances.items():
            center=self.pos(entrance.center(world.grid))
            horizontal=entrance.a[0]==entrance.b[0]
            tolerance=max(4,self.world_px(.2))
            rect=pg.Rect(center[0]-self.scale/2 if horizontal else center[0]-tolerance,center[1]-tolerance if horizontal else center[1]-self.scale/2,
                         self.scale if horizontal else 2*tolerance,2*tolerance if horizontal else self.scale)
            if rect.collidepoint(pos):return "door",id_
        dead=nearby(a for a in world.actors if a.team==Team.RED and not a.alive)
        if dead:return "dead",dead.id
        return "ground",self.cell(pos)

    def target_error(self,cell):
        tool=self.tool;planner=self.world.planner
        if tool["kind"]=="throw":return planner.item_error(self.world.actor(tool["ids"][0]),tool["item"],"throw",self.append(),cell)
        if tool["kind"]=="landing":
            d=self.draft
            return planner.throw_error(self.world.actor(d.thrower),d.item,cell,d.stacks[d.thrower],d.room,d.door)
        if tool["kind"]=="guard" and "cell" not in tool:
            if tool.get('room') and self.world.grid.zone_id(cell)!=tool['room']:return '警戒位置必须在所选房间内'
            if tool.get('room'):
                targets,error=planner.movement_targets(tool['ids'],cell,self.append())
                if error:return error
                if any(self.world.grid.zone_id(c)!=tool['room'] for c in targets.values()):return '房间内没有足够的警戒站位，请重新选点'
            return None if self.world.grid.walkable(cell) else "目标不可通行"
        return None

    def tool_click(self,pos):
        tool=self.tool;kind=tool["kind"];cell=self.cell(pos);point=self.map_point(pos)
        if kind=='room':
            room=self.world.grid.zone_id(cell)
            if room is None:self.notify('点击一个房间或区域');return
            self.door_menu(room=room);return
        if kind in {"throw","landing"}:
            error=self.target_error(cell)
            if error:self.notify(error);return
            if kind=="landing":
                if not self.edit_draft(landing=cell):return
                self.tool=None
                if self.quick_pending:self.commit_draft()
            else:self.submit(tool["ids"],"throw",item=tool["item"],cell=cell)
        elif kind=="guard" and "cell" not in tool:
            error=self.target_error(cell)
            if error:self.notify(error)
            else:tool["cell"]=cell
        elif kind in {"face","guard"}:
            origin=self.world.grid.cell_center(tool["cell"]) if "cell" in tool else self.world.actor(tool["ids"][0]).position
            if origin.distance_to(point)<.25:self.notify("请指定方向");return
            self.submit(tool["ids"],kind,cell=tool.get("cell"),angle=atan2(point.y-origin.y,point.x-origin.x))

    def events(self,events):
        for event in events:
            if event.type==pg.QUIT:self.running=False
            elif event.type==pg.VIDEORESIZE:self.resize(event.size)
            elif event.type==pg.KEYDOWN:self.key(event)
            elif event.type==pg.MOUSEBUTTONDOWN:
                self.mouse=event.pos
                if self.overlay:
                    if event.button==1:
                        for rect,action,enabled,reason in reversed(self.buttons):
                            if rect.collidepoint(event.pos):
                                if enabled:action()
                                else:self.notify(reason)
                                break
                    continue
                if self.loot_panel:
                    self.loot_click(event)
                    continue
                if event.button==3 and self.page=='mission' and not self.draft and self.ctrl_room(event.pos):continue
                if event.button==2 and self.viewport.collidepoint(event.pos) and self.page=="mission" and not self.move_drag:self.panning=True;continue
                if self.menu and event.button==1 and (event.pos[1]<48 or event.pos[0]>=self.viewport.right and self.menu.hit(event.pos) is None):
                    for rect,action,enabled,reason in reversed(self.buttons):
                        if rect.collidepoint(event.pos) and enabled:
                            action();break
                    continue
                if self.menu:
                    if event.button==1:
                        hit=self.menu.hit(event.pos)
                        if hit:self.notify(self.menu.activate(hit));continue
                        self.menu=None
                        actor_hit=next((i for rect,i in self.cards if rect.collidepoint(event.pos)),None)
                        if actor_hit is not None:self.select([actor_hit],self.shift())
                        elif self.viewport.collidepoint(event.pos):
                            kind,target=self.hit_object(event.pos)
                            if kind=="ally":self.select([target],self.shift())
                        continue
                    elif event.button==3:
                        self.menu=None
                        if not self.draft:self.open_context_at(event.pos)
                        continue
                clicked=False
                if event.button==1:
                    for rect,action,enabled,reason in reversed(self.buttons):
                        if rect.collidepoint(event.pos):
                            if enabled:action();self.play("confirm")
                            else:self.notify(reason)
                            clicked=True;break
                if clicked or self.page!="mission" or self.overlay:continue
                for rect,i in self.cards:
                    if rect.collidepoint(event.pos):
                        if self.draft:self.choose_plan_actor(i)
                        elif event.button==3:self.personal_menu(i,event.pos)
                        elif event.button==1:self.select([i],self.shift())
                        clicked=True;break
                if clicked or not self.viewport.collidepoint(event.pos):continue
                if self.plan_map_down(event):continue
                if self.tool:
                    if event.button==1:self.tool_click(event.pos)
                    elif event.button==3:self.cancel_tool()
                    continue
                if self.draft:continue
                if event.button==3 and self.loot_context(event.pos):continue
                kind,target=self.hit_object(event.pos)
                if event.button==1:
                    if kind=="ally":self.select([target],self.shift())
                    else:self.drag=(event.pos,self.shift())
                elif event.button==3:
                    if kind in {"ally","dead"}:self.personal_menu(target,event.pos)
                    elif kind=="door":self.door_menu(door=target,anchor=event.pos)
                    elif kind=="room":self.door_menu(room=target,anchor=event.pos)
                    elif kind=="enemy":
                        ids=list(self.selected)
                        self.menu=ContextMenu("攻击目标",f"执行者：{ids}",[Entry("攻击此目标",lambda ids=ids,target=target:self.submit(ids,"attack",target_id=target),
                            error=lambda target=target:None if target in self.world.perception.player_visible else "目标失去视野")],event.pos,(self.width,self.height))
                    elif kind=="ground":self.move_drag={"start":event.pos,"cell":target,"ids":list(self.selected),"append":self.shift()}
            elif event.type==pg.MOUSEBUTTONUP:
                self.mouse=event.pos
                if event.button==3 and self.move_drag:
                    drag=self.move_drag;self.move_drag=None
                    if self.page=="mission" and not self.overlay and self.viewport.collidepoint(event.pos):
                        dx,dy=event.pos[0]-drag["start"][0],event.pos[1]-drag["start"][1]
                        angle=atan2(dy,dx) if hypot(dx,dy)/self.scale>=.5 else None
                        if 'plan_stage' in drag:
                            self.move_plan_actor(drag['plan_stage'],drag['ids'][0],drag['cell'],angle)
                        else:self.submit(drag["ids"],"move",cell=drag["cell"],angle=angle,append=drag["append"])
                    continue
                if event.button==2:self.panning=False
                if event.button==1 and self.drag:
                    start,toggle=self.drag;self.drag=None
                    if hypot(event.pos[0]-start[0],event.pos[1]-start[1])>4:
                        rect=pg.Rect(start,(event.pos[0]-start[0],event.pos[1]-start[1]));rect.normalize()
                        self.select([a.id for a in self.world.actors if a.team==Team.RED and a.alive and rect.collidepoint(self.pos(a.position))],toggle)
                    elif not toggle:self.select([])
            elif event.type==pg.MOUSEMOTION:
                self.mouse=event.pos
                if self.panning and not self.move_drag:self.offset[0]+=event.rel[0];self.offset[1]+=event.rel[1]
            elif event.type==pg.MOUSEWHEEL:
                if self.overlay:
                    if self.overlay=='actor':self.detail_scroll=max(0,self.detail_scroll-event.y)
                    elif self.overlay=='help':self.help_scroll=max(0,self.help_scroll-event.y)
                    continue
                if self.loot_panel:
                    self.loot_last_click=None
                    if self.menu:self.menu.wheel(event.y,self.mouse)
                    elif self.loot_rect.collidepoint(self.mouse):self.loot_scroll=max(0,self.loot_scroll-event.y)
                    continue
                if self.move_drag:continue
                if self.menu:self.menu.wheel(event.y,self.mouse)
                elif self.overlay=="help":self.help_scroll=max(0,self.help_scroll-event.y)
                elif self.page=="mission" and not self.overlay:
                    if self.viewport.collidepoint(self.mouse):
                        anchor=self.map_point(self.mouse);self.scale=max(12,min(64,self.scale*1.1**event.y))
                        self.offset=[self.mouse[0]-anchor.x*self.scale,self.mouse[1]-anchor.y*self.scale]
                    elif not self.draft:self.queue_offset=max(0,self.queue_offset-event.y)

    def key(self,event):
        key=event.key;mods=event.mod
        if key==pg.K_F12:
            path=Path.cwd()/"screenshot.png";pg.image.save(self.screen,str(path));self.notify("已保存 screenshot.png");return
        if self.overlay:
            if key==pg.K_ESCAPE:self.close_overlay()
            return
        if self.loot_panel:
            if key==pg.K_ESCAPE:
                if self.menu:self.menu=None
                else:self.close_loot()
            elif self.menu and key in (pg.K_UP,pg.K_DOWN,pg.K_RETURN):self.notify(self.menu.key(key))
            elif key==pg.K_SPACE:self.notify('关闭容器窗口后，再恢复时间')
            return
        if key==pg.K_ESCAPE:
            if self.move_drag:self.move_drag=None
            elif self.tool:self.cancel_tool()
            elif self.menu:
                if self.menu.branch is not None:self.menu.branch=None
                else:self.menu=None
            elif self.plan_settings:self.plan_settings=False
            elif self.draft:self.leave_plan()
            elif self.action_focus:self.action_back()
            elif self.room_inspect:self.room_inspect=None
            elif self.overlay:self.close_overlay()
            elif self.page=="mission":self.show_overlay("pause")
            elif self.page=="brief":self.page="title"
            return
        if self.overlay or self.page!="mission":return
        if key==pg.K_SPACE:self.toggle_time();return
        if key==pg.K_TAB:self.speed=.5 if self.speed==1 else 1;return
        if self.menu and key in (pg.K_UP,pg.K_DOWN,pg.K_LEFT,pg.K_RIGHT,pg.K_RETURN):self.notify(self.menu.key(key));return
        if self.action_focus and key in (pg.K_UP,pg.K_DOWN,pg.K_LEFT,pg.K_RIGHT,pg.K_RETURN):self.action_key(key);return
        if self.draft:
            if key in (pg.K_1,pg.K_2,pg.K_3,pg.K_4):self.choose_plan_actor(key-pg.K_1+1)
            elif key==pg.K_z and mods&pg.KMOD_CTRL:self.undo_plan()
            elif key in (pg.K_q,pg.K_r,pg.K_h,pg.K_g,pg.K_x,pg.K_i,pg.K_l):self.notify('正在编排；先退出编排再下达个人指令')
            return
        if key in (pg.K_1,pg.K_2,pg.K_3,pg.K_4):
            i=key-pg.K_1+1;now=pg.time.get_ticks();a=self.world.actor(i)
            if self.last_number[0]==i and now-self.last_number[1]<=300 or not a.alive:
                self.offset=[self.viewport.centerx-a.position.x*self.scale,self.viewport.centery-a.position.y*self.scale]
            self.last_number=(i,now);self.select([i],bool(mods&pg.KMOD_SHIFT))
        elif key==pg.K_a and mods&pg.KMOD_CTRL:self.select([1,2,3,4])
        elif key in (pg.K_F1,pg.K_F2):
            index=key-pg.K_F1
            if mods&pg.KMOD_CTRL:self.groups[index]=list(self.selected)
            else:self.select(self.groups[index])
        elif key==pg.K_q:self.start_tool("guard",ids=self.command_ids())
        elif key==pg.K_r:self.batch_item("reload","rifle")
        elif key==pg.K_h:self.batch_item("bandage","bandage")
        elif key==pg.K_g:self.flash_menu()
        elif key==pg.K_x:self.stop(self.command_ids())
        elif key==pg.K_i:self.inventory_menu()
        elif key==pg.K_l:self.show_loot()

    def update(self,dt):
        if self.page=="mission" and not self.overlay and not self.loot_panel:
            keys=pg.key.get_pressed()
            if not self.move_drag and not pg.key.get_mods()&pg.KMOD_CTRL:
                self.offset[0]+=(keys[pg.K_a]-keys[pg.K_d])*600*dt
                self.offset[1]+=(keys[pg.K_w]-keys[pg.K_s])*600*dt
            self.offset[0]=max(self.viewport.left-47*self.scale,min(self.viewport.right-self.scale,self.offset[0]))
            self.offset[1]=max(self.viewport.top-35*self.scale,min(self.viewport.bottom-self.scale,self.offset[1]))
            if not self.world.paused:self.fx_time+=dt*self.speed
            self.world.update(dt*self.speed)
            self.selected=[i for i in self.selected if self.world.actor(i).alive]
            for name in self.world.audio_events:self.play(name)
            self.world.audio_events.clear()
            if self.world.winner is not None:self.clear_tools();self.page="ending"
            elif self.world.loot.notifications and not self.draft:
                ids=list(self.world.loot.notifications);self.world.loot.notifications.clear()
                self.show_loot(next((id_ for id_ in ids if id_ in self.world.loot.results),None))
        if self.menu:self.menu.update(self.mouse,pg.time.get_ticks())

    def line(self,a,b,color=LINE,width=1):pg.draw.line(self.screen,color,self.pos(a),self.pos(b),width)

    def bracket(self,point,r,color=ACCENT):
        x,y=self.pos(point);r=round(r);n=max(1,min(r,round(r*.4)))
        for sx in (-1,1):
            for sy in (-1,1):
                pg.draw.lines(self.screen,color,False,[(x+sx*(r-n),y+sy*r),(x+sx*r,y+sy*r),(x+sx*r,y+sy*(r-n))],2)

    def draw_map(self,blueprint=False):
        world=self.world;grid=world.grid;old=self.screen.get_clip();self.screen.set_clip(self.viewport)
        pg.draw.rect(self.screen,BG,self.viewport)
        for name,zone in grid.zones.items():
            x1,y1,x2,y2=RECTS[name];p=self.pos((x1,y1));q=self.pos((x2+1,y2+1))
            pg.draw.rect(self.screen,"#0A1719",(p[0],p[1],q[0]-p[0],q[1]-p[1]))
        if not blueprint:
            for cell in world.perception.visible_cells:
                if cell in grid.zone_cells:
                    p=self.pos(cell);pg.draw.rect(self.screen,"#102B2B",(p[0],p[1],self.scale+1,self.scale+1))
        for x in range(49):self.line((x,0),(x,36),"#102425")
        for y in range(37):self.line((0,y),(48,y),"#102425")
        seen=set()
        for feature in grid.edge_features.values():
            if feature.id in seen:continue
            seen.add(feature.id);placement=feature.placement
            x,y=placement.cell;direction=placement.direction
            ends={"N":((x,y),(x+1,y)),"S":((x,y+1),(x+1,y+1)),"E":((x+1,y),(x+1,y+1)),"W":((x,y),(x,y+1))}[direction]
            if feature.interactive_id:
                state=world.perception.doors.get(feature.interactive_id,"unknown")
                color=WARN if state in {"locked","unknown"} else ACCENT
                if state in {"open","broken"}:
                    a,b=ends;mid=((a[0]+b[0])/2,(a[1]+b[1])/2)
                    for p in ends:self.line(p,(p[0]+(mid[0]-p[0])*.35,p[1]+(mid[1]-p[1])*.35),color,2)
                else:self.line(*ends,color,3)
                if state=="unknown":self.text("?",*self.pos(((ends[0][0]+ends[1][0])/2+.2,(ends[0][1]+ends[1][1])/2-.5)),WARN,12)
            elif feature.kind=="window":self.line(*ends,ACCENT,1)
            else:self.line(*ends,LINE,2)
        for cell,feature in grid.cell_features.items():
            if cell not in grid.zone_cells:continue
            p=self.pos(cell);size=round(self.scale)
            inset=self.world_px(.12)
            pg.draw.rect(self.screen,LINE,(p[0]+inset,p[1]+inset,size-2*inset,size-2*inset),1)
            if feature.height>=2:self.line((cell[0]+.12,cell[1]+.12),(cell[0]+.88,cell[1]+.88),LINE)
        self.line((13,26.25),(22,26.25));self.line((13,28.75),(22,28.75))
        if not blueprint:
            for i in ([self.plan_actor] if self.draft and not self.quick_pending else self.selected):
                a=world.actor(i)
                if not a.alive:continue
                # Boundary rays stop at the same walls used by perception.
                for angle in (a.facing-a.view_angle/2,a.facing+a.view_angle/2):
                    end=a.position+Vec2(cos(angle),sin(angle))*a.view_distance
                    t,_=grid.raycast(a.position,end)
                    self.line(a.position,a.position+(end-a.position)*t,LINE)
            for a in world.actors:
                if not a.alive and f'corpse:{a.id}' in world.loot.objects:continue
                if a.team==Team.BLUE and a.id not in world.perception.player_visible:
                    if a.id in world.perception.player_raw:
                        x,y=self.pos(a.position);r=self.world_px(a.radius)
                        for start in range(0,round(2*pi*r),8):pg.draw.arc(self.screen,DIM,(x-r,y-r,2*r,2*r),start/r,(start+4)/r,1)
                        self.text("?",x+r+3,y-8,DIM,12)
                    continue
                x,y=self.pos(a.position);r=self.world_px(a.radius);color=TEXT if a.hit_flash>0 else ACCENT if a.team==Team.RED else ENEMY
                if not a.alive:
                    pg.draw.line(self.screen,DIM,(x-r,y-r),(x+r,y+r),2);pg.draw.line(self.screen,DIM,(x-r,y+r),(x+r,y-r),2)
                    continue
                if self.fx:
                    glow=pg.Surface((2*r+12,2*r+12),pg.SRCALPHA)
                    pg.draw.circle(glow,(*pg.Color(color)[:3],31 if self.fx==1 else 51),(r+6,r+6),r+2,2)
                    self.screen.blit(glow,(x-r-6,y-r-6))
                if a.team==Team.RED:pg.draw.circle(self.screen,color,(x,y),r,2)
                else:pg.draw.polygon(self.screen,color,[(x,y-r),(x+r,y),(x,y+r),(x-r,y)],2)
                pg.draw.line(self.screen,color,(x+cos(a.facing)*r,y+sin(a.facing)*r),(x+cos(a.facing)*(r+self.world_px(.4)),y+sin(a.facing)*(r+self.world_px(.4))),2)
                if a.stunned>0:pg.draw.circle(self.screen,WARN,(x,y),r+self.world_px(.18),1)
            for shot in world.shots:
                if shot.team==Team.RED.value or shot.shooter_id in world.perception.player_visible:
                    color=ACCENT if shot.team=="red" else ENEMY
                    self.line(shot.start,shot.end,color,1)
                    angle=atan2(shot.end.y-shot.start.y,shot.end.x-shot.start.x)
                    if shot.timer>.04:
                        x,y=self.pos(shot.start);pg.draw.line(self.screen,color,(x,y),(x+cos(angle)*6,y+sin(angle)*6),2)
                    if shot.blocked and shot.timer>.01:
                        x,y=self.pos(shot.end)
                        for offset in (-pi/6,0,pi/6):pg.draw.line(self.screen,color,(x,y),(x-cos(angle+offset)*5,y-sin(angle+offset)*5),1)
            for explosion in world.explosions:
                if grid.cell_of(explosion.position) in world.perception.visible_cells:
                    pg.draw.circle(self.screen,WARN,self.pos(explosion.position),round(explosion.radius*self.scale*(1-explosion.timer/explosion.duration)),2)
            for projectile in world.projectiles:
                progress=min(1,(world.time-projectile["release"])/.4)
                p=projectile["start"]+(projectile["end"]-projectile["start"])*progress
                pg.draw.circle(self.screen,WARN,self.pos(p),4,1)
        self.draw_fx()
        if not blueprint:self.draw_loot_objects()
        if not blueprint:self.draw_plans()
        self.room_labels=[]
        hovered_room=grid.zone_id(self.cell(self.mouse)) if self.viewport.collidepoint(self.mouse) and pg.key.get_mods()&pg.KMOD_CTRL and not blueprint else None
        for name,zone in grid.zones.items():
            x1,y1,x2,y2=RECTS[name];x,y=self.pos((x1+.35,y1+.25))
            label=f"{name} / {zone.label}";width=self.fonts[14].size(label)[0]+12
            rect=pg.Rect(x,y,width,24);self.room_labels.append((rect,name))
            if name==hovered_room:
                p=self.pos((x1,y1));q=self.pos((x2+1,y2+1))
                pg.draw.rect(self.screen,ACCENT,pg.Rect(p,(q[0]-p[0],q[1]-p[1])),2)
                self.tooltip=f'Ctrl＋右键：{zone.label} · 房间操作'
            if blueprint or name==hovered_room or not rect.inflate(16,32).collidepoint(self.mouse):
                self.text(label,x+5,y+2,ACCENT if name==hovered_room else DIM,14)
                if name in world.mission.room_checked:self.text("已检查威胁 · 保持警戒",x+5,y+25,ACCENT,12)
        if not blueprint:
            for a in world.actors:
                if a.team==Team.RED and a.alive:
                    x,y=self.pos(a.position);self.text(a.id,x-4,y-8,ACCENT,12)
                    if (a.id==self.plan_actor if self.draft else a.id in self.selected):self.bracket(a.position,self.world_px(a.radius+.18))
                    if a.current_action:
                        action=a.current_action;progress=min(1,action.timer/action.duration)
                        pg.draw.rect(self.screen,LINE,(x-20,y-29,40,4))
                        pg.draw.rect(self.screen,ACCENT,(x-20,y-29,round(40*progress),4))
                        names={"reload":"换弹","bandage":"包扎","open_door":"开门","kick_door":"踹门","throw_grenade":"投掷",
                               'search_loot':'搜索物品','transfer_item':'拿取','drop_item':'放下','equip_item':'装备'}
                        self.text(names.get(action.type.value,"动作"),x+25,y-35,DIM,12)
            if self.menu and getattr(self.menu,"actor_id",None):
                self.bracket(world.actor(self.menu.actor_id).position,self.world_px(.55),WARN)
            for id_,(point,time) in world.perception.last_seen.items():
                if id_ in world.perception.player_visible:continue
                x,y=self.pos(point);marker=pg.Surface((20,20),pg.SRCALPHA);points=[(10,2),(18,10),(10,18),(2,10),(10,2)]
                for a,b in zip(points,points[1:]):
                    length=hypot(b[0]-a[0],b[1]-a[1])
                    for start in range(0,round(length),8):
                        end=min(start+4,length)
                        pg.draw.line(marker,DIM,(a[0]+(b[0]-a[0])*start/length,a[1]+(b[1]-a[1])*start/length),
                                     (a[0]+(b[0]-a[0])*end/length,a[1]+(b[1]-a[1])*end/length),1)
                marker.set_alpha(round(153*max(0,1-(world.time-time)/5)));self.screen.blit(marker,(x-10,y-10))
            for sound in world.sounds:
                if sound.audible and sound.team==Team.BLUE.value and sound.area and grid.cell_of(sound.position) not in world.perception.visible_cells:
                    x,y=self.pos(sound.area);pg.draw.rect(self.screen,WARN,(x,y,3*self.scale,3*self.scale),1)
                    self.text("声源",x+4,y+3,WARN,12)
            if self.drag:
                start,_=self.drag;rect=pg.Rect(start,(self.mouse[0]-start[0],self.mouse[1]-start[1]));rect.normalize();pg.draw.rect(self.screen,ACCENT,rect,1)
        self.screen.set_clip(old)

    def draw_fx(self):
        if not self.fx:return
        surface=pg.Surface(self.viewport.size,pg.SRCALPHA)
        for y in range(0,self.viewport.height,4):pg.draw.line(surface,(0,0,0,13 if self.fx==1 else 20),(0,y),(surface.get_width(),y))
        y=round((self.fx_time%8)/8*(surface.get_height()+24))-24
        pg.draw.rect(surface,(157,255,227,8 if self.fx==1 else 15),(0,y,surface.get_width(),24))
        edge=26 if self.fx==1 else 46
        for i in range(32):pg.draw.rect(surface,(0,0,0,round(edge*(1-i/32))),surface.get_rect().inflate(-2*i,-2*i),1)
        self.screen.blit(surface,self.viewport.topleft)
        noise=self.noise[int(self.fx_time/.1)%8];noise.set_alpha(10 if self.fx==1 else 18)
        self.screen.blit(noise,self.viewport.topleft)

    def route(self,actor,cell,color=ACCENT,start=None,mark=True):
        points=self.world.planner.path(actor,cell,start=start)
        if len(points)>1:pg.draw.lines(self.screen,color,False,[self.pos(self.world.grid.cell_center(c)) for c in points],1)
        if mark:self.bracket(self.world.grid.cell_center(cell),self.world_px(.3),color)

    def draw_plans(self):
        world=self.world
        self.plan_markers=[]
        for i in ([] if self.draft else self.selected):
            a=world.actor(i);start=world.planner.position_cell(a)
            for index,n in enumerate(a.queue):
                if n.cell is not None and n.kind in {"move","guard","move_face"}:
                    self.route(a,n.cell,ACCENT,start);start=n.cell
                    x,y=self.pos(world.grid.cell_center(n.cell));self.text(index+1,x+9,y-9,ACCENT,12)
                    if n.angle is not None:self.direction_arrow(world.grid.cell_center(n.cell),n.angle,ACCENT)
        drafts=[(self.draft,None)] if self.draft else [(t.draft,t) for t in world.planner.tasks.values() if any(i in self.selected for i in t.draft.actors)]
        for d,task in drafts:
            if d.method=='loot':continue
            goals=d.stacks if task is None or task.phase not in {"enter","search"} else d.entries if task.phase=="enter" else {i:points[0] for i,points in task.searches.items() if points}
            for i,cell in goals.items():
                if self.draft or i not in d.actors:continue
                if world.actor(i).position.distance_to(world.grid.cell_center(cell))<.4:continue
                self.route(world.actor(i),cell,WARN if self.draft else ACCENT,mark=not bool(self.draft))
            for i,cell in d.entries.items():
                if i in d.actors and not self.draft:self.bracket(world.grid.cell_center(cell),self.world_px(.3),DIM)
            if d.landing:pg.draw.circle(self.screen,WARN,self.pos(world.grid.cell_center(d.landing)),round(use_for(d.item).radius*self.scale),1)
        if self.draft and not self.quick_pending:self.draw_plan_markers(self.draft)
        if self.move_drag:
            drag=self.move_drag
            dx,dy=self.mouse[0]-drag["start"][0],self.mouse[1]-drag["start"][1]
            directed=hypot(dx,dy)/self.scale>=.5
            angle=atan2(dy,dx) if directed else None
            if 'plan_stage' in drag:
                self.draw_plan_move_preview(drag['ids'][0],drag['plan_stage'],drag['cell'],angle)
            else:
                error=self.draw_move_preview(drag['ids'],drag['cell'],drag['append'],ACCENT,angle)
                self.tooltip=error or world.planner.takeover_text(drag["ids"]) or ("追加微操 · " if drag["append"] else "替换微操 · ")+("定向移动" if directed else "随移动方向 · 拖出半格指定朝向")
        elif self.tool and self.tool['kind']=='entrance':
            self.tooltip='点击目标房间的一扇门 · 将重新生成站位'
        elif self.draft and not self.quick_pending and not self.tool and not self.menu and not self.plan_settings and self.plan_stage in {'stack','entry'} and self.viewport.collidepoint(self.mouse):
            if self.hit_object(self.mouse)[0]=='ground' or self.draft_marker_hit(self.mouse):
                self.draw_plan_move_preview(self.plan_actor,self.plan_stage,self.cell(self.mouse))
        elif self.tool and self.viewport.collidepoint(self.mouse):
            tool=self.tool;cell=self.cell(self.mouse);point=world.grid.cell_center(cell);error=self.target_error(cell)
            color=ENEMY if error else ACCENT
            if tool["kind"] in {"landing","throw"}:
                item=self.draft.item if self.draft else tool["item"];use=use_for(item)
                actor=world.actor(self.draft.thrower if self.draft else tool["ids"][0])
                origin=world.grid.cell_center(self.draft.stacks[actor.id]) if self.draft else world.grid.cell_center(world.planner.origin(actor,world.planner.micro_append(actor,self.append())))
                risk=any(a.alive and a.team==Team.RED and a.position.distance_to(point)<=use.radius for a in world.actors)
                if risk and not error:color=WARN
                pg.draw.circle(self.screen,LINE,self.pos(origin),round(use.range*self.scale),1)
                pg.draw.circle(self.screen,color,self.pos(point),round(use.radius*self.scale),1)
                self.line(origin,point,color);self.bracket(point,self.world_px(.3),color)
                self.tooltip=error or ("友军处于影响范围 · 左键仍可提交" if risk else "左键设置落点")
            elif tool["kind"]=="face" or "cell" in tool:
                origin=world.grid.cell_center(tool["cell"]) if "cell" in tool else world.actor(tool["ids"][0]).position
                self.line(origin,self.map_point(self.mouse),ACCENT);self.tooltip="左键指定朝向"
            else:self.bracket(point,self.world_px(.3),color);self.tooltip=error or "左键选择警戒位置"
            if tool["kind"]=="room":self.tooltip="左键选择房间或区域 · 右键返回"
            elif tool["kind"]!="landing":self.tooltip=world.planner.takeover_text(tool["ids"]) or self.tooltip
        elif not self.menu and not self.draft and self.viewport.collidepoint(self.mouse):
            kind,target=self.hit_object(self.mouse)
            if self.loot_hits(self.mouse):
                obj=self.loot_hits(self.mouse)[0];self.tooltip=obj.name+' · 右键搜索 / 查看物品'
            elif kind=="ground" and self.selected and self.world.grid.walkable(target):
                error=self.draw_move_preview(self.selected,target,self.shift(),LINE)
                self.tooltip=error or world.planner.takeover_text(self.selected) or "右键松开移动 · 拖出半格指定朝向 · Shift 追加微操"
            elif kind=="door":self.tooltip=target.replace("door_","")+" · 右键行动菜单";self.bracket(world.mission.entrances[target].center(world.grid),self.world_px(.4))
            elif kind=="ally":self.tooltip=f"{target} {world.actor(target).name} · 右键查看个人物品"

    def draw_move_preview(self,ids,cell,append,color,angle=None):
        p=self.world.planner
        targets,error=p.movement_targets(ids,cell,append)
        if error:self.bracket(self.world.grid.cell_center(cell),self.world_px(.3),ENEMY)
        for i,target in targets.items():
            actor=self.world.actor(i)
            self.route(actor,target,color,p.origin(actor,p.micro_append(actor,append)))
            point=self.world.grid.cell_center(target);x,y=self.pos(point)
            self.text(i,x+8,y-9,ACCENT,12)
            if angle is not None:self.direction_arrow(point,angle,WARN)
        return error

    def direction_arrow(self,origin,angle,color):
        tip=origin+Vec2(cos(angle),sin(angle))*1.0
        self.line(origin,tip,color,2)
        for side in (-.55,.55):
            self.line(tip,tip-Vec2(cos(angle+side),sin(angle+side))*.25,color,2)

    def draw_hud(self):
        world=self.world;x=self.width-300
        pg.draw.rect(self.screen,PANEL,(0,0,self.width,48));pg.draw.line(self.screen,LINE,(0,47),(self.width,47))
        self.text("SC / 灰港档案室",18,12,ACCENT,20)
        self.text(f"配置 {self.config}   消灭敌人 {sum(not a.alive for a in world.actors if a.team==Team.BLUE)}/10",250,14,TEXT)
        self.text(f"{int(world.time)//60:02}:{int(world.time)%60:02}",530,12,ACCENT,20)
        self.button((620,7,140,34),"Ⅱ 暂停中" if world.paused else "▶ 执行中",self.toggle_time,accent=True)
        self.button((770,7,82,34),f"{self.speed:g} 倍速",lambda:setattr(self,"speed",.5 if self.speed==1 else 1))
        if world.combat_cleared:self.button((862,7,160,34),'查看战斗结果',lambda:self.finish_looting())
        self.button((self.width-196,7,84,34),"操作说明",lambda:self.show_overlay("help"))
        self.button((self.width-102,7,84,34),"设置",lambda:self.show_overlay("pause"))
        pg.draw.rect(self.screen,PANEL,(x,48,300,self.height-160));pg.draw.line(self.screen,LINE,(x,48),(x,self.height-112))
        if self.draft:self.draw_draft(x+16)
        else:self.draw_selection(x+16)
        self.draw_cards()
        actor_focus=not self.draft and not self.action_focus and not self.room_inspect and not (self.menu and hasattr(self.menu,'focus_entries')) and bool(self.command_ids())
        if actor_focus:
            ids=self.command_ids()
            self.button((x+16,self.height-238,262,28),'伤势与携带详情',lambda i=ids[0]:self.inspect_actor(i))
            self.button((x+16,self.height-204,126,30),'携带物品 I',self.inventory_menu)
        self.draw_global_entries(x+16,actor_focus)
        if self.draft and not self.quick_pending:
            self.button((18,58,126,30),'返回原视野',self.restore_plan_camera)
            self.button((154,58,126,30),'聚焦入口',self.focus_plan)
            stage={'stack':'门外准备','entry':'进门就位','flash':'闪光落点'}[self.plan_stage]
            label=self.plan_feedback or f'{stage} · 编辑 {self.plan_actor} 号 · 左键选人 · 右键移动 · 右键拖动指定朝向'
            if self.plan_stage=='flash' and not self.plan_feedback:label='闪光落点 · 选择投掷者和落点；橙圈内友军也会受影响'
            pg.draw.rect(self.screen,PANEL,(18,self.viewport.bottom-43,self.viewport.width-36,32))
            self.text(label,28,self.viewport.bottom-38,WARN if self.plan_feedback else TEXT,14,width=self.viewport.width-56)
            self.draw_plan_settings()
        elif not self.draft:
            self.button((18,58,126,30),'房间操作…',lambda:self.start_tool('room'))
            if self.saved_plan:self.button((154,58,160,30),'恢复未下达草稿',self.restore_plan)
        if self.hints and self.hint_index<5 and not self.draft:
            hints=[("01 / 搜索物资","右键身边的黄色补给箱，指定搜索者；完成后暂停分配。"),("02 / 行动入口","右键门→选择行动→立即下令，或编排站位。"),
                   ("03 / 个人物品","右键队员卡可用物品；原多选集合保持不变。"),("04 / 两组协同","F1 / F2 选双人组；草稿标记 A，全部就绪后放行。"),("05 / 随时接管","微操接管取消整组行动；Shift 追加微操路段。")]
            title,body=hints[self.hint_index];y=self.viewport.bottom-82
            pg.draw.rect(self.screen,PANEL,(18,y,min(660,self.viewport.width-36),70));pg.draw.rect(self.screen,LINE,(18,y,min(660,self.viewport.width-36),70),1)
            self.text(title,30,y+8,ACCENT,14);self.text(body,30,y+33,TEXT,14,width=535)
            self.button((580,y+20,80,32),"下一条",lambda:setattr(self,"hint_index",self.hint_index+1))

    def draw_global_entries(self,x,split=False):
        self.button((x+136 if split else x,self.height-204,126 if split else 262,30),f'待分配 {len(self.world.loot.results)} · L',lambda:self.show_loot(),bool(self.world.loot.results))
        self.button((x,self.height-168,262,28),'近期事件',lambda:self.show_overlay('events'))

    def focus_action(self,entry):
        if entry.children:
            context=self.menu
            self.menu=ContextMenu(entry.label,'执行者：'+('、'.join(map(str,self.selected)) or '未选择'),entry.children,
                                  (self.viewport.right-300,180),(self.viewport.right,self.viewport.bottom))
            if context and hasattr(context,'focus_entries'):
                self.menu.focus_title=context.focus_title;self.menu.focus_entries=context.focus_entries
                self.menu.planning=getattr(context,'planning',False)
        elif entry.reason():self.notify(entry.reason())
        elif entry.action:entry.action()

    def draw_object_focus(self,x,title,entries,room=None):
        self.text(title,x,64,ACCENT,20,width=262)
        self.text('执行者：'+('、'.join(map(str,self.selected)) or '未选择'),x,98,TEXT,14,width=262)
        y=132
        # Object menus outside planning retain their existing actions.
        if room:
            last=self.world.mission.room_checked.get(room)
            self.text('尚未完成威胁检查' if last is None else f'最后检查 {last:.0f}s · 不保证安全',x,y,DIM,14,width=262)
            count=sum(1 for i in self.world.perception.player_visible if self.world.actor(i).alive and self.world.grid.zone_id(self.world.grid.cell_of(self.world.actor(i).position))==room)
            self.text(f'当前可见威胁 {count}',x,y+25,WARN,14);y+=62
        for entry in entries:
            if y+32>self.height-280:break
            reason=None if entry.children else entry.reason()
            self.button((x,y,262,32),entry.label+('  ›' if entry.children else ''),lambda entry=entry:self.focus_action(entry),not reason,reason or '');y+=40
        self.button((x,self.height-246,262,32),'返回队员指挥' if self.selected else '返回战局概况',self.clear_tools)

    def draw_selection(self,x):
        w=self.world;ids=[i for i in self.command_ids() if w.actor(i).alive]
        if self.action_focus:
            self.draw_action_focus(x);return
        if self.menu and hasattr(self.menu,'focus_entries'):
            self.draw_object_focus(x,self.menu.focus_title,self.menu.focus_entries);return
        if not ids:
            self.text('战局概况',x,64,ACCENT,20)
            self.text('当前未选择队员',x,108,TEXT,16)
            self.text('左键队员／框选 · Ctrl+A 全选',x,142,DIM,14,width=262)
            self.text('Ctrl＋右键房间：查看房间操作',x,172,DIM,14,width=262)
            self.text(f'在场存活 {sum(a.alive for a in w.actors[:4])} 人',x,218,TEXT,16)
            blocked=sum(t.phase=='blocked' for t in w.planner.tasks.values())
            self.text(f'挂起行动 {blocked} · 选中参与者处理',x,254,WARN if blocked else DIM,14,width=262)
            return
        self.text("指挥 / COMMAND",x,64,ACCENT,20)
        self.text(f"执行 {len(ids)} 人  ·  {', '.join(map(str,ids))}",x,98,TEXT)
        controls=self.height-366
        self.button((x,controls,126,28),"全选 Ctrl+A",lambda:self.select([1,2,3,4]))
        self.button((x+136,controls,126,28),"取消计划 X",lambda ids=ids:self.stop(ids),bool(ids),"先选择队员" if not ids else w.planner.takeover_text(ids) or "取消计划并在下一格停步")
        self.button((x,controls+32,126,28),"警戒 Q",lambda ids=ids:self.start_tool("guard",ids=ids),bool(ids))
        self.button((x+136,controls+32,126,28),"闪光 G",self.flash_menu,bool(ids))
        reload_ids=[i for i in ids if not w.planner.item_error(w.actor(i),'rifle','reload',self.shift())]
        bandage_ids=[i for i in ids if not w.planner.item_error(w.actor(i),'bandage','bandage',self.shift())]
        self.button((x,controls+64,126,28),f"换弹 R · {len(reload_ids)}人",lambda:self.batch_item("reload","rifle"),bool(reload_ids),w.planner.takeover_text(reload_ids) or '只给需要且能够换弹的队员下令')
        self.button((x+136,controls+64,126,28),f"包扎 H · {len(bandage_ids)}人",lambda:self.batch_item("bandage","bandage"),bool(bandage_ids),w.planner.takeover_text(bandage_ids) or '只给需要且能够包扎的队员下令')
        self.button((x,controls+96,126,28),"自动开火",lambda:self.set_fire(ids,False),bool(ids))
        self.button((x+136,controls+96,126,28),"禁止开火",lambda:self.set_fire(ids,True),bool(ids))
        y=132
        for label in ("A","B"):
            entries=w.planner.sync_status(label);ready=sum(v for _,v in entries)
            if not entries:continue
            self.button((x,y,180,28),f"放行 {label} · {ready}/{len(entries)}",lambda label=label:self.notify(w.planner.release(label)),ready==len(entries),"全部就绪后可放行")
            self.button((x+190,y,72,28),"等待",lambda label=label:self.submit(ids,"wait",sync=label),bool(ids));y+=34
        if len(ids)==1:
            actor=w.actor(ids[0]);self.text(f"{actor.name} / 行动队列 {len(actor.queue)}/8",x,y,ACCENT,14);y+=27
            self.queue_offset=min(self.queue_offset,max(0,len(actor.queue)-1))
            for index,node in enumerate(actor.queue[self.queue_offset:]):
                actual=index+self.queue_offset
                if y+52>controls-18:break
                task=w.planner.tasks.get(node.task_id)
                label=w.planner.task_label(task) if task else LABELS.get(node.kind,node.kind)
                if node.kind in {"move","move_face"}:label+=" · 定向" if node.angle is not None else " · 随移动"
                self.text(f"{actual+1}. {label}",x,y,TEXT,14,width=210)
                self.button((x+226,y-2,36,26),"×",lambda actual=actual:w.planner.delete_node(actor,actual),reason=w.planner.takeover_text([actor.id]) if task else '删除此节点')
                state=(task.reason if task.phase=="blocked" else STAGES[task.phase]) if task else node.reason or {'queued':'待执行','active':'执行中','waiting':'等待信号','allocation':'等待物资决定','blocked':'已挂起'}.get(node.status,node.status)
                self.text(state,x,y+21,WARN if task and task.phase=="blocked" or node.status=="blocked" else DIM,12,width=170)
                if task and task.phase=="blocked":self.button((x+176,y+24,86,26),"继续",lambda task=task:self.notify(w.planner.retry_task(task.id)))
                elif node.status=="blocked":self.button((x+176,y+24,86,26),"重试",lambda node=node,actor=actor:self.retry_node(actor,node))
                y+=58
            if not actor.queue:self.text("无计划 · 保持警戒",x,y,DIM,14);y+=28
        else:
            self.text("小队行动",x,y,ACCENT,14);y+=30
            tasks=sorted((t for t in w.planner.tasks.values() if any(i in ids for i in t.draft.actors)),key=lambda t:(t.phase!='blocked',t.id))
            self.queue_offset=min(self.queue_offset,max(0,len(tasks)-1))
            for task in tasks[self.queue_offset:]:
                if y+95>controls-18:break
                self.text(w.planner.task_label(task),x,y,TEXT,14,width=262)
                self.text(f"{task.draft.actors} · {STAGES[task.phase]}",x,y+22,WARN if task.phase=="blocked" else DIM,14)
                detail=task.reason or (f"搜索：{[i for i in task.draft.actors if i not in task.guards]}  警戒：{sorted(task.guards)}" if task.draft.method=='loot' else '')
                self.text(detail,x,y+44,WARN if task.reason else DIM,12,width=262)
                if task.phase=="blocked":self.button((x,y+65,126,28),"继续行动",lambda task=task:self.notify(w.planner.retry_task(task.id)))
                self.button((x+136,y+65,126,28),"取消行动",lambda task=task:w.planner.cancel_task(task.id));y+=107
            for i in ids:
                a=w.actor(i)
                if y+22>controls-18:break
                if a.task_id or a.queue and a.queue[0].task_id:continue
                self.text(f"{i} {a.name} · {LABELS.get(a.queue[0].kind,'执行') if a.queue else '警戒'}",x,y,DIM,14);y+=25
        self.text('滚轮查看任务 · 挂起须手动继续',x,controls-18,DIM,12)
        if w.events:
            self.text(w.events[-1][1],x,self.height-142,DIM,12,width=263)

    def retry_node(self,actor,node):
        self.notify(self.world.planner.retry_node(actor,node))

    def draw_draft(self,x):
        self.draw_plan_contents(x)

    def reorder_draft(self,index,delta):
        other=index+delta
        if not 0<=other<len(self.draft.actors):return
        ids=list(self.draft.actors);ids[index],ids[other]=ids[other],ids[index]
        self.edit_draft(actors=ids)

    def cycle_thrower(self):
        d=self.draft;candidates=[i for i in d.actors if self.world.planner.available(self.world.actor(i),d.item,self.append())>0]
        if not candidates:self.notify("没有可用物品");return
        index=candidates.index(d.thrower) if d.thrower in candidates else -1
        self.edit_draft(thrower=candidates[(index+1)%len(candidates)])

    def draw_cards(self):
        y=self.height-112;pg.draw.rect(self.screen,BG,(0,y,self.width,112));pg.draw.line(self.screen,LINE,(0,y),(self.width,y))
        width=(self.width-40)//4;self.cards=[]
        for j,a in enumerate(self.world.actors[:4]):
            rect=pg.Rect(12+j*(width+4),y+10,width,91);self.cards.append((rect,a.id))
            pg.draw.rect(self.screen,PANEL,rect);pg.draw.rect(self.screen,ACCENT if (a.id==self.plan_actor if self.draft else a.id in self.selected) else LINE,rect,1)
            self.text(f"{a.id} / {a.name}",rect.x+12,rect.y+8,ACCENT if a.alive else DIM,20)
            self.text(f"{a.weapon.ammo:02} / {a.weapon.reserve_ammo:02}",rect.right-103,rect.y+9,TEXT,20)
            task=self.world.planner.tasks.get(a.queue[0].task_id) if a.queue else None
            status=self.actor_duty(a)
            self.text(status,rect.x+12,rect.y+32,WARN if a.blocked_reason or task and task.phase=="blocked" or a.stunned>0 else DIM,14,width=width-80)
            response=a.response or "保持观察"
            worst=min(a.body.region_hp_fraction(region) for region in ('head','torso','left_arm','right_arm','left_leg','right_leg'))
            if a.alive and worst<.95:response=self.injury_summary(a)
            if a.fire_reason in {"友军挡线","弹药耗尽","射线被遮挡"}:response+=" · "+a.fire_reason
            if a.alive:self.text(response,rect.x+12,rect.y+51,WARN if a.response=="受袭搜索" or worst<.95 else DIM,12,width=width-80)
            self.text("禁火" if a.fire_mode==FireMode.HOLD_FIRE else "自动",rect.right-56,rect.y+39,WARN if a.fire_mode==FireMode.HOLD_FIRE else DIM,14)
            self.text(f"{self.world.loot.weight(a):.1f}/{a.inventory.capacity:g}kg  闪光可用 {a.inventory.available('flashbang')} / 已安排 {a.inventory.reserved('flashbang')}  包扎 {a.inventory.available('bandage')}" if a.alive else '装备留在尸体 · 队友需到场回收',rect.x+12,rect.y+70,DIM,12,width=width-20)
            if a.current_action:
                progress=min(1,a.current_action.timer/a.current_action.duration)
                pg.draw.line(self.screen,ACCENT,(rect.x+1,rect.bottom-2),(rect.x+1+int((width-2)*progress),rect.bottom-2),2)

    def draw_title(self):
        self.draw_map(True)
        pg.draw.rect(self.screen,BG,(0,0,550,self.height))
        self.text("SC / TACTICAL SYSTEMS",56,70,ACCENT,16)
        self.text("SCARLET",52,150,TEXT,48);self.text("CONTRACT",52,211,TEXT,48)
        self.text("灰港档案室",56,290,ACCENT,28)
        self.text("四人小队 · 实时指挥 · 随时暂停",56,350,DIM,16)
        self.text("用一条命令组织突入。",56,385,TEXT,16)
        self.text("用一次暂停，改变每个人的下一步。",56,412,TEXT,16)
        self.button((56,478,360,46),"开始行动  →",lambda:setattr(self,"page","brief"),accent=True)
        self.button((56,536,360,40),f"敌情配置：{self.config} · 点击切换",lambda:setattr(self,"config",{"A":"B","B":"C","C":"A"}[self.config]))
        self.button((56,588,174,40),"操作说明",lambda:self.show_overlay("help"))
        self.button((242,588,174,40),"设置",lambda:self.show_overlay("settings"))
        self.button((56,640,360,40),"退出",lambda:setattr(self,"running",False))
        self.text("OFFLINE DEMO / 01     ·     48 × 36",56,self.height-54,DIM,14)

    def draw_brief(self):
        saved_scale,saved_offset=self.scale,self.offset
        self.scale=min((self.width-430)/48,self.viewport.height/36)
        self.offset=[(self.width-430)/2-24*self.scale,self.viewport.centery-18*self.scale]
        self.draw_map(True);self.scale,self.offset=saved_scale,saved_offset;x=self.width-430
        pg.draw.rect(self.screen,PANEL,(x,0,430,self.height));pg.draw.line(self.screen,LINE,(x,0),(x,self.height))
        self.text("行动简报",x+30,66,ACCENT,28);self.text("OP. GREYPORT",x+30,112,DIM,16)
        for j,line in enumerate(["灰港档案室已被武装人员占据。","从南侧安全区进入建筑，清除全部敌人。","","目标：消灭 10 名敌人","成功条件：至少一名队员存活","敌情配置："+self.config,"","4 名队员 / 每人 30 + 90 发步枪弹","每人 1 枚闪光弹、1 份包扎用品","","白线为建筑简图，不代表实时视野。","门状态和敌人只有观察后才能确认。","搜索完成不能保证房间永远安全。"]):
            self.text(line,x+30,168+j*30,TEXT if j in (3,4) else DIM,16,width=370)
        self.button((x+30,self.height-134,370,46),"进入关卡 · 暂停部署",self.start_mission,accent=True)
        self.button((x+30,self.height-76,370,40),"返回标题",lambda:setattr(self,"page","title"))

    def draw_ending(self):
        self.draw_map();w=self.world;success=w.winner==Team.RED
        rect=pg.Rect(self.width//2-330,self.height//2-260,660,520)
        pg.draw.rect(self.screen,PANEL,rect);pg.draw.rect(self.screen,ACCENT if success else ENEMY,rect,1)
        x,y=rect.x+36,rect.y+32
        self.text("行动完成" if success else "行动失败",x,y,ACCENT if success else ENEMY,28)
        lines=[f"灰港档案室 / 配置 {self.config}",f"消灭敌人 {sum(not a.alive for a in w.actors if a.team==Team.BLUE)} / 10",
               f"存活队员 {sum(a.alive for a in w.actors[:4])} / 4",f"模拟用时 {int(w.time)//60:02}:{int(w.time)%60:02} · 暂停 {w.pause_count} 次",
               f"发射 {w.stats['rounds']} 发 · 友军中弹 {w.stats['friendly_hits']} 次",
               f"使用闪光 {w.stats['items'].get('flashbang',0)} · 包扎 {w.stats['items'].get('bandage',0)} · 友军震撼 {w.stats['friendly_stuns']} 次"]
        for j,line in enumerate(lines):self.text(line,x,y+65+j*35,TEXT if j<3 else DIM,16)
        if success:
            self.button((x,rect.bottom-142,282,40),'继续搜索物资',self.continue_looting,accent=True)
            self.button((x+306,rect.bottom-142,282,40),'同配置重试',self.start_mission)
        else:self.button((x,rect.bottom-142,588,40),"同配置重试",self.start_mission,accent=True)
        self.button((x,rect.bottom-90,282,40),"下一个配置",self.next_mission)
        self.button((x+306,rect.bottom-90,282,40),"返回标题",lambda:setattr(self,"page","title"))

    def next_mission(self):self.config={"A":"B","B":"C","C":"A"}[self.config];self.start_mission()

    def continue_looting(self):
        self.world.continue_looting();self.page='mission';self.clear_tools()

    def finish_looting(self):
        self.world.set_paused(True);self.world.winner=Team.RED;self.page='ending';self.clear_tools()

    def draw_overlay(self):
        veil=pg.Surface(self.screen.get_size(),pg.SRCALPHA);veil.fill((0,0,0,170));self.screen.blit(veil,(0,0))
        self.buttons=[];rect=pg.Rect(self.width//2-350,70,700,self.height-140)
        pg.draw.rect(self.screen,PANEL,rect);pg.draw.rect(self.screen,LINE,rect,1);x,y=rect.x+32,rect.y+28
        if self.overlay=='events':
            self.text('近期事件',x,y,ACCENT,28)
            for j,(when,message) in enumerate(self.world.events[-11:]):
                self.text(f'{when:06.1f}  {message}',x,y+60+j*30,TEXT,14,width=636)
            if not self.world.events:self.text('暂无事件',x,y+60,DIM,16)
            self.button((x,rect.bottom-68,636,40),'返回原操作',self.close_overlay,accent=True)
            return
        if self.overlay=='actor':
            actor=self.world.actor(self.detail_actor)
            self.text(f'{actor.id} {actor.name} · 伤势与携带详情',x,y,ACCENT,28)
            for index,a in enumerate(self.world.actors[:4]):
                def choose(i=a.id):self.detail_actor=i;self.detail_scroll=0
                self.button((x+index*160,y+48,150,28),f'{a.id} {a.name}',choose,accent=a.id==actor.id)
            self.text(self.actor_duty(actor),x,y+88,TEXT,16,width=630)
            regions=[('head','头部'),('torso','躯干'),('left_arm','左臂'),('right_arm','右臂'),('left_leg','左腿'),('right_leg','右腿')]
            for j,(region,label) in enumerate(regions):
                fraction=actor.body.region_hp_fraction(region)
                self.text(f'{label} {fraction:.0%}',x+(j%2)*310,y+119+(j//2)*26,WARN if fraction<.95 else TEXT,16)
            stats=actor.body.derived_stats()
            self.text(f'移动能力 {stats.movement_efficiency:.0%} · 操作能力 {stats.manipulation_efficiency:.0%}',x,y+206,TEXT,16)
            self.text(f'已装备 {actor.weapon.definition.name} · 弹匣 {actor.weapon.ammo} / 备用 {actor.weapon.reserve_ammo}',x,y+235,TEXT,16)
            self.text(f'实际 {self.world.loot.weight(actor):.1f} kg · 已预约 {self.world.loot.reserved_weight(actor.id):.1f} kg · 容量 {actor.inventory.capacity:g} kg',x,y+264,ACCENT,16)
            carried=list(self.world.loot.carried(actor).values()) if actor.alive else []
            rows=max(1,(rect.bottom-110-(y+299))//27)
            self.detail_scroll=min(self.detail_scroll,max(0,len(carried)-rows))
            for j,item in enumerate(carried[self.detail_scroll:self.detail_scroll+rows]):
                self.text(f'{item.name} ×{item.quantity} · {item.weight:.2f} kg',x,y+299+j*27,TEXT,14,width=630)
            if not carried:self.text('装备已留在尸体，需到场回收' if not actor.alive else '没有额外携带物品',x,y+299,DIM,14)
            self.text('只读 · 滚轮查看物品 · 返回保留原选择和分配预约',x,rect.bottom-98,DIM,14)
            self.button((x,rect.bottom-68,636,40),'返回物资分配' if self.loot_panel else '返回指挥',self.close_overlay,accent=True)
            return
        self.text("操作说明" if self.overlay=="help" else "战术终端 / 设置",x,y,ACCENT,28)
        if self.overlay=="help":
            lines=["选择：左键队员 / 队员卡；Shift 增减；空地拖动框选。","1–4 单选，双击数字居中；Ctrl+A 全选。","F1 / F2 选择双人组；Ctrl+F1 / F2 保存当前编组。","右键松开移动；拖出半格指定本段朝向。","门和房间动作统一在右栏：选动作→立即下令／编排站位。","编排自动暂停；左键选队员，右键移动，右键拖动指定朝向。","右键队员 / 队员卡仅使用此人物品，保留原选择。","空格暂停 / 继续；Tab 切换 0.5 / 1 倍速。","Q：警戒位置→方向；R：换弹；H：包扎；G：闪光。","Shift 追加微操路段，最多 8 项；接管会取消整组宏观。","微操移动优先于射击；来弹不抢占当前移动。","宏观受到未知来弹时挂起，手动点击继续。","正常交战属于计划执行；声音不改变路线。","右键门操作；左上“房间操作”后选区域，或 Ctrl＋右键房间。","同步 A / B：全部就绪后点击右栏“放行”。","WASD 平移；中键拖动；滚轮缩放；F12 截图。","编排：Ctrl+Z 撤销；Esc 返回选点／设置，退出保留可恢复草稿。","闪光可震撼友军；自动开火会避免已知友军挡线。","每名队员首次阵亡自动暂停；无复活、补给和护送。"]
            lines[-1]='队员阵亡自动暂停；尸体可跨过，经过时减速。'
            lines[4:4]=['右键黄色物资点，指定搜索者；完成后自动暂停。','容器物品：双击由交互角色拿取，右键选择其他角色。','I 查看携带物品、放下和装备；L 返回待分配窗口。','Ctrl＋右键区域→搜索区域物资；参与者须已在区域内。']
            for j,line in enumerate(lines[self.help_scroll:]):
                if y+72+j*30>rect.bottom-90:break
                self.text(line,x,y+72+j*30,TEXT,16,width=636)
            self.text("滚轮翻阅 · 所有战术时间在此界面冻结",x,rect.bottom-98,DIM,14)
        else:
            self.button((x,y+76,636,42),"显示器特效："+["关闭","轻度","标准"][self.fx],lambda:setattr(self,"fx",(self.fx+1)%3))
            self.button((x,y+132,636,42),f"音量：{round(self.volume*100)}%",lambda:setattr(self,"volume",round((self.volume+.25)%1.25,2)))
            self.button((x,y+188,636,42),"首次发现敌人暂停："+("开启" if self.auto_contact else "关闭"),self.toggle_contact)
            self.button((x,y+244,636,42),"关卡操作提示："+("开启" if self.hints else "关闭"),lambda:setattr(self,"hints",not self.hints))
            if self.page=="mission":
                self.button((x,y+314,310,42),"重新部署同配置",self.start_mission)
                self.button((x+326,y+314,310,42),"返回标题",self.back_title)
            self.text("扫描线只作用于地图；菜单和文字保持清晰。",x,y+390,DIM,14)
        self.button((x,rect.bottom-68,636,40),"返回",self.close_overlay,accent=True)

    def toggle_contact(self):self.auto_contact=not self.auto_contact;self.world.auto_contact=self.auto_contact
    def back_title(self):self.overlay=None;self.page="title";self.clear_tools()

    def draw(self):
        self.screen.fill(BG);self.buttons=[];self.tooltip="";self.cards=[]
        if self.page=="title":self.draw_title()
        elif self.page=="brief":self.draw_brief()
        elif self.page=="ending":self.draw_ending()
        else:self.draw_map();self.draw_hud()
        if self.event_log and not self.overlay:self.draw_event_log()
        if self.loot_panel:self.draw_loot_panel()
        if self.overlay:self.draw_overlay()
        if self.menu:self.menu.draw(self)
        if self.notice and pg.time.get_ticks()<self.notice_until:
            rect=pg.Rect(18,58,min(self.width-36,self.fonts[16].size(self.notice)[0]+28),36)
            pg.draw.rect(self.screen,PANEL,rect);pg.draw.rect(self.screen,WARN,rect,1);self.text(self.notice,rect.x+12,rect.y+7,WARN)
        if self.tooltip and not self.overlay:
            width=min(self.width-40,self.fonts[14].size(self.tooltip)[0]+24);x=max(8,min(self.mouse[0]+16,self.width-width-8));y=max(8,min(self.mouse[1]+24,self.height-34))
            pg.draw.rect(self.screen,BG,(x,y,width,28));pg.draw.rect(self.screen,LINE,(x,y,width,28),1);self.text(self.tooltip,x+10,y+4,TEXT,14,width=width-20)
        if self.tool and self.page=="mission":
            impact="编辑草稿 · 尚未下达" if self.draft else self.world.planner.takeover_text(self.tool.get("ids",[])) or ("追加微操" if self.append() else "替换微操")
            kind=self.tool['kind']
            step={'room':'左键选房间','entrance':'左键选入口门','landing':'左键选闪光落点'}.get(kind,'左键指定朝向' if 'cell' in self.tool else '左键选点')
            label=step+" · 右键返回 · "+impact
            width=min(self.viewport.width-36,self.fonts[14].size(label)[0]+24)
            pg.draw.rect(self.screen,PANEL,(18,94,width,32))
            self.text(label,28,99,WARN,14,width=width-20)

    def run(self):
        while self.running:
            dt=min(.25,self.clock.tick(60)/1000);self.mouse=pg.mouse.get_pos()
            self.events(pg.event.get());self.update(dt);self.draw();pg.display.flip()
        pg.quit()
