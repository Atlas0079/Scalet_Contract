from __future__ import annotations
from dataclasses import dataclass
import pygame as pg

BG="#071112"; LINE="#36585B"; ACCENT="#9DFFE3"; TEXT="#DCF7EE"
WARN="#E8B86A"; ENEMY="#FF796E"; DIM="#819C99"; PANEL="#0C191B"


@dataclass
class Entry:
    label: str
    action: object = None
    children: list | None = None
    error: object = None
    label_fn: object = None

    def reason(self): return self.error() if callable(self.error) else self.error


class ContextMenu:
    """Two levels; opening a branch never invokes an action."""
    def __init__(self,title,subtitle,entries,anchor,size):
        self.title=title;self.subtitle=subtitle;self.entries=entries
        self.anchor=anchor;self.size=size;self.branch=None;self.hover=None;self.since=0
        self.outside_since=0;self.keyboard=None;self.scroll=[0,0]
        self.root=self.rect((anchor[0]+12,anchor[1]+12),entries,True)

    def rect(self,pos,entries,root=False):
        height=min(self.size[1]-16,16+(48 if root else 24)+32*len(entries))
        return pg.Rect(max(8,min(pos[0],self.size[0]-288)),max(8,min(pos[1],self.size[1]-height-8)),280,height)

    def panels(self):
        values=[(self.root,self.entries,0,56)]
        if self.branch is not None:
            entries=self.entries[self.branch].children
            x=self.root.right+4 if self.root.right+284<=self.size[0]-8 else self.root.left-284
            rect=self.rect((x,self.root.y+56+32*(self.branch-self.scroll[0])),entries)
            values.append((rect,entries,1,32))
        return values

    def hit(self,pos):
        for rect,entries,level,offset in reversed(self.panels()):
            if rect.collidepoint(pos):
                index=(pos[1]-rect.y-offset)//32+self.scroll[level]
                if 0<=index<len(entries) and pos[1]>=rect.y+offset and pos[1]<rect.bottom-8:
                    return level,int(index)
                return level,-1
        return None

    def update(self,pos,now):
        hit=self.hit(pos)
        if hit!=self.hover:self.hover=hit;self.since=now;self.keyboard=None
        if hit and hit[1]>=0:
            self.outside_since=now
            if hit[0]==0 and now-self.since>=180:
                self.branch=hit[1] if self.entries[hit[1]].children else None
        elif now-self.outside_since>300:self.branch=None

    def activate(self,hit):
        if hit is None or hit[1]<0:return None
        level,index=hit
        if level==1 and self.branch is None:return None
        entries=self.entries if level==0 else self.entries[self.branch].children
        if not 0<=index<len(entries):return None
        entry=(self.entries if level==0 else self.entries[self.branch].children)[index]
        if entry.children:self.branch=index;self.keyboard=(1,0);return None
        reason=entry.reason()
        if reason:return reason
        if entry.action:entry.action()
        return None

    def key(self,key):
        level,index=self.keyboard or (0,0)
        if level==1 and self.branch is None:level,index=0,0
        entries=self.entries if level==0 or self.branch is None else self.entries[self.branch].children
        if not entries:return None
        index=min(index,len(entries)-1)
        if key in (pg.K_UP,pg.K_DOWN): index=(index+(1 if key==pg.K_DOWN else -1))%len(entries)
        if key==pg.K_LEFT:level=0;index=self.branch or 0;self.branch=None
        self.keyboard=(level,index)
        if key in (pg.K_RIGHT,pg.K_RETURN):return self.activate(self.keyboard)

    def wheel(self,delta,pos):
        hit=self.hit(pos)
        if hit:
            level=hit[0];rect,entries,_,offset=self.panels()[level]
            limit=max(0,len(entries)-(rect.height-offset-8)//32)
            self.scroll[level]=max(0,min(limit,self.scroll[level]-delta))

    def draw(self,app):
        for rect,entries,level,offset in self.panels():
            pg.draw.rect(app.screen,PANEL,rect);pg.draw.rect(app.screen,ACCENT,rect,1)
            app.text(self.title if level==0 else self.entries[self.branch].label,rect.x+12,rect.y+7,ACCENT,14,width=256)
            if level==0:app.text(self.subtitle() if callable(self.subtitle) else self.subtitle,rect.x+12,rect.y+29,DIM,14,width=256)
            old=app.screen.get_clip();app.screen.set_clip(rect.inflate(-2,-2))
            for index,entry in enumerate(entries):
                y=rect.y+offset+32*(index-self.scroll[level])
                if y<rect.y+offset or y+32>rect.bottom-7:continue
                active=(self.keyboard or self.hover)==(level,index)
                if active:pg.draw.rect(app.screen,LINE,(rect.x+5,y,270,31))
                error=entry.reason()
                label=entry.label_fn() if entry.label_fn else entry.label
                app.text(label,rect.x+12,y+5,DIM if error else TEXT,16,width=237)
                if entry.children:app.text("‹" if rect.right+284>self.size[0]-8 else "›",rect.right-23,y+4,ACCENT,20)
                if active:app.tooltip=error or label
            app.screen.set_clip(old)
