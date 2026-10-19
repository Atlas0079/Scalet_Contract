(function(root){'use strict';
const C=typeof module!=='undefined'?require('./content.js'):root.BubbleContent;
const BLUEPRINTS=typeof module!=='undefined'?require('./blueprints.js'):root.BubbleBlueprints;
const Complexes=typeof module!=='undefined'?require('./complexes.js'):root.BubbleComplexes;
const Planning=typeof module!=='undefined'?require('./planning.js'):root.BubblePlanning;
const {random,inside,items,furnishings}=C;
const catalog={...C.catalog,depot:{label:'电车维修站',category:'industry'},market:{label:'旧市集',category:'commerce'}};
const TILE={VOID:0,GROUND:1,STREET:2,RAIL:3,FLOOR:4,WALL:5,PASSAGE:6,YARD:7,PLAZA:8};
const tileNames=['未开发区域','未铺装地面','街巷','电车轨道','室内地板','占格厚墙','厚墙内通道','共用院地','站前铺地'];
const dirs=[[0,-1],[1,0],[0,1],[-1,0]];
function rotate(x,y,w,h,r){return r===0?[x,y]:r===1?[h-1-y,x]:r===2?[w-1-x,h-1-y]:[y,w-1-x];}
function vertex(x,y,w,h,r){return r===0?[x,y]:r===1?[h-y,x]:r===2?[w-x,h-y]:[y,w-x];}
function rotateEdge(e,w,h,r){const a=vertex(e.x,e.y,w,h,r),b=vertex(e.x+(e.axis==='horizontal'?1:0),e.y+(e.axis==='vertical'?1:0),w,h,r);return{...e,x:Math.min(a[0],b[0]),y:Math.min(a[1],b[1]),axis:r%2?(e.axis==='vertical'?'horizontal':'vertical'):e.axis};}
function compileEdge(p){
 const w=Math.max(...p.rooms.map(r=>r.x+r.w)),h=Math.max(...p.rooms.map(r=>r.y+r.h)),cells=new Uint8Array(w*h),roomAt=new Int16Array(w*h);roomAt.fill(-1);const edges=new Map(),doors=[];
 const key=e=>e.axis+':'+e.x+':'+e.y;
 p.rooms.forEach((q,i)=>{for(let y=q.y;y<q.y+q.h;y++)for(let x=q.x;x<q.x+q.w;x++){if(cells[y*w+x])throw Error('房间重叠 '+p.id);cells[y*w+x]=TILE.FLOOR;roomAt[y*w+x]=i;}for(let x=q.x;x<q.x+q.w;x++)for(const y of [q.y,q.y+q.h]){const e={x,y,axis:'horizontal',kind:'wall'};edges.set(key(e),e);}for(let y=q.y;y<q.y+q.h;y++)for(const x of [q.x,q.x+q.w]){const e={x,y,axis:'vertical',kind:'wall'};edges.set(key(e),e);}});
 for(const [a,b,options={}] of p.links){const A=p.rooms[a],B=p.rooms[b];let e,sides;
  if(A.x+A.w===B.x||B.x+B.w===A.x){const x=A.x+A.w===B.x?B.x:A.x,lo=Math.max(A.y,B.y),hi=Math.min(A.y+A.h,B.y+B.h);if(lo>=hi)throw Error('不相邻 '+p.id);const y=Math.floor((lo+hi-1)/2);e={x,y,axis:'vertical'};sides=[[A.x<B.x?x-1:x,y],[A.x<B.x?x:x-1,y]];}
  else if(A.y+A.h===B.y||B.y+B.h===A.y){const y=A.y+A.h===B.y?B.y:A.y,lo=Math.max(A.x,B.x),hi=Math.min(A.x+A.w,B.x+B.w);if(lo>=hi)throw Error('不相邻 '+p.id);const x=Math.floor((lo+hi-1)/2);e={x,y,axis:'horizontal'};sides=[[x,A.y<B.y?y-1:y],[x,A.y<B.y?y:y-1]];}
  else throw Error('不相邻 '+p.id);
  const span=e.axis==='vertical'?Math.min(A.y+A.h,B.y+B.h)-Math.max(A.y,B.y):Math.min(A.x+A.w,B.x+B.w)-Math.max(A.x,B.x),width=Math.min(options.width||1,span),shift=-Math.floor((width-1)/2);for(let n=0;n<width;n++){const delta=shift+n,d={...e,x:e.x+(e.axis==='horizontal'?delta:0),y:e.y+(e.axis==='vertical'?delta:0),kind:'door',a,b,width,role:options.role||'房间门',opening:p.id+'-'+a+'-'+b,sides:sides.map(q=>[q[0]+(e.axis==='horizontal'?delta:0),q[1]+(e.axis==='vertical'?delta:0)])};edges.set(key(d),d);doors.push(d);}
 }
 const normal=dirs[{north:0,east:1,south:2,west:3}[p.front||'north']],axis=normal[0]?'vertical':'horizontal',ex=p.entry[0],ey=p.entry[1],insideCell=[ex-(normal[0]>0?1:0),ey-(normal[1]>0?1:0)],outsideCell=[insideCell[0]+normal[0],insideCell[1]+normal[1]],entryRoom=roomAt[insideCell[1]*w+insideCell[0]];
 if(entryRoom<0)throw Error('入口未接房间 '+p.id);const d={x:ex,y:ey,axis,kind:'door',a:-1,b:entryRoom,sides:[outsideCell,insideCell]};edges.set(key(d),d);doors.push(d);
 for(const exit of p.exits||[]){const n=dirs[{north:0,east:1,south:2,west:3}[exit.front]],axis=n[0]?'vertical':'horizontal';for(let k=0;k<(exit.width||1);k++){const x=exit.x+(axis==='horizontal'?k:0),y=exit.y+(axis==='vertical'?k:0),inner=[x-(n[0]>0?1:0),y-(n[1]>0?1:0)],outer=[inner[0]+n[0],inner[1]+n[1]],b=roomAt[inner[1]*w+inner[0]];if(b<0||cells[outer[1]*w+outer[0]]&&outer[0]>=0&&outer[0]<w&&outer[1]>=0&&outer[1]<h)throw Error('设施外门位置无效 '+p.id);const d={x,y,axis,kind:'door',a:-1,b,sides:[outer,inner],width:exit.width||1,role:exit.role,opening:p.id+'-exit-'+exit.x+'-'+exit.y};edges.set(key(d),d);doors.push(d);}}
 for(const[a,b]of p.openLinks||[]){const A=p.rooms[a],B=p.rooms[b];if(A.x+A.w===B.x||B.x+B.w===A.x){const x=A.x+A.w===B.x?B.x:A.x;for(let y=Math.max(A.y,B.y);y<Math.min(A.y+A.h,B.y+B.h);y++)edges.delete(key({axis:'vertical',x,y}));}else{const y=A.y+A.h===B.y?B.y:A.y;for(let x=Math.max(A.x,B.x);x<Math.min(A.x+A.w,B.x+B.w);x++)edges.delete(key({axis:'horizontal',x,y}));}}
 return{...p,w,h,cells,roomAt,edges:[...edges.values()],doors,entryNormal:normal,entryRoom,anchor:insideCell};
}
function compileSolid(p){
 const w=Math.max(...p.rooms.map(r=>r.x+r.w))+1,h=Math.max(...p.rooms.map(r=>r.y+r.h))+1,cells=new Uint8Array(w*h),roomAt=new Int16Array(w*h);roomAt.fill(-1);
 p.rooms.forEach((q,i)=>{for(let y=q.y-1;y<=q.y+q.h;y++)for(let x=q.x-1;x<=q.x+q.w;x++)if(!cells[y*w+x])cells[y*w+x]=TILE.WALL;});
 p.rooms.forEach((q,i)=>{for(let y=q.y;y<q.y+q.h;y++)for(let x=q.x;x<q.x+q.w;x++){if(roomAt[y*w+x]>=0)throw Error('蓝图房间重叠 '+p.id);cells[y*w+x]=TILE.FLOOR;roomAt[y*w+x]=i;}});
 const pairs=new Map();
 for(let y=1;y<h-1;y++)for(let x=1;x<w-1;x++)if(cells[y*w+x]===TILE.WALL){
  for(const [dx,dy,axis] of [[1,0,'vertical'],[0,1,'horizontal']]){let a=roomAt[(y-dy)*w+x-dx],b=roomAt[(y+dy)*w+x+dx];if(a<0||b<0||a===b)continue;const key=[Math.min(a,b),Math.max(a,b)].join(':');if(!pairs.has(key))pairs.set(key,{a,b,axis,spots:[]});pairs.get(key).spots.push([x,y]);}
 }
 const doors=[];const graph=Array.from({length:p.rooms.length},()=>new Set());
 // Door connections are explicitly authored. Toilets never become transit rooms.
 for(const [a,b] of p.links){const pair=pairs.get([Math.min(a,b),Math.max(a,b)].join(':'));if(!pair)throw Error('指定房间不相邻 '+p.id+' '+a+','+b);const [x,y]=pair.spots[Math.floor(pair.spots.length/2)];cells[y*w+x]=TILE.PASSAGE;doors.push({x,y,a:pair.a,b:pair.b,axis:pair.axis,kind:'door',sides:pair.axis==='vertical'?[[x-1,y],[x+1,y]]:[[x,y-1],[x,y+1]]});graph[pair.a].add(pair.b);graph[pair.b].add(pair.a);}
 const [ex,ey]=p.entry,front=p.front||'north',di={north:0,east:1,south:2,west:3}[front],normal=dirs[di];
 const ri=roomAt[(ey-normal[1])*w+ex-normal[0]];if(ri<0)throw Error('入口未接房间 '+p.id);
 cells[ey*w+ex]=TILE.PASSAGE;const entry={x:ex+(normal[0]>0?1:0),y:ey+(normal[1]>0?1:0),a:-1,b:ri,kind:'door',axis:di%2?'vertical':'horizontal',sides:[[ex+normal[0],ey+normal[1]],[ex-normal[0],ey-normal[1]]]};doors.push(entry);
 const seen=new Set([ri]),queue=[ri];for(let k=0;k<queue.length;k++)for(const n of graph[queue[k]])if(!seen.has(n)){seen.add(n);queue.push(n);}if(seen.size!==p.rooms.length)throw Error('蓝图房间不连通 '+p.id);
 return{...p,w,h,cells,roomAt,edges:doors,doors,entry:[entry.x,entry.y],anchor:[ex,ey],entryNormal:normal,entryRoom:ri};
}
const compile=p=>p.wallMode==='solid'?compileSolid(p):compileEdge(p);
const PLANS=[...BLUEPRINTS,...Complexes.extras].map(compile);
function generate(seed='ALYBE-TILES',size=960){
 const R=random(seed),ri=(a,b)=>Math.floor(a+R()*(b-a+1)),pick=a=>a[ri(0,a.length-1)],W=Number(size),H=Math.round(W*.81),cx=Math.floor(W/2),cy=Math.floor(H/2),N=W*H;
 const tiles=new Uint8Array(N),owners=new Int32Array(N),objectAt=new Int32Array(N),roomAt=new Int32Array(N),reserved=new Uint8Array(N),vEdges=new Uint8Array((W+1)*H),hEdges=new Uint8Array(W*(H+1));
 const design=Planning.plan(seed,W,H);
 const world={version:11,seed:String(seed),name:'阿利贝地下城区 · 地质与建设',width:W,height:H,gridSize:1,units:'metres',tileNames,boundary:[],roads:design.roads,tram:design.tram,portals:design.portals,station:design.station,districts:design.regions,blocks:design.blocks,buildings:[],openSpaces:design.spaces,streetObjects:[],catalog,blueprints:[...BLUEPRINTS,...Complexes.extras],assumptions:['单层岩体与空腔；格边墙门、特殊厚墙占格','天然地质以分叉、回环、尽头洞道为主，少量位置扩大成洞室；城市拓宽近处洞道、打通薄岩层并保留难开凿岩体','统一建设区先规划街块；居民自建区由住户与共用通道逐步扩挖，保留未挖岩体','公共空地限于少数路口和明确作业用途，不把剩余地面统一命名为广场','机器人服务普遍；仿生人设施限医院管制区和少量隐蔽诊所']};
 const inBounds=(x,y)=>x>=0&&y>=0&&x<W&&y<H;
 for(let i=0;i<N;i++)if(design.ground[i])tiles[i]=TILE.GROUND;
 function line(a,b){if(a[0]!==b[0]&&a[1]!==b[1])throw Error('工程街段必须正交');const out=[],dx=Math.sign(b[0]-a[0]),dy=Math.sign(b[1]-a[1]);let x=a[0],y=a[1];while(true){out.push([x,y]);if(x===b[0]&&y===b[1])break;x+=dx;y+=dy;}return out;}
 function paintPath(points,width,kind,name){const center=[];for(let i=1;i<points.length;i++)center.push(...line(points[i-1],points[i]));const lo=Math.floor(width/2),hi=width-lo-1,cells=new Set();for(const[x,y]of center)for(let yy=y-lo;yy<=y+hi;yy++)for(let xx=x-lo;xx<=x+hi;xx++)if(inBounds(xx,yy)&&tiles[yy*W+xx]===TILE.GROUND){tiles[yy*W+xx]=TILE.STREET;cells.add(yy*W+xx);}const road={cells:[...cells],id:'S'+(world.roads.length+1),scope:'engineered',name,kind,width,points,center};world.roads.push(road);return road;}
 for(const road of world.roads)for(const i of road.cells)if(tiles[i]===TILE.GROUND)tiles[i]=TILE.STREET;
 for(const i of world.station.platformCells)if(tiles[i]===TILE.GROUND)tiles[i]=TILE.PLAZA;
 for(const route of world.tram)for(const i of route.cells)tiles[i]=TILE.STREET;
 for(let i=0;i<N;i++)if(design.informalMask[i]&&!design.streetMask[i]&&!design.geology[i]){tiles[i]=TILE.VOID;design.excavation[i]=0;}
 for(const space of world.openSpaces)for(const i of space.cells)if(tiles[i]===TILE.GROUND)tiles[i]=TILE.YARD;
 const blockAt=new Int32Array(N);world.blocks.forEach((b,j)=>{if(b.cells)for(const i of b.cells)blockAt[i]=j+1;else for(let y=b.y;y<b.y+b.h;y++)for(let x=b.x;x<b.x+b.w;x++)blockAt[y*W+x]=j+1;});
 function district(x,y){return world.districts.reduce((a,b)=>Math.hypot(x-a.x,y-a.y)<Math.hypot(x-b.x,y-b.y)?a:b);}
 const frontage=[];for(let y=2;y<H-2;y++)for(let x=2;x<W-2;x++)if(tiles[y*W+x]===TILE.STREET){for(let d=0;d<4;d++){const n=dirs[d];if(tiles[(y+n[1])*W+x+n[0]]===TILE.GROUND)frontage.push({x,y,out:d});}}
 const countByType={};let bid=0;
 const rotatedPlans=new Map();
 function rotated(p,r){const key=p.id+':'+r;if(rotatedPlans.has(key))return rotatedPlans.get(key);const w=r%2?p.h:p.w,h=r%2?p.w:p.h,cells=[],rs=[];
  for(let y=0;y<p.h;y++)for(let x=0;x<p.w;x++)if(p.cells[y*p.w+x]){const xy=rotate(x,y,p.w,p.h,r);cells.push({x:xy[0],y:xy[1],tile:p.cells[y*p.w+x],room:p.roomAt[y*p.w+x]});}
  for(const room of p.rooms){const a=rotate(room.x,room.y,p.w,p.h,r),z=rotate(room.x+room.w-1,room.y+room.h-1,p.w,p.h,r);rs.push({...room,x:Math.min(a[0],z[0]),y:Math.min(a[1],z[1]),w:Math.abs(a[0]-z[0])+1,h:Math.abs(a[1]-z[1])+1});}
  const doors=p.doors.map(d=>({...rotateEdge(d,p.w,p.h,r),sides:d.sides.map(q=>rotate(q[0],q[1],p.w,p.h,r))})),entryDoor=doors.find(d=>d.a<0),entry=[entryDoor.x,entryDoor.y],anchor=rotate(...p.anchor,p.w,p.h,r),edges=p.edges.map(e=>rotateEdge(e,p.w,p.h,r));
  const n=p.entryNormal,normal=r===0?n:r===1?[-n[1],n[0]]:r===2?[-n[0],-n[1]]:[n[1],-n[0]];
  const out={w,h,cells,rooms:rs,entry,doors,normal,anchor,edges};rotatedPlans.set(key,out);return out;
 }
 function place(plan,f,setback=1){
  const n=dirs[f.out];let p;for(let r=0;r<4;r++){const q=rotated(plan,r);if(q.normal[0]===-n[0]&&q.normal[1]===-n[1]){p=q;break;}}
  const ax=f.x+n[0]*setback,ay=f.y+n[1]*setback,ox=ax-p.anchor[0],oy=ay-p.anchor[1],ex=ox+p.entry[0],ey=oy+p.entry[1];if(ox<1||oy<1||ox+p.w>=W-1||oy+p.h>=H-1){if(plan.wholeBlock)throw Error('街块越界 '+JSON.stringify({ox,oy,w:p.w,h:p.h,W,H}));return false;}
  if(plan.legalStatus==='非正规'&&district(ox+p.w/2,oy+p.h/2).security!=='较弱')return false;
  for(const q of p.cells){const index=(oy+q.y)*W+ox+q.x,t=tiles[index];if(plan.informal?!design.informalMask[index]:design.informalMask[index])return false;if(t!==TILE.GROUND&&!(plan.informal&&t===TILE.VOID&&design.rock[index]!==3)&&!(q.tile===TILE.WALL&&t===TILE.WALL)){if(plan.wholeBlock)throw Error('街块冲突 '+plan.id+' @ '+(ox+q.x)+','+(oy+q.y)+' tile='+t);return false;}}
  for(const e of p.edges){const x=ox+e.x,y=oy+e.y,old=e.axis==='vertical'?vEdges[y*(W+1)+x]:hEdges[y*W+x];if(old&&(old===2||e.kind==='door'))return false;}
  for(let s=1;s<setback;s++)if(![TILE.GROUND,...(plan.wholeBlock?[TILE.STREET,TILE.YARD]:[])].includes(tiles[(f.y+n[1]*s)*W+f.x+n[0]*s])){if(plan.wholeBlock)throw Error('入口连接冲突 '+JSON.stringify({f,n,setback,tile:tiles[(f.y+n[1]*s)*W+f.x+n[0]*s]}));return false;}
  const b={id:'B'+String(++bid).padStart(4,'0'),type:plan.type,category:catalog[plan.type].category,name:plan.name+' '+((countByType[plan.type]=(countByType[plan.type]||0)+1)),blueprint:plan.id,form:plan.name,special:!!plan.special,wallMode:plan.wallMode,wholeBlock:!!plan.wholeBlock,layout:plan.layout||plan.name,operations:plan.operations||null,construction:plan.informal?'自建扩挖':plan.wholeBlock?'统一建设':'规划沿街',blockId:plan.informal?null:plan.blockId||world.blocks[blockAt[Math.floor(oy+p.h/2)*W+Math.floor(ox+p.w/2)]-1]?.id||null,legalStatus:plan.legalStatus||'正规',x:ox,y:oy,w:p.w,h:p.h,entry:{x:ex,y:ey},entryCell:{x:ax,y:ay},front:['south','west','north','east'][f.out],district:district(ox+p.w/2,oy+p.h/2).id,cells:[],rooms:[],doors:[],edges:[],access:{a:[ex,ey],b:[f.x,f.y]}};
  const baseRoom=world.buildings.reduce((s,b)=>s+b.rooms.length,0);
  p.rooms.forEach((r,i)=>b.rooms.push({...r,id:b.id+'-R'+(i+1),x:ox+r.x,y:oy+r.y,objects:[],reserved:[]}));
  p.doors.forEach(d=>b.doors.push({...d,x:ox+d.x,y:oy+d.y,sides:d.sides.map(q=>[ox+q[0],oy+q[1]]),a:d.a<0?'outside':b.rooms[d.a].id,b:b.rooms[d.b].id}));
  p.edges.forEach(e=>{const edge={x:ox+e.x,y:oy+e.y,axis:e.axis,kind:e.kind};b.edges.push(edge);if(e.axis==='vertical')vEdges[edge.y*(W+1)+edge.x]=e.kind==='door'?2:1;else hEdges[edge.y*W+edge.x]=e.kind==='door'?2:1;});
  for(const q of p.cells){const i=(oy+q.y)*W+ox+q.x;tiles[i]=q.tile;if(plan.informal&&!design.geology[i])design.excavation[i]=4;if(!owners[i])owners[i]=bid;if(q.room>=0)roomAt[i]=baseRoom+q.room+1;b.cells.push(i);}
  for(let s=1;s<setback;s++)tiles[(f.y+n[1]*s)*W+f.x+n[0]*s]=TILE.STREET;
  world.buildings.push(b);return b;
 }
 // Whole-block complexes are designed and excavated before frontage infill.
 for(const block of world.blocks.filter(b=>b.method==='complex')){const raw=block.plan,compiled=compile(raw),normal=compiled.entryNormal,dir=dirs.findIndex(n=>n[0]===-normal[0]&&n[1]===-normal[1]);const f={x:block.x+compiled.anchor[0]+normal[0]*2,y:block.y+compiled.anchor[1]+normal[1]*2,out:dir};const b=place(compiled,f,2);if(!b)throw Error('完整街块无法落位 '+block.id);block.buildingIds=[b.id];block.fillRatio=b.cells.length/(block.w*block.h);block.layout=b.layout;block.operations=b.operations;
  for(const sp of world.openSpaces.filter(s=>s.projectId===block.id))sp.buildingIds=[b.id];
 }

 const region=p=>world.districts.find(d=>d.program===p)||world.districts[world.districts.length-1];
 const targetPrograms=[['school','planned_housing',1],['bathhouse','planned_housing',1],['tram-depot','transport',1],['air-water','production',1],['covered-market','oldtown',1],['community-club','planned_housing',1],['security-post','transport',1],['office-court','transport',1],['recycling-yard','production',1],['robot-service','industry',1],['robot-private','industry',3],['robot-private','oldtown',2],['robot-parts','industry',2],['power-service','industry',1],['robot-salvage','oldtown',1],['food-supply','oldtown',2],['clinic','oldtown',1],['pharmacy','hospital',2]];
 if(R()<.55&&world.blocks.some(b=>b.program==='hospital'))targetPrograms.push(['hidden-android','oldtown',1]);
 world.unplacedServices=[];
 for(const[id,program,count]of targetPrograms){const p=PLANS.find(p=>p.id===id),anchor=region(program);if(!p)throw Error('设施蓝图缺失 '+id);for(let k=0;k<count;k++){const order=frontage.filter(f=>district(f.x,f.y).id===anchor.id).map(f=>({f,score:Math.hypot(f.x-anchor.x,f.y-anchor.y)+R()*8})).sort((a,b)=>a.score-b.score);let built=false;for(const{f}of order)if(place(p,f,1)){built=true;break;}if(!built)world.unplacedServices.push({id,district:anchor.id});}}
 const normalPlans=PLANS.filter(p=>!p.special),frontGaps=[];
 function frontageRuns(){const groups=new Map();
  for(let y=2;y<H-2;y++)for(let x=2;x<W-2;x++)if(tiles[y*W+x]===TILE.STREET)for(let d=0;d<4;d++){
   const n=dirs[d];if(tiles[(y+n[1])*W+x+n[0]]!==TILE.GROUND||design.informalMask[(y+n[1])*W+x+n[0]])continue;const horizontal=d===0||d===2,fixed=horizontal?y:x,pos=horizontal?x:y,key=d+':'+fixed;
   if(!groups.has(key))groups.set(key,{out:d,fixed,horizontal,values:[]});groups.get(key).values.push(pos);
  }
  const runs=[];for(const g of groups.values()){g.values.sort((a,b)=>a-b);let start=g.values[0],prev=start;for(let i=1;i<=g.values.length;i++){const v=g.values[i];if(v!==prev+1){if(prev-start>=5)runs.push({...g,start,end:prev});start=v;}prev=v;}}
  // Streetside rows are laid out as groups, preserving a shared frontage line.
  runs.sort((a,b)=>{const da=a.horizontal?Math.abs(a.fixed-cy):80,db=b.horizontal?Math.abs(b.fixed-cy):80;return da-db||a.fixed-b.fixed||a.start-b.start;});return runs;
 }
 function fillFrontages(infill=false){const runs=frontageRuns();for(const run of runs){let cursor=run.start;const setback=1;
   while(cursor<run.end-4){const px=run.horizontal?cursor:run.fixed,py=run.horizontal?run.fixed:cursor,d=district(px,py),nearRail=world.tram.some(l=>l.stops.some(st=>Math.hypot(px-st.x,py-st.y)<25));let choices;
    const uses={transport:['warehouse','shop','grocery','diner','robot_parts'],planned_housing:['apartment','dorm','grocery','diner','shop','bakery'],industry:['workshop','warehouse','robot_shop','robot_parts','power_shop','salvage','apartment'],oldtown:['apartment','shop','grocery','diner','robot_shop','salvage'],hospital:['pharmacy','shop','grocery','diner','apartment'],production:['warehouse','workshop','power_shop','robot_parts','apartment'],services:['apartment','shop','grocery','diner']};
    choices=normalPlans.filter(p=>(uses[d.program]||uses.services).includes(p.type));
    choices=[...choices];for(let j=choices.length-1;j>0;j--){const k=ri(0,j);[choices[j],choices[k]]=[choices[k],choices[j]];}
    let built=null;for(const plan of choices){const n=dirs[run.out];let p;for(let r=0;r<4;r++){const q=rotated(plan,r);if(q.normal[0]===-n[0]&&q.normal[1]===-n[1]){p=q;break;}}
     const span=run.horizontal?p.w:p.h,offset=run.horizontal?p.anchor[0]:p.anchor[1];if(cursor+span-1>run.end)continue;
     const f={x:run.horizontal?cursor+offset:run.fixed,y:run.horizontal?run.fixed:cursor+offset,out:run.out};built=place(plan,f,setback);if(built){cursor+=span;break;}
    }
    if(!built)cursor++;else if(R()<.09){const gap=3;if(!infill)frontGaps.push({x:run.horizontal?cursor+2:run.fixed,y:run.horizontal?run.fixed:cursor+2,out:run.out});cursor+=gap+1;}
   }
  }
 }
 fillFrontages();
 // A second generation of straight back lanes enters residual space; no random walk or diagonal interpolation.
 const backStarts=[...frontGaps,...frontageRuns().filter(r=>r.end-r.start>13).map(run=>{const pos=ri(run.start+3,run.end-3);return{x:run.horizontal?pos:run.fixed,y:run.horizontal?run.fixed:pos,out:run.out};})];let added=0;
 for(const f of backStarts){if(added>=Math.floor(W/18))break;const start=[f.x,f.y],n=dirs[f.out],limit=ri(18,32);let end=[...start];
  for(let t=1;t<=limit;t++){const x=start[0]+n[0]*t,y=start[1]+n[1]*t;let clear=true;for(let yy=y-1;yy<=y+1;yy++)for(let xx=x-1;xx<=x+1;xx++)if(!inBounds(xx,yy)||![TILE.GROUND,TILE.STREET].includes(tiles[yy*W+xx]))clear=false;if(!clear)break;end=[x,y];}
  if(Math.abs(end[0]-start[0])+Math.abs(end[1]-start[1])>=14){paintPath([start,end],3,'backlane','后排通行巷');added++;}
 }
 fillFrontages(true);
 // In self-built areas, a household proposal creates its own short access passage.
 // Failed house placements restore the tentative excavation; no vacant street blocks are pre-cut.
 const frontier=[];function offer(x,y,d){if(!inBounds(x,y)||tiles[y*W+x]!==TILE.STREET)return;const n=dirs[d],i=(y+n[1])*W+x+n[0];if(design.informalMask[i]&&[TILE.GROUND,TILE.VOID].includes(tiles[i]))frontier.push({x,y,out:d});}
 for(let y=4;y<H-4;y+=3)for(let x=4;x<W-4;x+=3)if(tiles[y*W+x]===TILE.STREET)for(let d=0;d<4;d++)offer(x,y,d);
 const selfPlans=normalPlans.filter(p=>['apartment','shop','workshop','grocery','robot_shop','diner'].includes(p.type)),selfLimit=Math.round(design.informalMask.reduce((n,v)=>n+v,0)/115);let selfBuilt=0,attempts=0;
 while(frontier.length&&selfBuilt<selfLimit&&attempts++<selfLimit*14){
  const index=ri(0,frontier.length-1),f=frontier[index];frontier[index]=frontier.at(-1);frontier.pop();if(tiles[f.y*W+f.x]!==TILE.STREET)continue;
  const width=R()<.78?3:4,lo=Math.floor(width/2),hi=width-lo-1,segments=R()<.45?2:1,path=[[f.x,f.y]],saved=new Map();let x=f.x,y=f.y,d=f.out,valid=true;
  for(let leg=0;leg<segments&&valid;leg++){const len=leg===0?ri(4,15):ri(5,13);if(leg)d=(d+(R()<.5?1:3))%4;for(let step=0;step<len&&valid;step++){x+=dirs[d][0];y+=dirs[d][1];for(let yy=y-lo;yy<=y+hi&&valid;yy++)for(let xx=x-lo;xx<=x+hi;xx++){if(!inBounds(xx,yy)){valid=false;break;}const i=yy*W+xx;if(tiles[i]===TILE.STREET)continue;if(!design.informalMask[i]||design.rock[i]===3||![TILE.GROUND,TILE.VOID].includes(tiles[i])){valid=false;break;}if(!saved.has(i))saved.set(i,tiles[i]);}if(valid)path.push([x,y]);}}
  if(!valid)continue;for(const i of saved.keys())tiles[i]=TILE.STREET;
  let built=null;const order=[...selfPlans];for(let k=order.length-1;k>0;k--){const j=ri(0,k);[order[k],order[j]]=[order[j],order[k]];}for(const p of order){for(const out of [(d+1)%4,(d+3)%4,d]){const normal=dirs[out],edge=(normal[0]+normal[1])>0?hi:lo;built=place({...p,informal:true},{x:x+normal[0]*edge,y:y+normal[1]*edge,out},1);if(built)break;}if(built)break;}
  if(!built){for(const[i,t]of saved)tiles[i]=t;continue;}
  selfBuilt++;built.growthStep=selfBuilt;for(const i of saved.keys()){if(!design.geology[i])design.excavation[i]=4;design.streetMask[i]=1;}
  const points=[path[0]];for(let k=1;k<path.length-1;k++){const a=path[k-1],b=path[k],c=path[k+1];if(b[0]-a[0]!==c[0]-b[0]||b[1]-a[1]!==c[1]-b[1])points.push(b);}points.push(path.at(-1));world.roads.push({id:'S'+(world.roads.length+1),scope:'resident',name:'住户共用出入巷',kind:'self-built',width,center:path,points,cells:[...saved.keys()],serves:[built.id],growthStep:selfBuilt});
  for(let k=1;k<path.length;k+=3){const[xx,yy]=path[k];for(let dir=0;dir<4;dir++)for(let offset=-lo;offset<=hi;offset++){const n=dirs[dir],edge=n[0]+n[1]>0?hi:lo;offer(xx+n[0]*edge+dirs[(dir+1)%4][0]*offset,yy+n[1]*edge+dirs[(dir+1)%4][1]*offset,dir);}}
 }
 for(let wave=0;wave<2;wave++){
  const candidates=[];for(let y=4;y<H-4;y++)for(let x=4;x<W-4;x++)if(tiles[y*W+x]===TILE.STREET)for(let d=0;d<4;d++){const n=dirs[d],i=(y+n[1])*W+x+n[0];if(design.informalMask[i]&&[TILE.GROUND,TILE.VOID].includes(tiles[i]))candidates.push({x,y,out:d});}
  for(let i=candidates.length-1;i>0;i--){const j=ri(0,i);[candidates[i],candidates[j]]=[candidates[j],candidates[i]];}
  for(const f of candidates){for(let attempt=0;attempt<5;attempt++){const b=place({...pick(selfPlans),informal:true},f,1);if(b){b.growthStep=++selfBuilt;b.growthReason='沿既有共用通道增建';break;}}}
 }
 world.growthSummary={selfBuilt,attempts,plannedBuildings:world.buildings.length-selfBuilt};
 // Only facilities with a declared operational need receive a small external yard.
 for(const b of world.buildings.filter(b=>b.type==='depot')){let cells=[];const y=b.y+b.h+1;for(let yy=y;yy<y+4;yy++)for(let x=b.x+1;x<b.x+Math.min(13,b.w-1);x++)if(inBounds(x,yy)&&tiles[yy*W+x]===TILE.GROUND)cells.push(yy*W+x);if(cells.length>=12){for(const i of cells)tiles[i]=TILE.YARD;world.openSpaces.push({id:'C'+(world.openSpaces.length+1),name:b.type==='depot'?'电车作业等候区':'收货与装卸区',purpose:'设施装卸与搬运',cells,x:b.x+1,y,w:12,h:4,buildingIds:[b.id],service:true});}}
 let oid=0;const allObjects=[];
 const fixtures={...furnishings,'卫生间':['toilet','sink','shower'],'起居厨房':['sofa','table','stove','sink','fridge','tv'],'洗手间':['sink'],'清洁间':['shelf','sink'],'接待与候诊':['bench','counter'],'公共门厅':['bench','sign'],'公共过道':[],'市场大厅':['counter','shelf','shelf','shelf','crates','table'],'电车检修库':['tram','workbench','tools','cart'],'检测室':['workbench','monitor','computer'],'机器人维修工位':['robotdock','workbench','tools'],'接单与配件':['counter','shelf','computer'],'配件售货区':['shelf','shelf','counter'],'电子检测':['computer','tools'],'药品售货':['medicine','counter','computer'],'药品库':['medicine','medicine','fridge'],'电源检测':['electric','tools','workbench'],'二手机体陈列':['robotdock','crates'],'拆件工位':['workbench','tools','robotdock'],'仿生人组织修复':['synthbed','monitor','medicine'],'专用耗材库':['medicine','fridge'],'消毒准备':['sink','medicine'],'备品间':['shelf'],'联合加工大厅':['lathe','cutter','robotarm'],'货运分拣大厅':['pallet','cart','shelf'],'材料库':['crates','shelf']};
 // Object footprints are deliberately discrete, rather than fractional-metre rectangles.
 function dimensions(type){const t=items[type];if(type==='tram')return[2,9];if(type==='bunk')return[1,2];if(type==='bed'||type==='medbed')return[1,2];if(type==='doublebed')return[2,2];return[Math.max(1,Math.ceil(t[1])),Math.max(1,Math.ceil(t[2]))];}
 for(const b of world.buildings)for(const r of b.rooms){
  const center=[r.x+Math.floor(r.w/2),r.y+Math.floor(r.h/2)];reserved[center[1]*W+center[0]]=1;
  for(const d of b.doors.filter(d=>d.a===r.id||d.b===r.id)){const near=d.sides[d.a===r.id?0:1];if(near[0]<r.x||near[1]<r.y||near[0]>=r.x+r.w||near[1]>=r.y+r.h)throw Error('门侧未接房间 '+r.id);const bend=[center[0],near[1]];for(const [x,y] of [...line(near,bend),...line(bend,center)]){const pad=d.width>=3?1:0;for(let yy=Math.max(r.y,y-pad);yy<=Math.min(r.y+r.h-1,y+pad);yy++)for(let xx=Math.max(r.x,x-pad);xx<=Math.min(r.x+r.w-1,x+pad);xx++)reserved[yy*W+xx]=1;}}
  for(let y=r.y;y<r.y+r.h;y++)for(let x=r.x;x<r.x+r.w;x++)if(reserved[y*W+x])r.reserved.push(y*W+x);
  function put(type,x,y,rotation=0){const d=dimensions(type),w=d[rotation?1:0],h=d[rotation?0:1],blocking=type!=='shower';if(x<r.x||y<r.y||x+w>r.x+r.w||y+h>r.y+r.h)return false;
   for(let yy=y;yy<y+h;yy++)for(let xx=x;xx<x+w;xx++)if(blocking&&reserved[yy*W+xx]||objectAt[yy*W+xx]||tiles[yy*W+xx]!==TILE.FLOOR)return false;
   const o={id:'O'+(++oid),type,name:items[type][0],family:items[type][3],x,y,w,h,blocking,rotation:rotation?90:0,roomId:r.id,buildingId:b.id};for(let yy=y;yy<y+h;yy++)for(let xx=x;xx<x+w;xx++)objectAt[yy*W+xx]=oid;r.objects.push(o);allObjects.push(o);return true;
  }
  let wanted=fixtures[r.name]||[];
  if(r.name==='卧室'&&Math.min(r.w,r.h)<=3)wanted=wanted.map(t=>t==='doublebed'?'bed':t);
  if(r.name==='教室'){for(let y=r.y+1;y<r.y+r.h-1;y+=3)for(let x=r.x;x<r.x+r.w-1;x+=3)if(put('desk',x,y))put('chair',x,y+1);wanted=['books'];}
  if(r.name==='市场大厅'||r.name==='货运分拣大厅'){for(let y=r.y+1;y<r.y+r.h-2;y+=4)for(let x=r.x+1;x<r.x+r.w-2;x+=4){put('counter',x,y);put('crates',x,y+1);}wanted=['shelf','cart'];}
  if(['加工车间','联合加工大厅','机加工车间','机加工延伸区'].includes(r.name)){for(let y=r.y;y<r.y+r.h-2;y+=4)for(let x=r.x;x<r.x+r.w-2;x+=5)put((x+y)%2?'lathe':'cutter',x,y);wanted=['workbench','tools'];}
  if(['装配车间','装配与检验'].includes(r.name)){for(let y=r.y+1;y<r.y+r.h-2;y+=4)for(let x=r.x+1;x<r.x+r.w-2;x+=5)put('workbench',x,y);wanted=['robotarm','tools','computer','monitor'];}
  if(['材料准备','收货与分拣','发货整备','货物库房','仓储延伸区','成品暂存'].includes(r.name)){for(let y=r.y+1;y<r.y+r.h-2;y+=5)for(let x=r.x+1;x<r.x+r.w-2;x+=4)put(r.name==='发货整备'?'workbench':'pallet',x,y);wanted=['cart','shelf'];}
  if(r.name==='电车检修库'){put('tram',r.x+2,r.y);put('tram',r.x+r.w-4,r.y);wanted=['workbench','tools','cart'];}
  if(r.name==='公共洗浴'){for(let x=r.x;x<r.x+r.w;x+=2)put('shower',x,r.y);wanted=['sink','toilet'];}
  for(const type of wanted){if(!items[type])continue;let placed=false;const base=dimensions(type);
   for(let attempt=0;attempt<60&&!placed;attempt++){const rotate=attempt%2,w=base[rotate?1:0],h=base[rotate?0:1];if(w>r.w||h>r.h)continue;let x=ri(r.x,r.x+r.w-w),y=ri(r.y,r.y+r.h-h);if(attempt%4===0)x=r.x;if(attempt%4===1)y=r.y;if(attempt%4===2)x=r.x+r.w-w;if(attempt%4===3)y=r.y+r.h-h;
    placed=put(type,x,y,rotate);
   }
   if(!placed&&['bed','doublebed','toilet','sink'].includes(type)){const fallback=type==='doublebed'?'bed':type;for(let y=r.y;y<r.y+r.h&&!placed;y++)for(let x=r.x;x<r.x+r.w&&!placed;x++)for(let rot=0;rot<2&&!placed;rot++)placed=put(fallback,x,y,rot);}
  }
 }
 for(const space of world.openSpaces.filter(s=>s.buildingIds)){
  const types=space.service?['pallet','cart','crates']:['bench','bicycle'];
  for(const type of types){const d=dimensions(type);let done=false;for(let attempt=0;attempt<60&&!done;attempt++){const i=pick(space.cells),x=i%W,y=Math.floor(i/W),ww=d[0],hh=d[1];let clear=true;
    for(let yy=y;yy<y+hh;yy++)for(let xx=x;xx<x+ww;xx++)if(!inBounds(xx,yy)||tiles[yy*W+xx]!==TILE.YARD||objectAt[yy*W+xx])clear=false;
    if(!clear||world.buildings.some(b=>b.doors.some(d=>d.a==='outside'&&Math.abs(d.x-x)+Math.abs(d.y-y)<5)))continue;
    const o={id:'O'+(++oid),type,name:items[type][0],family:items[type][3],x,y,w:ww,h:hh,blocking:true,rotation:0,roomId:null,buildingId:null,spaceId:space.id};for(let yy=y;yy<y+hh;yy++)for(let xx=x;xx<x+ww;xx++)objectAt[yy*W+xx]=oid;allObjects.push(o);world.streetObjects.push(o);done=true;
   }
  }
 }
 const footprint=new Uint8Array(N),queue=new Int32Array(N);let fh=0,ft=0;const start=world.portals[0].y*W+world.portals[0].x;footprint[start]=1;queue[ft++]=start;
 while(fh<ft){const i=queue[fh++],x=i%W,y=(i/W)|0;for(const j of [x?i-1:-1,x<W-1?i+1:-1,y?i-W:-1,y<H-1?i+W:-1])if(j>=0&&tiles[j]&&!footprint[j]){footprint[j]=1;queue[ft++]=j;}}
 world.developmentEnvelope=Array.from(design.cityMask);for(let i=0;i<N;i++){if(!footprint[i]&&!owners[i]&&tiles[i]===TILE.GROUND){tiles[i]=TILE.VOID;design.excavation[i]=0;}design.cityMask[i]=footprint[i]?1:0;}
 design.terrainStats.developedCells=design.cityMask.reduce((n,v)=>n+v,0);design.terrainStats.reusedCells=design.cityMask.reduce((n,v,i)=>n+(v&&!!design.geology[i]),0);
 world.stats={buildings:world.buildings.length,landmarks:world.buildings.filter(b=>b.special).length,layouts:new Set(world.buildings.map(b=>b.blueprint)).size,rooms:world.buildings.reduce((n,b)=>n+b.rooms.length,0),objects:oid,buildingTypes:countByType,openSpaces:world.openSpaces.length};
 world.plannedMask=Array.from(design.plannedMask);world.informalMask=Array.from(design.informalMask);world.rock=Array.from(design.rock);world.growth=Array.from(design.growth);world.terrainStats=design.terrainStats;world.cityMask=Array.from(design.cityMask);world.geology=Array.from(design.geology);world.excavation=Array.from(design.excavation);world.planningSummary={regions:world.districts.length,blockTypes:[...new Set(world.blocks.map(b=>b.kind))],completeComplexes:world.buildings.filter(b=>b.wholeBlock).length,excavatedCells:world.excavation.filter(Boolean).length,internalRailMetres:world.tram.filter(l=>l.scope==='internal').reduce((n,l)=>n+l.lengthMetres,0)};
 world.tiles=Array.from(tiles);world.edges=[];for(let y=0;y<H;y++)for(let x=0;x<=W;x++){const t=vEdges[y*(W+1)+x];if(t)world.edges.push({x,y,axis:'vertical',kind:t===2?'door':'wall'});}for(let y=0;y<=H;y++)for(let x=0;x<W;x++){const t=hEdges[y*W+x];if(t)world.edges.push({x,y,axis:'horizontal',kind:t===2?'door':'wall'});}
 Object.defineProperty(world,'runtime',{value:{tiles,owners,roomAt,objectAt,objects:allObjects,reserved,vEdges,hEdges,blockAt},enumerable:false});
 world.validation=validate(world);return world;
}
function validate(w){const errors=[],W=w.width,H=w.height,N=W*H,t=w.runtime.tiles,objects=w.runtime.objectAt,seen=new Uint8Array(N),queue=new Int32Array(N);let head=0,tail=0;
 const inBoundsDoor=(x,y)=>Number.isInteger(x)&&Number.isInteger(y)&&x>=0&&y>=0&&x<W&&y<H;
 const pass=i=>i>=0&&i<N&&t[i]!==TILE.VOID&&t[i]!==TILE.WALL&&(!objects[i]||!w.runtime.objects[objects[i]-1].blocking);
 const start=w.portals[0].y*W+w.portals[0].x;if(pass(start)){seen[start]=1;queue[tail++]=start;}
 while(head<tail){const i=queue[head++],x=i%W,y=(i/W)|0;const neighbours=[[x?i-1:-1,w.runtime.vEdges[y*(W+1)+x]],[x<W-1?i+1:-1,w.runtime.vEdges[y*(W+1)+x+1]],[y?i-W:-1,w.runtime.hEdges[y*W+x]],[y<H-1?i+W:-1,w.runtime.hEdges[(y+1)*W+x]]];for(const [j,edge] of neighbours)if(edge!==1&&pass(j)&&!seen[j]){seen[j]=1;queue[tail++]=j;}}
 let entries=0,rooms=0;
 for(const b of w.buildings){b.streetReachable=!!seen[b.entryCell.y*W+b.entryCell.x];if(b.streetReachable)entries++;else errors.push('建筑入口不可达 '+b.id);
  for(const d of b.doors.filter(d=>d.a==='outside')){const [x,y]=d.sides[0];if(!inBoundsDoor(x,y)||!seen[y*W+x])errors.push('门外通路不可达 '+b.id+' @ '+d.x+','+d.y);}
  for(const d of b.doors)if((d.axis==='vertical'?w.runtime.vEdges[d.y*(W+1)+d.x]:w.runtime.hEdges[d.y*W+d.x])!==2||!Number.isInteger(d.x)||!Number.isInteger(d.y))errors.push('门边无效 '+b.id);
  for(const r of b.rooms){const center=(r.y+Math.floor(r.h/2))*W+r.x+Math.floor(r.w/2);if(seen[center])rooms++;else errors.push('房间中心不可达 '+r.id);if(r.name==='卫生间'&&r.w*r.h>(b.special?9:6))errors.push('卫生间超出面积限制 '+r.id);
   for(const o of r.objects)if(![o.x,o.y,o.w,o.h].every(Number.isInteger)||o.x<r.x||o.y<r.y||o.x+o.w>r.x+r.w||o.y+o.h>r.y+r.h)errors.push('物件占格无效 '+o.id);
  }
 }
 w.runtime.reachable=seen;
 return{errors,reachableEntrances:entries,reachableRooms:rooms,walkableCells:tail,scope:'四邻域移动同时检查格子和边界；普通墙阻止跨边，厚墙与物件阻格，门边按可通过处理'};
}
root.BubbleGenerator={generate,validate,catalog,items,inside,TILE,plans:PLANS};if(typeof module!=='undefined')module.exports=root.BubbleGenerator;
})(typeof window!=='undefined'?window:globalThis);
