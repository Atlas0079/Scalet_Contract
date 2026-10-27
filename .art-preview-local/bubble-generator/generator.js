(function(root){'use strict';
const C=typeof module!=='undefined'?require('./content.js'):root.BubbleContent;
const Options=typeof module!=='undefined'?require('./options.js'):root.BubbleOptions;
const Planning=typeof module!=='undefined'?require('./planning.js'):root.BubblePlanning;
const {random,inside,items,furnishings}=C;
const Environment=typeof module!=='undefined'?require('./environment.js'):root.BubbleEnvironment;
const catalog={...C.catalog,depot:{label:'电车维修站',category:'industry'},market:{label:'旧市集',category:'commerce'}};
const TILE={VOID:0,GROUND:1,STREET:2,RAIL:3,FLOOR:4,WALL:5,PASSAGE:6,YARD:7,PLAZA:8};
const tileNames=['未开发区域','未铺装地面','街巷','电车轨道','室内地板','占格厚墙','厚墙内通道','共用院地','站前铺地'];
const dirs=[[0,-1],[1,0],[0,1],[-1,0]];
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
 if(entryRoom<0)throw Error('入口未接房间 '+p.id);
 function exterior(x,y,front,width,opening,role){
  const n=dirs[{north:0,east:1,south:2,west:3}[front]],axis=n[0]?'vertical':'horizontal',inner=[x-(n[0]>0?1:0),y-(n[1]>0?1:0)],ri=inner[0]>=0&&inner[1]>=0&&inner[0]<w&&inner[1]<h?roomAt[inner[1]*w+inner[0]]:-1;
  if(ri<0)throw Error('外门未接房间 '+p.id);const room=p.rooms[ri],lo=n[0]?room.y:room.x,hi=n[0]?room.y+room.h:room.x+room.w,at=n[0]?y:x;if(hi-lo<width)throw Error('外门净宽不足 '+p.id);
  const positions=[...new Set([Math.max(lo,Math.min(at,hi-width)),...Array.from({length:hi-lo-width+1},(_,i)=>lo+i)])].sort((a,b)=>Math.abs(a-at)-Math.abs(b-at));
  for(const t of positions){const segments=[];for(let k=0;k<width;k++){const xx=n[0]?x:t+k,yy=n[0]?t+k:y,inside=[xx-(n[0]>0?1:0),yy-(n[1]>0?1:0)],outside=[inside[0]+n[0],inside[1]+n[1]],edge={x:xx,y:yy,axis};
    if(roomAt[inside[1]*w+inside[0]]!==ri||outside[0]>=0&&outside[1]>=0&&outside[0]<w&&outside[1]<h&&cells[outside[1]*w+outside[0]]||!edges.has(key(edge)))break;
    segments.push({...edge,kind:'door',a:-1,b:ri,width,opening,role,sides:[outside,inside]});}
   if(segments.length!==width)continue;for(const d of segments){edges.set(key(d),d);doors.push(d);}return segments;
  }throw Error('无法安排完整外门 '+p.id+' '+width+'米');
 }
 const primary=exterior(ex,ey,p.front||'north',Math.max(C.exteriorMinimum(p),p.entryWidth??C.exteriorWidth(p)),'primary','主入口');
 for(const exit of p.exits||[])exterior(exit.x,exit.y,exit.front,Math.max(C.exteriorMinimum(p,exit.role||'对外出口'),exit.width||2),p.id+'-exit-'+exit.x+'-'+exit.y,exit.role||'对外出口');
 for(const[a,b]of p.openLinks||[]){const A=p.rooms[a],B=p.rooms[b];if(A.x+A.w===B.x||B.x+B.w===A.x){const x=A.x+A.w===B.x?B.x:A.x;for(let y=Math.max(A.y,B.y);y<Math.min(A.y+A.h,B.y+B.h);y++)edges.delete(key({axis:'vertical',x,y}));}else{const y=A.y+A.h===B.y?B.y:A.y;for(let x=Math.max(A.x,B.x);x<Math.min(A.x+A.w,B.x+B.w);x++)edges.delete(key({axis:'horizontal',x,y}));}}
 return{...p,w,h,cells,roomAt,edges:[...edges.values()],doors,entry:[primary[0].x,primary[0].y],entryNormal:normal,entryRoom,anchor:primary[0].sides[1]};
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
 const room=p.rooms[ri],span=normal[0]?room.h:room.w,start=Math.max(normal[0]?room.y:room.x,Math.min(normal[0]?ey:ex,(normal[0]?room.y+room.h:room.x+room.w)-2));if(span<2)throw Error('外门净宽不足 '+p.id);let entry;
 for(let k=0;k<2;k++){const x=normal[0]?ex:start+k,y=normal[0]?start+k:ey,inner=[x-normal[0],y-normal[1]];if(roomAt[inner[1]*w+inner[0]]!==ri)throw Error('外门未接房间 '+p.id);cells[y*w+x]=TILE.PASSAGE;const d={x:x+(normal[0]>0?1:0),y:y+(normal[1]>0?1:0),a:-1,b:ri,kind:'door',axis:di%2?'vertical':'horizontal',width:2,opening:'primary',role:'主入口',sides:[[x+normal[0],y+normal[1]],inner]};doors.push(d);if(!entry)entry=d;}
 const seen=new Set([ri]),queue=[ri];for(let k=0;k<queue.length;k++)for(const n of graph[queue[k]])if(!seen.has(n)){seen.add(n);queue.push(n);}if(seen.size!==p.rooms.length)throw Error('蓝图房间不连通 '+p.id);
 return{...p,w,h,cells,roomAt,edges:doors,doors,entry:[entry.x,entry.y],anchor:[entry.sides[0][0]-normal[0],entry.sides[0][1]-normal[1]],entryNormal:normal,entryRoom:ri};
}
const compile=p=>{for(const r of p.rooms)if(Math.min(r.w,r.h)<C.roomMinimum(r))throw Error('房间净宽不足 '+p.id+' '+r.name+' '+r.w+'×'+r.h);return p.wallMode==='solid'?compileSolid(p):compileEdge(p);};
function generate(seed='ALYBE-TILES',input={},report=()=>{}){
 const options=Options.normalize(input),design=Planning.plan(String(seed),options,compile,report),W=design.width,H=design.height,N=W*H;
 const interiorTotal=design.projects.reduce((n,q)=>n+q.p.rooms.length+1,1);let interiorDone=0;const interiorProgress=detail=>report({phase:'interiors',detail,done:interiorDone,total:interiorTotal});interiorProgress('编译房间与出入口');
 const R=random(seed+'-furnishings'),ri=(a,b)=>Math.floor(a+R()*(b-a+1)),pick=a=>a[ri(0,a.length-1)],tiles=new Uint8Array(N),owners=new Int32Array(N),objectAt=new Int32Array(N),roomAt=new Int32Array(N),reserved=new Uint8Array(N),vEdges=new Uint8Array((W+1)*H),hEdges=new Uint8Array(W*(H+1)),blockAt=new Int32Array(N);
 const world={version:22,seed:String(seed),options,name:'阿利贝地下城 · 规划与生长',width:W,height:H,worldOrigin:design.worldOrigin,gridSize:1,units:'metres',boundary:[],tileNames,roads:design.roads,tram:design.tram,portals:design.portals,station:design.station,districts:design.regions,blocks:design.blocks,buildings:[],openSpaces:design.spaces,streetObjects:[],catalog,history:design.history,demolitions:design.demolitions,planningEvents:design.planningEvents,settlement:design.settlement,warnings:design.warnings,assumptions:['中央车站为完整换乘建筑，适合的出口配为贯通线路，其余可独立终到','原始岩体占主体，少量天然空腔由裂隙与弱岩层共同决定形状','先选择中央车站，再围绕车站完整建设规划街坊；第0年代表规划建设完成','规划街坊的街道、建筑和公共空间共同落位，政府按周期评估后续开发，居民持续扩挖与改建','同一张地图共存岩体内开凿、天然空腔内建设、共用洞厅和混合扩挖','1米格与单层空间；房间尺度和内部连接随用途、地块与建设方式变化','开凿成本与预算使用相对工程量，未模拟完整人口、经济或真实地质演化']};
 const inBounds=(x,y)=>x>=0&&y>=0&&x<W&&y<H;
 function line(a,b){const out=[];let[x,y]=a;while(x!==b[0]||y!==b[1]){out.push([x,y]);if(x!==b[0])x+=Math.sign(b[0]-x);else y+=Math.sign(b[1]-y);}out.push([x,y]);return out;}
 for(let i=0;i<N;i++)if(design.ground[i])tiles[i]=design.streetMask[i]?TILE.STREET:TILE.GROUND;
 for(const space of world.openSpaces)for(const i of space.cells)if(tiles[i]!==TILE.STREET)tiles[i]=space.kind==='foundation'?TILE.WALL:TILE.YARD;
 world.blocks.forEach((b,j)=>{for(const i of b.cells)blockAt[i]=j+1;});
 const countByType={};let roomBase=0;
 for(const q of design.projects){if(q.p.type==='station')countByType.station=(countByType.station||0)+1;const p=q.p,ox=q.x,oy=q.y,id=q.id,bid=world.buildings.length+1,primary=p.doors.find(d=>d.a<0),block=world.blocks.find(k=>k.id===q.blockId);
  const b={id,program:p.program,useLabel:C.programs[p.program]?.label||catalog[p.type].label,capacity:q.capacity,decision:q.decision,siting:q.siting,retainedInPlanYear:q.retainedInPlanYear,type:p.type,category:catalog[p.type].category,name:p.type==='station'?'中央车站':p.name+' '+((countByType[p.type]=(countByType[p.type]||0)+1)),blueprint:p.templateId||p.id,form:p.name,special:!!p.special,wallMode:p.wallMode||'edge',wholeBlock:!!p.wholeBlock,layout:p.layout||p.name,operations:p.operations||null,excavationMode:q.excavationMode,naturalShare:q.naturalShare,alterations:q.alterations,earthwork:q.earthwork,households:p.households||null,construction:q.construction,blockId:q.blockId,legalStatus:p.legalStatus||'正规',year:q.year,builtYear:q.year,phase:q.phase,cycle:q.cycle,builtOrder:q.builtOrder,frontageOrder:q.frontageOrder,frontageYear:q.frontageYear,frontageRoadId:q.frontageRoadId,sitePrepared:q.sitePrepared,requiresMultipleExits:q.requiresMultipleExits,worldX:q.worldX,worldY:q.worldY,x:ox,y:oy,w:p.w,h:p.h,entry:{x:ox+primary.x,y:oy+primary.y},entryCell:{x:ox+p.anchor[0],y:oy+p.anchor[1]},front:['north','east','south','west'][dirs.findIndex(n=>n[0]===p.entryNormal[0]&&n[1]===p.entryNormal[1])],district:q.district,cells:[],rooms:[],doors:[],edges:[],accessRoadIds:q.accessRoadIds,access:{a:[ox+primary.x,oy+primary.y],b:[ox+primary.sides[0][0],oy+primary.sides[0][1]]}};
  p.rooms.forEach((r,i)=>b.rooms.push({...r,id:b.id+'-R'+(i+1),x:ox+r.x,y:oy+r.y,objects:[],reserved:[]}));
  p.doors.forEach(d=>b.doors.push({...d,x:ox+d.x,y:oy+d.y,sides:d.sides.map(v=>[ox+v[0],oy+v[1]]),a:d.a<0?'outside':b.rooms[d.a].id,b:b.rooms[d.b].id}));
  p.edges.forEach(e=>{const edge={x:ox+e.x,y:oy+e.y,axis:e.axis,kind:e.kind};b.edges.push(edge);if(e.axis==='vertical')vEdges[edge.y*(W+1)+edge.x]=e.kind==='door'?2:1;else hEdges[edge.y*W+edge.x]=e.kind==='door'?2:1;});
  for(let y=0;y<p.h;y++)for(let x=0;x<p.w;x++)if(p.cells[y*p.w+x]){const i=(oy+y)*W+ox+x;tiles[i]=p.cells[y*p.w+x];owners[i]=bid;if(p.roomAt[y*p.w+x]>=0)roomAt[i]=roomBase+p.roomAt[y*p.w+x]+1;b.cells.push(i);blockAt[i]=world.blocks.indexOf(block)+1;}
  b.floorArea=b.rooms.reduce((n,r)=>n+r.w*r.h,0);roomBase+=p.rooms.length;world.buildings.push(b);interiorDone++;interiorProgress('编译建筑 '+world.buildings.length+' / '+design.projects.length);
 }
 world.growthSummary={alterations:world.buildings.reduce((n,b)=>n+b.alterations.length,0),selfBuilt:world.buildings.filter(b=>b.phase==='resident').length,plannedBuildings:world.buildings.filter(b=>b.phase==='government').length};world.unplacedServices=world.history.flatMap(h=>h.rejected?[{year:h.year,count:h.rejected}]:[]);
 let oid=0;const allObjects=[];
 const fixtures={...furnishings,'单人客房':['bed','locker','desk'],'双人客房':['bed','bed','locker','table'],'机器人检测':['robotdock','monitor','workbench','computer'],'包装分拣':['workbench','cart','crates'],'食品加工':['workbench','stove','sink','shelf'],'起居卧室':['bed','table','stove','sink','shelf'],'家庭起居':['bed','sofa','table','shelf'],'工作间':['workbench','desk','computer'],'出租单间':['bed','table','shelf'],'卫生间':['toilet','sink','shower'],'起居厨房':['sofa','table','stove','sink','fridge','tv'],'洗手间':['sink'],'清洁间':['shelf','sink'],'接待与候诊':['bench','counter'],'公共门厅':['bench','sign'],'公共过道':[],'市场大厅':['counter','shelf','shelf','shelf','crates','table'],'电车检修库':['tram','workbench','tools','cart'],'检测室':['workbench','monitor','computer'],'机器人维修工位':['robotdock','workbench','tools'],'接单与配件':['counter','shelf','computer'],'配件售货区':['shelf','shelf','counter'],'电子检测':['computer','tools'],'药品售货':['medicine','counter','computer'],'药品库':['medicine','medicine','fridge'],'电源检测':['electric','tools','workbench'],'二手机体陈列':['robotdock','crates'],'拆件工位':['workbench','tools','robotdock'],'仿生人组织修复':['synthbed','monitor','medicine'],'专用耗材库':['medicine','fridge'],'消毒准备':['sink','medicine','workbench'],'护理准备':['medicine','workbench','sink','computer'],'备品间':['shelf'],'联合加工大厅':['lathe','cutter','robotarm'],'货运分拣大厅':['pallet','cart','shelf'],'材料库':['crates','shelf']};
 // Object footprints are deliberately discrete, rather than fractional-metre rectangles.
 function dimensions(type){const t=items[type];if(type==='tram')return[2,9];if(type==='bunk')return[1,2];if(type==='bed'||type==='medbed')return[1,2];if(type==='doublebed')return[2,2];return[Math.max(1,Math.ceil(t[1])),Math.max(1,Math.ceil(t[2]))];}
 for(const b of world.buildings)for(const r of b.rooms){
  interiorProgress('布置 '+b.name+' / '+r.name);const R=random(seed+'-furnish-'+r.id),ri=(a,b)=>Math.floor(a+R()*(b-a+1));
  const center=[r.x+Math.floor(r.w/2),r.y+Math.floor(r.h/2)];reserved[center[1]*W+center[0]]=1;
  for(const d of b.doors.filter(d=>d.a===r.id||d.b===r.id)){
   const near=d.sides[d.a===r.id?0:1];if(near[0]<r.x||near[1]<r.y||near[0]>=r.x+r.w||near[1]>=r.y+r.h)throw Error('门侧未接房间 '+r.id);
   const other=b.rooms.find(q=>q.id===(d.a===r.id?d.b:d.a)),clear=C.roomMinimum(r)===1||other&&C.roomMinimum(other)===1?1:Math.min(d.width>=3?3:2,r.w,r.h);
   const choices=[[center[0],near[1]],[near[0],center[1]]].map(bend=>{const cells=new Set();for(const[x,y]of [...line(near,bend),...line(bend,center)]){const left=Math.max(r.x,Math.min(x-(x>=center[0]?clear-1:0),r.x+r.w-clear)),top=Math.max(r.y,Math.min(y-(y>=center[1]?clear-1:0),r.y+r.h-clear));for(let yy=top;yy<top+clear;yy++)for(let xx=left;xx<left+clear;xx++)cells.add(yy*W+xx);}return{cells,cost:[...cells].filter(i=>!reserved[i]).length};});
   choices.sort((a,b)=>a.cost-b.cost);for(const i of choices[0].cells)reserved[i]=1;
  }
  for(let y=r.y;y<r.y+r.h;y++)for(let x=r.x;x<r.x+r.w;x++)if(reserved[y*W+x])r.reserved.push(y*W+x);
  function keepsAccess(pieces){
   const blocked=new Set(),seen=new Set(),queue=[];let freeCount=0;
   for(const p of pieces)if(p.type!=='shower')for(let yy=p.y;yy<p.y+p.h;yy++)for(let xx=p.x;xx<p.x+p.w;xx++)blocked.add(yy*W+xx);
   const clear=(x,y)=>x>=r.x&&x<r.x+r.w&&y>=r.y&&y<r.y+r.h&&!blocked.has(y*W+x)&&(!objectAt[y*W+x]||!allObjects[objectAt[y*W+x]-1].blocking);
   for(let y=r.y;y<r.y+r.h;y++)for(let x=r.x;x<r.x+r.w;x++)if(clear(x,y)){freeCount++;if(!queue.length){queue.push([x,y]);seen.add(y*W+x);}}
   for(let k=0;k<queue.length;k++){const[x,y]=queue[k];for(const[dx,dy]of dirs){const a=x+dx,b=y+dy,i=b*W+a;if(clear(a,b)&&!seen.has(i)){seen.add(i);queue.push([a,b]);}}}
   if(seen.size!==freeCount||!freeCount)return false;
   for(const p of [...r.objects,...pieces]){if(p.type==='shower')continue;let access=false;for(let yy=p.y;yy<p.y+p.h;yy++)for(const xx of [p.x-1,p.x+p.w])if(xx>=r.x&&xx<r.x+r.w&&seen.has(yy*W+xx))access=true;for(let xx=p.x;xx<p.x+p.w;xx++)for(const yy of [p.y-1,p.y+p.h])if(yy>=r.y&&yy<r.y+r.h&&seen.has(yy*W+xx))access=true;if(!access)return false;}
   return true;
  }
  function put(type,x,y,rotation=0,validated=false){const d=dimensions(type),w=d[rotation?1:0],h=d[rotation?0:1],blocking=type!=='shower';if(x<r.x||y<r.y||x+w>r.x+r.w||y+h>r.y+r.h)return false;
   for(let yy=y;yy<y+h;yy++)for(let xx=x;xx<x+w;xx++)if(blocking&&reserved[yy*W+xx]||objectAt[yy*W+xx]||tiles[yy*W+xx]!==TILE.FLOOR)return false;
   if(!validated&&!keepsAccess([{type,x,y,w,h}]))return false;
   const o={id:'O'+(++oid),type,name:items[type][0],family:items[type][3],x,y,w,h,blocking,rotation:rotation?90:0,roomId:r.id,buildingId:b.id};for(let yy=y;yy<y+h;yy++)for(let xx=x;xx<x+w;xx++)objectAt[yy*W+xx]=oid;r.objects.push(o);allObjects.push(o);return true;
  }
  let wanted=[...(fixtures[r.name]||[])];
  if(r.circulation||/过道|人员通道/.test(r.name))wanted=[];
  if(r.name==='接待与人员通廊')wanted=['counter','bench','computer'];
  if(r.name==='卧室'&&Math.min(r.w,r.h)<=3)wanted=wanted.map(t=>t==='doublebed'?'bed':t);
  const modules={
   sleep:{w:4,h:4,items:[['bed',0,0],['locker',1,0],['desk',0,3]]},
   ward:{w:4,h:4,items:[['medbed',0,0],['locker',1,0],['monitor',2,0]]},
   study:{w:4,h:3,items:[['desk',0,0],['chair',0,1],['books',2,0]]},
   sitting:{w:4,h:4,items:[['sofa',0,0],['table',0,2],['books',3,0,1]]},
   dining:{w:4,h:4,items:[['table',1,1],['chair',0,1],['chair',3,1],['chair',1,0],['chair',1,2]]},
   waiting:{w:4,h:3,items:[['bench',0,0],['bench',0,2]]},
   office:{w:4,h:4,items:[['computer',0,0],['chair',0,1],['shelf',2,0,1]]},
   pharmacy:{w:4,h:3,items:[['medicine',0,0],['medicine',1,0],['workbench',0,2]]},
   storage:{w:4,h:4,items:[['shelf',0,0],['crates',0,2]]},
   pallets:{w:4,h:4,items:[['pallet',0,0],['pallet',0,2]]},
   retail:{w:4,h:4,items:[['shelf',0,0],['shelf',0,2]]},
   kitchen:{w:4,h:4,items:[['stove',0,0],['sink',1,0],['workbench',0,3],['fridge',3,0]]},
   machine:{w:6,h:5,items:[['lathe',0,0],['workbench',0,3],['tools',4,0,1]]},
   assembly:{w:5,h:5,items:[['workbench',0,0],['robotarm',0,2],['crates',3,0]]},
   workshop:{w:5,h:4,items:[['workbench',0,0],['tools',3,0,1],['cart',0,2]]},
   air:{w:6,h:5,items:[['air',0,0],['electric',0,3],['tools',4,0,1]]},
   water:{w:5,h:5,items:[['tank',0,0],['pump',0,3]]},
   laundry:{w:4,h:3,items:[['washer',0,0],['washer',1,0],['sink',3,0]]},
   care:{w:4,h:4,items:[['workbench',0,0],['medicine',3,0],['sink',0,3],['computer',2,3]]},
   sterile:{w:4,h:3,items:[['workbench',0,0],['medicine',3,0],['sink',0,2]]},
   treatment:{w:5,h:5,items:[['medbed',0,0],['monitor',1,0],['tools',3,0,1],['sink',3,3]]}
  };
  let kind=null;
  if(/候车|站台/.test(r.name))kind='waiting';
  else if(/病房/.test(r.name))kind='ward';
  else if(/宿舍|寝室|客房/.test(r.name))kind='sleep';
  else if(/候诊|接待与候诊/.test(r.name))kind='waiting';
  else if(/用餐|餐厅|公共厨房/.test(r.name))kind=r.name==='公共厨房'?'kitchen':'dining';
  else if(/厨房|餐厨|备餐|食品加工/.test(r.name))kind='kitchen';
  else if(/机加工|加工车间|加工大厅|加工延伸/.test(r.name))kind='machine';
  else if(/装配/.test(r.name))kind='assembly';
  else if(/维修|工作间|分拣|机器人检测/.test(r.name))kind='workshop';
  else if(/材料准备|成品暂存|货物库房|仓储|收货|发货/.test(r.name))kind='pallets';
  else if(/药房|药品/.test(r.name))kind='pharmacy';
  else if(/后仓|储藏|零件库|材料库|备件库|食品库|干货|耗材|档案/.test(r.name))kind='storage';
  else if(/售货|店面|市场/.test(r.name))kind='retail';
  else if(/办公室|站务室|控制室|值班|电脑营业|打印装订/.test(r.name))kind='office';
  else if(/教室|阅览|图书/.test(r.name))kind='study';
  else if(/空气处理/.test(r.name))kind='air';
  else if(/水处理/.test(r.name))kind='water';
  else if(/洗衣/.test(r.name))kind='laundry';
  else if(/处置|诊室/.test(r.name))kind='treatment';
  else if(/消毒/.test(r.name))kind='sterile';
  else if(/护理/.test(r.name))kind='care';
  else if(/起居|活动室|休息室/.test(r.name))kind='sitting';
  function stamp(module,x,y){
   const pieces=module.items.map(([type,dx,dy,rotation=0])=>{const size=dimensions(type);return{type,x:x+dx,y:y+dy,rotation,w:size[rotation?1:0],h:size[rotation?0:1]};});
   if(pieces.some(p=>p.x+p.w>r.x+r.w||p.y+p.h>r.y+r.h))return false;
   for(const p of pieces)for(let yy=p.y;yy<p.y+p.h;yy++)for(let xx=p.x;xx<p.x+p.w;xx++)if(reserved[yy*W+xx]||objectAt[yy*W+xx])return false;
   if(!keepsAccess(pieces))return false;
   for(const p of pieces)put(p.type,p.x,p.y,p.rotation,true);return true;
  }
  if(kind&&r.w*r.h>=30&&!r.circulation){
   const module=modules[kind],zoned=new Set(),positions=[];let zones=0;
   // Pack functional bays into the space left by the door routes. Each bay includes its working clearance.
   for(let y=r.y;y+module.h<=r.y+r.h;y++)for(let x=r.x;x+module.w<=r.x+r.w;x++)positions.push({x,y,score:((x-r.x)%module.w)+((y-r.y)%module.h)+(x-r.x+y-r.y)*.01});
   positions.sort((a,b)=>a.score-b.score);
   for(const p of positions){let overlaps=false;for(let yy=p.y;yy<p.y+module.h&&!overlaps;yy++)for(let xx=p.x;xx<p.x+module.w;xx++)if(zoned.has(yy*W+xx)){overlaps=true;break;}if(overlaps)continue;
    if(stamp(module,p.x,p.y)){zones++;for(let yy=p.y;yy<p.y+module.h;yy++)for(let xx=p.x;xx<p.x+module.w;xx++)zoned.add(yy*W+xx);}
   }
   if(zones){r.capacity=kind==='ward'||kind==='sleep'?r.objects.filter(o=>o.type==='bed'||o.type==='medbed').length:r.capacity;
    wanted=kind==='waiting'?['counter','computer']:kind==='kitchen'?['fridge','shelf']:kind==='sitting'?['tv','table']:kind==='ward'?['medicine','sink']:kind==='retail'?['counter','computer']:['cart','shelf'].filter(t=>['machine','assembly','storage','pallets','workshop'].includes(kind));
   }
  }
  if(r.name==='卧室'&&r.w*r.h>35){stamp(modules.study,r.x,r.y);if(r.w*r.h>60)stamp(modules.sitting,r.x+Math.max(0,r.w-4),r.y+Math.max(0,r.h-4));}
  if(b.type==='station'){
   if(r.zone==='platform'){const horizontal=r.w>=r.h;for(let offset=2;offset<(horizontal?r.w:r.h)-2;offset+=5)put('bench',r.x+(horizontal?offset:0),r.y+(horizontal?0:offset));put('sign',r.x,r.y);}
   if(/站务室|信号控制室/.test(r.name))for(let x=r.x;x<r.x+r.w-2;x+=4){put('computer',x,r.y);put('shelf',x+2,r.y);}
   if(/供电设备/.test(r.name))for(let x=r.x;x<r.x+r.w-2;x+=4){put('electric',x,r.y);put('monitor',x+2,r.y);}
   if(/清洁备品/.test(r.name))wanted=['shelf','shelf','bin'];
  }
  if(r.name==='电车检修库'){put('tram',r.x+2,r.y);put('tram',r.x+r.w-4,r.y);wanted=['workbench','tools','cart'];}
  if(r.name==='公共洗浴'){for(let x=r.x;x<r.x+r.w;x+=2)put('shower',x,r.y);wanted=['sink','toilet'];}
  for(const type of wanted){if(!items[type])continue;let placed=false;const base=dimensions(type);
   // Evaluate wall positions first, then interior positions; the same seed keeps unchanged rooms stable.
   const positions=[];for(let rotation=0;rotation<2;rotation++){const w=base[rotation?1:0],h=base[rotation?0:1];for(let y=r.y;y<=r.y+r.h-h;y++)for(let x=r.x;x<=r.x+r.w-w;x++){const wall=x===r.x||y===r.y||x+w===r.x+r.w||y+h===r.y+r.h;positions.push({x,y,rotation,score:(wall?0:10)+R()});}}
   positions.sort((a,b)=>a.score-b.score);for(const p of positions)if(put(type,p.x,p.y,p.rotation)){placed=true;break;}
   if(!placed&&type==='doublebed')for(let y=r.y;y<r.y+r.h&&!placed;y++)for(let x=r.x;x<r.x+r.w&&!placed;x++)for(let rotation=0;rotation<2&&!placed;rotation++)placed=put('bed',x,y,rotation);
  }
 interiorDone++;
 }
 interiorProgress('布置公共空间与整理数据');
 function preservesSpace(space,x,y,w,h){
  const available=new Set(space.cells.filter(i=>{const xx=i%W,yy=Math.floor(i/W);return!(xx>=x&&xx<x+w&&yy>=y&&yy<y+h)&&(!objectAt[i]||!allObjects[objectAt[i]-1].blocking);}));
  const entries=new Set(world.buildings.filter(b=>space.buildingIds.includes(b.id)).flatMap(b=>b.doors.filter(d=>d.a==='outside').map(d=>d.sides[0][1]*W+d.sides[0][0]))),queue=[...available].filter(i=>entries.has(i)||[i-1,i+1,i-W,i+W].some(j=>tiles[j]===TILE.STREET)),seen=new Set(queue);
  for(let k=0;k<queue.length;k++){const i=queue[k];for(const j of [i-1,i+1,i-W,i+W])if(available.has(j)&&!seen.has(j)){seen.add(j);queue.push(j);}}
  return available.size===seen.size;
 }
 for(const space of world.openSpaces.filter(s=>s.buildingIds?.length||s.program)){
  const R=random(seed+'-space-'+space.id),pick=a=>a[Math.floor(R()*a.length)];
  const publicProject=space.program==='park'||space.program==='plaza',available=new Set(space.cells);
  if(publicProject){const cx=Math.floor(space.x+space.w/2),cy=Math.floor(space.y+space.h/2);for(const i of space.cells){const x=i%W,y=Math.floor(i/W);if(x>=cx&&x<cx+2||y>=cy&&y<cy+2||[i-1,i+1,i-W,i+W].some(j=>tiles[j]===TILE.STREET))reserved[i]=1;}}
  const types=space.program==='park'?['planter','planter','planter','bench','bench','table','lamp']:space.program==='plaza'?['bench','bench','sign']:space.service?(space.cells.length>=12?['crates']:[]):['bench','bicycle'];
  for(const type of types){const d=dimensions(type);let done=false;for(let attempt=0;attempt<60&&!done;attempt++){const i=pick(space.cells),x=i%W,y=Math.floor(i/W),ww=d[0],hh=d[1];let clear=true;
    for(let yy=y;yy<y+hh;yy++)for(let xx=x;xx<x+ww;xx++)if(!inBounds(xx,yy)||tiles[yy*W+xx]!==TILE.YARD||!available.has(yy*W+xx)||reserved[yy*W+xx]||objectAt[yy*W+xx])clear=false;
    if(!clear||!preservesSpace(space,x,y,ww,hh)||world.buildings.some(b=>b.doors.some(d=>d.a==='outside'&&Math.abs(d.x-x)+Math.abs(d.y-y)<5)))continue;
    const o={id:'O'+(++oid),type,name:items[type][0],family:items[type][3],x,y,w:ww,h:hh,blocking:true,rotation:0,roomId:null,buildingId:null,spaceId:space.id};for(let yy=y;yy<y+hh;yy++)for(let xx=x;xx<x+ww;xx++)objectAt[yy*W+xx]=oid;allObjects.push(o);world.streetObjects.push(o);done=true;
   }
  }
 }
 const reclaimedGround=[];for(let i=0;i<N;i++)if(tiles[i]===TILE.GROUND&&!design.geology[i]){tiles[i]=TILE.VOID;design.excavation[i]=0;reclaimedGround.push(i);}
 const assigned=new Uint8Array(N);for(const r of world.roads)for(const i of r.cells)assigned[i]=1;for(const r of world.openSpaces)for(const i of r.cells)assigned[i]=1;for(const b of world.buildings)for(const i of b.cells)assigned[i]=1;
 world.landUseSummary={unassignedExcavation:tiles.reduce((n,t,i)=>n+!!(t&&!design.geology[i]&&!assigned[i]),0),reclaimedRockCells:reclaimedGround.length,artificialOpenCells:world.openSpaces.reduce((n,s)=>n+s.cells.filter(i=>!design.geology[i]).length,0),spaces:world.openSpaces.length};
 const footprint=new Uint8Array(N),queue=new Int32Array(N);let fh=0,ft=0;const start=world.station.y*W+world.station.x;footprint[start]=1;queue[ft++]=start;
 while(fh<ft){const i=queue[fh++],x=i%W,y=(i/W)|0;for(const j of [x?i-1:-1,x<W-1?i+1:-1,y?i-W:-1,y<H-1?i+W:-1])if(j>=0&&tiles[j]&&!footprint[j]){footprint[j]=1;queue[ft++]=j;}}
 world.developmentEnvelope=Array.from(design.cityMask);for(let i=0;i<N;i++){if(!footprint[i]&&!owners[i]&&tiles[i]===TILE.GROUND){tiles[i]=TILE.VOID;design.excavation[i]=0;}design.cityMask[i]=footprint[i]?1:0;}
 design.terrainStats.developedCells=design.cityMask.reduce((n,v)=>n+v,0);design.terrainStats.reusedCells=design.cityMask.reduce((n,v,i)=>n+(v&&!!design.geology[i]),0);

 const areas=world.buildings.map(b=>b.floorArea).sort((a,b)=>a-b),housing=world.buildings.filter(b=>b.category==='housing').map(b=>b.floorArea).sort((a,b)=>a-b);
 world.areaSummary={median:areas[Math.floor(areas.length/2)]||0,mean:Math.round(areas.reduce((n,v)=>n+v,0)/Math.max(1,areas.length)),housingMedian:housing[Math.floor(housing.length/2)]||0,small:areas.filter(a=>a<150).length,medium:areas.filter(a=>a>=150&&a<1000).length,large:areas.filter(a=>a>=1000).length};
 world.stats={buildings:world.buildings.length,landmarks:world.buildings.filter(b=>b.special).length,layouts:new Set(world.buildings.map(b=>b.blueprint)).size,rooms:world.buildings.reduce((n,b)=>n+b.rooms.length,0),objects:oid,buildingTypes:countByType,openSpaces:world.openSpaces.length};
 world.plannedMask=Array.from(design.plannedMask);world.informalMask=Array.from(design.informalMask);world.rock=Array.from(design.rock);world.growth=Array.from(design.growth);world.terrainStats=design.terrainStats;world.cityMask=Array.from(design.cityMask);world.geology=Array.from(design.geology);world.excavation=Array.from(design.excavation);world.planningSummary={regions:world.districts.length,blockTypes:[...new Set(world.blocks.map(b=>b.kind))],closedStreetBlocks:world.blocks.length,streetFrontedBuildings:world.buildings.filter(b=>b.frontageOrder<b.builtOrder).length,completeComplexes:world.buildings.filter(b=>b.wholeBlock).length,excavatedCells:world.excavation.filter(Boolean).length,internalRailMetres:world.tram.filter(l=>l.scope==='internal').reduce((n,l)=>n+l.internalLengthMetres,0)};
 world.tiles=Array.from(tiles);world.edges=[];for(let y=0;y<H;y++)for(let x=0;x<=W;x++){const t=vEdges[y*(W+1)+x];if(t)world.edges.push({x,y,axis:'vertical',kind:t===2?'door':'wall'});}for(let y=0;y<=H;y++)for(let x=0;x<W;x++){const t=hEdges[y*W+x];if(t)world.edges.push({x,y,axis:'horizontal',kind:t===2?'door':'wall'});}
 Object.defineProperty(world,'runtime',{value:{tiles,owners,roomAt,objectAt,objects:allObjects,reserved,vEdges,hEdges,blockAt},enumerable:false});
 interiorDone=interiorTotal;interiorProgress('房间、家具与公共空间完成');report({phase:'scenes',detail:'布置灾后场景、实体与容器',done:0,total:1});Environment.apply(world,validate,report);report({phase:'validation',detail:'检查格边墙门、入口、房间与物件通行',done:0,total:1});world.validation=validate(world);world.validation.errors.push(...Environment.validate(world));world.validation.collapsedRooms=world.environmentSummary.collapsedRooms;if(world.validation.errors.length)throw Error(world.validation.errors.join('；'));report({phase:'validation',detail:'通行检查完成：'+world.validation.reachableRooms+' 间房可达',done:1,total:1});return world;
}
function validate(w){const errors=[],W=w.width,H=w.height,N=W*H,t=w.runtime.tiles,objects=w.runtime.objectAt,seen=new Uint8Array(N),queue=new Int32Array(N);let head=0,tail=0;
 const inBoundsDoor=(x,y)=>Number.isInteger(x)&&Number.isInteger(y)&&x>=0&&y>=0&&x<W&&y<H;
 const pass=i=>i>=0&&i<N&&t[i]!==TILE.VOID&&t[i]!==TILE.WALL&&(!objects[i]||!w.runtime.objects[objects[i]-1].blocks_movement);
 const start=w.station.y*W+w.station.x;if(pass(start)){seen[start]=1;queue[tail++]=start;}
 while(head<tail){const i=queue[head++],x=i%W,y=(i/W)|0;const neighbours=[[x?i-1:-1,w.runtime.vEdges[y*(W+1)+x]],[x<W-1?i+1:-1,w.runtime.vEdges[y*(W+1)+x+1]],[y?i-W:-1,w.runtime.hEdges[y*W+x]],[y<H-1?i+W:-1,w.runtime.hEdges[(y+1)*W+x]]];for(const [j,edge] of neighbours)if(edge!==1&&pass(j)&&!seen[j]){seen[j]=1;queue[tail++]=j;}}
 for(const p of w.portals)if(!seen[p.y*W+p.x])errors.push('快速旅行点不可达 '+p.id);
 let entries=0,rooms=0;
 for(const b of w.buildings){b.streetReachable=!!seen[b.entryCell.y*W+b.entryCell.x];if(b.streetReachable)entries++;else errors.push('建筑入口不可达 '+b.id);
  if(b.requiresMultipleExits&&new Set(b.doors.filter(d=>d.a==='outside').map(d=>d.opening||'primary')).size<2)errors.push('缺少第二出口 '+b.id);
  const openings=new Map();for(const d of b.doors.filter(d=>d.a==='outside')){const key=d.opening||'primary';if(!openings.has(key))openings.set(key,[]);openings.get(key).push(d);}
  for(const ds of openings.values()){const unique=new Set(ds.map(d=>d.axis+':'+d.x+':'+d.y)),axis=ds[0].axis,along=ds.map(d=>axis==='horizontal'?d.x:d.y).sort((a,b)=>a-b);if(unique.size<C.exteriorMinimum(b,ds[0].role)||ds.some(d=>d.width!==unique.size||d.axis!==axis||d.b!==ds[0].b||(axis==='horizontal'?d.y!==ds[0].y:d.x!==ds[0].x))||along.some((v,i)=>i&&v!==along[i-1]+1))errors.push('建筑外门净宽不足或不连续 '+b.id);}
  for(const d of b.doors.filter(d=>d.a==='outside')){const [x,y]=d.sides[0];if(!inBoundsDoor(x,y)||!seen[y*W+x])errors.push('门外通路不可达 '+b.id+' @ '+d.x+','+d.y);}
  for(const d of b.doors)if((d.axis==='vertical'?w.runtime.vEdges[d.y*(W+1)+d.x]:w.runtime.hEdges[d.y*W+d.x])!==2||!Number.isInteger(d.x)||!Number.isInteger(d.y))errors.push('门边无效 '+b.id);
  for(const r of b.rooms){if(r.usable===false)continue;const center=(r.y+Math.floor(r.h/2))*W+r.x+Math.floor(r.w/2);if(seen[center])rooms++;else errors.push('房间中心不可达 '+r.id);if(Math.min(r.w,r.h)<C.roomMinimum(r))errors.push('房间净宽不足 '+r.id);if(r.name==='卫生间'&&r.w*r.h>(b.special?9:6))errors.push('卫生间超出面积限制 '+r.id);
   for(const o of r.objects){if(![o.x,o.y,o.w,o.h].every(Number.isInteger)||o.x<r.x||o.y<r.y||o.x+o.w>r.x+r.w||o.y+o.h>r.y+r.h)errors.push('物件占格无效 '+o.id);
    if(o.suspended)continue;let access=!o.blocks_movement;for(let y=o.y;y<o.y+o.h;y++)for(const x of [o.x-1,o.x+o.w])if(x>=r.x&&x<r.x+r.w&&seen[y*W+x])access=true;for(let x=o.x;x<o.x+o.w;x++)for(const y of [o.y-1,o.y+o.h])if(y>=r.y&&y<r.y+r.h&&seen[y*W+x])access=true;if(!access)errors.push('物件缺少可达操作面 '+o.id);
   }
  }
 }
 for(let i=0;i<N;i++){if(t[i]&&w.rock[i]===3)errors.push('保留岩体被开凿 '+i);if(t[i]===TILE.GROUND&&!w.geology[i])errors.push('人工裸地未分配用途 '+i);}
 for(const space of w.openSpaces)if(!space.purpose||!space.projectId||!space.cells.every(i=>space.kind==='foundation'?t[i]===TILE.WALL:seen[i]||objects[i]&&w.runtime.objects[objects[i]-1].blocks_movement))errors.push('室外用地缺少用途或无法到达 '+space.id);
 for(const b of w.buildings){const d=b.doors.find(d=>d.a==='outside'),i=d.sides[0][1]*W+d.sides[0][0];if(t[i]!==TILE.STREET||!(b.frontageOrder<b.builtOrder)||b.frontageYear>b.year)errors.push('建筑未依附先行开凿道路 '+b.id);}
 for(const b of w.blocks){const floor=b.cells.filter(i=>w.runtime.owners[i]).length,used=b.cells.filter(i=>w.developmentEnvelope[i]).length;if(floor/b.buildableArea<.5)errors.push('规划街坊未完成内部建设 '+b.id);}
 for(const r of w.roads){if(r.cells.some(i=>t[i]!==TILE.STREET))errors.push('道路占地与实际通路不一致 '+r.id);if((r.clearWidth||r.width)<(r.minimumWidth||2)||r.earthwork?.excavated>0&&(r.clearWidth||r.width)<3)errors.push('挖岩道路净宽不足 '+r.id);}
 w.runtime.reachable=seen;
 return{errors,reachableEntrances:entries,reachableRooms:rooms,walkableCells:tail,scope:'四邻域移动同时检查格子和边界；普通墙阻止跨边，厚墙与物件阻格，门边按可通过处理'};
}
root.BubbleGenerator={generate,validate,compile,catalog,items,inside,TILE};if(typeof module!=='undefined')module.exports=root.BubbleGenerator;
})(typeof window!=='undefined'?window:globalThis);
