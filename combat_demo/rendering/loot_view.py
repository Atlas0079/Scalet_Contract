"""Object menus and allocation UI; physical results belong to the simulation."""
import pygame as pg

from simulation.actor import Team
from simulation.loot import LOOT_BRIGHT, LOOT_OPENED
from simulation.orders import LABELS, STAGES
from .widgets import ContextMenu, Entry, BG, PANEL, LINE, TEXT, DIM, WARN, ACCENT, ENEMY


class LootViewMixin:
    def init_loot_ui(self):
        self.loot_panel=None
        self.loot_actors={}
        self.loot_rows=[]
        self.loot_rect=pg.Rect(0,0,0,0)
        self.loot_last_click=None
        self.loot_scroll=0
        self.loot_candidate=None
        self.event_log=False
        self.detail_actor=1
        self.detail_scroll=0

    def injury_summary(self,actor):
        if not actor.alive:return '已阵亡'
        regions=[('head','头部'),('torso','躯干'),('left_arm','左臂'),('right_arm','右臂'),('left_leg','左腿'),('right_leg','右腿')]
        region,label=min(regions,key=lambda pair:actor.body.region_hp_fraction(pair[0]))
        if actor.body.region_hp_fraction(region)>=.95:return '无明显伤势'
        return f'{label}受伤 · 移动 {actor.body.derived_stats().movement_efficiency:.0%}'

    def actor_duty(self,actor):
        if not actor.alive:return '已阵亡'
        if actor.stunned>0:return f'震撼 {actor.stunned:.1f}s'
        node=actor.queue[0] if actor.queue else None
        task=self.world.planner.tasks.get(node.task_id) if node else None
        if task:
            if task.phase=='blocked':return '已挂起 · 需手动继续'
            if task.draft.method=='loot':
                job=task.jobs.get(actor.id)
                if job:return '等待物资决定' if job.status=='allocation' else LABELS.get(job.kind,job.kind)
                return '原地警戒' if actor.id in task.guards else '观察寻找物资'
            return self.world.planner.task_label(task)+' · '+STAGES[task.phase]
        if node:
            if node.status=='blocked':return '已挂起 · '+(node.reason or '需重试')
            if node.kind=='guard':return '已就位 · 定点警戒' if node.started else '前往警戒位／调整朝向'
            return LABELS.get(node.kind,node.kind)
        return '无计划 · 原地观察'

    def inspect_actor(self,i):
        self.detail_actor=i;self.detail_scroll=0
        self.show_overlay('actor')

    def finish_loot_next(self):
        self.close_loot()
        if self.world.loot.results:self.show_loot()

    def cancel_loot_pickup(self,item_id):
        token,reservation=self.world.loot.pickup_reservation(self.loot_panel,item_id)
        if token:
            self.world.loot.cancel_pickup(token)
            self.world.message('已撤销此件拿取 · 物品仍在来源，其他安排保留')
        self.menu=None;self.loot_last_click=None

    def pickup_impact(self,item_id,actor):
        if not actor:return '右键选择拿取者'
        task=self.world.loot.pickup_task(self.loot_panel,item_id)
        if task and actor.id in task.draft.actors:
            return '将离开警戒位，到场拿取' if actor.id in task.guards else '本行动分工 · 拿取后继续搜索'
        return self.world.planner.takeover_text([actor.id]) or '替换旧微操 · 同容器拿取依次追加'

    def loot_hits(self,pos):
        if not self.viewport.collidepoint(pos):return []
        return [obj for obj in self.world.loot.objects.values() if obj.discovered
                and pg.Rect(self.pos((obj.cell[0],obj.cell[1])),(max(12,self.scale),max(12,self.scale))).collidepoint(pos)]

    def loot_context(self,pos):
        hits=self.loot_hits(pos)
        if not hits:return False
        kind,target=self.hit_object(pos)
        if len(hits)==1 and kind in {'ground','dead'}:
            self.object_menu(hits[0].id,pos);return True
        entries=[Entry(obj.name,lambda id_=obj.id:self.object_menu(id_,pos)) for obj in hits]
        if kind=='ally':entries.insert(0,Entry(f'{target} 号队员',lambda:self.personal_menu(target,pos)))
        elif kind=='door':entries.insert(0,Entry('门 · 行动菜单',lambda:self.door_menu(door=target,anchor=pos)))
        elif kind=='enemy':entries.insert(0,Entry('攻击当前敌人',lambda:self.submit(self.selected,'attack',target_id=target)))
        self.menu=ContextMenu('选择交互对象','同一位置有多个目标',entries,pos,(self.width,self.height))
        return True

    def object_menu(self,id_,pos):
        obj=self.world.loot.objects.get(id_)
        if not obj:return
        self.clear_tools()
        if obj.searched:
            entries=[Entry(f'{i} {self.world.actor(i).name} · 查看物品',
                           lambda i=i:self.show_loot(id_,i)) for i in self.selected]
            if not entries:entries=[Entry('先选择交互角色',error='先选择一名队员')]
        else:
            entries=[Entry(f'{i} {self.world.actor(i).name} · 搜索',
                           lambda i=i:self.submit([i],'loot_search',object_id=id_),
                           error=lambda i=i:self.world.loot.search_error(self.world.actor(i),id_)) for i in self.selected]
            if not entries:entries=[Entry('先选择搜索者',error='先选择一名或多名队员')]
        subtitle=lambda:((self.world.planner.takeover_text(self.selected) or '到场搜索 · 完成后暂停分配') if not obj.searched else '分配只下令 · 到场才拿到')
        self.menu=ContextMenu(obj.name,subtitle,entries,pos,(self.width,self.height))
        self.menu.focus_title=obj.name;self.menu.focus_entries=entries

    def show_loot(self,id_=None,actor_id=None):
        if id_ is None:id_=next(iter(self.world.loot.results),None)
        obj=self.world.loot.objects.get(id_)
        if obj is None or not obj.searched:return
        result=self.world.loot.results.get(id_)
        if actor_id is None:
            actor_id=result.actor_id if result and result.actor_id is not None else self.loot_actors.get(id_)
        if actor_id is None and len(self.selected)==1:actor_id=self.selected[0]
        self.loot_actors[id_]=actor_id
        self.world.set_paused(True)
        self.clear_tools();self.drag=None;self.panning=False
        self.loot_panel=id_;self.loot_scroll=0;self.loot_last_click=None;self.loot_rows=[]
        self.loot_candidate=actor_id
        self.world.loot.notifications=[v for v in self.world.loot.notifications if v!=id_]

    def close_loot(self):
        if self.loot_panel in self.world.loot.results:
            self.world.loot.allocate(self.loot_panel,{})
        self.loot_panel=None;self.menu=None;self.loot_last_click=None;self.loot_rows=[]
        self.world.set_paused(True)
        if self.world.loot.results:
            self.world.message(f'仍有 {len(self.world.loot.results)} 处等待分配决定 · 按 L 处理')

    def pickup_error(self,item_id,actor_id):
        if actor_id is None:return '当前没有交互角色，请右键选择拾取者'
        return self.world.loot.allocation_error(self.loot_panel,{item_id:actor_id})

    def pickup(self,item_id,actor_id):
        error=self.pickup_error(item_id,actor_id)
        if not error:error=self.world.loot.allocate(self.loot_panel,{item_id:actor_id},finish=False)
        if error:self.notify(error);return
        self.menu=None;self.loot_last_click=None

    def pickup_menu(self,item_id,pos):
        self.loot_last_click=None
        entries=[]
        for actor in self.world.actors:
            if actor.team!=Team.RED:continue
            item=self.world.loot.objects[self.loot_panel].known.get(item_id)
            _,old=self.world.loot.pickup_reservation(self.loot_panel,item_id)
            total=self.world.loot.weight(actor)+self.world.loot.reserved_weight(actor.id)+(item.weight if item and (not old or old.actor_id!=actor.id) else 0)
            entries.append(Entry(f'{actor.id} {actor.name}'+(' · 当前' if old and old.actor_id==actor.id else '')+f' · {total:.1f}/{actor.inventory.capacity:g}kg',
                lambda i=actor.id:self.pickup(item_id,i),
                error=lambda i=actor.id:self.pickup_error(item_id,i)))
        def subtitle():
            hit=self.menu.keyboard or self.menu.hover if self.menu else None
            actors=[a for a in self.world.actors if a.team==Team.RED]
            if not hit or not 0<=hit[1]<len(actors):return '到场拿取 · 悬停查看指令影响'
            actor=actors[hit[1]]
            task=self.world.loot.pickup_task(self.loot_panel,item_id)
            if task and actor.id in task.draft.actors:
                return '离开警戒位，到场拿取' if actor.id in task.guards else '本行动分工 · 拿取后继续搜索'
            return self.world.planner.takeover_text([actor.id]) or '替换旧微操 · 同容器拿取追加'
        _,old=self.world.loot.pickup_reservation(self.loot_panel,item_id)
        if old:entries.append(Entry('撤销此件拿取安排',lambda:self.cancel_loot_pickup(item_id)))
        self.loot_candidate=self.loot_actors.get(self.loot_panel)
        self.menu=ContextMenu('更换拿取者' if old else '选择拾取角色',subtitle,entries,pos,(self.viewport.right,self.viewport.bottom))
        self.menu.loot_item_id=item_id

    def loot_click(self,event):
        if event.button==1 and event.pos[0]>=self.viewport.right:
            for rect,action,enabled,reason in reversed(self.buttons):
                if rect.collidepoint(event.pos):
                    if enabled:action()
                    else:self.notify(reason)
                    return
        if self.menu:
            if event.button==1:
                hit=self.menu.hit(event.pos)
                if hit:self.notify(self.menu.activate(hit));return
            self.menu=None;self.loot_last_click=None
            return
        if event.button==1:
            for rect,action,enabled,reason in reversed(self.buttons):
                if rect.collidepoint(event.pos):
                    self.loot_last_click=None
                    if enabled:action()
                    else:self.notify(reason)
                    return
        item_id=next((i for rect,i in self.loot_rows if rect.collidepoint(event.pos)),None)
        if item_id is None:self.loot_last_click=None;return
        if event.button==3:self.pickup_menu(item_id,event.pos)
        elif event.button==1:
            now=pg.time.get_ticks();last=self.loot_last_click
            if last and last[0]==item_id and now-last[1]<=300 and pg.Vector2(event.pos).distance_to(last[2])<=6:
                self.loot_last_click=None
                self.pickup(item_id,self.loot_actors.get(self.loot_panel))
            else:self.loot_last_click=(item_id,now,event.pos)

    def inventory_menu(self,i=None):
        ids=self.command_ids()
        if i is None and not ids:self.notify('先选择队员');return
        if i is None and len(ids)!=1:
            self.menu=ContextMenu('查看谁的携带物品','每件物品都有实际携带者',
                [Entry(f'{id_} {self.world.actor(id_).name}',lambda id_=id_:self.inventory_menu(id_)) for id_ in ids],
                self.mouse,(self.width,self.height))
            return
        i=ids[0] if i is None else i
        actor=self.world.actor(i)
        entries=[]
        for id_,item in self.world.loot.carried(actor).items():
            children=[Entry('放到脚下',lambda id_=id_:self.submit([i],'loot_drop',cargo_id=id_))]
            if item.weapon:children.insert(0,Entry('装备这把武器',lambda id_=id_:self.submit([i],'loot_equip',cargo_id=id_)))
            entries.append(Entry(f'{item.name} ×{item.quantity} · {item.weight:.1f}kg',children=children))
        if not entries:entries=[Entry('没有可转移的携带物品',error='主武器保持装备，不能直接丢弃')]
        self.clear_tools()
        self.menu=ContextMenu(f'{i} {actor.name} · 携带物品',f'{self.world.loot.weight(actor):.1f} / {actor.inventory.capacity:g} kg · 放下也需动作',entries,self.mouse,(self.width,self.height))
        self.menu.actor_id=i

    def loot_task_error(self,room):
        if not self.selected:return '先选择参与者'
        outside=[i for i in self.selected if self.world.grid.zone_id(self.world.planner.position_cell(self.world.actor(i)))!=room]
        if outside:return f'{"、".join(map(str,outside))} 号尚未进入此区域 · 先通过入口进入，再搜索物资'
        return None

    def loot_task_entries(self,room):
        ids=list(self.selected)
        def submit(guards):
            error=self.world.planner.submit_loot_task(ids,room,guards)
            if error:self.notify(error)
            else:self.clear_tools()
        entries=[Entry('全员搜索',lambda:submit([]),error=lambda:self.loot_task_error(room))]
        if len(ids)>1:
            entries.append(Entry(f'{ids[-1]} 号原地警戒，其余搜索',lambda:submit([ids[-1]]),error=lambda:self.loot_task_error(room)))
        return Entry('搜索区域物资',children=entries)

    def draw_loot_objects(self):
        for obj in self.world.loot.objects.values():
            if not obj.discovered:continue
            x,y=self.pos(self.world.grid.cell_center(obj.cell));r=self.world_px(.34)
            color=obj.color
            if obj.kind=='corpse':
                pg.draw.lines(self.screen,color,False,[(x-r,y-r),(x+r,y+r)],2)
                pg.draw.lines(self.screen,color,False,[(x+r,y-r),(x-r,y+r)],2)
            elif obj.kind=='ground':
                q=self.world_px(.12)
                pg.draw.polygon(self.screen,color,[(x-r,y+q),(x,y-r),(x+r,y+q),(x+q,y+r)],2)
            else:
                pg.draw.rect(self.screen,color,(x-r,y-r,2*r,2*r),2)
                pg.draw.line(self.screen,color,(x-r,y-1),(x+r,y-1),1)
            if obj.searched and not obj.known:self.text('空',x+r+2,y-8,DIM,12)
            elif obj.opened and not obj.searched:self.text('…',x+r+2,y-8,LOOT_BRIGHT,12)
        for task in self.world.planner.tasks.values():
            if task.draft.method!='loot':continue
            for i,job in task.jobs.items():
                if i not in self.selected:continue
                obj=self.world.loot.objects.get(job.object_id)
                if obj and job.cell:self.route(self.world.actor(i),job.cell,LOOT_BRIGHT)

    def draw_loot_panel(self):
        w=self.world;obj=w.loot.objects.get(self.loot_panel)
        if obj is None:self.close_loot();return
        self.buttons=[];self.loot_rows=[];self.tooltip=''
        items=list(obj.known.values());visible_rows=min(5,max(1,len(items)))
        bounds=self.viewport.inflate(-20,-20)
        anchor=self.pos(w.grid.cell_center(obj.cell))
        pin=(max(bounds.left,min(anchor[0],bounds.right)),max(bounds.top,min(anchor[1],bounds.bottom)))
        width=min(430,bounds.width);height=min(222+visible_rows*48,bounds.height)
        left=pin[0]+28 if pin[0]+28+width<=bounds.right else pin[0]-width-28
        rect=pg.Rect(left,pin[1]-height//2,width,height).clamp(bounds);self.loot_rect=rect
        edge=(rect.left if pin[0]<rect.centerx else rect.right,max(rect.top+12,min(pin[1],rect.bottom-12)))
        pg.draw.line(self.screen,LOOT_BRIGHT,pin,edge,1)
        pg.draw.circle(self.screen,LOOT_BRIGHT,pin,5,1)
        pg.draw.rect(self.screen,PANEL,rect);pg.draw.rect(self.screen,LOOT_BRIGHT,rect,1)
        x,y=rect.x+14,rect.y+10
        self.text(obj.name,x,y,LOOT_BRIGHT,20,width=rect.width-155)
        self.button((rect.right-150,y,136,26),'完成此处分配',self.close_loot,reason='已安排保留，其余留在原处；Esc 同样完成此处决定')
        actor=w.actor(self.loot_actors.get(obj.id))
        label=f'{actor.id} {actor.name}'+(' · 阵亡' if not actor.alive else '') if actor else '未指定 · 右键选择拾取者'
        self.text('当前交互：'+label,x,y+30,ACCENT,14,width=rect.width-28)
        self.text('双击安排到场拿取 · 右键改派／撤销 · 已暂停',x,y+53,TEXT,14,width=rect.width-28)
        rows=max(1,(rect.height-222)//48)
        self.loot_scroll=max(0,min(self.loot_scroll,max(0,len(items)-rows)))
        for index,item in enumerate(items[self.loot_scroll:self.loot_scroll+rows]):
            row=pg.Rect(x,y+80+index*48,rect.width-28,46);self.loot_rows.append((row,item.id))
            if row.collidepoint(self.mouse):pg.draw.rect(self.screen,LINE,row)
            reservation=next((r for r in w.loot.reservations.values() if r.object_id==obj.id and r.item_id==item.id),None)
            self.text(f'{item.name} ×{item.quantity} · {item.weight:.2f} kg',x+5,row.y+3,TEXT,14,width=row.width-10)
            status=f'仍在来源 · 已安排 {reservation.actor_id} 号 · 右键改派／撤销' if reservation else '仍在来源 · 双击安排当前角色到场拿取'
            self.text(status,x+5,row.y+24,WARN if reservation else DIM,12,width=row.width-10)
            if row.collidepoint(self.mouse):
                task=w.loot.pickup_task(obj.id,item.id)
                internal=task and actor and actor.id in task.draft.actors
                self.tooltip=self.pickup_error(item.id,actor.id if actor else None) or (
                    '本行动分工；警戒者拿取会离开警戒位' if internal else
                    w.planner.takeover_text([actor.id]) or '拿取指令会替换旧微操；同容器拿取依次追加')
        if not items:self.text('已取空',x,y+85,DIM,16)
        sources=list(w.loot.results)
        self.text(f'等待决定 {len(sources)} 处 · 切换查看不会完成当前决定',x,rect.bottom-126,TEXT,12,width=rect.width-28)
        if sources:
            index=sources.index(obj.id) if obj.id in sources else -1
            self.button((x,rect.bottom-101,172,28),'仅查看下一处',lambda:self.show_loot(sources[(index+1)%len(sources)]),len(sources)>1,reason='当前来源继续等待决定，已有预约保留')
            self.button((x+180,rect.bottom-101,222,28),'完成此处并处理下一处',self.finish_loot_next)
        self.text('已安排保留 · 未安排留在原处 · 关闭后按空格执行',x,rect.bottom-64,ACCENT,12,width=rect.width-28)
        self.text('滚轮翻页 · '+('当前记录' if obj.visible else f'上次查看 {obj.seen_at:.1f}s'),x,rect.bottom-35,DIM,12)
        self.draw_loot_actor(actor)

    def draw_loot_actor(self,actor):
        item_id=None
        if self.menu and hasattr(self.menu,'loot_item_id'):
            item_id=self.menu.loot_item_id
            hit=self.menu.keyboard or self.menu.hover
            actors=[a for a in self.world.actors if a.team==Team.RED]
            if hit and hit[0]==0 and 0<=hit[1]<len(actors):self.loot_candidate=actors[hit[1]].id
            actor=self.world.actor(self.loot_candidate)
        if item_id is None:
            item_id=next((i for rect,i in self.loot_rows if rect.collidepoint(self.mouse)),None)
        x=self.width-284;y=64;w=self.world
        pg.draw.rect(self.screen,PANEL,(self.width-299,48,299,self.height-160))
        self.text('分配参考 · 只读',x,y,ACCENT,20)
        self.text('悬停人选查看 · 不改变原小队选择',x,y+33,DIM,12)
        if not actor:
            self.text('右键物品选择拿取者',x,y+70,TEXT,16);self.draw_global_entries(x);return
        self.text(f'{actor.id} {actor.name}',x,y+65,ACCENT,20)
        obj=w.loot.objects[self.loot_panel]
        distance=(actor.position-w.grid.cell_center(obj.cell)).length()
        self.text(f'直线距离 {distance:.1f} m · 不代表可达',x,y+96,DIM,12)
        self.text(self.injury_summary(actor),x,y+121,WARN,14,width=262)
        self.text(self.actor_duty(actor),x,y+150,TEXT,14,width=262)
        actual=w.loot.weight(actor);reserved=w.loot.reserved_weight(actor.id)
        item=obj.known.get(item_id)
        _,old=w.loot.pickup_reservation(obj.id,item_id)
        extra=item.weight if item and (not old or old.actor_id!=actor.id) else 0
        self.text(f'现有 {actual:.1f} + 预约 {reserved:.1f} kg',x,y+181,TEXT,14)
        self.text(f'本次后 {actual+reserved+extra:.1f} / {actor.inventory.capacity:g} kg',x,y+207,ACCENT,16)
        self.text(f'已装备 {actor.weapon.definition.name} · 弹匣 {actor.weapon.ammo}',x,y+240,TEXT,14,width=262)
        if item and item.weapon:self.text(f'待拿 {item.name} · 拾取不自动装备',x,y+264,WARN,12,width=262)
        impact=self.pickup_error(item_id,actor.id) or self.pickup_impact(item_id,actor) if item else '悬停物品查看此次命令的影响'
        # Wrap consequences instead of hiding them in a truncated tooltip.
        lines=[];line=''
        for char in impact:
            if self.fonts[14].size(line+char)[0]>260:lines.append(line);line=''
            line+=char
        lines.append(line)
        for j,line in enumerate(lines[:5]):self.text(line,x,y+302+j*22,WARN,14)
        self.button((x,self.height-246,262,32),'查看伤势与携带详情',lambda:self.inspect_actor(actor.id))
        self.draw_global_entries(x)

    def draw_event_log(self):
        rect=pg.Rect(26,80,min(850,self.width-52),min(450,self.height-180))
        pg.draw.rect(self.screen,PANEL,rect);pg.draw.rect(self.screen,ACCENT,rect,1)
        self.text('近期事件 · 最近 11 条',rect.x+18,rect.y+12,ACCENT,20)
        for index,(when,message) in enumerate(self.world.events[-11:]):
            self.text(f'{when:06.1f}  {message}',rect.x+18,rect.y+52+index*30,TEXT,14,width=rect.width-36)
        self.button((rect.right-112,rect.y+8,96,32),'收起',lambda:setattr(self,'event_log',False))
