"""Draft interaction; the existing planner validates every change."""
from copy import deepcopy
from math import pi
import pygame as pg
from .widgets import ACCENT, TEXT, WARN, DIM, LINE, PANEL, ENEMY

METHODS={'direct':'直接突入','breach':'破门突入','flash':'闪光突入','stack':'门外集结','guarddoor':'门口警戒','open':'开门','kick':'踹门'}
ENTRY_METHODS={'direct','breach','flash'}


class PlanningViewMixin:
    def init_planning(self):
        self.plan_after='hold';self.quick_pending=False
        self.plan_markers=[];self.plan_actor=None;self.plan_stage='stack'
        self.plan_history=[];self.saved_plan=None;self.plan_camera=None
        self.plan_settings=False;self.plan_settings_rect=None;self.plan_feedback=''
        self.plan_candidate=None;self.action_focus=None

    def world_px(self,distance):return max(1,round(distance*self.scale))

    def toggle_time(self):
        if self.draft and not self.quick_pending:
            self.notify('正在编排：先下达计划，或退出编排后恢复时间');return
        self.world.set_paused(not self.world.paused)

    def choose_plan_actor(self,i):
        if i not in self.draft.actors:
            self.notify('该队员未参与此计划；退出编排后可重新选择参与者');return
        self.plan_actor=i;self.move_drag=None

    def set_plan_stage(self,stage):
        self.plan_stage=stage;self.move_drag=None;self.tool=None
        if stage=='flash':self.tool={'kind':'landing','ids':self.draft.actors}

    def focus_plan(self):
        d=self.draft
        cells=list(d.stacks.values())+(list(d.entries.values()) if d.method in ENTRY_METHODS else [])
        xs=[c[0]+.5 for c in cells];ys=[c[1]+.5 for c in cells]
        self.scale=max(12,min(40,self.viewport.width/(max(xs)-min(xs)+10),(self.viewport.height-100)/(max(ys)-min(ys)+8)))
        self.offset=[self.viewport.centerx-(min(xs)+max(xs))/2*self.scale,self.viewport.centery-(min(ys)+max(ys))/2*self.scale]

    def restore_plan_camera(self):
        if self.plan_camera:self.scale,self.offset=self.plan_camera[0],list(self.plan_camera[1])

    def remember_plan(self):
        self.saved_plan=deepcopy((self.draft,self.draft_append,self.plan_history,self.plan_actor,self.plan_stage))
        self.restore_plan_camera()

    def leave_plan(self):self.clear_tools()

    def restore_plan(self):
        if not self.saved_plan:return
        d,append,history,actor,stage=deepcopy(self.saved_plan)
        fresh,error=self.preview_draft(d,append=append)
        if error:self.notify('草稿暂不能恢复：'+error);return
        self.clear_tools();self.draft=fresh;self.draft_append=append;self.plan_history=history
        self.plan_actor=actor;self.plan_stage=stage;self.plan_feedback='已恢复草稿，尚未下达'
        self.plan_candidate=None
        self.plan_camera=(self.scale,list(self.offset));self.world.set_paused(True);self.focus_plan()

    def preview_draft(self,d=None,**changes):
        d=d or self.draft
        args={k:getattr(d,k) for k in ('item','thrower','landing','sync','opening','after_entry','stack_overrides','entry_overrides','stack_angles','entry_angles')}
        args['append']=self.draft_append
        args.update({k:v for k,v in changes.items() if k not in {'actors','door','room','method'}})
        return self.world.planner.preview_task(changes.get('actors',d.actors),changes.get('door',d.door),changes.get('room',d.room),changes.get('method',d.method),**args)

    def undo_plan(self):
        if not self.plan_history:return
        d,append=self.plan_history[-1];fresh,error=self.preview_draft(d,append=append)
        if error:self.notify('无法撤销：'+error);return
        self.plan_history.pop();self.draft=fresh;self.draft_append=append
        self.tool=None;self.move_drag=None;self.draft_error='';self.plan_feedback='已撤销上一次调整'
        if self.plan_stage=='flash' and not fresh.item:self.plan_stage='stack'

    def set_plan_append(self,append):
        if append==self.draft_append:return
        fresh,error=self.preview_draft(append=append)
        if error:self.notify(error);return
        self.plan_history.append((deepcopy(self.draft),self.draft_append))
        self.draft=fresh;self.draft_append=append;self.draft_error='';self.plan_feedback=''

    def choose_plan_entrance(self):
        self.plan_settings=False
        self.move_drag=None;self.tool={'kind':'entrance','ids':self.draft.actors}

    def plan_position_error(self,stage,i,cell):
        key=(id(self.draft),self.draft_append,stage,i,cell)
        if not self.plan_candidate or self.plan_candidate[0]!=key:
            values=dict(getattr(self.draft,stage+'_overrides'));values[i]=cell
            _,error=self.preview_draft(**{stage+'_overrides':values});self.plan_candidate=(key,error)
        return self.plan_candidate[1]

    def draft_marker_hit(self,pos):
        point=self.map_point(pos)
        hits=[(point.distance_to(center),stage,i) for center,stage,i in self.plan_markers
              if stage==self.plan_stage and point.distance_to(center)<=max(.4,8/self.scale)]
        return min(hits)[1:] if hits else None

    def plan_map_down(self,event):
        if not self.draft:return False
        if self.plan_settings:
            if not self.plan_settings_rect or not self.plan_settings_rect.collidepoint(event.pos):self.plan_settings=False
            return True
        kind,target=self.hit_object(event.pos)
        if self.tool and self.tool['kind']=='entrance':
            if event.button==1:
                if kind!='door':self.notify('点击连接目标房间的门');return True
                entrance=self.world.mission.entrances[target]
                if self.draft.room not in (entrance.zone_a,entrance.zone_b):self.notify('该门不连接目标房间');return True
                if target==self.draft.door:self.tool=None;return True
                if self.edit_draft(door=target,landing=None,stack_overrides={},entry_overrides={},stack_angles={},entry_angles={}):
                    self.tool=None;self.focus_plan()
            elif event.button==3:self.cancel_tool()
            return True
        if self.tool:
            if event.button==1 and kind=='ally':self.choose_plan_actor(target);return True
            return False
        hit=self.draft_marker_hit(event.pos)
        if event.button==1:
            if hit:self.choose_plan_actor(hit[1])
            elif kind=='ally':self.choose_plan_actor(target)
        elif event.button==3 and not self.quick_pending and self.plan_stage in {'stack','entry'}:
            # Use the ordinary move gesture: press at the destination, drag to face,
            # release to apply. Only its destination (draft versus live order) differs.
            self.move_drag={'start':event.pos,'cell':self.cell(event.pos),'ids':[self.plan_actor],
                            'plan_stage':self.plan_stage}
        return True

    def move_plan_actor(self,stage,i,cell,angle):
        positions=dict(getattr(self.draft,stage+'_overrides'));positions[i]=cell
        angles=dict(getattr(self.draft,stage+'_angles'))
        if angle is None:angles.pop(i,None)
        else:angles[i]=angle
        # Position and facing form one validated, undoable draft adjustment.
        return self.edit_draft(**{stage+'_overrides':positions,stage+'_angles':angles})

    def draw_plan_move_preview(self,i,stage,cell,angle=None):
        d=self.draft;w=self.world;point=w.grid.cell_center(cell)
        error=self.plan_position_error(stage,i,cell);color=ENEMY if error else ACCENT
        self.bracket(point,self.world_px(.4),color)
        if not error:
            origin=w.planner.origin(w.actor(i),self.draft_append) if stage=='stack' else d.inside
            self.route(w.actor(i),cell,color,start=origin,mark=False)
            default=(d.angle if d.actors.index(i)<3 else d.angle+pi) if stage=='stack' else w.planner.room_angle(d.room,cell)
            self.direction_arrow(point,default if angle is None else angle,color)
        self.tooltip=error or f'{i} 号 · '+('松开右键设置站位和朝向' if angle is not None else '右键设置站位 · 按住拖动指定朝向')

    def draw_plan_markers(self,d):
        self.plan_markers=[];grid=self.world.grid
        for stage,slots in (('stack',d.stacks),('entry',d.entries)):
            if stage=='entry' and d.method not in ENTRY_METHODS:continue
            active=stage==self.plan_stage
            for i,cell in slots.items():
                center=grid.cell_center(cell)
                if active:self.plan_markers.append((center,stage,i))
                x,y=self.pos(center);r=max(8,self.world_px(.34));color=(WARN if stage=='stack' else ACCENT) if active else LINE
                if stage=='stack':pg.draw.rect(self.screen,color,(x-r,y-r,2*r,2*r),2 if active else 1)
                else:pg.draw.polygon(self.screen,color,[(x,y-r),(x+r,y),(x,y+r),(x-r,y)],2 if active else 1)
                if not active:continue
                default=(d.angle if d.actors.index(i)<3 else d.angle+pi) if stage=='stack' else self.world.planner.room_angle(d.room,cell)
                self.direction_arrow(center,getattr(d,stage+'_angles').get(i,default),color)
                pg.draw.rect(self.screen,PANEL,(x-7,y-9,15,19));self.text(str(i),x-4,y-9,color,12)
                if self.plan_actor==i:
                    self.bracket(center,r+7,color)
                    self.route(self.world.actor(i),cell,color,start=None if stage=='stack' else d.inside,mark=False)

    def plan_text_lines(self,value,x,y,color=DIM,max_lines=2):
        lines=[];line=''
        for char in value:
            if self.fonts[12].size(line+char)[0]>262:lines.append(line);line=''
            line+=char
        lines.append(line)
        for j,line in enumerate(lines[:max_lines]):self.text(line,x,y+j*17,color,12,width=262)

    def plan_impact(self,ids,append):
        planner=self.world.planner
        related=planner.related_tasks(ids)
        if related and not append:
            members=sorted({i for t in related for i in planner.tasks[t].draft.actors})
            return f'将取消 {len(related)} 项关联行动 · 影响 '+ '/'.join(map(str,members))+' 号'
        queued=[str(i) for i in ids if self.world.actor(i).queue]
        if queued:return '保留已有行动，排在队尾' if append else '将替换 '+ '/'.join(queued)+' 号原指令'
        return '下达后按空格执行' if self.world.paused else '下达后立即执行'

    def draw_plan_contents(self,x):
        d=self.draft;w=self.world
        self.text('选择闪光落点' if self.quick_pending else '编排 · '+w.grid.zones[d.room].label,x,64,ACCENT,20,width=262)
        if self.quick_pending:
            self.text('快速下令 · 左键落点后立即下达',x,105,WARN,14,width=262)
            self.text('右键或 Esc 取消 · 道具尚未消耗',x,138,DIM,12)
            self.text('执行者：'+'、'.join(map(str,d.actors)),x,175,TEXT,16)
            self.button((x,self.height-246,262,34),'取消选点',self.clear_tools);return
        self.text(METHODS[d.method]+' · 已暂停 · 尚未下达',x,96,DIM,12)
        count=3 if d.item else 2 if d.method in ENTRY_METHODS else 1;width=(262-(count-1)*6)//count
        for j,(stage,label) in enumerate([('stack','门外准备'),('entry','进门就位'),('flash','闪光落点')][:count]):
            self.button((x+j*(width+6),122,width,30),label,lambda stage=stage:self.set_plan_stage(stage),accent=self.plan_stage==stage)
        self.text('进入顺序 · 点选编辑，箭头排序' if d.method in ENTRY_METHODS else '行动成员 · 点选编辑',x,163,DIM,12)
        for index,i in enumerate(d.actors):
            y=185+index*32
            self.button((x,y,188,28),f'{index+1:02}   {i} 号 · {w.actor(i).name}',lambda i=i:self.choose_plan_actor(i),accent=i==self.plan_actor)
            self.button((x+194,y,31,28),'↑',lambda index=index:self.reorder_draft(index,-1),index>0,'已经是首位' if index==0 else '')
            self.button((x+231,y,31,28),'↓',lambda index=index:self.reorder_draft(index,1),index<len(d.actors)-1,'已经是末位' if index==len(d.actors)-1 else '')
        if self.plan_stage=='flash':
            self.button((x,320,126,30),f'换投掷者：{d.thrower}',self.cycle_thrower)
            self.button((x+136,320,126,30),'修改落点' if d.landing else '选择落点',lambda:self.set_plan_stage('flash'))
        controls=358 if self.plan_stage=='flash' else 320
        self.button((x,controls,126,28),'撤销 Ctrl+Z',self.undo_plan,bool(self.plan_history),'没有可撤销的调整' if not self.plan_history else '')
        self.button((x+136,controls,126,28),'计划设置…',lambda:setattr(self,'plan_settings',not self.plan_settings),accent=self.plan_settings)
        footer=self.height-314;pg.draw.line(self.screen,LINE,(x,footer-8),(x+262,footer-8))
        summary=('追加' if self.draft_append else '替换')+'计划 · '+('同步 '+d.sync if d.sync else '无需同步')
        if d.method in ENTRY_METHODS:summary+=' · '+('就位警戒' if d.after_entry=='hold' else '检查威胁')
        self.text(summary,x,footer,TEXT,12,width=262)
        impact=self.plan_impact(d.actors,self.draft_append)
        self.plan_text_lines(self.draft_error or impact,x,footer+21,ENEMY if self.draft_error else WARN if '替换' in impact or '取消' in impact else DIM)
        self.button((x,self.height-246,126,34),'下达计划',self.commit_draft,not(d.item and d.landing is None),
                    '先在“闪光落点”设置目标' if d.item and d.landing is None else '下达后保持暂停，按空格执行',True)
        self.button((x+136,self.height-246,126,34),'退出 · 留草稿',self.leave_plan)

    def draw_plan_settings(self):
        if not self.plan_settings or not self.draft or self.quick_pending:return
        d=self.draft;w=self.world;rect=pg.Rect(self.viewport.right-360,100,342,450 if d.item else 402)
        self.plan_settings_rect=rect;pg.draw.rect(self.screen,PANEL,rect);pg.draw.rect(self.screen,ACCENT,rect,1)
        x=rect.x+16;y=rect.y+12;self.text('计划设置',x,y,ACCENT,20)
        self.button((rect.right-76,y,60,28),'收起',lambda:setattr(self,'plan_settings',False));y+=45
        if d.method in ENTRY_METHODS:self.button((x,y,310,30),METHODS[d.method]+' · 更改方式',self.method_menu)
        else:self.text(METHODS[d.method],x,y,TEXT,16)
        y+=38
        self.button((x,y,310,30),'更换入口 · 在地图选门',self.choose_plan_entrance);y+=38
        other=w.grid.zone_id(d.outside)
        def reverse():
            if self.edit_draft(room=other,landing=None,stack_overrides={},entry_overrides={},stack_angles={},entry_angles={}):self.focus_plan()
        self.button((x,y,310,30),'反向进入：'+w.grid.zones[other].label,reverse,d.method not in ENTRY_METHODS or other in w.mission.rooms,'该侧不属于可突入房间');y+=38
        if d.method in ENTRY_METHODS:
            self.button((x,y,310,30),'突入后：'+('就位警戒' if d.after_entry=='hold' else '检查威胁'),lambda:self.edit_draft(after_entry='search' if d.after_entry=='hold' else 'hold'));y+=38
        self.text('同步放行 · 同组全部就绪后手动放行',x,y,DIM,12);y+=23
        for j,(sync,label) in enumerate(((None,'不等待'),('A','同步 A'),('B','同步 B'))):
            self.button((x+j*106,y,98,28),label,lambda sync=sync:self.edit_draft(sync=sync),accent=d.sync==sync)
        y+=37
        self.button((x,y,151,30),'替换原计划',lambda:self.set_plan_append(False),accent=not self.draft_append)
        self.button((x+159,y,151,30),'追加到队尾',lambda:self.set_plan_append(True),accent=self.draft_append);y+=42
        if d.item:
            self.button((x,y,310,30),'开门方式：'+('踹开' if d.opening=='kick' else '打开'),lambda:self.edit_draft(opening='open' if d.opening=='kick' else 'kick'));y+=40
        self.text('自定站位受阻会挂起，不自动换位',x,y,WARN,12)

    def action_back(self):
        f=self.action_focus
        f['keyboard']=None
        if f['choice'] is not None:f['choice']=None
        elif f['path']:f['entries']=f['path'].pop()
        else:self.clear_tools()

    def choose_action(self,entry):
        self.action_focus['keyboard']=None
        if entry.children:
            self.action_focus['path'].append(self.action_focus['entries']);self.action_focus['entries']=entry.children
        elif entry.reason():self.notify(entry.reason())
        elif entry.action:entry.action()

    def action_key(self,key):
        f=self.action_focus;count=2 if f['choice'] else len(f['entries'])
        index=f['keyboard'] if f['keyboard'] is not None else 0
        if key in (pg.K_UP,pg.K_DOWN):
            f['keyboard']=(index+(1 if key==pg.K_DOWN else -1))%count
        elif key==pg.K_LEFT:self.action_back()
        elif key in (pg.K_RIGHT,pg.K_RETURN):
            if f['choice']:
                if f['keyboard'] is None:f['keyboard']=1
                elif key==pg.K_RETURN:self.new_draft(*f['choice'],quick=index==0)
            else:self.choose_action(f['entries'][index])

    def draw_action_focus(self,x):
        f=self.action_focus;room=f['room'];w=self.world
        self.text(f['title'],x,64,ACCENT,20,width=262)
        self.text('执行者：'+('、'.join(map(str,self.selected)) or '未选择'),x,99,TEXT,14,width=262);y=132
        if room:
            last=w.mission.room_checked.get(room)
            self.text('尚未检查威胁' if last is None else f'上次检查 {last:.0f}s · 不保证安全',x,y,DIM,12);y+=25
            count=sum(1 for i in w.perception.player_visible if w.actor(i).alive and w.grid.zone_id(w.grid.cell_of(w.actor(i).position))==room)
            self.text(f'当前可见威胁 {count}',x,y,WARN,12);y+=20
        choice=f['choice']
        if choice:
            ids,door,target,method,item=choice;self.text(METHODS[method],x,y,ACCENT,20);y+=40
            preview=w.planner.choose_entrance(ids,door,target,method,self.shift(),item)
            error=None if preview else w.planner.entrance_error
            if preview:
                self.text('实际执行：'+'、'.join(map(str,preview.actors)),x,y,TEXT,14);y+=28
                self.text('目标：'+w.grid.zones[preview.room].label,x,y,TEXT,14);y+=32
            if method in ENTRY_METHODS:
                self.button((x,y,262,30),'突入后：'+('就位警戒' if self.plan_after=='hold' else '检查威胁'),lambda:setattr(self,'plan_after','search' if self.plan_after=='hold' else 'hold'));y+=42
            self.button((x,y,262,36),'选落点后下令' if item else '立即下令 · '+METHODS[method],lambda:self.new_draft(*choice,quick=True),not error,error or '暂停时先下令，按空格执行',f['keyboard']!=1);y+=44
            self.button((x,y,262,36),'编排站位 · 暂停编辑',lambda:self.new_draft(*choice),not error,error or '调整站位、朝向与进入顺序',f['keyboard']==1);y+=44
            impact=self.plan_impact(preview.actors,self.shift()) if preview else ''
            self.plan_text_lines(error or impact or ('Shift：追加到队尾' if self.shift() else '立即下令使用默认站位'),x,y,WARN if error or impact else DIM,3)
        else:
            self.text('选择行动，再决定下令或编排',x,y,DIM,12);y+=30
            for index,entry in enumerate(f['entries']):
                reason=None if entry.children else entry.reason()
                self.button((x,y,262,34),entry.label+('  ›' if entry.children else ''),lambda entry=entry:self.choose_action(entry),not reason,reason or '',f['keyboard']==index);y+=42
        self.button((x,self.height-246,262,32),'返回上一级' if choice or f['path'] else '返回队员指挥',self.action_back)
