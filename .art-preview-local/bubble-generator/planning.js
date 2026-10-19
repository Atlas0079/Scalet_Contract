(function(root){'use strict';
const C=typeof module!=='undefined'?require('./content.js'):root.BubbleContent;
const Complexes=typeof module!=='undefined'?require('./complexes.js'):root.BubbleComplexes;
// Terrain fields have no district labels, target outline, or urban coordinates.
class Heap{
 constructor(){this.a=[];}
 push(i,v){const a=this.a;let k=a.length;a.push([i,v]);while(k){const p=(k-1)>>1;if(a[p][1]<=v)break;a[k]=a[p];k=p;}a[k]=[i,v];}
 pop(){const a=this.a,out=a[0],last=a.pop();if(a.length){let k=0;while(k*2+1<a.length){let c=k*2+1;if(c+1<a.length&&a[c+1][1]<a[c][1])c++;if(a[c][1]>=last[1])break;a[k]=a[c];k=c;}a[k]=last;}return out;}
 get length(){return this.a.length;}
}
function plan(seed,W,H){
 const R=C.random(seed+'-geology-v7'),ri=(a,b)=>Math.floor(a+R()*(b-a+1)),N=W*H;
 const geology=new Uint8Array(N),rock=new Uint8Array(N),excavation=new Uint8Array(N),ground=new Uint8Array(N),cityMask=new Uint8Array(N),streetMask=new Uint8Array(N),protectedCells=new Uint8Array(N),growth=new Uint8Array(N);
 const naturalLines=[],roads=[],tram=[],portals=[],spaces=[],blocks=[],regions=[];
 const adjacent=i=>{const x=i%W,y=(i/W)|0;return[x?i-1:-1,x<W-1?i+1:-1,y?i-W:-1,y<H-1?i+W:-1];};
 const inside=(x,y)=>x>=4&&y>=4&&x<W-4&&y<H-4;
 function field(step){const nx=Math.ceil(W/step)+3,ny=Math.ceil(H/step)+3,a=Float32Array.from({length:nx*ny},()=>R());return(x,y)=>{x=x/step+1;y=y/step+1;const ix=Math.floor(x),iy=Math.floor(y),u=x-ix,v=y-iy,s=u*u*(3-2*u),t=v*v*(3-2*v);return(a[iy*nx+ix]*(1-s)+a[iy*nx+ix+1]*s)*(1-t)+(a[(iy+1)*nx+ix]*(1-s)+a[(iy+1)*nx+ix+1]*s)*t;};}
 const detail=field(W*.055),fine=field(11),strata=field(W*.15),hardness=field(W*.07);
 for(let y=0;y<H;y++)for(let x=0;x<W;x++){const v=.72*strata(x,y)+.28*hardness(x,y);rock[y*W+x]=v>.72?3:v>.58?2:1;}
 function distance(mask,edgeIsBlocked=true){const d=new Int32Array(N),q=new Int32Array(N);d.fill(N);let h=0,t=0;for(let i=0;i<N;i++)if(!mask[i]||(edgeIsBlocked&&(i<W||i>=N-W||i%W===0||i%W===W-1))){d[i]=0;q[t++]=i;}while(h<t){const i=q[h++];for(const j of adjacent(i))if(j>=0&&d[j]>d[i]+1){d[j]=d[i]+1;q[t++]=j;}}return d;}
 const hardClearance=distance(Uint8Array.from(rock,v=>v!==3));
 // Separate small cave systems. Graph edges never connect different geological systems.
 const systems=[],systemTarget=Math.max(7,Math.round(N/27000)),separation=Math.max(62,Math.sqrt(N/systemTarget)*.72);
 for(let k=0;k<systemTarget*150&&systems.length<systemTarget;k++){const x=ri(25,W-26),y=ri(25,H-26);if(hardClearance[y*W+x]<12||systems.some(c=>Math.hypot(c.x-x,c.y-y)<separation))continue;systems.push({x,y,id:systems.length});}
 const zones=new Int16Array(N);for(let y=4;y<H-4;y++)for(let x=4;x<W-4;x++){let first=Infinity,second=Infinity,id=-1;for(const c of systems){const d=Math.hypot(x-c.x,y-c.y);if(d<first){second=first;first=d;id=c.id;}else if(d<second)second=d;}if(second-first>18)zones[y*W+x]=id+1;}
 const zoneDepth=distance(zones),nodes=[],links=[],spacing=Math.max(21,W*.027);let loops=0;
 for(const system of systems){const ids=[],wanted=ri(4,7);for(let k=0;k<500&&ids.length<wanted;k++){const x=k===0?system.x:system.x+ri(-70,70),y=k===0?system.y:system.y+ri(-70,70);if(!inside(x,y)||zones[y*W+x]!==system.id+1||zoneDepth[y*W+x]<12||hardClearance[y*W+x]<12||ids.some(i=>Math.hypot(nodes[i].x-x,nodes[i].y-y)<spacing))continue;ids.push(nodes.length);nodes.push({x,y,cluster:system.id});}
  const connected=new Set(ids.slice(0,1)),used=new Set();while(connected.size<ids.length){let best=null;for(const a of connected)for(const b of ids)if(!connected.has(b)){const d=Math.hypot(nodes[a].x-nodes[b].x,nodes[a].y-nodes[b].y);if(!best||d<best.d)best={a,b,d};}links.push(best);used.add([Math.min(best.a,best.b),Math.max(best.a,best.b)].join(':'));connected.add(best.b);}
  if(ids.length>=5&&R()<.22){const extra=[];for(let a=0;a<ids.length;a++)for(let b=a+1;b<ids.length;b++)if(!used.has([ids[a],ids[b]].join(':')))extra.push({a:ids[a],b:ids[b],d:Math.hypot(nodes[ids[a]].x-nodes[ids[b]].x,nodes[ids[a]].y-nodes[ids[b]].y)});extra.sort((a,b)=>a.d-b.d);if(extra.length){links.push(extra[0]);loops++;}}
 }
 function bore(x,y,r,kind=2,cluster=null){for(let yy=Math.floor(y-r);yy<=y+r;yy++)for(let xx=Math.floor(x-r);xx<=x+r;xx++)if(inside(xx,yy)&&Math.hypot(xx-x,yy-y)<r*(.9+.16*fine(xx,yy))){const i=yy*W+xx;if(rock[i]!==3&&(cluster===null||zones[i]===cluster+1&&zoneDepth[i]>2)){geology[i]=kind;rock[i]=0;}}}
 // Grid search bends the passages around resistant formations, retaining irregular widths.
 function passage(A,B,baseRadius){
  const start=A.y*W+A.x,goal=B.y*W+B.x,h=new Heap(),costs=new Map([[start,0]]),parent=new Map();h.push(start,0);let found=false;
  while(h.length){const[i,priority]=h.pop(),v=costs.get(i),x=i%W,y=(i/W)|0;if(priority>v+Math.hypot(x-B.x,y-B.y)*.75+.001&&i!==start)continue;if(i===goal){found=true;break;}
   for(const[dx,dy]of [[1,0],[-1,0],[0,1],[0,-1],[1,1],[-1,1],[1,-1],[-1,-1]]){const xx=x+dx,yy=y+dy,j=yy*W+xx;if(!inside(xx,yy)||hardClearance[j]<baseRadius+2||zones[j]!==A.cluster+1||zoneDepth[j]<baseRadius+2)continue;const step=Math.hypot(dx,dy)*(.8+detail(xx,yy)*1.1+fine(xx,yy)*.3),nv=v+step;
    if(nv<(costs.get(j)??Infinity)){costs.set(j,nv);parent.set(j,i);h.push(j,nv+Math.hypot(xx-B.x,yy-B.y)*.75);}}
  }
  if(!found)return false;const trace=[];for(let i=goal;;i=parent.get(i)){trace.push([i%W,Math.floor(i/W)]);if(i===start)break;}trace.reverse();naturalLines.push(trace);
  for(let k=0;k<trace.length;k++){const[x,y]=trace[k],r=baseRadius*(.72+.5*detail(x,y))+.5*Math.sin(k*.09);bore(x,y,r,2,A.cluster);}return true;
 }
 let successfulLinks=0;for(const p of links)if(passage(nodes[p.a],nodes[p.b],ri(5,8)))successfulLinks++;
 // Blind side passages make ends and branches without opening entire regions.
 for(let n=0;n<Math.round(nodes.length*.30);n++){const a=nodes[ri(0,nodes.length-1)],angle=R()*Math.PI*2,len=ri(18,Math.round(spacing*.8)),b={x:Math.round(a.x+Math.cos(angle)*len),y:Math.round(a.y+Math.sin(angle)*len),cluster:a.cluster};if(inside(b.x,b.y)&&hardClearance[b.y*W+b.x]>7&&zones[b.y*W+b.x]===a.cluster+1)passage(a,b,ri(3,5));}
 // A few chambers are local enlargements along the passages, not a continuous noise mask.
 const chambers=[];const candidates=[...nodes].sort((a,b)=>Math.hypot(a.x-W/2,a.y-H/2)-Math.hypot(b.x-W/2,b.y-H/2));
 for(let n=0;n<Math.max(4,Math.round(nodes.length*.07));n++){const p=n===0?candidates[0]:nodes[ri(0,nodes.length-1)];if(!geology[p.y*W+p.x]||chambers.some(c=>Math.hypot(c.x-p.x,c.y-p.y)<spacing))continue;const radius=n===0?Math.min(23,W*.032):ri(9,18);bore(p.x,p.y,radius,1,p.cluster);bore(p.x+radius*.45,p.y-radius*.25,radius*.7,1,p.cluster);chambers.push({x:p.x,y:p.y,radius});}
 // More isolated chambers, separated from every existing void by a solid-rock buffer.
 let pockets=0;const pocketTarget=Math.round(12+W/80),pocketSites=[];
 for(let k=0;k<1800&&pockets<pocketTarget;k++){const radius=ri(5,11),x=ri(24,W-25),y=ri(24,H-25),gap=radius+7;if(hardClearance[y*W+x]<radius+3)continue;let nearby=false;
  for(let yy=y-gap;yy<=y+gap&&!nearby;yy++)for(let xx=x-gap;xx<=x+gap;xx++)if(geology[yy*W+xx]){nearby=true;break;}
  if(!nearby){bore(x,y,radius,1);bore(x+radius*.25,y-radius*.3,radius*.7,1);pocketSites.push({x,y,radius});pockets++;}
 }
 const caveSeen=new Uint8Array(N),caveQueue=new Int32Array(N),caveComponents=[];for(let i=0;i<N;i++)if(geology[i]&&!caveSeen[i]){let h=0,t=0;caveQueue[t++]=i;caveSeen[i]=1;while(h<t){const j=caveQueue[h++];for(const n of adjacent(j))if(n>=0&&geology[n]&&!caveSeen[n]){caveSeen[n]=1;caveQueue[t++]=n;}}caveComponents.push(t);}caveComponents.sort((a,b)=>b-a);
 const caveDistance=distance(Uint8Array.from(geology,v=>!v));
 const voidDepth=distance(geology),safeRock=distance(Uint8Array.from(rock,t=>t!==3));
 let origin=0,best=-Infinity;for(let y=Math.floor(H*.22);y<H*.78;y++)for(let x=Math.floor(W*.22);x<W*.78;x++){const i=y*W+x;if(!geology[i])continue;const score=Math.min(voidDepth[i],45)-.12*Math.hypot(x-W/2,y-H/2);if(score>best){origin=i;best=score;}}
 if(best===-Infinity)throw Error('此地质种子没有可供建立聚落的天然空间');
 const ox=origin%W,oy=(origin/W)|0,cost=new Float64Array(N),heap=new Heap();cost.fill(Infinity);cost[origin]=0;heap.push(origin,0);
 const developed=new Uint8Array(N),target=Math.round(N*.30);let count=0,lastCost=0;
 while(heap.length&&count<target){const[i,v]=heap.pop();if(v!==cost[i]||developed[i])continue;developed[i]=1;growth[i]=1+Math.min(2,Math.floor(count/(target/3)));count++;lastCost=v;
  for(const[dx,dy]of [[1,0],[-1,0],[0,1],[0,-1],[1,1],[-1,1],[1,-1],[-1,-1]]){const x=i%W+dx,y=((i/W)|0)+dy,j=y*W+x;if(!inside(x,y)||safeRock[j]<5)continue;const radial=Math.hypot(x-ox,y-oy)/W,edge=Math.min(x,W-x,y,H-y)/Math.min(W,H);
   const nearTunnel=Math.min(1,caveDistance[j]/32),resistance=geology[j]?.55:rock[j]===2?3.4:1.0+nearTunnel*1.8;const step=resistance*(.65+detail(x,y)) + radial*.7 + Math.max(0,.13-edge)*32;const nv=v+step*Math.hypot(dx,dy);if(nv<cost[j]){cost[j]=nv;heap.push(j,nv);}}
 }
 // Remove unbuildably thin exploration tendrils; retain the broad connected settlement.
 const depth=distance(developed),core=Uint8Array.from(depth,d=>d>=7),reach=distance(Uint8Array.from(core,v=>!v));
 const candidate=Uint8Array.from(developed,(v,i)=>v&&reach[i]<=6?1:0),seen=new Uint8Array(N),q=new Int32Array(N);let head=0,tail=0;
 q[tail++]=origin;seen[origin]=1;while(head<tail){const i=q[head++];cityMask[i]=ground[i]=1;if(!geology[i])excavation[i]=1;for(const j of adjacent(i))if(j>=0&&candidate[j]&&!seen[j]){seen[j]=1;q[tail++]=j;}}
 // A corner-touching frontier cell becomes usable only after a four-neighbour approach exists.
 for(let stage=1;stage<=2;stage++){seen.fill(0);head=0;tail=0;q[tail++]=origin;seen[origin]=1;while(head<tail){const i=q[head++];for(const j of adjacent(i))if(j>=0&&cityMask[j]&&growth[j]<=stage&&!seen[j]){seen[j]=1;q[tail++]=j;}}for(let i=0;i<N;i++)if(cityMask[i]&&growth[i]<=stage&&!seen[i])growth[i]=stage+1;}
 const cityDepth=distance(cityMask);

 // Single-bubble railway. These two sockets are preview fixtures, not colony topology.
 const railwayClearance=distance(Uint8Array.from(rock,v=>v!==3),false),railMask=new Uint8Array(N);
 let stationCell=origin,stationScore=Infinity,meanX=0,meanY=0,cityCount=0;
 for(let i=0;i<N;i++)if(cityMask[i]){meanX+=i%W;meanY+=(i/W)|0;cityCount++;}meanX/=cityCount;meanY/=cityCount;
 for(let y=24;y<H-24;y++)for(let x=28;x<W-28;x++){const i=y*W+x;if(cityDepth[i]<28||railwayClearance[i]<24)continue;let fits=true;for(let xx=x-30;xx<=x+30;xx+=3)if(railwayClearance[y*W+xx]<22){fits=false;break;}if(!fits)continue;const score=Math.hypot(x-(meanX+W*.025),y-(meanY-H*.02));if(score<stationScore){stationScore=score;stationCell=i;}}
 if(!Number.isFinite(stationScore))throw Error('城区没有能容纳中心车站的位置');
 const sx=stationCell%W,sy=(stationCell/W)|0,station={id:'ST1',name:'泡内中央车站',x:sx,y:sy,w:42,h:12,platformCells:[],role:'bubble-hub'};
 for(let y=sy-6;y<sy+6;y++)for(let x=sx-21;x<sx+21;x++){const i=y*W+x;station.platformCells.push(i);ground[i]=streetMask[i]=1;if(!geology[i])excavation[i]=3;}
 function socket(side,fraction){const x=side==='west'?5:W-5;let best=null,score=Infinity;for(let y=24;y<H-24;y++){let ok=true;for(let xx=side==='west'?5:W-30;xx<=(side==='west'?30:W-5);xx++)if(railwayClearance[y*W+xx]<22){ok=false;break;}if(ok&&Math.abs(y-H*fraction)<score){score=Math.abs(y-H*fraction);best={id:'P'+(portals.length+1),name:(side==='west'?'西':'东')+'侧预览接口',x,y,direction:side,source:'preview-fixture'};}}if(!best)throw Error('预览接口没有足够的铁路通道净空');portals.push(best);return best;}
 const west=socket('west',.43),east=socket('east',.63);
 const railAllowed=(x,y)=>inside(Math.floor(x),Math.floor(y))&&railwayClearance[Math.floor(y)*W+Math.floor(x)]>=18;
 function railPath(A,B){const start=A[1]*W+A[0],goal=B[1]*W+B[0],costs=new Float64Array(N),parent=new Int32Array(N),heap=new Heap();costs.fill(Infinity);parent.fill(-1);costs[start]=0;heap.push(start,0);
  while(heap.length){const[i,p]=heap.pop(),x=i%W,y=(i/W)|0,v=costs[i];if(i!==start&&p>v+Math.hypot(x-B[0],y-B[1])*.7+.001)continue;if(i===goal)break;for(const[dx,dy]of [[1,0],[-1,0],[0,1],[0,-1],[1,1],[-1,1],[1,-1],[-1,-1]]){const xx=x+dx,yy=y+dy,j=yy*W+xx;if(!railAllowed(xx,yy))continue;const nv=v+Math.hypot(dx,dy)*(cityMask[j]?.8:geology[j]?1.1:rock[j]===2?2.5:1.5);if(nv<costs[j]){costs[j]=nv;parent[j]=i;heap.push(j,nv+Math.hypot(xx-B[0],yy-B[1])*.7);}}}
  if(!Number.isFinite(costs[goal]))throw Error('车站与预览接口之间无法安排铁路 '+JSON.stringify({A,B,start:railwayClearance[start],end:railwayClearance[goal]}));const raw=[];for(let i=goal;;i=parent[i]){raw.push([i%W,(i/W)|0]);if(i===start)break;}raw.reverse();
  const clear=(a,b)=>{const steps=Math.ceil(Math.hypot(b[0]-a[0],b[1]-a[1]));for(let n=0;n<=steps;n++){const t=n/Math.max(1,steps);if(!railAllowed(a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t))return false;}return true;};
  const out=[raw[0]];let i=0;while(i<raw.length-1){let next=raw.length-1;while(next>i+1&&!clear(raw[i],raw[next]))next--;out.push(raw[next]);i=next;}for(let k=1;k<out.length-1;){const a=out[k-1],b=out[k],c=out[k+1];let ok=Math.min(Math.hypot(b[0]-a[0],b[1]-a[1]),Math.hypot(c[0]-b[0],c[1]-b[1]))<28;if(ok){const n=Math.ceil(Math.hypot(c[0]-a[0],c[1]-a[1]));for(let j=0;j<=n;j++){const t=j/Math.max(1,n),x=Math.floor(a[0]+(c[0]-a[0])*t),y=Math.floor(a[1]+(c[1]-a[1])*t);if(railwayClearance[y*W+x]<12){ok=false;break;}}}if(ok){out.splice(k,1);k=Math.max(1,k-1);}else k++;}return out;
 }
 const left=railPath([30,west.y],[sx-26,sy]),right=railPath([sx+26,sy],[W-30,east.y]);
 const control=[[west.x,west.y],...left,[sx+26,sy],...right.slice(1),[east.x,east.y]];
 // Collapse short hooks that would force an implausibly tight double-track bend.
 for(let k=1;k<control.length-1;){const a=control[k-1],b=control[k],c=control[k+1],la=Math.hypot(b[0]-a[0],b[1]-a[1]),lb=Math.hypot(c[0]-b[0],c[1]-b[1]),dot=((b[0]-a[0])*(c[0]-b[0])+(b[1]-a[1])*(c[1]-b[1]))/(la*lb),angle=Math.acos(Math.max(-1,Math.min(1,dot))),radius=Math.min(40,la*.45,lb*.45)/Math.tan(angle/2);let clear=radius<8;
  if(clear){const count=Math.ceil(Math.hypot(c[0]-a[0],c[1]-a[1]));for(let j=0;j<=count;j++){const t=j/Math.max(1,count),x=Math.floor(a[0]+(c[0]-a[0])*t),y=Math.floor(a[1]+(c[1]-a[1])*t);if(railwayClearance[y*W+x]<10){clear=false;break;}}}
  if(clear){control.splice(k,1);k=Math.max(1,k-1);}else k++;
 }
 // Round each vertex with tangent-continuous circular arcs, then sample the shared centreline.
 const smooth=[],append=p=>{if(!smooth.length||Math.hypot(p[0]-smooth.at(-1)[0],p[1]-smooth.at(-1)[1])>.001)smooth.push(p);};
 function segment(a,b){const len=Math.hypot(b[0]-a[0],b[1]-a[1]),n=Math.max(1,Math.ceil(len/.6));for(let k=1;k<=n;k++)append([a[0]+(b[0]-a[0])*k/n,a[1]+(b[1]-a[1])*k/n]);}
 append(control[0]);for(let k=1;k<control.length-1;k++){const a=control[k-1],b=control[k],c=control[k+1],la=Math.hypot(b[0]-a[0],b[1]-a[1]),lb=Math.hypot(c[0]-b[0],c[1]-b[1]),trim=Math.min(40,la*.45,lb*.45),u=[(b[0]-a[0])/la,(b[1]-a[1])/la],v=[(c[0]-b[0])/lb,(c[1]-b[1])/lb],dot=Math.max(-1,Math.min(1,u[0]*v[0]+u[1]*v[1]));
  if(dot>.99999){segment(smooth.at(-1),b);continue;}const turn=Math.sign(u[0]*v[1]-u[1]*v[0]),angle=Math.acos(dot),radius=trim/Math.tan(angle/2),entry=[b[0]-u[0]*trim,b[1]-u[1]*trim],center=[entry[0]-u[1]*turn*radius,entry[1]+u[0]*turn*radius],theta=Math.atan2(entry[1]-center[1],entry[0]-center[0]);segment(smooth.at(-1),entry);const count=Math.max(1,Math.ceil(radius*angle/.5));for(let n=1;n<=count;n++){const t=theta+turn*angle*n/count;append([center[0]+Math.cos(t)*radius,center[1]+Math.sin(t)*radius]);}}
 segment(smooth.at(-1),control.at(-1));
 // Include the exact station point in its straight platform segment.
 let hub=0,hubDist=Infinity;for(let k=0;k<smooth.length;k++){const d=Math.hypot(smooth[k][0]-sx,smooth[k][1]-sy);if(d<hubDist){hubDist=d;hub=k;}}smooth[hub]=[sx,sy];
 let firstUrban=smooth.findIndex(([x,y])=>cityMask[Math.floor(y)*W+Math.floor(x)]),lastUrban=smooth.length-1;while(lastUrban>hub&&!cityMask[Math.floor(smooth[lastUrban][1])*W+Math.floor(smooth[lastUrban][0])])lastUrban--;
 firstUrban=Math.min(firstUrban,hub-1);lastUrban=Math.max(lastUrban,hub+1);
 function swept(points,radius){const cells=new Set();for(let k=1;k<points.length;k++){const a=points[k-1],b=points[k],dx=b[0]-a[0],dy=b[1]-a[1],den=dx*dx+dy*dy;for(let y=Math.floor(Math.min(a[1],b[1])-radius);y<=Math.ceil(Math.max(a[1],b[1])+radius);y++)for(let x=Math.floor(Math.min(a[0],b[0])-radius);x<=Math.ceil(Math.max(a[0],b[0])+radius);x++){if(!inside(x,y))continue;const t=den?Math.max(0,Math.min(1,((x+.5-a[0])*dx+(y+.5-a[1])*dy)/den)):0;if(Math.hypot(x+.5-a[0]-t*dx,y+.5-a[1]-t*dy)<radius)cells.add(y*W+x);}}return[...cells];}
 for(const spec of [{name:'西侧泡间接入',scope:'interbubble',points:smooth.slice(0,firstUrban+1)},{name:'泡内贯通线',scope:'internal',points:smooth.slice(firstUrban,lastUrban+1)},{name:'东侧泡间接出',scope:'interbubble',points:smooth.slice(lastUrban)}]){
  const cells=swept(spec.points,2),corridor=swept(spec.points,4);for(const i of corridor){if(rock[i]===3)throw Error('铁路曲线侵入保留岩体');ground[i]=streetMask[i]=1;if(!geology[i])excavation[i]=3;}for(const i of cells)railMask[i]=1;
  let length=0;for(let k=1;k<spec.points.length;k++)length+=Math.hypot(spec.points[k][0]-spec.points[k-1][0],spec.points[k][1]-spec.points[k-1][1]);roads.push({id:'S'+(roads.length+1),name:'电车共用主街',kind:'main',scope:'tram-street',width:8,points:spec.points,center:spec.points,cells:corridor});tram.push({...spec,widthMetres:4,trackOffsets:[-1,1],cells,lengthMetres:Math.round(length),stops:spec.scope==='internal'?[{id:station.id,x:sx,y:sy,name:station.name}]:[]});
 }
 function addRegion(x,y,program,name){const r={id:'D'+(regions.length+1),x,y,w:100,h:90,left:x-50,top:y-45,program,name,security:program==='oldtown'?'较弱':'正常',history:program==='oldtown'?'初期开凿区，沿既有设施逐步增建':'城市扩张后配置的专业服务',category:['transport','production','industry'].includes(program)?'industry':program==='hospital'?'civic':program==='services'?'commerce':'housing'};regions.push(r);return r;}
 addRegion(ox,oy,'oldtown','最初聚落与旧街');
 // Plan complete construction projects beside the connected transport network.
 const plannedMask=new Uint8Array(N),informalMask=new Uint8Array(N),configs=[['planned_housing','公司宿舍综合体'],['hospital','公司医院综合体'],['production','机加工与装配厂'],['transport','物流综合体'],['production','精密零件厂'],['production','设备翻修工场']];
 const normals={north:[0,-1],east:[1,0],south:[0,1],west:[-1,0]};
 function accessField(){const obstacle=Uint8Array.from(rock,(v,i)=>v!==3&&!protectedCells[i]?1:0),clear=distance(obstacle),parent=new Int32Array(N),dist=new Int32Array(N);parent.fill(-1);dist.fill(-1);let h=0,t=0;for(let i=0;i<N;i++)if(streetMask[i]&&clear[i]>=3){parent[i]=i;dist[i]=0;q[t++]=i;}while(h<t){const i=q[h++];for(const j of adjacent(i))if(j>=0&&dist[j]<0&&clear[j]>=3&&inside(j%W,(j/W)|0)){parent[j]=i;dist[j]=dist[i]+1;q[t++]=j;}}return{parent,dist};}
 function doorAnchor(plan,d,ox,oy,depth=4){const n=normals[d.front],ix=ox+d.x-(n[0]>0?1:0),iy=oy+d.y-(n[1]>0?1:0);return{x:ix+n[0]*depth,y:iy+n[1]*depth,n,ix,iy};}
 let factoryIndex=0;
 for(const[program,kind]of configs){let chosen=null;const variant=program==='production'?factoryIndex++%3:ri(0,2),field=accessField();
  for(const factor of [1,.83,.68]){
   const spec={id:'K'+(blocks.length+1),kind,program,variant,designSeed:seed+'-'+kind,scale:Math.min(1,W/750)*factor},plan=Complexes.complex(spec),local=new Set();for(const r of plan.rooms)for(let y=r.y;y<r.y+r.h;y++)for(let x=r.x;x<r.x+r.w;x++)local.add(y*plan.w+x);const footprint=[...local].map(i=>[i%plan.w,Math.floor(i/plan.w)]);const ranked=[];
   const primary={x:plan.entry[0],y:plan.entry[1],front:plan.front,width:1,role:'人员入口'};
   for(let y=12;y<H-plan.h-12;y+=7)for(let x=12;x<W-plan.w-12;x+=7){const anchor=doorAnchor(plan,primary,x,y),ai=anchor.y*W+anchor.x;if(field.dist[ai]<0||field.dist[ai]>W*.22)continue;let valid=true,natural=0;
    for(const[xx,yy]of footprint){const i=(y+yy)*W+x+xx;if(!cityMask[i]||protectedCells[i]||streetMask[i]||hardClearance[i]<5){valid=false;break;}natural+=!!geology[i];}
    if(!valid)continue;for(const d of [primary,...plan.exits]){const a=doorAnchor(plan,d,x,y);if(!inside(a.x,a.y)||field.dist[a.y*W+a.x]<0){valid=false;break;}}if(!valid)continue;
    const spacing=Math.min(...regions.map(r=>Math.hypot(x+plan.w/2-r.x,y+plan.h/2-r.y))),score=spacing*.23-field.dist[ai]*.75+natural/footprint.length*14;
    ranked.push({score,...spec,plan,x,y,w:plan.w,h:plan.h,footprint,primary,method:'complex'});
   }
   ranked.sort((a,b)=>b.score-a.score);for(const candidate of ranked.slice(0,18)){const cells=candidate.footprint.map(([x,y])=>(candidate.y+y)*W+candidate.x+x);for(const i of cells)protectedCells[i]=1;const access=accessField();const valid=[candidate.primary,...candidate.plan.exits].every(d=>{const a=doorAnchor(candidate.plan,d,candidate.x,candidate.y);return access.dist[a.y*W+a.x]>=0;});for(const i of cells)protectedCells[i]=0;if(valid){chosen=candidate;break;}}if(chosen)break;
  }
  if(!chosen)continue;const b=chosen;b.cells=b.footprint.map(([x,y])=>(b.y+y)*W+b.x+x);delete b.footprint;const set=new Set(b.cells);b.outline=[];
  for(const i of b.cells){const x=i%W,y=Math.floor(i/W);if(!set.has(i-1))b.outline.push([x,y,x,y+1]);if(!set.has(i+1))b.outline.push([x+1,y,x+1,y+1]);if(!set.has(i-W))b.outline.push([x,y,x+1,y]);if(!set.has(i+W))b.outline.push([x,y+1,x+1,y+1]);protectedCells[i]=1;ground[i]=cityMask[i]=1;if(!growth[i])growth[i]=3;if(!geology[i])excavation[i]=2;}
  b.accessRoadIds=[];blocks.push(b);const r=addRegion(b.x+b.plan.entry[0],b.y+b.plan.entry[1]-3,program,kind+'周边');b.district=r.id;
  for(const d of [b.primary,...b.plan.exits]){const a=doorAnchor(b.plan,d,b.x,b.y),f=accessField(),start=a.y*W+a.x;if(f.dist[start]<0)throw Error('设施外门没有合理接路 '+kind+' '+d.role);const path=[];for(let i=start;;i=f.parent[i]){path.push([i%W,Math.floor(i/W)]);if(f.parent[i]===i)break;}
   for(const[x,y]of path)for(let yy=y-2;yy<=y+2;yy++)for(let xx=x-2;xx<=x+2;xx++){const i=yy*W+xx;if(inside(xx,yy)&&!protectedCells[i]&&rock[i]!==3){ground[i]=1;if(!geology[i])excavation[i]=3;}}
   if(path.length>1){road(path.reverse(),5,kind+'接入街','project-access');Object.assign(roads.at(-1),{servesProject:b.id,purpose:d.role});b.accessRoadIds.push(roads.at(-1).id);}
   const apron=[];for(let depth=1;depth<=4;depth++)apron.push([a.ix+a.n[0]*depth,a.iy+a.n[1]*depth]);for(const[x,y]of apron)for(let yy=y-1;yy<=y+1;yy++)for(let xx=x-1;xx<=x+1;xx++){const i=yy*W+xx;if(inside(xx,yy)&&!protectedCells[i]&&rock[i]!==3){ground[i]=1;if(!geology[i])excavation[i]=3;}}
   road(apron,3,kind+'入口通路','project-access');Object.assign(roads.at(-1),{servesProject:b.id,purpose:d.role});b.accessRoadIds.push(roads.at(-1).id);
   if(d.width>=3){const cells=[];for(let depth=1;depth<=7;depth++)for(let offset=-2;offset<=d.width+1;offset++){const x=a.ix+a.n[0]*depth+(a.n[0]===0?offset:0),y=a.iy+a.n[1]*depth+(a.n[1]===0?offset:0),i=y*W+x;if(inside(x,y)&&!protectedCells[i]&&rock[i]!==3){ground[i]=1;cells.push(i);if(!geology[i])excavation[i]=2;}}spaces.push({id:'C'+(spaces.length+1),name:kind+' '+d.role+'作业区',purpose:'收发货与短暂停放',cells:[...new Set(cells)],x:a.x-4,y:a.y-4,w:9,h:9,service:true,projectId:b.id});}
  }
  // The protected planning envelope follows the assembled volumes and their access streets.
  for(const i of b.cells){const x=i%W,y=Math.floor(i/W);for(let yy=Math.max(4,y-18);yy<=Math.min(H-5,y+18);yy++)for(let xx=Math.max(4,x-18);xx<=Math.min(W-5,x+18);xx++)if(cityMask[yy*W+xx]&&Math.abs(xx-x)+Math.abs(yy-y)<=22)plannedMask[yy*W+xx]=1;}
  for(const rd of roads.filter(rd=>rd.servesProject===b.id))for(const i of rd.cells){plannedMask[i]=1;for(const j of adjacent(i))if(j>=0)plannedMask[j]=1;}
  for(const sp of spaces.filter(sp=>sp.projectId===b.id))for(const i of sp.cells)plannedMask[i]=1;
 }
 for(const [program,name]of [['industry','私营维修与配件街'],['services','生活服务街']]){let pos=origin,score=-1;for(let y=10;y<H-10;y+=7)for(let x=10;x<W-10;x+=7){const i=y*W+x;if(cityDepth[i]<18||protectedCells[i])continue;const s=Math.min(...regions.map(r=>Math.hypot(x-r.x,y-r.y)));if(s>score){score=s;pos=i;}}addRegion(pos%W,Math.floor(pos/W),program,name);}
 for(let i=0;i<N;i++)if(cityMask[i]&&!plannedMask[i])informalMask[i]=1;
 const nearest=(x,y)=>regions.reduce((a,b)=>Math.hypot(x-a.x,y-a.y)<Math.hypot(x-b.x,y-b.y)?a:b);
 const clearance=new Uint8Array(N);for(let y=4;y<H-4;y++)for(let x=4;x<W-4;x++){let ok=true;for(let yy=y-2;yy<=y+2&&ok;yy++)for(let xx=x-2;xx<=x+2;xx++)if(!ground[yy*W+xx]||protectedCells[yy*W+xx]){ok=false;break;}clearance[y*W+x]=ok?1:0;}
 function raster(a,b){const out=[];let[x,y]=a;while(x!==b[0]||y!==b[1]){out.push([x,y]);if(x!==b[0])x+=Math.sign(b[0]-x);else y+=Math.sign(b[1]-y);}out.push([x,y]);return out;}
 function road(center,width,name,kind='lane',scope='engineered'){
  if(center.length<2)return;const points=[center[0]];for(let i=1;i<center.length-1;i++){const a=center[i-1],b=center[i],c=center[i+1];if(b[0]-a[0]!==c[0]-b[0]||b[1]-a[1]!==c[1]-b[1])points.push(b);}points.push(center[center.length-1]);
  const low=Math.floor(width/2),high=width-low-1,cells=new Set();for(const[x,y]of center)for(let yy=y-low;yy<=y+high;yy++)for(let xx=x-low;xx<=x+high;xx++)if(inside(xx,yy)&&ground[yy*W+xx]&&!protectedCells[yy*W+xx]){streetMask[yy*W+xx]=1;cells.add(yy*W+xx);}
  roads.push({id:'S'+(roads.length+1),center,points,width,name,kind,scope,cells:[...cells]});
 }
 // A small number of streets inherit genuine natural fissures, snapped to floor cells.
 const inherited=[];for(const trace of naturalLines){let run=[];const cells=[];for(let k=1;k<trace.length;k++)cells.push(...raster(trace[k-1],trace[k]).slice(1));for(const p of [...cells,null]){let ok=!!p;if(p){const[x,y]=p;ok=!!clearance[y*W+x];for(let yy=y-1;yy<=y+1&&ok;yy++)for(let xx=x-1;xx<=x+1;xx++)if(!geology[yy*W+xx]){ok=false;break;}}if(ok)run.push(p);else{if(run.length>=60)inherited.push(run);run=[];}}}
 inherited.sort((a,b)=>b.length-a.length);for(const path of inherited.slice(0,2))road(path,3,'沿天然裂隙拓宽的旧巷','inherited','natural');

 function clipped(a,b,width,name){let run=[];for(const p of [...raster(a,b),null]){if(p&&clearance[p[1]*W+p[0]]&&plannedMask[p[1]*W+p[0]])run.push(p);else{if(run.length>=14)road(run,width,name);run=[];}}}
 // Local construction bands share street alignments; cross streets vary by band.
 const rows=[];for(let y=ri(15,27);y<H-10;y+=ri(27,39))rows.push(y);
 for(let k=0;k<rows.length;k++)clipped([5,rows[k]],[W-6,rows[k]],ri(4,6),'规划生活街 '+(k+1));
 let prior=[];for(let k=1;k<rows.length;k++){const cols=[];for(let x=ri(18,42);x<W-10;x+=ri(32,59))cols.push(x);if(k%3===0)for(const x of prior.filter((_,i)=>i%2===0))cols.push(x);cols.sort((a,b)=>a-b);let last=-100;for(const x of cols){if(x-last<23)continue;clipped([x,rows[k-1]],[x,rows[k]],ri(3,5),'规划支街');last=x;}prior=cols;}
 // Connect actual street components through buildable floor; endpoints and detours are orthogonal.
 function labels(mask){const label=new Int32Array(N),parts=[];for(let i=0;i<N;i++)if(mask[i]&&!label[i]){const cells=[];let h=0,t=0;q[t++]=i;label[i]=parts.length+1;while(h<t){const k=q[h++];cells.push(k);for(const j of adjacent(k))if(j>=0&&mask[j]&&!label[j]){label[j]=parts.length+1;q[t++]=j;}}parts.push(cells);}return{label,parts};}
 let network=labels(streetMask),main=network.parts.reduce((a,b)=>a.length>b.length?a:b),connected=new Uint8Array(N);for(const i of main)connected[i]=1;
 for(let round=0;round<network.parts.length;round++){
  const parent=new Int32Array(N);parent.fill(-1);head=0;tail=0;for(let i=0;i<N;i++)if(connected[i]&&clearance[i]){q[tail++]=i;parent[i]=i;}let goal=-1;
  while(head<tail&&goal<0){const i=q[head++];for(const j of adjacent(i))if(j>=0&&clearance[j]&&parent[j]<0){parent[j]=i;q[tail++]=j;if(streetMask[j]&&!connected[j]){goal=j;break;}}}
  if(goal<0)break;const path=[];let join=goal;while(!connected[join]){path.push([join%W,(join/W)|0]);join=parent[join];}path.push([join%W,(join/W)|0]);road(path.reverse(),5,'公共联络街');
  head=0;tail=0;q[tail++]=goal;connected[goal]=1;while(head<tail){const i=q[head++];for(const j of adjacent(i))if(j>=0&&streetMask[j]&&!connected[j]){connected[j]=1;q[tail++]=j;}}
 }
 // Drop isolated inaccessible road fragments rather than filling them with unreachable houses.
 for(let i=0;i<N;i++)if(streetMask[i]&&!connected[i])streetMask[i]=0;
 for(let k=roads.length-1;k>=0;k--)if(!roads[k].center.some(([x,y])=>connected[y*W+x]))roads.splice(k,1);
 // A single widened junction serves the earliest inhabited quarter.
 let jp=null,js=Infinity;for(let i=0;i<N;i++)if(streetMask[i]&&cityMask[i]&&streetMask[i-3]&&streetMask[i+3]&&streetMask[i-W*3]&&streetMask[i+W*3]){const d=Math.hypot(i%W-ox,Math.floor(i/W)-oy);if(d<js){js=d;jp=i;}}
 if(jp!==null){const x=jp%W,y=(jp/W)|0,cells=[];for(let yy=y-3;yy<=y+3;yy++)for(let xx=x-3;xx<=x+3;xx++)if(cityMask[yy*W+xx]&&!protectedCells[yy*W+xx])cells.push(yy*W+xx);spaces.push({id:'C1',name:'旧街口候车处',purpose:'路口候车与集散',x:x-3,y:y-3,w:7,h:7,cells});}
 const parcelMask=Uint8Array.from(plannedMask,(v,i)=>v&&ground[i]&&!protectedCells[i]&&!streetMask[i]?1:0);
 for(const cells of labels(parcelMask).parts){if(cells.length<24)continue;let l=W,t=H,r=0,b=0,sx=0,sy=0;for(const i of cells){const x=i%W,y=(i/W)|0;l=Math.min(l,x);r=Math.max(r,x);t=Math.min(t,y);b=Math.max(b,y);sx+=x;sy+=y;}const d=nearest(sx/cells.length,sy/cells.length);blocks.push({id:'K'+(blocks.length+1),district:d.id,kind:{transport:'站前商服街',planned_housing:'宿舍配套住区',industry:'机器人维修与配件街',oldtown:'旧住区增建街块',hospital:'医院配套服务街',production:'厂区配套作坊街',services:'生活服务街块'}[d.program],method:'frontage',program:d.program,x:l,y:t,w:r-l+1,h:b-t+1,cells});}

 const roadIds=new Map(roads.map((r,i)=>[r.id,'S'+(i+1)]));for(const b of blocks)if(b.accessRoadIds)b.accessRoadIds=b.accessRoadIds.filter(id=>roadIds.has(id)).map(id=>roadIds.get(id));roads.forEach((r,i)=>r.id='S'+(i+1));
 const terrainStats={caveSystems:systems.length,caveComponents:caveComponents.length,largestCaveShare:caveComponents[0]/caveComponents.reduce((n,v)=>n+v,0),naturalLoops:loops,caveJunctions:nodes.length,caveLinks:successfulLinks,caveChambers:chambers.length,isolatedPockets:pockets,naturalCells:geology.reduce((n,v)=>n+!!v,0),developedCells:cityMask.reduce((n,v)=>n+v,0),reusedCells:cityMask.reduce((n,v,i)=>n+(v&&!!geology[i]),0),retainedHardRock:rock.reduce((n,v)=>n+(v===3),0),origin:{x:ox,y:oy},growthCost:Math.round(lastCost)};
 return{geology,rock,growth,excavation,ground,cityMask,plannedMask,informalMask,streetMask,roads,tram,portals,station,railMask,regions,blocks,spaces,terrainStats};
}
root.BubblePlanning={plan};if(typeof module!=='undefined')module.exports=root.BubblePlanning;
})(typeof window!=='undefined'?window:globalThis);
