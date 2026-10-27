(function(root){'use strict';
const C=typeof module!=='undefined'?require('./content.js'):root.BubbleContent;
const Rail=typeof module!=='undefined'?require('./rail-station.js'):root.BubbleRailStation;
const Layouts=typeof module!=='undefined'?require('./room-layouts.js'):root.BubbleRoomLayouts;
const D=[[0,-1],[1,0],[0,1],[-1,0]],K=(x,y)=>x+','+y;
class Heap{constructor(){this.a=[];}push(i,v){const a=this.a;let k=a.length;a.push([i,v]);while(k){const p=(k-1)>>1;if(a[p][1]<=v)break;a[k]=a[p];k=p;}a[k]=[i,v];}pop(){const a=this.a,out=a[0],last=a.pop();if(a.length){let k=0;while(k*2+1<a.length){let c=k*2+1;if(c+1<a.length&&a[c+1][1]<a[c][1])c++;if(a[c][1]>=last[1])break;a[k]=a[c];k=c;}a[k]=last;}return out;}get length(){return this.a.length;}}
function hash(seed){let h=2166136261;for(const c of String(seed))h=Math.imul(h^c.charCodeAt(0),16777619);return(x,y,s=0)=>{let n=Math.imul(x,374761393)^Math.imul(y,668265263)^h^Math.imul(s,1274126177);n=Math.imul(n^(n>>>13),1274126177);return((n^(n>>>16))>>>0)/4294967296;};}
function geology(seed,o){
 const rand=hash(seed),cache=new Map(),angle=rand(0,0,81)*Math.PI,cos=Math.cos(angle),sin=Math.sin(angle);
 function noise(x,y,scale,salt){
  x/=scale;y/=scale;const ix=Math.floor(x),iy=Math.floor(y),u=x-ix,v=y-iy,a=u*u*(3-2*u),b=v*v*(3-2*v);
  return(rand(ix,iy,salt)*(1-a)+rand(ix+1,iy,salt)*a)*(1-b)+(rand(ix,iy+1,salt)*(1-a)+rand(ix+1,iy+1,salt)*a)*b;
 }
 function sample(x,y){
  const key=K(x,y);if(cache.has(key))return cache.get(key);
  const warpX=(noise(x,y,120,21)-.5)*44,warpY=(noise(x,y,160,22)-.5)*44;
  const u=(x+warpX)*cos+(y+warpY)*sin,v=-(x+warpX)*sin+(y+warpY)*cos;
  const strength=.66*noise(u,v,95,8)+.34*noise(u,v,31,4),weakness=.65*noise(u,v*.58,110,19)+.35*noise(u,v,43,24);
  const rock=strength>1-o.hardRock?3:strength>.62?2:1;
  // Two joint families intersect within continuous, warped bedding/strength fields.
  const jointA=Math.abs(noise(u,v*.32,42,31)-.5)*100;
  const jointB=Math.abs(noise(u*.38+v*.2,v,58,32)-.5)*125;
  const activity=.65*noise(x,y,110,40)+.35*noise(x,y,45,41),aperture=Math.max(.65,(weakness-.30)*o.tunnelWidth*1.55)+Math.max(0,weakness-.5)*o.chamberRatio*60;
  const active=activity>.82-o.caveDensity*.32;
  let geology=0;
  if(rock!==3&&active){
   const passage=Math.min(jointA,jointB)<aperture;
   const chamber=weakness>.54&&jointA+jointB<aperture*(2.1+o.chamberRatio);
   if(passage||chamber)geology=chamber||aperture>8?1:2;
   // Resistant remnants leave irregular ribs and pillars within widened weak beds.
   if(strength>.71&&noise(u,v,17,45)>.7)geology=0;
  }
  const result={rock:geology?0:rock,geology,weakness};cache.set(key,result);return result;
 }
 return{sample};
}
function rotated(p,r){if(!r)return p;const w=r%2?p.h:p.w,h=r%2?p.w:p.h,point=(x,y)=>r===1?[p.h-1-y,x]:r===2?[p.w-1-x,p.h-1-y]:[y,p.w-1-x],vertex=(x,y)=>r===1?[p.h-y,x]:r===2?[p.w-x,p.h-y]:[y,p.w-x];const cells=new Uint8Array(w*h),roomAt=new Int16Array(w*h);roomAt.fill(-1);for(let y=0;y<p.h;y++)for(let x=0;x<p.w;x++){const[a,b]=point(x,y);cells[b*w+a]=p.cells[y*p.w+x];roomAt[b*w+a]=p.roomAt[y*p.w+x];}
 const edge=e=>{const a=vertex(e.x,e.y),b=vertex(e.x+(e.axis==='horizontal'?1:0),e.y+(e.axis==='vertical'?1:0));return{...e,x:Math.min(a[0],b[0]),y:Math.min(a[1],b[1]),axis:r%2?(e.axis==='horizontal'?'vertical':'horizontal'):e.axis};},n=p.entryNormal;
 return{...p,w,h,cells,roomAt,rooms:p.rooms.map(q=>{const a=point(q.x,q.y),b=point(q.x+q.w-1,q.y+q.h-1);return{...q,x:Math.min(a[0],b[0]),y:Math.min(a[1],b[1]),w:Math.abs(a[0]-b[0])+1,h:Math.abs(a[1]-b[1])+1};}),edges:p.edges.map(edge),doors:p.doors.map(e=>({...edge(e),sides:e.sides.map(q=>point(...q))})),anchor:point(...p.anchor),entryNormal:r===1?[-n[1],n[0]]:r===2?[-n[0],-n[1]]:[n[1],-n[0]],outdoorCells:(p.outdoorCells||[]).map(q=>({...q,cells:q.cells.map(c=>point(...c))}))};
}
function dwelling(w,h,front,profile,o){
 const p=Layouts.fitted('dwelling',w,h,'housing',C.random('dwelling-'+w+'-'+h+'-'+profile),o,profile==='workhome'?1:0);
 if(profile==='shared'){for(const r of p.rooms){if(r.name==='卫生间')r.name='个人储藏';if(r.name==='起居厨房')r.name='共用起居';if(r.name==='卧室')r.name=r.w*r.h<18?'单人寝室':'双人寝室';}}
 return{rooms:p.rooms,links:p.links,entryX:p.entry[0]};
}

function groupPlan(id,R,o){
 const passage=Layouts.corridorWidth(R,'public',o.publicCorridorMax,o),shared=R()<o.sharedHousing,profile=shared?'shared':['combined','family','dining'][Math.floor(R()*3)],rawForm=Math.floor(R()*3),target=Math.max(3,Math.round(o.households*(.35+R()*1.65))),variants=[];
 for(let w=7;w<=11;w++)for(let d=8;d<=12;d++)for(let n=3;n<=20;n++){const area=n*dwelling(w,d,3,profile,o).rooms.reduce((n,r)=>n+r.w*r.h,0)+n*w*passage+(shared?64:0);if(area>=o.groupMin&&area<=o.groupMax)variants.push({w,d,n,score:Math.abs(n-target)*8+R()*20});}
 variants.sort((a,b)=>a.score-b.score);if(!variants.length)throw Error('住宅组团面积范围无法容纳有效户型，请放宽最小和最大面积');
 const {w:unitW,d:depth,n:count}=variants[0],form=rawForm===0&&count>4?1:rawForm,cols=form===0?count:Math.ceil(count/2),end=cols*unitW+(form===2?passage:0),rooms=[{name:'公共过道',x:0,y:form===1?depth:0,w:end+(shared?8:0),h:passage,circulation:'public'}],links=[];
 let wing=-1;if(form===2){wing=rooms.length;rooms.push({name:'公共过道',x:0,y:passage,w:passage,h:depth+(count-cols)*unitW,circulation:'public'});links.push([0,wing]);}
 for(let i=0;i<count;i++){
  const unit=dwelling(unitW,depth,3,profile,o),base=rooms.length;
  if(form===2&&i>=cols){const y=passage+depth+(i-cols)*unitW;rooms.push(...unit.rooms.map(q=>({...q,x:passage+q.y,y:y+unitW-q.x-q.w,w:q.h,h:q.w})));links.push([wing,base]);}
  else{const above=form===1&&i<cols,x=(i%cols)*unitW+(form===2?passage:0),y=form===1?(above?0:depth+passage):passage;rooms.push(...unit.rooms.map(q=>({...q,x:x+q.x,y:y+(above?depth-q.y-q.h:q.y)})));links.push([0,base]);}
  links.push(...unit.links.map(([a,b])=>[base+a,base+b]));
 }
 if(shared){const y=rooms[0].y;for(const r of [{name:'公共厨房',x:end,y:y-4,w:8,h:4},{name:'洗衣烘干',x:end,y:y+passage,w:4,h:4},{name:'淋浴间',x:end+4,y:y+passage,w:2,h:4},{name:'公共卫生间',x:end+6,y:y+passage,w:2,h:4}]){links.push([0,rooms.length]);rooms.push(r);}}
 const minY=Math.min(0,...rooms.map(r=>r.y));for(const r of rooms)r.y-=minY;
 return{id,templateId:'group-'+['single-bar','double-bar','corner'][form]+'-'+profile,name:shared?'共厨工人住区':['单侧联排住区','双排共廊住宅','折角多户住区'][form],type:shared?'dorm':'apartment',wallMode:'edge',front:'west',entry:[0,rooms[0].y+Math.floor(passage/2)],rooms,links,households:count,layout:count+'户 · '+['单侧通廊','双侧通廊','折角通廊'][form],operations:'街巷 → 公共过道 → 独立住宅'};
}
function singlePlan(id,R,o){
 const ri=(a,b)=>Math.floor(a+R()*(b-a+1)),variants=[];
 for(let attempt=0;attempt<80;attempt++){
  const form=attempt%4,w=ri(5,10),d=ri(3,5),rooms=[],links=[],add=(name,x,y,w,h)=>{rooms.push({name,x,y,w,h});return rooms.length-1;};let entry,front='north',name;
  if(form===0){const f=ri(3,5);add('起居厨房',0,0,w,f);add('卧室',0,f,w-2,Math.min(d,Math.floor(48/(w-2))));add('卫生间',w-2,f,2,3);links.push([0,1],[0,2]);entry=[Math.floor(w/2),0];name='紧凑独立户';}
  if(form===1){const a=ri(3,5);add('起居室',0,0,a,4);add('厨房',0,4,a,3);add('卧室',0,7,a,ri(3,4));add('卫生间',a,4,2,3);links.push([0,1],[1,2],[1,3]);entry=[Math.floor(a/2),0];name='窄面深宅';}
  if(form===2){const width=ri(5,8),count=ri(2,4),height=4+count*3,passage=Layouts.corridorWidth(R,'private',o.privateCorridorMax,o);add('户内过道',0,0,passage,height);add('起居餐室',passage,0,width,4);links.push([0,1]);for(let j=0;j<count;j++){const k=add(j===0?'厨房':'卧室',passage,4+j*3,width,3);links.push([0,k]);}const k=add('卫生间',passage+width,0,2,3);links.push([1,k]);entry=[0,2];front='west';name='侧廊家庭住宅';}
  if(form===3){const unit=dwelling(ri(8,14),ri(9,16),4,R()<.5?'family':'workhome',o);rooms.push(...unit.rooms);links.push(...unit.links);entry=[unit.entryX,0];name='多室家庭住宅';}
  const area=rooms.reduce((n,r)=>n+r.w*r.h,0);if(area>=o.homeMin&&area<=o.homeMax)variants.push({id,templateId:'single-'+form,name,type:'apartment',wallMode:'edge',entry,front,rooms,links,households:1,layout:name});
 }
 if(!variants.length)throw Error('单户面积范围无法容纳有效户型，请放宽范围');
 const target=o.homeMin*Math.pow(o.homeMax/o.homeMin,R());variants.sort((a,b)=>Math.abs(a.rooms.reduce((n,r)=>n+r.w*r.h,0)-target)-Math.abs(b.rooms.reduce((n,r)=>n+r.w*r.h,0)-target));return variants[0];
}

function plan(seed,o,compile,report=()=>{}){
 const progress=(phase,detail,done=null,total=null)=>report({phase,detail,done,total});
 progress('station','采样岩层、空腔与车站候选位置',0,61);
 const geo=geology(seed,o),stationSite=Rail.layout(o,compile),candidateSites=[];let origin=null,railDesign=null;
 const siteCells=[...stationSite.cells];for(const line of stationSite.lines){const a=line.bay[0],b=line.bay[1],length=Math.max(1,Math.ceil(Math.hypot(b[0]-a[0],b[1]-a[1])));for(let j=0;j<=length;j++){const x=a[0]+(b[0]-a[0])*j/length,y=a[1]+(b[1]-a[1])*j/length;for(let yy=Math.floor(y-stationSite.trackWidth/2);yy<y+stationSite.trackWidth/2;yy++)for(let xx=Math.floor(x-stationSite.trackWidth/2);xx<x+stationSite.trackWidth/2;xx++)siteCells.push([xx,yy]);}}
 for(const access of stationSite.accesses){const a=access.points[0],b=access.points[1],points=[];for(let x=Math.min(a[0],b[0]);x<=Math.max(a[0],b[0]);x++)points.push([x,a[1]]);for(let y=Math.min(a[1],b[1]);y<=Math.max(a[1],b[1]);y++)points.push([b[0],y]);for(const[x,y]of points)for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++)siteCells.push([x+dx,y+dy]);const width=Math.max(3,Math.min(8,Math.ceil(Math.sqrt(o.junctionMax||9)))),lo=Math.floor(width/2),hi=width-lo-1;for(let y=b[1]-lo;y<=b[1]+hi;y++)for(let x=b[0]-lo;x<=b[0]+hi;x++)siteCells.push([x,y]);}
 for(let y=-240;y<=240;y+=8){progress('station','比较完整站房、站台与接入空间',(y+240)/8,61);for(let x=-240;x<=240;x+=8){if(!geo.sample(x,y).geology)continue;let cost=0,natural=0,valid=true;for(let i=0;i<siteCells.length;i+=3){const p=siteCells[i],g=geo.sample(x+p[0],y+p[1]);if(g.rock===3){valid=false;break;}natural+=!!g.geology;cost+=g.geology?.3:.3+o.excavationCost*(g.rock===2?6:2)*(1.5-g.weakness);}if(valid)candidateSites.push({at:[x,y],score:cost/Math.max(1,siteCells.length/3)-natural/Math.max(1,siteCells.length/3)*2+Math.hypot(x,y)*.001});}}
 candidateSites.sort((a,b)=>a.score-b.score);progress('station','站区候选采样完成',61,61);let best=null;
 for(const candidate of candidateSites.slice(0,8)){const at=candidate.at,sample=(x,y)=>geo.sample(at[0]+x,at[1]+y);if(siteCells.some(p=>sample(...p).rock===3))continue;const design=Rail.planRoutes(stationSite,o,sample,index=>progress('rail','为出口 '+(index+1)+' 规划满足转弯半径的线路',null,null));const rank=design.failures.length*10000+candidate.score;if(!best||rank<best.rank)best={at,design,rank};if(!design.failures.length)break;}
 if(!best)throw Error('地质中未找到能容纳完整站房和站台的场地');origin=best.at;railDesign=best.design;progress('rail','站区铁路接入规划完成',o.exits.length,o.exits.length);
 const occupied=new Map(),streets=new Map(),reserved=new Set(),projects=[],roads=[],spaces=[],railPlans=[],warnings=[],history=[],quarters=[],parcels=[];let sequence=0,eventCounter=0,remainingEffort=Infinity,yearEffort=0,currentYear=0;
 const demolitions=[],planningEvents=[],vacated=new Map();let relocationPending=0,totalDisplaced=0,totalResettled=0,spatial=null;
 function demandState(year){
  const state=C.populationNeeds(o,year),supply=Object.fromEntries(Object.keys(state.targets).map(k=>[k,0]));
  for(const q of projects)for(const[k,v]of Object.entries(q.capacity||C.planningCapacity(q.p,o)))supply[k]=(supply[k]||0)+v;
  return{population:state.population,needs:Object.entries(state.targets).map(([key,target])=>({key,label:C.demandLabels[key],target,supply:supply[key],shortage:Math.max(0,target-supply[key])})),supply};
 }
 function useChoices(year,actor,R,excluded=new Set(),allowSurplus=false){
  const state=demandState(actor==='government'?year+o.governmentInterval:year),priority={family:1.2,workers:1.25,guests:.75,industry:1.1,repair:.85,logistics:.9,retail:1,meals:1.05,health:1.1,education:.75,hygiene:.65,utilities:1.4,safety:.7,administration:.6,leisure:.6};
  const choices=[];
  for(const[program,def]of Object.entries(C.programs)){if(excluded.has(program)||!def.actors.includes(actor)||o.facilityRules.some(r=>r.program===program&&r.mode==='forbidden'))continue;
   const need=state.needs.find(n=>n.key===def.key),count=projects.filter(q=>q.p.program===program).length,required=o.facilityRules.find(r=>r.program===program&&r.mode==='required'),missing=required?Math.max(0,required.count-count):0;
   if(!missing&&need.target<=0)continue;
   if(actor==='government'&&!missing&&def.area>Math.pow(o.blockScale-o.streetMax,2)*1.6)continue;
   if(!missing&&!need.shortage&&(!allowSurplus||!['family','workers'].includes(def.key)))continue;
   const approximate=C.planningCapacity({program,type:program,rooms:[{name:'起居卧室',w:def.area,h:1}]},o)[def.key]||1,match=Math.max(.03,Math.min(1,need.shortage/approximate));
   let weight=(need.shortage/Math.max(1,need.target))*priority[def.key]*match+(allowSurplus?.05:0);
   if(relocationPending&&['family','workers'].includes(def.key))weight*=1.7;
   if(program==='robot')weight*=o.industry==='robotics'?2:.3;if(program==='bakery')weight*=o.industry==='food'?2:.5;
   if(program==='transport')weight*=o.role==='logistics'||o.industry==='logistics'?1.8:1;
   if(missing)weight+=12*missing;
   if(actor==='government'&&program==='utility'&&state.supply.utilities===0)weight+=8;
   if(actor==='government'&&program==='production'&&state.supply.industry===0&&need.target>=60)weight+=2.5;
   if(weight>0)choices.push({program,def,need,weight,required:missing>0,rank:-Math.log(Math.max(.00001,R()))/weight});
  }
  return choices.sort((a,b)=>a.rank-b.rank);
 }
 function decisionFor(program,year,actor){const state=demandState(actor==='government'?year+o.governmentInterval:year),need=state.needs.find(n=>n.key===C.programs[program].key);return{program,service:need.label,requested:need.target,available:need.supply,shortage:need.shortage,reason:o.facilityRules.some(r=>r.program===program&&r.mode==='required'&&projects.filter(q=>q.p.program===program).length<r.count)?'指定项目':!need.shortage?'规划储备与街坊配套':relocationPending&&['family','workers'].includes(need.key)?'拆迁安置与居住需求':actor==='government'?'规划期需求':'当年需求'};}
 const key=(x,y)=>K(x-origin[0],y-origin[1]),sample=(x,y)=>geo.sample(x+origin[0],y+origin[1]),free=(x,y)=>developmentAllowed(x,y)&&!occupied.has(K(x,y))&&sample(x,y).rock!==3;
 function widthCells(points,width){const out=new Map(),lo=Math.floor(width/2),hi=width-lo-1;for(const[x,y]of points)for(let yy=y-lo;yy<=y+hi;yy++)for(let xx=x-lo;xx<=x+hi;xx++)out.set(K(xx,yy),[xx,yy]);return[...out.values()];}
 function roadCellsFit(cells,width,blocked=new Set()){return width>=2&&cells.every(([x,y])=>{const k=K(x,y);return free(x,y)&&!blocked.has(k)&&(!reserved.has(k)||streets.has(k))&&(width>=3||streets.has(k)||sample(x,y).geology);});}
 function openingApproach(segments,x,y,width){const d=segments[0],normal=[d.sides[0][0]-d.sides[1][0],d.sides[0][1]-d.sides[1][1]],axis=normal[0]?1:0,outer=segments.map(d=>[x+d.sides[0][0],y+d.sides[0][1]]),lo=Math.floor(width/2),hi=width-lo-1,min=Math.min(...outer.map(p=>p[axis])),max=Math.max(...outer.map(p=>p[axis])),center=[...outer[0]],back=normal[0]>0||normal[1]>0?lo:hi;center[axis]=Math.max(max-hi,Math.min(min+lo,Math.floor((min+max)/2)));center[0]+=normal[0]*back;center[1]+=normal[1]*back;return center;}
 function raster(a,b){const out=[[...a]];let[x,y]=a;while(x!==b[0]||y!==b[1]){if(x!==b[0])x+=Math.sign(b[0]-x);else y+=Math.sign(b[1]-y);out.push([x,y]);}return out;}
 function simplify(points){const out=[points[0]];for(let i=1;i<points.length-1;i++)if(points[i][0]-points[i-1][0]!==points[i+1][0]-points[i][0]||points[i][1]-points[i-1][1]!==points[i+1][1]-points[i][1])out.push(points[i]);out.push(points.at(-1));return out;}
 function earthwork(cells){let cost=0,natural=0,excavated=0;const seen=new Set();for(const[x,y]of cells){const k=K(x,y);if(seen.has(k)||streets.has(k))continue;seen.add(k);const t=sample(x,y);if(t.rock===3)return{cost:Infinity,natural,excavated};if(vacated.has(k)){cost+=.2;}else if(t.geology){natural++;cost+=.3;}else{excavated++;cost+=.3+o.excavationCost*(t.rock===2?6:2)*(1.5-t.weakness);}}return{cost:Math.round(cost*10)/10,natural,excavated};}
 function spend(cost){remainingEffort-=cost;yearEffort+=cost;}
 const routeProfiles={planned:{dig:1,walk:.85,bend:2,lateral:.10},resident:{dig:1.25,walk:.32,bend:.35,lateral:0},cargo:{dig:.8,walk:1.35,bend:1.8,lateral:.025},egress:{dig:1,walk:.65,bend:.5,lateral:0}};
 function commitRoad(points,width,year,project,purpose,kind='project-access',scope='engineered'){
  const cells=widthCells(points,width),minimumWidth=cells.some(([x,y])=>!streets.has(K(x,y))&&!sample(x,y).geology)?3:2,work=earthwork(cells),routing=routeSummary(points,width,kind==='self-built'?'resident':kind==='site-access'?'egress':'planned'),id='S'+(roads.length+1),order=++eventCounter;
  if(width<minimumWidth)throw Error('挖岩道路至少3米：'+purpose);for(const[x,y]of cells){const k=K(x,y);if(!streets.has(k))streets.set(k,{x,y,year,order,roadId:id,kind});}
  const rd={id,order,routing,minimumWidth,points:simplify(points),center:points,width,year,builtYear:year,purpose,kind,scope,servesProject:project,serves:project?[project]:[],cells,earthwork:work};roads.push(rd);spatial=null;spend(work.cost);return rd;
 }
 // Station rooms and track bays are planned before public streets and government blocks.
 for(const cell of stationSite.cells)occupied.set(K(...cell),'B0000');
 for(const line of railDesign.lines){for(const arm of line.arms){const cells=railCells(arm.points);for(const cell of cells)reserved.add(K(...cell));}railPlans.push(line);}
 // The closest railway position determines whether a site belongs to the city or the outward transport section.
 // Index cutoffs only move outward with time, so earlier development remains valid.
 let territoryTree=null,territoryRadius=-1;const territoryCache=new Map(),cityEnds=new Map();
 function territoryNode(points,depth=0){if(!points.length)return null;const axis=depth%2;points.sort((a,b)=>a.p[axis]-b.p[axis]);const mid=points.length>>1;return{...points[mid],axis,left:territoryNode(points.slice(0,mid),depth+1),right:territoryNode(points.slice(mid+1),depth+1)};}
 function cityIndex(arm,radius){const index=arm.points.findIndex((p,i)=>i>1&&Math.hypot(...p)>radius+48);return index<0?arm.points.length-1:index;}
 function gateYear(year){const radius=Math.min(190,95+Math.floor(year/8)*18);if(radius===territoryRadius)return;territoryRadius=radius;territoryCache.clear();for(const route of railPlans)for(const arm of route.arms)cityEnds.set(arm.exitIndex,cityIndex(arm,radius));}
 function developmentAllowed(x,y){if(!territoryTree)return true;const key=K(x,y);if(territoryCache.has(key))return territoryCache.get(key);let best=x*x+y*y,allowed=true;
  function visit(node){if(!node)return;const distance=(node.p[0]-x)**2+(node.p[1]-y)**2,inner=node.index<=cityEnds.get(node.exitIndex);if(distance<best-1e-8||Math.abs(distance-best)<1e-8&&inner){best=distance;allowed=inner;}const delta=(node.axis?y:x)-node.p[node.axis],first=delta<0?node.left:node.right,second=delta<0?node.right:node.left;visit(first);if(delta*delta<=best+1e-8)visit(second);}
  visit(territoryTree);territoryCache.set(key,allowed);return allowed;
 }
 territoryTree=territoryNode(railPlans.flatMap(route=>route.arms.flatMap(arm=>arm.points.map((p,index)=>({p,index,exitIndex:arm.exitIndex})))));gateYear(0);
 const stationPublicEdges=new Map(stationSite.p.edges.map(e=>[e.axis+':'+(e.x+stationSite.x)+':'+(e.y+stationSite.y),e.kind]));
 function railCells(points){const cells=new Map(),half=o.mainWidth/2;for(const p of points)for(let y=Math.floor(p[1]-half);y<=p[1]+half;y++)for(let x=Math.floor(p[0]-half);x<=p[0]+half;x++)if(Math.hypot(x+.5-p[0],y+.5-p[1])<half){if(sample(x,y).rock===3||stationSite.mask.has(K(x,y)))throw Error('铁路完整净宽侵犯岩体或站房 '+x+','+y);cells.set(K(x,y),[x,y]);}return[...cells.values()];}
 for(const line of railPlans){const points=raster(line.bay[0],line.bay[1]);commitRoad(points,stationSite.trackWidth,0,'station',line.name+'站内轨道区','station-track');}
 for(const access of stationSite.accesses){const a=access.points[0],b=access.points[1],bend=[b[0],a[1]],points=[...raster(a,bend),...raster(bend,b).slice(1)];if(!widthCells(points,3).every(([x,y])=>free(x,y)))throw Error('站厅出入口缺少三米接路空间');commitRoad(points,3,0,'station','站厅公共接入通路','main');commitRoad([b],Math.max(3,Math.min(8,Math.ceil(Math.sqrt(o.junctionMax||9)))),0,'station','站前集散节点','main');}
 function stationWaiting(){const p=stationSite.p,cells=stationSite.cells,work=earthwork(cells),perArea=Math.round(work.cost/cells.length*80)/10,q={p,x:stationSite.x,y:stationSite.y,cells,paths:[],yards:[],year:0,id:'B0000',parcel:null,requiresMultipleExits:true,earthwork:work,totalCost:work.cost,sitePrepared:true,constructionMode:'站区整体开凿与站房建设',decision:{reason:'中央交通节点与换乘需求',service:'客流与线路',shortage:0,requested:o.passengerFlow,available:0},siting:{program:'station',score:perArea,constructionCost:work.cost,naturalShare:work.natural/cells.length,networkMetres:{station:0,jobs:null,services:null,people:null,freight:0,stops:0,district:null},localPeople:0,localJobs:0,localDemand:o.passengerFlow,localSupply:stationSite.platforms.length,factors:[{label:'单位面积站区建设',cost:perArea}],basis:'站厅、站台、出入口与满足转弯半径的接入线路共同选址'}};if(work.cost>remainingEffort)throw Error('公共投入不足以完成中央车站');commit(q,'government',0);}
 function extendRails(year,radius){gateYear(year);
  for(const route of railPlans){const active=route.arms.filter(a=>a.exit.year<=year);if(!active.length)continue;const truncate=arm=>{const points=[];for(const p of arm.points){points.push(p);if(Math.hypot(...p)>radius+48&&points.length>2)break;}return points;},bay=raster(route.bay[0],route.bay[1]);let points;
   if(route.mode==='through'){const left=active.find(a=>a.exitIndex===route.exitIndices[0]),right=active.find(a=>a.exitIndex===route.exitIndices[1]);points=[...(left?truncate(left).reverse():[bay[0]]),...bay.slice(1),...(right?truncate(right).slice(1):[])];}else points=[...bay,...truncate(active[0]).slice(1)];
   route.activeArms=active.map(a=>({...a,realized:truncate(a)}));route.realized=points;let road=route.road;if(!road){road=route.road={id:'rail-'+route.id,name:route.name,kind:'rail',scope:'tram-street',width:o.mainWidth,year,builtYear:year,order:++eventCounter,purpose:'中央车站与铁路出口',servesProject:'station',serves:['station'],earthwork:{cost:0,natural:0,excavated:0}};roads.push(road);}const cells=railCells(points),work=earthwork(cells);for(const key of ['cost','natural','excavated'])road.earthwork[key]+=work[key];spend(work.cost);for(const[x,y]of cells)if(!streets.has(K(x,y)))streets.set(K(x,y),{x,y,year,order:road.order,roadId:road.id,kind:'rail'});road.points=points;road.center=points;road.cells=cells;frontageVersion=-1;spatial=null;
  }
 }

 function outdoor(p){return(p.outdoors||[]).filter(s=>s.w*s.h<=o.courtMax).map(s=>({...s,cells:Array.from({length:s.w*s.h},(_,i)=>[s.x+i%s.w,s.y+Math.floor(i/s.w)])}));}
 const parcelAt=(x,y)=>parcels.find(b=>b.mask.has(K(x,y)));
 let frontageVersion=-1,frontages=[];
 // Public streets support development; loading and secondary-exit paths only provide access.
 function developmentStreet(s){return !!s?.roadId&&developmentAllowed(s.x,s.y)&&['main','rail','planned-grid','district-link','self-built'].includes(s.kind);}
 function streetFrontages(){if(frontageVersion===roads.length)return frontages;frontageVersion=roads.length;frontages=[];
  for(const s of streets.values())if(developmentStreet(s))for(let d=0;d<4;d++){const n=D[d],x=s.x+n[0],y=s.y+n[1];if(!streets.has(K(x,y))&&!reserved.has(K(x,y)))frontages.push({x,y,side:d,street:s,parcel:parcelAt(x,y)});}return frontages;
 }
 // Distances and catchments follow the actual four-neighbour street network, including access paths.
 // A track is traversable, but only a realised stop or loading facility contributes transport benefit.
 function spatialContext(){
  if(spatial)return spatial;
  const publicStation=stationSite.publicCells.filter(p=>!streets.has(K(...p))).map(([x,y])=>({x,y,kind:'station-interior'})),cells=[...streets.values(),...publicStation],ids=new Map(cells.map((s,i)=>[K(s.x,s.y),i])),N=cells.length,neighbours=new Int32Array(N*4);neighbours.fill(-1);
  for(let i=0;i<N;i++)for(let d=0;d<4;d++){const a=cells[i],b=[a.x+D[d][0],a.y+D[d][1]],edge=D[d][0]?('vertical:'+Math.max(a.x,b[0])+':'+a.y):('horizontal:'+a.x+':'+Math.max(a.y,b[1]));neighbours[i*4+d]=stationPublicEdges.get(edge)==='wall'?-1:ids.get(K(...b))??-1;}
  const queue=new Int32Array(N),visited=new Int32Array(N),depth=new Uint16Array(N);let stamp=0;
  function distances(sources){const out=new Float64Array(N);out.fill(Infinity);let h=0,t=0;for(const i of sources)if(i!==undefined&&out[i]!==0){out[i]=0;queue[t++]=i;}while(h<t){const i=queue[h++];for(let d=0;d<4;d++){const j=neighbours[i*4+d];if(j>=0&&out[j]===Infinity){out[j]=out[i]+1;queue[t++]=j;}}}return out;}
  const hub=ids.get(K(0,0)),station=distances([hub]),anchors={jobs:[],services:[],people:[],freight:[hub],stops:[hub],district:[]},fields={people:new Float64Array(N),jobs:new Float64Array(N)};
  for(const key of Object.keys(C.demandLabels))fields[key]=new Float64Array(N);
  const indexAt=(x,y)=>ids.get(K(Math.round(x),Math.round(y)));
  for(const q of projects){const door=q.p.doors.find(d=>d.a<0),i=indexAt(q.x+door.sides[0][0],q.y+door.sides[0][1]);if(i===undefined||!Number.isFinite(station[i]))continue;
   const cap=q.capacity||C.planningCapacity(q.p,o),people=(cap.family||0)+(cap.workers||0)+(cap.guests||0),jobs=(cap.industry||0)+(cap.repair||0),values=Object.entries({...cap,people,jobs}).filter(([key,value])=>value&&fields[key]);
   if(people)anchors.people.push(i);if(jobs)anchors.jobs.push(i);if(cap.retail||cap.meals||cap.health)anchors.services.push(i);if(q.p.program==='transport')anchors.freight.push(i);
   // Local demand and supply use the same 96 m walking catchment and quadratic distance decay.
   let h=0,t=0;stamp++;queue[t++]=i;visited[i]=stamp;depth[i]=0;
   while(h<t){const at=queue[h++],distance=depth[at],weight=(1-distance/96)**2;for(const[key,value]of values)fields[key][at]+=value*weight;
    if(distance>=95)continue;for(let d=0;d<4;d++){const next=neighbours[at*4+d];if(next>=0&&visited[next]!==stamp){visited[next]=stamp;depth[next]=distance+1;queue[t++]=next;}}
   }
  }
  for(const q of quarters)for(const id of q.roadIds){const road=roads.find(r=>r.id===id);if(road)for(const point of road.center){const i=indexAt(...point);if(i!==undefined)anchors.district.push(i);}}
  for(const route of railPlans){const points=route.realized;if(!points||railPlans.indexOf(route)>=Math.ceil(railPlans.length*o.railCoverage))continue;const length=points.reduce((n,p,i)=>i?n+Math.hypot(p[0]-points[i-1][0],p[1]-points[i-1][1]):0,0);if(length<o.minRailLength)continue;for(let k=o.stopSpacing;k<points.length-20;k+=o.stopSpacing)anchors.stops.push(indexAt(...points[k]));}
  spatial={cells,ids,station,fields,indexAt,ratings:new Map(),needs:C.populationNeeds(o,currentYear),...Object.fromEntries(Object.entries(anchors).map(([key,sources])=>[key,distances(sources)]))};return spatial;
 }
 function siteContext(program,street,phase='resident'){
  const ctx=spatialContext(),i=ctx.indexAt(street.x,street.y);if(i===undefined||!Number.isFinite(ctx.station[i]))return null;
  const cacheKey=program+':'+phase+':'+i;if(ctx.ratings.has(cacheKey))return ctx.ratings.get(cacheKey);const capDistance=v=>Math.min(360,Number.isFinite(v)?v:360),d=Object.fromEntries(['station','jobs','services','people','freight','stops','district'].map(key=>[key,capDistance(ctx[key][i])])),f=Object.fromEntries(Object.entries(ctx.fields).map(([key,values])=>[key,values[i]])),key=C.programs[program].key;
  const residential=['family','workers'].includes(key),industrial=['industry','repair','logistics'].includes(key),needs=ctx.needs,ratio=(needs.targets[key]||0)/Math.max(1,needs.population),localNeed=f.people*ratio,localSupply=f[key],gap=Math.max(0,localNeed-localSupply),competition=localNeed>0?Math.min(2,localSupply/Math.max(1,localNeed)):0;
  let factors;
  if(residential)factors=[['就业通达',d.jobs*.12],['生活服务',d.services*.08],['邻里与规划配套',Math.min(d.people,d.district+12)*.22],['车站步行',d.stops*.035],['就业住房平衡',Math.max(0,f.people*o.employmentRate-f.jobs)*.09]];
  else if(key==='guests')factors=[['客运站点',d.stops*.20],['生活服务',d.services*.08],['聚落联系',Math.min(d.people,d.district+12)*.12]];
  else if(industrial)factors=[['货运接入',d.freight*(key==='logistics'?.20:.10)],['产业协作',d.jobs*.045],['劳动力通达',d.people*.08],['居住干扰',program==='production'?Math.max(0,24-d.people)*.6:0]];
  else factors=[['服务对象通达',d.people*.24],['当地供需',competition*18-gap*.12],['公共交通',d.stops*.035]];
  factors.push(['中央站联系',d.station*.025]);
  // Planned districts bring a complete package of housing and services; resident projects need existing support.
  if(phase==='government')factors=factors.map(([name,value])=>[name,value*.45]);
  const round=v=>Math.round(v*10)/10,score=factors.reduce((n,[,v])=>n+v,0);
  const result={score,program,networkMetres:Object.fromEntries(Object.entries(d).map(([k,v])=>[k,Number.isFinite(ctx[k][i])?ctx[k][i]:null])),localDemand:round(localNeed),localSupply:round(localSupply),localPeople:round(f.people),localJobs:round(f.jobs),factors:factors.map(([label,value])=>({label,cost:round(value)}))};ctx.ratings.set(cacheKey,result);return result;
 }
 function rateSite(q,phase){if(!developmentStreet(q.frontage))return null;const context=siteContext(q.p.program,q.frontage,phase);if(!context)return null;const construction=q.totalCost/Math.max(1,q.cells.length)*8,accessTravel=(q.paths||[]).reduce((n,a)=>n+routeSummary(a.path,a.width,a.role?.includes('货')||a.role?.includes('装卸')?'cargo':'egress').travelCost,0)/Math.max(1,Math.sqrt(q.cells.length));
  return{...context,score:context.score+construction+accessTravel,constructionCost:q.totalCost,naturalShare:q.earthwork.natural/Math.max(1,q.cells.length),factors:[...context.factors,{label:'单位面积建设',cost:Math.round(construction*10)/10},{label:'场内接路通行',cost:Math.round(accessTravel*10)/10}],basis:'建造时的路网、周边容量与地质；步行服务范围96米'};
 }
 const gridHash=hash(seed+'-shared-streets'),junctions=new Map(),streetEdges=new Map(),developedBlocks=new Set();
 function gridCoordinate(i,axis){let v=0;for(let k=0;k<Math.abs(i);k++)v+=i>0&&k===0?stationSite.accesses[1].points[1][axis]-stationSite.gridOrigin[axis]:Math.round(o.blockScale*(.78+gridHash(k,axis,i<0?4:3)*.38));return i<0?-v:v;}
 function junction(i,j){const key=K(i,j);if(junctions.has(key))return junctions.get(key);if(i===0&&j===0||i===1&&j===1){const point=i===0?stationSite.gridOrigin:stationSite.accesses[1].points[1];junctions.set(key,[...point]);return junctions.get(key);}const x=gridCoordinate(i,0)+stationSite.gridOrigin[0],y=gridCoordinate(j,1)+stationSite.gridOrigin[1];let best=[x,y],score=Infinity;
  // Shared junctions move together with their incident streets; neighbours cannot invent a second boundary road.
  for(let dy=j===0?0:-8;dy<=(j===0?0:8);dy+=4)for(let dx=i===0?0:-8;dx<=(i===0?0:8);dx+=4){let cost=0;for(const[a,b]of [[0,0],[3,0],[-3,0],[0,3],[0,-3]]){const t=sample(x+dx+a,y+dy+b);cost+=t.rock===3?1000:t.geology?.2:2*(1.5-t.weakness);}cost+=Math.hypot(dx,dy)*.45;if(cost<score){score=cost;best=[x+dx,y+dy];}}
  junctions.set(key,best);return best;
 }
 function boundarySpecs(i,j){return[[i,j,i+1,j],[i+1,j,i+1,j+1],[i+1,j+1,i,j+1],[i,j+1,i,j]].map(([a,b,c,d])=>({key:[K(a,b),K(c,d)].sort().join('|'),a:junction(a,b),b:junction(c,d)}));}
 // Construction counts the complete width; walking and bends have independent, positive costs.
 function routeSummary(points,width,profile){const weights=routeProfiles[profile],work=earthwork(widthCells(points,width));let bends=0;for(let i=2;i<points.length;i++)if(points[i][0]-points[i-1][0]!==points[i-1][0]-points[i-2][0]||points[i][1]-points[i-1][1]!==points[i-1][1]-points[i-2][1])bends++;
  const length=points.length-1,direct=Math.abs(points[0][0]-points.at(-1)[0])+Math.abs(points[0][1]-points.at(-1)[1]);return{profile,width,length,direct,bends,construction:work.cost,travelCost:length*weights.walk,turnCost:bends*weights.bend,score:work.cost*weights.dig+length*weights.walk+bends*weights.bend};
 }
 function routePath(a,b,width,profile,blocked=new Set(),extra=new Map()){
  const weights=routeProfiles[profile],lo=Math.floor(width/2),hi=width-lo-1,direct=Math.abs(b[0]-a[0])+Math.abs(b[1]-a[1]),heap=new Heap(),cost=new Map(),parents=new Map(),coords=new Map(),valid=new Map(),steps=new Map(),start=K(...a)+':4';
  const heuristic=(x,y)=>(Math.abs(x-b[0])+Math.abs(y-b[1]))*weights.walk;
  function clear(x,y){const key=K(x,y);if(valid.has(key))return valid.get(key);const cells=widthCells([[x,y]],width),fits=roadCellsFit(cells,width,blocked)&&cells.every(([xx,yy])=>profile!=='resident'||!parcelAt(xx,yy)?.major||streets.has(K(xx,yy)));valid.set(key,fits);return fits;}
  function step(x,y,direction){const key=K(x,y)+':'+direction;if(steps.has(key))return steps.get(key);if(!clear(x,y))return Infinity;const[dx,dy]=D[direction];let dig=0;
   // Only the new leading strip is charged on each step, avoiding width-squared repetition.
   for(let n=-lo;n<=hi;n++){const xx=dx?x+(dx>0?hi:-lo):x+n,yy=dy?y+(dy>0?hi:-lo):y+n,k=K(xx,yy);if(!streets.has(k)&&!extra.has(k))dig+=earthwork([[xx,yy]]).cost;}
   const lateral=Math.abs((x-a[0])*(b[1]-a[1])-(y-a[1])*(b[0]-a[0]))/Math.max(1,direct),value=dig*weights.dig+weights.walk+lateral*weights.lateral;steps.set(key,value);return value;
  }
  if(!clear(...a)||!clear(...b))return null;cost.set(start,0);coords.set(start,[...a,4]);heap.push(start,heuristic(...a));let visits=0,end=null;
  while(heap.length&&visits++<(profile==='planned'?30000:14000)){const[k,value]=heap.pop(),[x,y,previous]=coords.get(k),base=cost.get(k);if(value>base+heuristic(x,y)+.001)continue;if(x===b[0]&&y===b[1]){end=k;break;}
   for(let direction=0;direction<4;direction++){const[dx,dy]=D[direction],xx=x+dx,yy=y+dy,padding=profile==='planned'?32:16;if(xx<Math.min(a[0],b[0])-padding||xx>Math.max(a[0],b[0])+padding||yy<Math.min(a[1],b[1])-padding||yy>Math.max(a[1],b[1])+padding)continue;
    const next=K(xx,yy)+':'+direction,nv=base+step(xx,yy,direction)+(previous===4||previous===direction?0:weights.bend);if(nv<(cost.get(next)??Infinity)){cost.set(next,nv);coords.set(next,[xx,yy,direction]);parents.set(next,k);heap.push(next,nv+heuristic(xx,yy));}
   }
  }
  if(!end)return null;const path=[];for(let k=end;k;k=parents.get(k))path.push(coords.get(k).slice(0,2));return path.reverse();
 }
 function plannedPath(a,b,width,extra=new Map()){return routePath(a,b,width,'planned',new Set(),extra);}
 function accessPath(start,end,width,blocked=new Set(),profile='egress'){return routePath(start,end,width,profile,blocked);}
 function commissionSpaces(parcel,corners,year){
  const add=(program,cells,junctionId=null)=>{const work=earthwork(cells);if(!cells.length||work.cost>remainingEffort*.15)return false;spend(work.cost);
   const space={id:'C'+(spaces.length+1),name:program==='park'?'街区公园':'路口广场',program,junctionId,kind:program,purpose:program==='park'?'独立规划的地下公园，供休息、种植与邻里活动':'十字路口的集散、会合与公共活动场地',projectId:parcel.quarterId,buildingIds:[],year,builtYear:year,cells};
   spaces.push(space);for(const p of cells)occupied.set(K(...p),parcel.quarterId);return true;
  };
  if(spaces.filter(s=>s.program==='plaza').length<o.plazaCount){
   for(const node of corners){if(spaces.some(s=>s.program==='plaza'&&s.junctionId===K(...node)))continue;const arms=D.filter(([dx,dy])=>[6,9].every(distance=>[-2,-1,0,1,2].some(offset=>streets.has(K(node[0]+dx*distance+dy*offset,node[1]+dy*distance-dx*offset)))));if(arms.length!==4)continue;
    const cells=[];for(let y=node[1]-11;y<=node[1]+11;y++)for(let x=node[0]-11;x<=node[0]+11;x++)if(parcel.mask.has(K(x,y))&&free(x,y)&&!streets.has(K(x,y))&&!reserved.has(K(x,y)))cells.push([x,y]);
    if(cells.length<36)continue;const keys=new Set(cells.map(p=>K(...p))),seen=new Set(),queue=cells.filter(([x,y])=>D.some(([dx,dy])=>streets.has(K(x+dx,y+dy))));for(const p of queue)seen.add(K(...p));for(let i=0;i<queue.length;i++)for(const[dx,dy]of D){const p=[queue[i][0]+dx,queue[i][1]+dy],k=K(...p);if(keys.has(k)&&!seen.has(k)){seen.add(k);queue.push(p);}}
    if(seen.size===cells.length&&add('plaza',cells,K(...node)))break;
   }
  }
  if(parcel.mask.size>=900&&spaces.filter(s=>s.program==='park').length<o.parkCount&&parcel.program!=='production'){
   const candidates=[],w=12,h=10;
   for(let y=parcel.y+2;y<=parcel.y+parcel.h-h-2;y+=2)for(let x=parcel.x+2;x<=parcel.x+parcel.w-w-2;x+=2){const cells=[];let valid=true,frontage=0;
    for(let yy=y;yy<y+h&&valid;yy++)for(let xx=x;xx<x+w;xx++){const k=K(xx,yy);if(!parcel.mask.has(k)||!free(xx,yy)||streets.has(k)||reserved.has(k)){valid=false;break;}cells.push([xx,yy]);frontage+=D.some(([dx,dy])=>streets.has(K(xx+dx,yy+dy)));}
    if(valid&&frontage>=6)candidates.push({cells,score:earthwork(cells).cost-frontage*3});
   }
   candidates.sort((a,b)=>a.score-b.score);if(candidates.length)add('park',candidates[0].cells);
  }
 }
 function fillQuarter(parcel,kind,index,year,cycle,R,mainUse){
  const mask=parcel.mask,bounds=parcel,streetArea=new Set(),minX=bounds.x,minY=bounds.y,stride=bounds.w+1;
  for(const k of mask)if(streets.has(k))streetArea.add(k);
  parcel.buildableArea=[...mask].filter(k=>!streets.has(k)&&!occupied.has(k)&&!reserved.has(k)&&sample(...k.split(',').map(Number)).rock!==3).length;
  let placed=0;const unavailable=new Set();
  for(let pass=0;pass<90;pass++){
   const prefix=new Int32Array((bounds.w+1)*(bounds.h+1)),sites=[];
   for(let yy=0;yy<bounds.h;yy++)for(let xx=0;xx<bounds.w;xx++){const x=minX+xx,y=minY+yy,k=K(x,y),clear=mask.has(k)&&free(x,y)&&!streets.has(k)&&!reserved.has(k),i=(yy+1)*stride+xx+1;prefix[i]=(clear?0:1)+prefix[i-1]+prefix[i-stride]-prefix[i-stride-1];if(clear)for(let d=0;d<4;d++)if(developmentStreet(streets.get(K(x+D[d][0],y+D[d][1]))))sites.push({x,y,r:d});}
   const clearRect=(x,y,w,h)=>{x-=minX;y-=minY;if(x<0||y<0||x+w>bounds.w||y+h>bounds.h)return false;return prefix[(y+h)*stride+x+w]-prefix[y*stride+x+w]-prefix[(y+h)*stride+x]+prefix[y*stride+x]===0;};
   const choice=placed===0&&!unavailable.has(mainUse)?{program:mainUse}:useChoices(year,'government',R,unavailable,true)[0];if(!choice)break;
   const program=choice.program,def=C.programs[program],major=def.area>=600,target=def.area*(.75+R()*.5)*(program==='production'?o.factoryScale*o.factoryScale:1),candidates=[];
   const widths=(major?[18,22,26,30,36,42,48,56]:[6,8,10,12,14,16,20,24]).filter(v=>v>=def.minW),depths=(major?[12,18,22,28,34,40]:[6,8,10,12,16,20]).filter(v=>v>=def.minH);
   const step=Math.max(1,Math.floor(sites.length/180));
   for(let si=Math.floor(R()*step);si<sites.length;si+=step){const f=sites[si],context=siteContext(program,streets.get(K(f.x+D[f.r][0],f.y+D[f.r][1])),'government');if(!context)continue;for(const w of widths)for(const h of depths){const ax=f.r===0?Math.floor(w/2):f.r===1?h-1:f.r===2?w-1-Math.floor(w/2):0,ay=f.r===0?0:f.r===1?Math.floor(w/2):f.r===2?h-1:w-1-Math.floor(w/2),ww=f.r%2?h:w,hh=f.r%2?w:h,x=f.x-ax,y=f.y-ay;
     if(!clearRect(x,y,ww,hh))continue;let terrain=0;for(let yy=y;yy<y+hh;yy+=4)for(let xx=x;xx<x+ww;xx+=4){const t=sample(xx,yy);terrain+=t.geology?.15:(t.rock===2?6:2)*(1.5-t.weakness);}terrain/=Math.ceil(ww/4)*Math.ceil(hh/4);
     const score=Math.abs(Math.log(w*h/target))*3+terrain*.22+Math.abs(w-h)*.012+context.score*.08;candidates.push({x,y,w,h,r:f.r,score});
   }}
   candidates.sort((a,b)=>a.score-b.score);let done=false;
   for(const c of candidates.slice(0,30)){
    const bid='B'+String(sequence+1).padStart(4,'0'),raw=Layouts.fitted(seed+'-planned-'+index+'-'+placed,c.w,c.h,program,C.random(seed+'-lot-'+index+'-'+placed),o,(placed+index)%4),p=rotated(compile(raw),c.r);p.outdoorCells=outdoor(p);
    const q=proposal(p,c.x,c.y,year,bid,parcel,false);if(!q)continue;q.siting=rateSite(q,'government');if(!q.siting)continue;q.decision=decisionFor(program,year,'government');sequence++;q.constructionMode=kind==='cavern'?'共用洞厅内建设':'街道与房间直接开凿';commit(q,'government',cycle);placed++;unavailable.clear();done=true;break;
   }
   if(!done){unavailable.add(program);if(placed===0&&major)return 0;}
  }
  // Unassigned land retains its original geology; public spaces are commissioned before building placement.
  const stationArea=[...mask].filter(k=>stationSite.mask.has(k)).length,floor=projects.filter(q=>q.parcel===parcel).reduce((n,q)=>n+q.cells.length,0)+stationArea,used=[...mask].filter(k=>occupied.has(k)||streets.has(k)).length;
  parcel.buildableArea=[...mask].filter(k=>!streets.has(k)&&(!occupied.has(k)||parcel.buildingIds.includes(occupied.get(k)))&&!reserved.has(k)&&sample(...k.split(',').map(Number)).rock!==3).length;
  parcel.stationArea=stationArea;parcel.fillRatio=floor/mask.size;parcel.developedRatio=used/mask.size;return placed;
 }
 function transaction(){return{spatial,occupied:new Map(occupied),streets:new Map(streets),vacated:new Map(vacated),junctions:new Map(junctions),roads:[...roads],spaces:[...spaces],projects:[...projects],quarters:quarters.length,parcels:parcels.length,effort:yearEffort,remaining:remainingEffort,sequence,eventCounter,serves:roads.map(r=>[...r.serves])};}
 function rollback(s){for(const [map,copy]of [[occupied,s.occupied],[streets,s.streets],[vacated,s.vacated],[junctions,s.junctions]]){map.clear();for(const[k,v]of copy)map.set(k,v);}roads.splice(0,roads.length,...s.roads);spaces.splice(0,spaces.length,...s.spaces);projects.splice(0,projects.length,...s.projects);quarters.length=s.quarters;parcels.length=s.parcels;roads.forEach((r,i)=>r.serves=s.serves[i]);yearEffort=s.effort;remainingEffort=s.remaining;sequence=s.sequence;eventCounter=s.eventCounter;frontageVersion=-1;spatial=s.spatial;}
 function clearingPlan(c,year){
  if(!year)return{clear:[],keep:[],cost:0,area:0};const residents=projects.filter(q=>q.phase==='resident'&&!q.parcel&&q.cells.some(([x,y])=>C.inside(c.corners,x+.5,y+.5)||c.corners.some(p=>Math.abs(p[0]-x)<5&&Math.abs(p[1]-y)<5))),clear=[],keep=[];let cost=0,area=0;
  for(const q of residents){const capacity=q.capacity,people=(capacity.family||0)+(capacity.workers||0)+(capacity.guests||0),business=Object.entries(capacity).filter(([key])=>!['family','workers','guests'].includes(key)).reduce((n,[,v])=>n+v,0),age=year-q.year,organization=gridHash(q.x,q.y,51),resistance=(.25+Math.log1p(people)/3+Math.min(1,age/30)+Math.min(1,business/180))*(.4+organization*.8)*o.resistanceLevel,force=o.executionStrength*(.8+o.resettlementSupport*.8),price=Math.round(q.cells.length*(.35+o.resettlementSupport*.3)+people*(2+o.resettlementSupport*5)+business*.15+resistance*60),entry={q,people,business,resistance:Math.round(resistance*100)/100,cost:price};area+=q.cells.length;
   if(resistance>force||cost+price>remainingEffort*.3)keep.push(entry);else{clear.push(entry);cost+=price;}
  }return{clear,keep,cost,area};
 }
 function stageClearance(plan){
  for(const item of plan.clear){const q=item.q;for(const p of q.cells){const key=K(...p);occupied.delete(key);vacated.set(key,{year:Math.min(vacated.get(key)?.year??Infinity,q.cellYears.get(key)??q.year),demolishedYear:currentYear,owner:q.id});}
   for(let i=spaces.length-1;i>=0;i--)if(spaces[i].projectId===q.id){for(const p of spaces[i].cells){const key=K(...p);occupied.delete(key);vacated.set(key,{year:Math.min(vacated.get(key)?.year??Infinity,spaces[i].year),demolishedYear:currentYear,owner:q.id});}spaces.splice(i,1);}projects.splice(projects.indexOf(q),1);
  }spend(plan.cost);frontageVersion=-1;spatial=null;
 }
 function adaptJunctions(c){
  for(const[i,j]of [[c.i,c.j],[c.i+1,c.j],[c.i+1,c.j+1],[c.i,c.j+1]]){const id=K(i,j);if([...streetEdges.keys()].some(key=>key.split('|').includes(id)))continue;const p=junction(i,j),fits=p=>widthCells([p],o.streetMax).every(([x,y])=>free(x,y));if(fits(p))continue;
   const candidates=[],reach=Math.min(8,Math.floor(o.blockScale*.15));for(let dy=-reach;dy<=reach;dy+=2)for(let dx=-reach;dx<=reach;dx+=2){const at=[p[0]+dx,p[1]+dy];if(fits(at))candidates.push({at,cost:earthwork(widthCells([at],o.streetMax)).cost+Math.hypot(dx,dy)*5});}candidates.sort((a,b)=>a.cost-b.cost);if(candidates.length)junctions.set(id,candidates[0].at);
  }
  c.specs=boundarySpecs(c.i,c.j);c.corners=[junction(c.i,c.j),junction(c.i+1,c.j),junction(c.i+1,c.j+1),junction(c.i,c.j+1)];
 }
 function makeQuarter(year,cycle,index){
  progress('development','第 '+year+' 年：评估第 '+(index+1)+' 规划区',year,o.years+1);const R=C.random(seed+'-network-district-'+index),choice=useChoices(year,'government',R,new Set(),true)[0];if(!choice){planningEvents.push({year,cycle,status:'deferred',kind:'review',reason:'当前用途规则下没有可安排的规划项目'});return null;}const mainUse=choice.program,kind=mainUse==='production'?'production':mainUse==='transport'?'transport':['housing','dorm','lodging'].includes(mainUse)?'housing':'civic',candidates=[];
  for(let j=-3;j<3;j++)for(let i=-3;i<3;i++){if(developedBlocks.has(K(i,j)))continue;const specs=boundarySpecs(i,j),shared=specs.filter(s=>streetEdges.has(s.key));
   const corners=[junction(i,j),junction(i+1,j),junction(i+1,j+1),junction(i,j+1)],cx=corners.reduce((n,p)=>n+p[0],0)/4,cy=corners.reduce((n,p)=>n+p[1],0)/4;
   let effort=0,area=0,hard=0;
   const minX=Math.min(...corners.map(p=>p[0])),maxX=Math.max(...corners.map(p=>p[0])),minY=Math.min(...corners.map(p=>p[1])),maxY=Math.max(...corners.map(p=>p[1]));
   for(let y=minY;y<maxY;y+=4)for(let x=minX;x<maxX;x+=4)if(C.inside(corners,x+.5,y+.5)){const t=sample(x,y);area++;hard+=t.rock===3;effort+=t.geology?.2:(t.rock===2?6:2)*(1.5-t.weakness);}
   if(hard/Math.max(1,area)>.06)continue;
   const network=spatialContext(),connections=[];for(const a of corners){let nearest=null;for(let n=0;n<network.cells.length;n+=4){const t=network.cells[n];if(!developmentStreet(t)||!Number.isFinite(network.station[n]))continue;const distance=Math.abs(a[0]-t.x)+Math.abs(a[1]-t.y);if(!nearest||distance<nearest.distance)nearest={a,b:[t.x,t.y],distance,street:t};}if(nearest)connections.push(nearest);}connections.sort((a,b)=>a.distance-b.distance);if(!connections.length)continue;
   const connection=connections[0],context=siteContext(mainUse,connection.street,'government'),connectionEffort=earthwork(widthCells(raster(connection.a,connection.b),Math.max(3,o.streetMin))).cost;
   const clearing=clearingPlan({corners},year),renewalScore=year?clearing.area/Math.max(1,area*16)*(50-180*o.renewalBias)+clearing.cost/600+clearing.keep.reduce((n,q)=>n+q.q.cells.length,0)/Math.max(1,area*16)*45:0;
   candidates.push({i,j,specs,corners,clearing,connections,shared:shared.length,score:effort/Math.max(1,area)*35+Math.hypot(cx,cy)*.03+Math.min(120,connectionEffort/80)+connection.distance*.12+context.score*.65+(shared.length?0:8)+renewalScore+R()*3});
  }
  candidates.sort((a,b)=>a.score-b.score);
  let retainedAttempts=0;
  for(const c of candidates){const snapshot=transaction(),clearing=clearingPlan(c,year);retainedAttempts+=clearing.keep.length;stageClearance(clearing);adaptJunctions(c);
   const attempt=()=>{
   const width=o.streetMax,extra=new Map(),paths=[],boundary=[];let valid=true;
   for(const spec of c.specs){const old=streetEdges.get(spec.key);let points=old?.center;if(points&&K(...points[0])!==K(...spec.a))points=[...points].reverse();if(!points)points=plannedPath(spec.a,spec.b,width,extra);if(!points){valid=false;break;}boundary.push(...points.slice(0,-1));paths.push({spec,points,width:old?.width||width,old});for(const p of widthCells(points,old?.width||width))extra.set(K(...p),p);}
   if(!valid)return null;
   const x=Math.min(...boundary.map(p=>p[0])),y=Math.min(...boundary.map(p=>p[1])),w=Math.max(...boundary.map(p=>p[0]))-x+1,h=Math.max(...boundary.map(p=>p[1]))-y+1;
   const major=['production','transport','civic'].includes(kind),rows=major&&h<70?1:Math.max(1,Math.ceil(h/38)),cols=w>68?Math.ceil(w/40):1;
   for(const [count,first,last,reverse]of [[rows,3,1,true],[cols,0,2,false]])for(let k=1;k<count;k++){const f=k/count,one=paths[first].points,two=paths[last].points,a=one[Math.min(one.length-1,Math.floor(one.length*(reverse?1-f:f)))],b=two[Math.min(two.length-1,Math.floor(two.length*(reverse?f:1-f)))],width=Math.max(3,o.streetMin-1),points=plannedPath(a,b,width,extra);if(points){paths.push({points,width});for(const p of widthCells(points,width))extra.set(K(...p),p);}}

   const mask=new Set();for(let yy=y;yy<y+h;yy++)for(let xx=x;xx<x+w;xx++)if(C.inside(boundary,xx+.5,yy+.5))mask.add(K(xx,yy));if(mask.size<200)return null;
   const work=earthwork([...mask].map(k=>k.split(',').map(Number)).filter(([x,y])=>sample(x,y).rock!==3));if(work.cost>remainingEffort*.92)return null;
   const network=spatialContext(),touches=[...extra.keys()].some(k=>{const i=network.ids.get(k);return i!==undefined&&Number.isFinite(network.station[i]);});let connector=null;
   if(!touches){const width=Math.max(3,o.streetMin),options=[];for(const a of c.corners){for(const old of c.connections){const points=plannedPath(a,old.b,width,extra);if(!points)continue;const cells=widthCells(points,width);if(cells.some(([x,y])=>reserved.has(K(x,y))&&!streets.has(K(x,y))))continue;const work=earthwork(cells);options.push({points,width,cost:work.cost});}}options.sort((a,b)=>a.cost-b.cost);connector=options[0];if(!connector||work.cost+connector.cost>remainingEffort*.92)return null;}
   const id='D'+(quarters.length+1),q={id,name:'第'+(index+1)+'规划街坊',program:kind,security:index%3===0?'较弱':'正常',year,cycle,x,y,w,h,category:kind==='production'?'industry':'housing',roadIds:[],blockIds:[],constructionMode:kind==='cavern'?'共用洞厅内建设':'街道与房间直接开凿',complete:true},parcel={id:'K'+(parcels.length+1),quarterId:id,district:id,year,cycle,x,y,w,h,mask,major:kind==='production'||kind==='transport',kind:kind==='cavern'?'共用洞厅街坊':'沿共用路网建设街坊',method:'street-block',program:kind,buildingIds:[],accessRoadIds:q.roadIds,layout:'共用街道围合、地形适配与成组功能空间',security:q.security};
   for(const path of paths){const rd=path.old||commitRoad(path.points,path.width,year,id,'规划街坊共用街道','planned-grid');if(!rd.serves.includes(id))rd.serves.push(id);q.roadIds.push(rd.id);}
   if(connector){const link=commitRoad(connector.points,connector.width,year,id,'独立规划区连接街','district-link');q.roadIds.push(link.id);connector.cost=link.earthwork.cost;}q.siting={sharedEdges:c.shared,detached:c.shared===0,connectionCost:connector?.cost||0,connectionLength:connector?connector.points.length-1:0,score:Math.round(c.score*10)/10};parcels.push(parcel);quarters.push(q);q.blockIds.push(parcel.id);frontageVersion=-1;spatial=null;
   commissionSpaces(parcel,c.corners,year);
   const count=fillQuarter(parcel,kind,index,year,cycle,R,mainUse);
   const retained=clearing.keep.filter(item=>item.q.cells.some(([x,y])=>mask.has(K(x,y))));
   const retainedArea=retained.reduce((n,item)=>n+item.q.cells.filter(p=>mask.has(K(...p))).length,0);parcel.fillRatio+=retainedArea/mask.size;parcel.retainedArea=retainedArea;parcel.buildableArea+=retainedArea;parcel.newBuildArea=projects.filter(p=>p.parcel===parcel).reduce((n,p)=>n+p.cells.length,0);
   if(count<1||(parcel.newBuildArea+retainedArea)/Math.max(1,parcel.buildableArea)<.5)return null;

   const openCavity=[...mask].filter(k=>!occupied.has(k)&&!streets.has(k)&&sample(...k.split(',').map(Number)).geology).length;
   if(openCavity>Math.max(40,mask.size*.06)){q.constructionMode='共用洞厅内建设';parcel.kind='天然洞厅内建筑群';for(const project of projects.filter(p=>p.parcel===parcel))project.constructionMode=q.constructionMode;}
   for(const path of paths)if(path.spec&&!path.old)streetEdges.set(path.spec.key,roads.find(r=>r.id===q.roadIds[paths.indexOf(path)]));developedBlocks.add(K(c.i,c.j));q.fillRatio=parcel.fillRatio;q.developedRatio=parcel.developedRatio;q.closedLoops=1;
   for(const item of retained)if(item.q.cells.every(p=>mask.has(K(...p)))){item.q.parcel=parcel;parcel.buildingIds.push(item.q.id);item.q.retainedInPlanYear=year;}
   const removed=new Set(clearing.clear.map(item=>item.q.id));for(const road of roads){road.serves=road.serves.filter(id=>!removed.has(id));if(removed.has(road.servesProject))road.servesProject=q.id;if(!road.serves.length)road.serves.push(q.id);}
   for(const item of clearing.clear){const old=item.q;demolitions.push({buildingId:old.id,name:old.p.name,program:old.p.program,builtYear:old.year,year,quarterId:q.id,people:item.people,resistance:item.resistance,cost:item.cost,lostCapacity:{...old.capacity},cells:old.cells.map(([x,y])=>[x+origin[0],y+origin[1]])});relocationPending+=item.people;totalDisplaced+=item.people;}
   q.retainedBuildings=retained.map(item=>item.q.id);q.demolishedBuildings=[...removed];q.redevelopment=clearing.area>0;
   planningEvents.push({year,cycle,status:'built',quarterId:q.id,kind:q.redevelopment?'renewal':'expansion',use:mainUse,demolished:[...removed],retained:retained.map(item=>({id:item.q.id,name:item.q.p.name,resistance:item.resistance})),clearanceCost:clearing.cost,peopleDisplaced:clearing.clear.reduce((n,item)=>n+item.people,0)});
   return q;
   };
   const result=attempt();if(result)return result;rollback(snapshot);
  }
  planningEvents.push({year,cycle,status:'deferred',kind:'review',retainedCandidates:retainedAttempts,reason:retainedAttempts?'拆迁阻力与现有建筑限制，项目延期评估':'缺少满足地质、需求与预算的完整场地'});if(year===0)warnings.push('第'+(index+1)+'街坊未找到可完整建设的地点');return null;
 }

 function streetDoors(p,x,y){
  const doors=p.doors.map(d=>({...d})),edges=p.edges.map(e=>({...e})),outside=p.doors.filter(d=>d.a<0),area=p.rooms.reduce((n,r)=>n+r.w*r.h,0);
  const candidates=[];
  for(let roomIndex=0;roomIndex<p.rooms.length;roomIndex++){const room=p.rooms[roomIndex];if(/卫生间|卧室|寝室|客房|淋浴/.test(room.name))continue;
   for(let direction=0;direction<4;direction++){const n=D[direction],length=direction%2?room.h:room.w;
    for(let offset=1;offset<length-1;offset++){const inner=direction===0?[room.x+offset,room.y]:direction===1?[room.x+room.w-1,room.y+offset]:direction===2?[room.x+offset,room.y+room.h-1]:[room.x,room.y+offset],outer=[inner[0]+n[0],inner[1]+n[1]];
     if(outer[0]>=0&&outer[1]>=0&&outer[0]<p.w&&outer[1]<p.h&&p.cells[outer[1]*p.w+outer[0]]||!streets.has(K(x+outer[0],y+outer[1])))continue;
     const distance=Math.min(...outside.map(d=>Math.abs(d.sides[1][0]-inner[0])+Math.abs(d.sides[1][1]-inner[1])));if(distance<7)continue;
     const cargo=/材料|成品|货物|后仓/.test(room.name),role=cargo?'装卸门':room.circulation?'共用通廊入口':/起居|接待|门厅|售货/.test(room.name)?'临街入口':'后勤出入口';
     candidates.push({inner,outer,roomIndex,direction,role,cargo,score:distance+(room.circulation?12:0)+(cargo&&p.special?18:0)+(direction!==D.findIndex(n=>n[0]===p.entryNormal[0]&&n[1]===p.entryNormal[1])?8:0)});
    }
   }
  }
  candidates.sort((a,b)=>b.score-a.score);let count=0;const limit=area>600?3:area>120?2:1;
  for(const c of candidates){if(count>=limit)break;if(doors.some(d=>d.a<0&&Math.abs(d.sides[1][0]-c.inner[0])+Math.abs(d.sides[1][1]-c.inner[1])<9))continue;
   const width=c.cargo&&p.special?3:C.exteriorWidth(p,c.role,c.inner.join(',')),normal=D[c.direction],axis=normal[0]?'vertical':'horizontal',vx=c.inner[0]+(normal[0]>0?1:0),vy=c.inner[1]+(normal[1]>0?1:0),opening=p.id+'-street-'+vx+'-'+vy,segments=[];
   for(let delta=0;delta<width;delta++){const inner=[c.inner[0]+(axis==='horizontal'?delta:0),c.inner[1]+(axis==='vertical'?delta:0)],outer=[inner[0]+normal[0],inner[1]+normal[1]];
    if(inner[0]<0||inner[1]<0||inner[0]>=p.w||inner[1]>=p.h||p.roomAt[inner[1]*p.w+inner[0]]!==c.roomIndex||!streets.has(K(x+outer[0],y+outer[1])))break;
    segments.push({x:vx+(axis==='horizontal'?delta:0),y:vy+(axis==='vertical'?delta:0),axis,kind:'door',a:-1,b:c.roomIndex,sides:[outer,inner],role:c.role,opening});
   }
   if(segments.length<width)continue;for(const d of segments){d.width=segments.length;const edge=edges.find(e=>e.axis===d.axis&&e.x===d.x&&e.y===d.y);if(edge){Object.assign(edge,d);doors.push(d);}}if(segments.length)count++;
  }
  return{...p,doors,edges};
 }
 function loadingAccess(p,x,y,blocked){
  const paths=[];if(!['production_complex','logistics_complex'].includes(p.type))return{p,paths};
  for(let roomIndex=0;roomIndex<p.rooms.length;roomIndex++){const room=p.rooms[roomIndex];if(!/材料准备|成品暂存/.test(room.name)||p.doors.some(d=>d.a<0&&d.b===roomIndex&&d.width>=2))continue;
   const choices=[];
   for(let direction=0;direction<4;direction++){const n=D[direction],axis=n[0]?'vertical':'horizontal',offset=Math.floor((direction%2?room.h:room.w)/2)-1,segments=[],apron=[];if(offset<0)continue;
    for(let k=0;k<3;k++){const inner=direction===0?[room.x+offset+k,room.y]:direction===1?[room.x+room.w-1,room.y+offset+k]:direction===2?[room.x+offset+k,room.y+room.h-1]:[room.x,room.y+offset+k],outer=[inner[0]+n[0],inner[1]+n[1]];
     segments.push({x:inner[0]+(n[0]>0?1:0),y:inner[1]+(n[1]>0?1:0),axis,kind:'door',a:-1,b:roomIndex,width:3,role:room.name==='材料准备'?'收货门':'装卸门',opening:p.id+'-loading-'+roomIndex,sides:[outer,inner]});
     apron.push([x+outer[0],y+outer[1]],[x+outer[0]+n[0],y+outer[1]+n[1]]);
    }
    if(apron.some(([a,b])=>blocked.has(K(a,b))||!free(a,b)))continue;const mid=segments[1].sides[0],start=[x+mid[0]+n[0],y+mid[1]+n[1]];
    const targets=[...streets.values()].filter(s=>developmentStreet(s)&&(roads.find(r=>r.id===s.roadId)?.width||0)>=3).map(s=>({p:[s.x,s.y],distance:Math.abs(s.x-start[0])+Math.abs(s.y-start[1])})).filter(s=>s.distance<=16).sort((a,b)=>a.distance-b.distance);
    for(const target of targets.slice(0,4)){const path=accessPath(start,target.p,3,blocked,'cargo');if(!path||path.length>24)continue;const work=earthwork([...widthCells(path,3),...apron]);choices.push({path,width:3,opening:3,apron,center:segments.map(d=>[x+d.sides[0][0],y+d.sides[0][1]]),segments,role:segments[0].role,cost:work.cost,routing:routeSummary(path,3,'cargo')});break;}
   }
   choices.sort((a,b)=>a.routing.score-b.routing.score);const choice=choices[0];if(!choice)return null;
   for(const d of choice.segments){const edge=p.edges.find(e=>e.axis===d.axis&&e.x===d.x&&e.y===d.y);if(!edge)return null;Object.assign(edge,d);p.doors.push(d);}paths.push(choice);
  }
  return{p,paths};
 }
 function egressAccess(p,x,y,blocked,paths){
  const primary=p.doors.find(d=>d.a<0),area=p.rooms.reduce((n,r)=>n+r.w*r.h,0),collective=(p.households||1)>1||['dorm','housing_complex'].includes(p.type),required=collective||p.special||area>=40;
  const groupCount=()=>new Set(p.doors.filter(d=>d.a<0).map(d=>d.opening||'primary')).size;
  function attach(segments){
   const primaryOutside=[x+primary.sides[0][0],y+primary.sides[0][1]],reach=collective?36:22,choices=[];
   for(const width of [...new Set([Math.max(2,segments.length),Math.max(3,segments.length)])]){const start=openingApproach(segments,x,y,width),apron=widthCells([start],width);if(!roadCellsFit(apron,width,blocked))continue;
    const targets=[...streets.values()].map(s=>({p:[s.x,s.y],distance:Math.abs(s.x-start[0])+Math.abs(s.y-start[1])})).filter(t=>t.distance<=reach&&Math.abs(t.p[0]-primaryOutside[0])+Math.abs(t.p[1]-primaryOutside[1])>=6).sort((a,b)=>a.distance-b.distance);
    for(const target of targets.slice(0,5)){const bends=[[target.p[0],start[1]],[start[0],target.p[1]]],paths=bends.map(bend=>[...raster(start,bend),...raster(bend,target.p).slice(1)]).filter(path=>roadCellsFit(widthCells(path,width),width,blocked)),routed=accessPath(start,target.p,width,blocked);if(routed)paths.push(routed);paths.sort((a,b)=>routeSummary(a,width,'egress').score-routeSummary(b,width,'egress').score);const path=paths[0];if(!path||path.length>reach+12)continue;
     const routing=routeSummary(path,width,'egress');choices.push({path,width,opening:segments.length,apron,center:segments.map(d=>[x+d.sides[0][0],y+d.sides[0][1]]),role:collective?'宿舍分流出口':'侧后出口',cost:earthwork([...widthCells(path,width),...apron]).cost,routing});
    }
   }choices.sort((a,b)=>a.routing.score-b.routing.score);return choices[0]||null;
  }
  const groups=new Map();for(const d of p.doors.filter(d=>d.a<0&&(d.opening||'primary')!==(primary.opening||'primary'))){const key=d.opening||d.axis+':'+d.x+':'+d.y;if(!groups.has(key))groups.set(key,[]);groups.get(key).push(d);}
  for(const segments of groups.values()){
   if(segments.every(d=>streets.has(K(x+d.sides[0][0],y+d.sides[0][1]))||paths.some(path=>path.apron.some(c=>c[0]===x+d.sides[0][0]&&c[1]===y+d.sides[0][1]))||(p.outdoorCells||[]).some(s=>s.cells.some(c=>c[0]===d.sides[0][0]&&c[1]===d.sides[0][1]))))continue;
   const route=attach(segments);if(!route)return null;paths.push(route);
  }
  if(!required||groupCount()>=2)return{p,paths,required};
  const candidates=[];
  for(let roomIndex=0;roomIndex<p.rooms.length;roomIndex++){const room=p.rooms[roomIndex];if(/卫生|淋浴|储藏|清洁|卧室|寝室|客房/.test(room.name))continue;
   for(let direction=0;direction<4;direction++){const n=D[direction],length=direction%2?room.h:room.w,width=C.exteriorWidth(p,collective?'宿舍分流出口':'侧后出口',roomIndex+'-'+direction);if(length<width)continue;const offset=Math.floor((length-width)/2),segments=[];
    for(let k=0;k<width;k++){const inner=direction===0?[room.x+offset+k,room.y]:direction===1?[room.x+room.w-1,room.y+offset+k]:direction===2?[room.x+offset+k,room.y+room.h-1]:[room.x,room.y+offset+k],outer=[inner[0]+n[0],inner[1]+n[1]];
     segments.push({x:inner[0]+(n[0]>0?1:0),y:inner[1]+(n[1]>0?1:0),axis:n[0]?'vertical':'horizontal',kind:'door',a:-1,b:roomIndex,width,opening:p.id+'-egress-'+roomIndex+'-'+direction,role:collective?'宿舍分流出口':'侧后出口',sides:[outer,inner]});
    }
    const d=segments[0],distance=Math.abs(d.x-primary.x)+Math.abs(d.y-primary.y);if(distance<Math.min(8,Math.max(p.w,p.h)*.5)||segments.some(d=>blocked.has(K(x+d.sides[0][0],y+d.sides[0][1]))))continue;
    candidates.push({segments,score:distance+(room.circulation?40:0)+(n[0]!==p.entryNormal[0]||n[1]!==p.entryNormal[1]?16:0)});
   }
  }
  candidates.sort((a,b)=>b.score-a.score);
  for(const candidate of candidates.slice(0,10)){const route=attach(candidate.segments);if(!route)continue;for(const d of candidate.segments){const edge=p.edges.find(e=>e.axis===d.axis&&e.x===d.x&&e.y===d.y);if(!edge)return null;Object.assign(edge,d);p.doors.push(d);}paths.push(route);return{p,paths,required};}
  return null;
 }
 function proposal(p,x,y,year,id,parcel,allowSite=false){const cells=[],blocked=new Set();for(let yy=0;yy<p.h;yy++)for(let xx=0;xx<p.w;xx++)if(p.cells[yy*p.w+xx]){const a=x+xx,b=y+yy,k=K(a,b);if(!free(a,b)||streets.has(k)||reserved.has(k)||parcel&&!parcel.mask.has(K(a,b)))return null;cells.push([a,b]);blocked.add(k);}for(const s of p.outdoorCells||[])for(const[a,b]of s.cells){const xx=x+a,yy=y+b;if(!free(xx,yy)||streets.has(K(xx,yy))||reserved.has(K(xx,yy))||parcel&&!parcel.mask.has(K(xx,yy)))return null;}
  p=streetDoors(p,x,y);const loading=loadingAccess(p,x,y,blocked);if(!loading)return null;const egress=egressAccess(p,x,y,blocked,loading.paths);if(!egress)return null;const primary=p.doors.find(d=>d.a<0),primaryKey=primary.opening||'primary',groups=new Map();for(const d of p.doors.filter(d=>d.a<0)){const k=d.opening||'primary';if(!groups.has(k))groups.set(k,[]);groups.get(k).push(d);}const paths=egress.paths,yards=[],removed=new Set();let frontage=null;
  for(const [group,ds]of groups){const d=ds[Math.floor(ds.length/2)];if((p.outdoorCells||[]).some(s=>s.cells.some(c=>c[0]===d.sides[0][0]&&c[1]===d.sides[0][1])))continue;const outer=[x+d.sides[0][0],y+d.sides[0][1]],n=[Math.sign(d.sides[0][0]-d.sides[1][0]),Math.sign(d.sides[0][1]-d.sides[1][1])],existing=streets.get(K(...outer));
   if(ds.every(d=>streets.has(K(x+d.sides[0][0],y+d.sides[0][1])))){if(group===primaryKey){if(!ds.every(d=>developmentStreet(streets.get(K(x+d.sides[0][0],y+d.sides[0][1])))))return null;frontage=existing;}continue;}
   if(ds.every(d=>paths.some(path=>path.apron.some(cell=>cell[0]===x+d.sides[0][0]&&cell[1]===y+d.sides[0][1]))))continue;
   if(group===primaryKey)return null;
   return null;
  }
  if(removed.size)p={...p,doors:p.doors.filter(d=>!removed.has(d.axis+':'+d.x+':'+d.y)),edges:p.edges.map(e=>removed.has(e.axis+':'+e.x+':'+e.y)?{...e,kind:'wall'}:e)};
  const work=earthwork([...cells,...(p.outdoorCells||[]).flatMap(s=>s.cells.map(([a,b])=>[a+x,b+y])),...yards.flatMap(s=>s.cells)]),siteWork=earthwork(paths.flatMap(a=>[...widthCells(a.path,a.width),...a.apron]));if(work.cost+siteWork.cost>remainingEffort)return null;return{p,x,y,cells,paths,yards,year,id,parcel,frontage,requiresMultipleExits:egress.required,earthwork:work,totalCost:work.cost+siteWork.cost,sitePrepared:paths.length>0};
 }
 function commit(q,phase,cycle){const id=q.id,accessRoadIds=[];for(const a of q.paths){const access=commitRoad(a.path,a.width,q.year,id,a.role+'场内作业通路','site-access');if(a.routing)access.routing={...a.routing,construction:access.earthwork.cost};accessRoadIds.push(access.id);const apronWork=earthwork(a.apron);spend(apronWork.cost);for(const cell of a.apron){const k=K(...cell);if(!streets.has(k))streets.set(k,{x:cell[0],y:cell[1],year:q.year,order:eventCounter});}const r={id:'S'+(roads.length+1),center:a.center,points:[a.center[0],a.center.at(-1)],width:a.width,year:q.year,builtYear:q.year,order:++eventCounter,purpose:a.role+'门前通行',servesProject:id,serves:[id],kind:'entrance',scope:'entrance',cells:a.apron,earthwork:apronWork};roads.push(r);}
  const primary=q.p.doors.find(d=>d.a<0),approach=streets.get(K(q.x+primary.sides[0][0],q.y+primary.sides[0][1]));q.frontageYear=approach?.year;q.frontageOrder=approach?.order;q.builtOrder=++eventCounter;q.frontageRoadId=approach?.roadId||accessRoadIds[0];
  if(q.frontageRoadId){const rd=roads.find(r=>r.id===q.frontageRoadId);if(rd&&!rd.serves.includes(id))rd.serves.push(id);accessRoadIds.push(q.frontageRoadId);}
  for(const d of q.p.doors.filter(d=>d.a<0)){const roadId=streets.get(K(q.x+d.sides[0][0],q.y+d.sides[0][1]))?.roadId;if(roadId&&!accessRoadIds.includes(roadId)){accessRoadIds.push(roadId);const road=roads.find(r=>r.id===roadId);if(road&&!road.serves.includes(id))road.serves.push(id);}}
  for(const[x,y]of q.cells)occupied.set(K(x,y),id);for(const s of [...q.yards,...(q.p.outdoorCells||[]).map(s=>({...s,cells:s.cells.map(([x,y])=>[q.x+x,q.y+y])}))]){let cells=s.cells.filter(([x,y])=>!occupied.has(K(x,y))&&!streets.has(K(x,y)));if(s.service){const available=new Set(cells.map(p=>K(...p))),connected=new Set(),queue=cells.filter(([x,y])=>D.some(([dx,dy])=>streets.has(K(x+dx,y+dy))));for(const p of queue)connected.add(K(...p));for(let h=0;h<queue.length;h++){const[x,y]=queue[h];for(const[dx,dy]of D){const k=K(x+dx,y+dy);if(available.has(k)&&!connected.has(k)){connected.add(k);queue.push([x+dx,y+dy]);}}}cells=cells.filter(p=>connected.has(K(...p)));}if(!cells.length)continue;const sp={...s,id:'C'+(spaces.length+1),projectId:id,year:q.year,builtYear:q.year,buildingIds:[id],cells};spaces.push(sp);for(const[x,y]of cells)occupied.set(K(x,y),id);}
  spend(q.earthwork.cost);if(q.parcel)q.parcel.buildingIds.push(id);projects.push({...q,capacity:C.planningCapacity(q.p,o),phase,cycle,accessRoadIds,alterations:[],cellYears:new Map(q.cells.map(p=>[K(...p),q.year]))});spatial=null;
 }
 function streetFacade(raw){if(!raw.wholeBlock||!raw.special)return raw;const n=D[{north:0,east:1,south:2,west:3}[raw.front||'north']],w=Math.max(...raw.rooms.map(r=>r.x+r.w)),h=Math.max(...raw.rooms.map(r=>r.y+r.h)),[ex,ey]=raw.entry,inside=[ex-(n[0]>0?1:0),ey-(n[1]>0?1:0)],parent=raw.rooms.findIndex(r=>inside[0]>=r.x&&inside[1]>=r.y&&inside[0]<r.x+r.w&&inside[1]<r.y+r.h);let c,entry;
  if(n[1]<0&&ey>0){c={x:ex-1,y:0,w:3,h:ey};entry=[ex,0];}else if(n[1]>0&&ey<h){c={x:ex-1,y:ey,w:3,h:h-ey};entry=[ex,h];}else if(n[0]<0&&ex>0){c={x:0,y:ey-1,w:ex,h:3};entry=[0,ey];}else if(n[0]>0&&ex<w){c={x:ex,y:ey-1,w:w-ex,h:3};entry=[w,ey];}if(!c||c.x<0||c.y<0||raw.rooms.some(r=>c.x<r.x+r.w&&c.x+c.w>r.x&&c.y<r.y+r.h&&c.y+c.h>r.y))return raw;
  return{...raw,entry,rooms:[...raw.rooms,{name:'入口通廊',...c,circulation:'public'}],links:[...raw.links,[parent,raw.rooms.length,{width:2,role:'入口门厅'}]]};
 }
 function findCandidate(raw,year,phase,cycle,R,preferred=null,onlyRoad=null){
  const compiled=compile(streetFacade(raw));compiled.outdoorCells=outdoor(compiled);const id='B'+String(++sequence).padStart(4,'0'),major=!!compiled.wholeBlock&&compiled.special,turns=[0,1,2,3].map(r=>rotated(compiled,r));let best=null;
  const consider=q=>{if(!q)return;const siting=rateSite(q,phase);if(!siting||phase==='resident'&&siting.score>100)return;q.siting=siting;const score=siting.score;if(!best||score<best.score)best={q,score};};
  if(phase==='government'&&major){const lots=parcels.filter(b=>b.major&&!b.buildingIds.length&&(!preferred||b.quarterId===preferred.id));for(const b of lots)for(const p of turns){if(p.w>b.w||p.h>b.h)continue;for(let attempt=0;attempt<8;attempt++){let x=b.x+Math.floor(R()*(b.w-p.w+1)),y=b.y+Math.floor(R()*(b.h-p.h+1));const n=p.entryNormal;if(n[0]<0)x=b.x-p.anchor[0];else if(n[0]>0)x=b.x+b.w-1-p.anchor[0];else if(n[1]<0)y=b.y-p.anchor[1];else y=b.y+b.h-1-p.anchor[1];consider(proposal(p,x,y,year,id,b,true));}}}
  else{
   let sites=streetFrontages().filter(f=>free(f.x,f.y)&&f.street.roadId&&f.street.kind!=='entrance'&&(!onlyRoad||f.street.roadId===onlyRoad.id)&&(phase!=='government'||f.parcel&&(!preferred||f.parcel.quarterId===preferred.id))&&(!f.parcel?.major||phase==='government'&&f.parcel.buildingIds.length)&&!(raw.legalStatus==='非正规'&&f.parcel&&f.parcel.security!=='较弱'));
   sites=sites.map(f=>({...f,context:siteContext(raw.program,f.street,phase),tie:R()*5})).filter(f=>f.context&&(phase!=='resident'||f.context.score<=100)).sort((a,b)=>(a.context.score+a.tie)-(b.context.score+b.tie));const pools=phase==='resident'?[sites.filter(f=>f.parcel),sites]:[sites];for(const pool of pools){let found=0;const seen=new Set();for(let attempt=0;attempt<Math.min(180,pool.length*2);attempt++){const f=pool[attempt%pool.length],key=K(f.x,f.y)+':'+f.side;if(seen.has(key))continue;seen.add(key);const n=D[f.side],p=turns.find(p=>p.entryNormal[0]===-n[0]&&p.entryNormal[1]===-n[1]),q=proposal(p,f.x-p.anchor[0],f.y-p.anchor[1],year,id,f.parcel,false);if(q){consider(q);if(++found>=18)break;}}if(best&&phase==='resident'&&R()<o.residentInfill)break;}
  }
  if(!best)return null;best.q.decision=raw.decision;return best.q;
 }
 function residentLane(raw,year,cycle,R,limit=6){
  const compiled=compile(streetFacade(raw));compiled.outdoorCells=outdoor(compiled);const turns=[0,1,2,3].map(r=>rotated(compiled,r)),id='B'+String(++sequence).padStart(4,'0'),starts=[],solutions=[];
  const ranked=streetFrontages().filter(f=>free(f.x,f.y)&&!f.parcel?.major).map(f=>{const context=siteContext(raw.program,f.street);return{...f,context,tie:R()*3};}).filter(f=>f.context&&f.context.score<85).sort((a,b)=>a.context.score+a.tie-b.context.score-b.tie);
  for(const f of ranked){if(starts.some(g=>Math.abs(g.x-f.x)+Math.abs(g.y-f.y)<12))continue;starts.push(f);if(starts.length===limit)break;}
  const sites=[];
  for(const f of starts){const n=D[f.side],p=turns.find(p=>p.entryNormal[0]===-n[0]&&p.entryNormal[1]===-n[1]),baseWidth=Math.round(o.alleyMin+R()*(o.alleyMax-o.alleyMin)),depths=[...new Set([6,Math.round(o.alleyLength*.45),Math.round(o.alleyLength*.75),o.alleyLength])].filter(d=>d<=o.alleyLength),offset=Math.round(Math.min(p.w,p.h)*o.branchChance*.5);
   for(const width of [...new Set([baseWidth,Math.max(3,baseWidth)])])for(const depth of depths)for(const lateral of [...new Set([-offset,0,offset])]){const x=f.x+n[0]*depth+n[1]*lateral-p.anchor[0],y=f.y+n[1]*depth-n[0]*lateral-p.anchor[1],inside=[x+p.anchor[0],y+p.anchor[1]],parcel=parcelAt(...inside),blocked=new Set(),cells=[];let fits=true;
    for(let yy=0;yy<p.h&&fits;yy++)for(let xx=0;xx<p.w;xx++)if(p.cells[yy*p.w+xx]){const a=x+xx,b=y+yy,k=K(a,b),at=parcelAt(a,b);if(!free(a,b)||streets.has(k)||reserved.has(k)||at&&at!==parcel||parcel&&!parcel.mask.has(k)){fits=false;break;}blocked.add(k);cells.push([a,b]);}
    if(!fits||parcel?.major)continue;for(const space of p.outdoorCells)for(const[a,b]of space.cells){const xx=x+a,yy=y+b,k=K(xx,yy);if(!free(xx,yy)||streets.has(k)||reserved.has(k)||parcel&&!parcel.mask.has(k))fits=false;blocked.add(k);cells.push([xx,yy]);}if(!fits)continue;
    const primary=p.doors.find(d=>d.a<0),segments=p.doors.filter(d=>d.a<0&&(d.opening||'primary')===(primary.opening||'primary')),approach=openingApproach(segments,x,y,width);if(!roadCellsFit(widthCells([approach],width),width,blocked))continue;
    const work=earthwork(cells);if(work.cost>remainingEffort*.8)continue;sites.push({f,n,p,width,x,y,inside,parcel,blocked,score:f.context.score+work.cost/Math.max(1,cells.length)*8+depth*.12+R()*2});
   }
  }
  sites.sort((a,b)=>a.score-b.score);
  for(const {f,n,p,width,x,y,inside,parcel,blocked}of sites.slice(0,limit*2)){
   const outer=[inside[0]-n[0],inside[1]-n[1]];if(streets.has(K(...outer)))continue;const primary=p.doors.find(d=>d.a<0),segments=p.doors.filter(d=>d.a<0&&(d.opening||'primary')===(primary.opening||'primary')),end=openingApproach(segments,x,y,width),start=[f.street.x,f.street.y],points=routePath(start,end,width,'resident',blocked);
   if(!points||points.length-1>o.alleyLength*1.8)continue;const route=routeSummary(points,width,'resident');if(route.construction>remainingEffort*.5)continue;
   const snapshot=transaction();let q;try{commitRoad(points,width,year,id,'连接候选房屋的居民共用巷','self-built','resident');frontageVersion=-1;q=proposal(p,x,y,year,id,parcel);if(q){q.siting=rateSite(q,'resident');if(q.siting){const connection=route.construction/Math.max(1,q.cells.length)*8,detour=(route.length-route.direct)*.15;q.siting.score+=connection+detour;q.siting.factors.push({label:'新增巷道建设',cost:Math.round(connection*10)/10},{label:'巷道绕行',cost:Math.round(detour*10)/10});q.siting.connection=route;q.siting.basis+='；房屋与新增巷道共同评估';q.siting.constructionCost+=route.construction;}}}finally{rollback(snapshot);}
   if(q?.siting&&q.siting.score<=100){q.decision=raw.decision;solutions.push({q,points,width,route});}
  }
  if(!solutions.length)return null;solutions.sort((a,b)=>a.q.siting.score-b.q.siting.score);const close=solutions.filter(s=>s.q.siting.score<=solutions[0].q.siting.score+2);return close[Math.floor(R()*close.length)];
 }
 function buildResident(raw,year,cycle,R){const infill=findCandidate(raw,year,'resident',cycle,R),extension=residentLane(raw,year,cycle,R,infill?3:8);if(!infill&&!extension)return false;
  // The preference only breaks close choices; a costly extension cannot bypass the combined comparison.
  if(extension&&(!infill||extension.q.siting.score+(o.residentInfill-.5)*6<infill.siting.score)){
   const road=commitRoad(extension.points,extension.width,year,extension.q.id,'房屋需求驱动的居民共用巷','self-built','resident');road.routing=extension.route;commit(extension.q,'resident',cycle);
  }else commit(infill,'resident',cycle);return true;
 }
 // Rebuild the same room/edge representation after a dated alteration; no second map format is needed.
 function editable(q){
  const p=q.p,primary=p.doors.find(d=>d.a<0),groups=new Map();for(const d of p.doors.filter(d=>d.a<0&&(d.opening||'primary')!==(primary.opening||'primary'))){const key=d.opening||d.axis+':'+d.x+':'+d.y;if(!groups.has(key))groups.set(key,[]);groups.get(key).push(d);}
  const exits=[...groups.values()].map(ds=>{const d=ds[0],n=[d.sides[0][0]-d.sides[1][0],d.sides[0][1]-d.sides[1][1]];return{x:Math.min(...ds.map(d=>d.x)),y:Math.min(...ds.map(d=>d.y)),front:['north','east','south','west'][D.findIndex(v=>v[0]===n[0]&&v[1]===n[1])],width:ds.length,role:d.role};});
  const primarySegments=p.doors.filter(d=>d.a<0&&(d.opening||'primary')===(primary.opening||'primary'));
  return{...p,entryWidth:primarySegments.length,rooms:p.rooms.map(r=>({...r})),links:p.links.map(l=>[l[0],l[1],{...(l[2]||{})}]),openLinks:(p.openLinks||[]).map(l=>[...l]),entry:[Math.min(...primarySegments.map(d=>d.x)),Math.min(...primarySegments.map(d=>d.y))],front:['north','east','south','west'][D.findIndex(n=>n[0]===p.entryNormal[0]&&n[1]===p.entryNormal[1])],exits,outdoors:[]};
 }
 function remodel(q,raw,year,kind,added,affected){
  let laneArea=0;const ownCourts=spaces.filter(s=>!s.service&&(s.projectId===q.id||s.kind==='cavern-hall'&&s.buildingIds.includes(q.id))),old=new Set(q.cells.map(p=>K(...p))),addSet=new Set(added.map(p=>K(...p))),narrowed=new Set();
  for(const s of ownCourts){const consumed=s.cells.filter(p=>addSet.has(K(...p))).length;if(consumed&&s.cells.length-consumed<Math.max(8,s.cells.length*.5))return false;if(consumed){const remaining=new Set(s.cells.filter(p=>!addSet.has(K(...p))).map(p=>K(...p))),queue=s.cells.filter(([x,y])=>remaining.has(K(x,y))&&(D.some(([dx,dy])=>streets.has(K(x+dx,y+dy)))||q.p.doors.some(d=>d.a<0&&q.x+d.sides[0][0]===x&&q.y+d.sides[0][1]===y))),seen=new Set(queue.map(p=>K(...p)));for(let i=0;i<queue.length;i++){const[x,y]=queue[i];for(const[dx,dy]of D){const k=K(x+dx,y+dy);if(remaining.has(k)&&!seen.has(k)){seen.add(k);queue.push([x+dx,y+dy]);}}}if(seen.size!==remaining.size)return false;}}
  for(const[x,y]of added){
   const k=K(x,y),owner=occupied.get(k);if(!developmentAllowed(x,y)||old.has(k)||sample(x,y).rock===3||reserved.has(k)||owner&&!ownCourts.some(s=>s.cells.some(p=>K(...p)===k)))return false;
   const parcel=parcelAt(x,y);if(parcel?.major||q.parcel&&!q.parcel.mask.has(K(x,y)))return false;
   if(streets.has(k)){
    laneArea++;const overlapping=roads.filter(r=>r.cells.some(p=>K(...p)===k));if(q.parcel||!overlapping.length||overlapping.some(r=>r.kind!=='self-built'||r.width<3))return false;
    for(const road of overlapping){if(widthCells(road.center,road.minimumWidth||3).some(p=>K(...p)===k))return false;narrowed.add(road);}
   }
  }
  // Preserve every external doorway and its immediate approach, including neighbours across a lane.
  if(added.length)for(const b of projects)for(const d of b.p.doors.filter(d=>d.a<0)){const x=b.x+d.sides[0][0],y=b.y+d.sides[0][1];if(added.some(([a,c])=>Math.abs(a-x)+Math.abs(c-y)<=1))return false;}
  const work=earthwork(added.filter(p=>!occupied.has(K(...p))));work.cost+=kind==='分户出租'?raw.rooms.filter((_,i)=>affected.includes(i)).reduce((n,r)=>n+r.w*r.h,0)*.35:added.length*.25;if(work.cost>remainingEffort)return false;
  const dx=Math.min(0,...raw.rooms.map(r=>r.x)),dy=Math.min(0,...raw.rooms.map(r=>r.y)),x=q.x+dx,y=q.y+dy;
  for(const r of raw.rooms){r.x-=dx;r.y-=dy;}raw.entry=[raw.entry[0]-dx,raw.entry[1]-dy];for(const e of raw.exits){e.x-=dx;e.y-=dy;}
  let p;try{p=compile(raw);}catch{return false;}
  const openingEdges=(plan,x,y)=>new Set(plan.doors.filter(d=>d.a<0).map(d=>d.axis+':'+(x+d.x)+':'+(y+d.y))),oldOpenings=openingEdges(q.p,q.x,q.y),newOpenings=openingEdges(p,x,y);if(oldOpenings.size!==newOpenings.size||[...oldOpenings].some(k=>!newOpenings.has(k)))return false;
  // Compile before mutating any occupancy, pavement or yard data.
  for(const r of narrowed){const before=r.cells.length;r.cells=r.cells.filter(p=>!addSet.has(K(...p)));r.clearWidth=r.minimumWidth||3;r.encroachedArea=(r.encroachedArea||0)+before-r.cells.length;}
  let courtArea=0;for(const space of ownCourts){const before=space.cells.length;space.cells=space.cells.filter(p=>!addSet.has(K(...p)));courtArea+=before-space.cells.length;}
  for(const cell of added){const k=K(...cell);streets.delete(k);occupied.set(k,q.id);q.cellYears.set(k,year);}
  q.x=x;q.y=y;q.p=p;q.capacity=C.planningCapacity(p,o);q.cells=[];for(let yy=0;yy<p.h;yy++)for(let xx=0;xx<p.w;xx++)if(p.cells[yy*p.w+xx])q.cells.push([x+xx,y+yy]);
  p.outdoorCells=ownCourts.map(space=>({...space,cells:space.cells.map(([a,b])=>[a-x,b-y])}));
  q.alterations.push({year,kind,addedArea:added.length,courtArea,narrowedLaneArea:laneArea,rooms:affected});
  for(const key of ['cost','natural','excavated'])q.earthwork[key]+=work[key];spend(work.cost);frontageVersion=-1;spatial=null;return true;
 }
 function subdivide(q,year,R){
  const p=q.p,possible=[];
  for(let i=0;i<p.rooms.length;i++){
   const r=p.rooms[i],connections=p.links.filter(l=>l[0]===i||l[1]===i);
   if(!['卧室','起居室','前室工作间'].includes(r.name)||r.w*r.h<18||Math.max(r.w,r.h)<6||Math.min(r.w,r.h)<3||connections.length!==1||p.doors.some(d=>d.a<0&&d.b===i)||(p.openLinks||[]).some(l=>l.includes(i)))continue;
   const l=connections[0],parent=l[0]===i?l[1]:l[0],h=p.rooms[parent];if(h.circulation||['起居厨房','起居餐室','起居室'].includes(h.name))possible.push({i,parent});
  }
  if(!possible.length)return false;
  const{i,parent}=possible[Math.floor(R()*possible.length)],raw=editable(q),r=raw.rooms[i],h=raw.rooms[parent],horizontal=h.y+h.h===r.y||h.y===r.y+r.h,cut=Math.floor((horizontal?r.w:r.h)/2),hall={name:'公共过道',x:r.x,y:r.y,w:r.w,h:r.h,circulation:'public'},second={...r,name:'出租单间'};
  if(horizontal){if(r.w<6||r.h<5)return false;hall.h=2;const bottom=h.y===r.y+r.h;hall.y=bottom?r.y+r.h-2:r.y;r.y+=bottom?0:2;r.h-=2;second.y=r.y;second.h=r.h;second.x+=cut;second.w-=cut;r.w=cut;}
  else{if(r.h<6||r.w<5)return false;hall.w=2;const right=h.x===r.x+r.w;hall.x=right?r.x+r.w-2:r.x;r.x+=right?0:2;r.w-=2;second.x=r.x;second.w=r.w;second.y+=cut;second.h-=cut;r.h=cut;}

  r.name='出租单间';const j=raw.rooms.length,k=j+1;raw.rooms.push(second,hall);raw.links=raw.links.filter(l=>l[0]!==i&&l[1]!==i);raw.links.push([parent,k],[k,i],[k,j]);raw.households=(p.households||1)+1;raw.layout=(p.layout||p.name).includes('分户共用生活设施')?p.layout:(p.layout||p.name)+' · 分户共用生活设施';
  return remodel(q,raw,year,'分户出租',[],[i,j,k]);
 }
 function annex(q,year,R){
  const p=q.p;
  function attachRoom(room,parent){const raw=editable(q),added=[];for(let y=room.y;y<room.y+room.h;y++)for(let x=room.x;x<room.x+room.w;x++)added.push([q.x+x,q.y+y]);const idx=raw.rooms.length;raw.rooms.push({...room,builtYear:year});raw.links.push([parent,idx]);raw.layout=(p.layout||p.name).includes('逐年加建')?p.layout:(p.layout||p.name)+' · 逐年加建';return remodel(q,raw,year,'房屋加建',added,[idx]);}
  // Existing courtyards can gradually acquire small annexes while retaining the access route.
  const court=spaces.find(s=>s.projectId===q.id&&!s.service&&s.cells.length>=16);
  if(court&&R()<.8){const cells=new Set(court.cells.map(p=>K(...p))),candidates=[];for(const[x,y]of court.cells){const room={name:'储藏间',x:x-q.x,y:y-q.y,w:2,h:3};let fits=true;for(let yy=y;yy<y+3;yy++)for(let xx=x;xx<x+2;xx++)if(!cells.has(K(xx,yy)))fits=false;if(!fits)continue;const parent=p.rooms.findIndex(r=>(r.x+r.w===room.x||room.x+room.w===r.x)&&Math.min(r.y+r.h,room.y+room.h)>Math.max(r.y,room.y)||(r.y+r.h===room.y||room.y+room.h===r.y)&&Math.min(r.x+r.w,room.x+room.w)>Math.max(r.x,room.x));if(parent>=0)candidates.push({room,parent});}while(candidates.length){const c=candidates.splice(Math.floor(R()*candidates.length),1)[0];if(attachRoom(c.room,c.parent))return true;}}
  if(!q.parcel&&R()<.5){for(let i=0;i<p.rooms.length;i++){const r=p.rooms[i];if(['卫生间','公共卫生间'].includes(r.name))continue;for(const side of [0,1,2,3])for(const offset of [-1,(side%2?r.h:r.w)-2]){const room={name:'储藏间',x:side%2?(side===1?r.x+r.w:r.x-3):r.x+offset,y:side%2?r.y+offset:side===0?r.y-3:r.y+r.h,w:3,h:3};if(p.rooms.some(b=>room.x<b.x+b.w&&room.x+3>b.x&&room.y<b.y+b.h&&room.y+3>b.y))continue;let pavement=false;for(let y=room.y;y<room.y+3;y++)for(let x=room.x;x<room.x+3;x++)if(streets.get(K(q.x+x,q.y+y))?.kind==='self-built')pavement=true;if(pavement&&attachRoom(room,i))return true;}}}
  const eligible=p.rooms.map((r,i)=>({r,i})).filter(({r})=>r.circulation||/起居|厨房|工作间|门厅|前室/.test(r.name));
  for(let attempt=0;attempt<56&&eligible.length;attempt++){
   const{r,i}=eligible[Math.floor(R()*eligible.length)],side=Math.floor(R()*4),w=3+Math.floor(R()*4),h=Math.min(3+Math.floor(R()*3),Math.floor(24/w)),vertical=side%2===0,offset=Math.floor(R()*Math.max(1,(vertical?r.w:r.h)+2))-1;
   const room={name:w*h>=9&&R()<.65?'卧室':'储藏间',x:vertical?r.x+offset:side===1?r.x+r.w:r.x-w,y:vertical?(side===0?r.y-h:r.y+r.h):r.y+offset,w,h,builtYear:year};
   if(p.rooms.some(b=>room.x<b.x+b.w&&room.x+room.w>b.x&&room.y<b.y+b.h&&room.y+room.h>b.y))continue;
   const raw=editable(q),added=[];for(let y=room.y;y<room.y+h;y++)for(let x=room.x;x<room.x+w;x++)added.push([q.x+x,q.y+y]);const idx=raw.rooms.length;raw.rooms.push(room);raw.links.push([i,idx]);raw.layout=(p.layout||p.name).includes('逐年加建')?p.layout:(p.layout||p.name)+' · 逐年加建';
   if(remodel(q,raw,year,'房屋加建',added,[idx]))return true;
  }return false;
 }
 function alter(year,R){
  const candidates=projects.filter(q=>year-q.year>=3&&!q.p.special&&q.p.wallMode==='edge'&&['apartment','dorm','shop','workshop'].includes(q.p.type)&&q.alterations.length<5);
  for(let attempt=0;attempt<12&&candidates.length;attempt++){const q=candidates.splice(Math.floor(R()*candidates.length),1)[0];if(R()<.4&&subdivide(q,year,R)||annex(q,year,R))return true;}
  return false;
 }

 function choose(year,phase,index,R){
  const choice=useChoices(year,'resident',R)[0];if(!choice)return null;const program=choice.program,def=choice.def,token=seed+'-resident-'+year+'-'+index;let raw;
  if(program==='dorm')raw=groupPlan(token,R,o);
  else if(program==='housing'&&R()<.6)raw=singlePlan(token,R,o);
  else{const target=def.area*(.65+R()*.65),w=Math.max(def.minW,Math.round(Math.sqrt(target)*(.8+R()*.4))),h=Math.max(def.minH,Math.round(target/w));raw=Layouts.fitted(token,w,h,program,R,o,Math.floor(R()*4));}
  return{...raw,program,decision:decisionFor(program,year,'resident'),templateId:raw.templateId||raw.id,id:token,wholeBlock:!!raw.wholeBlock,legalStatus:raw.legalStatus||'正规'};
 }

 let cycle=0,nextReview=0;
 progress('development','开始初期规划',0,o.years+1);for(let year=0;year<=o.years;year++){progress('development','第 '+year+' / '+o.years+' 年：规划与居民建设',year,o.years+1);
  currentYear=year;frontageVersion=-1;spatial=null;const R=C.random(seed+'-year-'+year),beforeState=demandState(year),beforeDemolitions=demolitions.length,beforeEvents=planningEvents.length,beforeIds=new Set(projects.map(q=>q.id));let rejected=0;
  yearEffort=0;remainingEffort=Infinity;extendRails(year,Math.min(190,95+Math.floor(year/8)*18));const infrastructureEffort=Math.round(yearEffort+(year===0?roads.filter(r=>r.kind==='main'||r.kind==='station-track').reduce((n,r)=>n+r.earthwork.cost,0):0));
  const review=year===0||year===nextReview&&o.projectsPerPeriod>0,publicBudget=review?(year===0?160000:45000)*o.publicInvestment*o.growthRate:0;
  yearEffort=0;remainingEffort=publicBudget;
  if(year===0)stationWaiting();
  if(review){
   cycle++;const thresholds={family:12,workers:12,guests:10,industry:25,repair:10,logistics:80,retail:100,meals:60,health:120,education:20,hygiene:40,utilities:100,safety:150,administration:120,leisure:100},state=demandState(year),pressure=Math.max(...state.needs.map(n=>n.shortage/Math.max(n.target,thresholds[n.key]))),required=o.facilityRules.some(r=>r.mode==='required'&&projects.filter(q=>q.p.program===r.program).length<r.count);
   if(year===0||pressure>.25||required||relocationPending){const target=year===0?o.plannedBlocks:o.projectsPerPeriod;for(let k=0;k<target;k++)if(!makeQuarter(year,cycle,quarters.length)){rejected++;break;}}
   else planningEvents.push({year,cycle,status:'not-needed',kind:'review',reason:'现有容量基本覆盖需求，本期不新增规划区'});
   const periodR=C.random(seed+'-review-'+cycle);nextReview=year+o.governmentInterval+Math.floor(periodR()*(o.governmentJitter*2+1))-o.governmentJitter;
   if(!quarters.length)throw Error('当前地质、用途与预算下未找到可完整建设的初期街坊');
  }
  const publicSpent=yearEffort,residentBudget=year===0?0:3200*o.selfActivity*o.growthRate;yearEffort=0;remainingEffort=residentBudget;
  const count=year===0?0:Math.floor(o.growthRate*5*o.selfActivity+R());
  for(let j=0;j<count;j++){let done=false;for(let retry=0;retry<3&&!done;retry++){
   if(retry===0&&R()<o.alterationShare&&alter(year,R)){done=true;continue;}const raw=choose(year,'resident',j*3+retry,R);if(!raw)break;
   done=buildResident(raw,year,cycle,R);
  }if(!done)rejected++;progress('development','第 '+year+' / '+o.years+' 年：居民项目 '+(j+1)+' / '+count,year,o.years+1);}
  const state=demandState(year),beds=s=>['family','workers','guests'].reduce((n,key)=>n+(s.supply[key]||0),0),targetBeds=s=>s.needs.filter(n=>['family','workers','guests'].includes(n.key)).reduce((n,v)=>n+v.target,0),lostBeds=demolitions.slice(beforeDemolitions).reduce((n,d)=>n+d.people,0),newBeds=Math.max(0,beds(state)-beds(beforeState)+lostBeds),resettled=Math.min(relocationPending,newBeds+Math.max(0,beds(beforeState)-targetBeds(beforeState)));relocationPending-=resettled;totalResettled+=resettled;
  let radius=50;for(const q of projects)radius=Math.max(radius,Math.hypot(q.x,q.y),Math.hypot(q.x+q.p.w,q.y+q.p.h));
  history.push({year,cycle,phase:year===0?'government':review?'government-resident':'resident',projects:projects.filter(q=>!beforeIds.has(q.id)).length,demolished:demolitions.length-beforeDemolitions,rejected,totalBuildings:projects.length,quarters:quarters.length,radius,effortBudget:publicBudget+residentBudget+infrastructureEffort,publicBudget,residentBudget,infrastructureEffort,effortUsed:Math.round(publicSpent+yearEffort+infrastructureEffort),publicSpent:Math.round(publicSpent),residentSpent:Math.round(yearEffort),alterations:projects.reduce((n,q)=>n+q.alterations.filter(a=>a.year===year).length,0),population:state.population,needs:state.needs,displaced:lostBeds,resettled,awaitingResettlement:relocationPending,nextReview: o.projectsPerPeriod?nextReview:null,planningEvents:planningEvents.slice(beforeEvents)});
 }
 progress('development','年度建设完成',o.years+1,o.years+1);
 for(const[program,target,label]of [['park',o.parkCount,'公园'],['plaza',o.plazaCount,'路口广场']]){const count=spaces.filter(s=>s.program===program).length;if(count<target)warnings.push(label+'已安排 '+count+'/'+target+' 处，其余缺少符合尺度与接路条件的场地');}
 for(const rule of o.facilityRules.filter(r=>r.mode==='required')){const count=projects.filter(q=>q.p.program===rule.program).length;if(count<rule.count)warnings.push(C.programs[rule.program].label+'已安排 '+count+'/'+rule.count+' 处，仍受场地或预算限制');}

 for(const failure of railDesign.failures)warnings.push('出口'+(failure.exitIndex+1)+'：'+failure.reason);
 // Raster bounds follow the realised city. Every field uses absolute coordinates, independent of these bounds.
 const all=[...streets.values(),...[...vacated.keys()].map(k=>{const[x,y]=k.split(',').map(Number);return{x,y};}),...projects.flatMap(q=>[{x:q.x,y:q.y},{x:q.x+q.p.w,y:q.y+q.p.h}])],minX=Math.min(-240,Math.floor(Math.min(...all.map(p=>p.x))-32)),minY=Math.min(-240,Math.floor(Math.min(...all.map(p=>p.y))-32)),maxX=Math.max(240,Math.ceil(Math.max(...all.map(p=>p.x))+32)),maxY=Math.max(240,Math.ceil(Math.max(...all.map(p=>p.y))+32)),W=maxX-minX+1,H=maxY-minY+1,N=W*H;if(N>2400000)throw Error('当前参数产生超过240万格，请降低发展年数或速度');
 // The transport tails cannot create development frontage or change the already chosen map extent.
 function toBoundary(points){const out=[points[0]],lo=[minX+.5,minY+.5],hi=[maxX+.5,maxY+.5];for(let i=1;i<points.length;i++){const a=points[i-1],b=points[i];let t=1;for(let axis=0;axis<2;axis++){if(b[axis]<lo[axis])t=Math.min(t,(lo[axis]-a[axis])/(b[axis]-a[axis]));if(b[axis]>hi[axis])t=Math.min(t,(hi[axis]-a[axis])/(b[axis]-a[axis]));}if(t<1){if(t>1e-8){let end=[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];
    // Intersect the sampled circular bend itself; splitting its final chord would create a tighter endpoint kink.
    if(i>1){const c=points[i-2],u=[a[0]-c[0],a[1]-c[1]],v=[b[0]-c[0],b[1]-c[1]],cross=u[0]*v[1]-u[1]*v[0];if(Math.abs(cross)>1e-7){const uu=u[0]**2+u[1]**2,vv=v[0]**2+v[1]**2,center=[c[0]+(uu*v[1]-vv*u[1])/(2*cross),c[1]+(u[0]*vv-v[0]*uu)/(2*cross)],radius=Math.hypot(a[0]-center[0],a[1]-center[1]),axis=Math.abs(end[0]-lo[0])<1e-6||Math.abs(end[0]-hi[0])<1e-6?0:1,other=1-axis,radicand=radius*radius-(end[axis]-center[axis])**2;if(radicand>=0){const roots=[-1,1].map(sign=>{const p=[...end];p[other]=center[other]+sign*Math.sqrt(radicand);return p;}).filter(p=>p[other]>=lo[other]&&p[other]<=hi[other]);roots.sort((p,q)=>Math.hypot(p[0]-end[0],p[1]-end[1])-Math.hypot(q[0]-end[0],q[1]-end[1]));if(roots.length)end=roots[0];}}}out.push(end);}return out;}out.push(b);}throw Error('地图范围超出铁路预留路径，请缩小发展规模或调整出口');}
 for(const route of railPlans){if(!route.realized)continue;for(const arm of route.activeArms){arm.extended=toBoundary(arm.points);const tail=arm.extended.slice(arm.realized.length-1),cells=railCells(tail).filter(([x,y])=>x>=minX&&x<=maxX&&y>=minY&&y<=maxY),work=earthwork(cells),id='rail-external-'+arm.exitIndex;
   if(!Number.isFinite(work.cost))throw Error('外部铁路受保留岩体阻挡');roads.push({id,name:'快速旅行点外运输隧道',kind:'rail-external',scope:'interbubble',width:o.mainWidth,minimumWidth:3,year:arm.exit.year,builtYear:arm.exit.year,order:route.road.order,purpose:'快速旅行点至地图边缘',servesProject:'station',serves:['station'],points:tail,center:tail,cells,earthwork:work});for(const[x,y]of cells)if(!streets.has(K(x,y)))streets.set(K(x,y),{x,y,year:arm.exit.year,order:route.road.order,roadId:id,kind:'rail-external'});
  }
  const bay=raster(route.bay[0],route.bay[1]);if(route.mode==='through'){const left=route.activeArms.find(a=>a.exitIndex===route.exitIndices[0]),right=route.activeArms.find(a=>a.exitIndex===route.exitIndices[1]);route.extendedPoints=[...(left?[...left.extended].reverse():[bay[0]]),...bay.slice(1),...(right?right.extended.slice(1):[])];}else route.extendedPoints=[...bay,...route.activeArms[0].extended.slice(1)];
 }
 const trams=[],portals=[];
 for(const route of railPlans){if(!route.realized)continue;const points=route.realized,length=points.reduce((n,p,i)=>i?n+Math.hypot(p[0]-points[i-1][0],p[1]-points[i-1][1]):0,0),internal=length>=o.minRailLength&&railPlans.indexOf(route)<Math.ceil(railPlans.length*o.railCoverage),stops=[{id:'ST1',platformId:route.id+'-P',x:route.stop[0],y:route.stop[1],name:'中央车站 · '+route.name}];if(internal)for(let i=o.stopSpacing;i<points.length-20;i+=o.stopSpacing)if(Math.hypot(points[i][0]-route.stop[0],points[i][1]-route.stop[1])>o.stopSpacing*.5)stops.push({id:route.id+'-stop-'+i,x:points[i][0],y:points[i][1],name:'片区电车站'});trams.push({id:route.id,name:route.name,mode:route.mode==='through'&&route.activeArms.length===2?'through':'terminal',plannedMode:route.mode,pairAngle:route.pairAngle,exitIndices:route.exitIndices,activeExitIndices:route.activeArms.map(a=>a.exitIndex),internalLengthMetres:Math.round(length),scope:internal?'internal':'interbubble',points:route.extendedPoints,widthMetres:4,trackOffsets:[-1,1],lengthMetres:Math.round(route.extendedPoints.reduce((n,p,i)=>i?n+Math.hypot(p[0]-route.extendedPoints[i-1][0],p[1]-route.extendedPoints[i-1][1]):0,0)),stops,year:Math.min(...route.activeArms.map(a=>a.exit.year)),roadId:route.road.id,bufferStop:route.mode==='through'?(route.activeArms.length===1?route.bay[route.activeArms[0].exitIndex===route.exitIndices[0]?1:0]:null):route.bay[0]});for(const arm of route.activeArms){const point=arm.realized.at(-1);portals.push({id:'P'+(arm.exitIndex+1),lineId:route.id,exitIndex:arm.exitIndex,x:Math.round(point[0]),y:Math.round(point[1]),bearing:arm.exit.bearing,offset:arm.exit.offset,year:arm.exit.year,direction:arm.exit.bearing+'°',source:'input',role:'fast-travel',trackEnd:arm.extended.at(-1),externalPoints:arm.extended.slice(arm.realized.length-1),name:'快速旅行点 '+(arm.exitIndex+1)});}}
 progress('terrain','汇整地形与已建空间',0,H);const geologyGrid=new Uint8Array(N),rock=new Uint8Array(N),ground=new Uint8Array(N),growth=new Uint16Array(N),excavation=new Uint8Array(N),cityMask=new Uint8Array(N),streetMask=new Uint8Array(N),plannedMask=new Uint8Array(N),informalMask=new Uint8Array(N);growth.fill(65535);const idx=(x,y)=>(y-minY)*W+x-minX,point=p=>[p[0]-minX,p[1]-minY];for(let y=minY;y<=maxY;y++){if((y-minY)%16===0)progress('terrain','汇整地形行 '+(y-minY)+' / '+H,y-minY,H);for(let x=minX;x<=maxX;x++){const s=sample(x,y),i=idx(x,y);rock[i]=s.rock;geologyGrid[i]=s.geology;if(s.geology)ground[i]=1;}}
 const mark=(x,y,year,kind,phase)=>{const i=idx(x,y);ground[i]=cityMask[i]=1;growth[i]=Math.min(growth[i],year);if(!geologyGrid[i])excavation[i]=kind;if(phase==='resident')informalMask[i]=1;else plannedMask[i]=1;};
 for(const p of streets.values()){mark(p.x,p.y,p.year,3,p.kind==='self-built'?'resident':'government');streetMask[idx(p.x,p.y)]=1;}for(const r of roads){r.cells=r.cells.map(([x,y])=>idx(x,y));r.points=r.points.map(point);r.center=r.center.map(point);r.name=r.name||r.purpose;}
 const regions=quarters.map(q=>({...q,x:q.x-minX,y:q.y-minY,w:q.w,h:q.h})),blocks=parcels.map(b=>{const {mask,...data}=b,cells=[...mask].map(k=>idx(...k.split(',').map(Number))),outline=[];for(const k of mask){const[x,y]=k.split(',').map(Number);for(const[dx,dy]of D)if(!mask.has(K(x+dx,y+dy))){const a=dx<0?[x,y,x,y+1]:dx>0?[x+1,y,x+1,y+1]:dy<0?[x,y,x+1,y]:[x,y+1,x+1,y+1];outline.push([a[0]-minX,a[1]-minY,a[2]-minX,a[3]-minY]);}}return{...data,x:b.x-minX,y:b.y-minY,cells,outline};}),outputProjects=[];
 for(const q of projects){const cells=q.cells.map(([x,y])=>idx(x,y)),construction=q.phase==='resident'?'自建扩挖':q.p.wholeBlock?'统一建设':'规划沿街',district=q.p.type==='station'?'station':q.parcel?.quarterId||quarters.reduce((a,b)=>Math.hypot(q.x-a.x,q.y-a.y)<Math.hypot(q.x-b.x,q.y-b.y)?a:b).id;for(const[x,y]of q.cells){const year=q.cellYears.get(K(x,y))??q.year,phase=year>q.year?'resident':q.phase;mark(x,y,year,phase==='resident'?4:2,phase);}const naturalShare=q.cells.filter(([x,y])=>sample(x,y).geology).length/q.cells.length,excavationMode=q.constructionMode==='共用洞厅内建设'?(naturalShare>.75?'天然洞厅内建设':naturalShare<.1?'人工洞厅内建设':'混合洞厅内建设'):naturalShare>.75?'天然空腔内建设':naturalShare<.1?'岩体内开凿':'沿洞壁混合扩挖';outputProjects.push({...q,x:q.x-minX,y:q.y-minY,worldX:q.x+origin[0],worldY:q.y+origin[1],cells,construction,district,blockId:q.parcel?.id||null,naturalShare,excavationMode});}
 // Demolition removes buildings, not the fact that their ground was excavated.
 for(const[k,old]of vacated){const[x,y]=k.split(',').map(Number);mark(x,y,old.year,2,'government');}
 const publicGround=new Set(spaces.flatMap(s=>s.cells.map(p=>K(...p)))),outsideSeen=new Set(),outsideQueue=[...streets.keys()];for(const k of outsideQueue)outsideSeen.add(k);
 for(let cursor=0;cursor<outsideQueue.length;cursor++){const[x,y]=outsideQueue[cursor].split(',').map(Number);for(const[dx,dy]of D){const a=x+dx,b=y+dy,k=K(a,b);if(a<minX||a>maxX||b<minY||b>maxY||outsideSeen.has(k)||occupied.has(k)&&!publicGround.has(k)||!ground[idx(a,b)])continue;outsideSeen.add(k);outsideQueue.push(k);}}
 const remnants=new Map();for(const[k,old]of vacated){if(occupied.has(k)||streets.has(k))continue;const kind=outsideSeen.has(k)?'cleared-site':'foundation',group=old.owner+':'+kind;if(!remnants.has(group))remnants.set(group,{kind,old,cells:[]});remnants.get(group).cells.push(k.split(',').map(Number));}
 for(const{kind,old,cells}of remnants.values()){const event=demolitions.find(d=>d.buildingId===old.owner);spaces.push({id:'C'+(spaces.length+1),name:kind==='foundation'?'拆迁后保留墙基':'旧房基与改建场地',purpose:kind==='foundation'?'保留的旧墙基与结构残余':'已清退房屋的地基，供通行与后续建设利用',kind,projectId:event.quarterId,buildingIds:[],year:old.demolishedYear,builtYear:old.demolishedYear,cells});}
 for(const s of spaces){for(const[x,y]of s.cells)mark(x,y,s.year,2);const ps=s.cells.map(point);s.cells=s.cells.map(([x,y])=>idx(x,y));s.x=Math.min(...ps.map(p=>p[0]));s.y=Math.min(...ps.map(p=>p[1]));s.w=Math.max(...ps.map(p=>p[0]))-s.x+1;s.h=Math.max(...ps.map(p=>p[1]))-s.y+1;const cx=s.x+s.w/2,cy=s.y+s.h/2;s.label=ps.reduce((best,p)=>Math.hypot(p[0]-cx,p[1]-cy)<Math.hypot(best[0]-cx,best[1]-cy)?p:best);}
 const station={id:'ST1',buildingId:'B0000',name:'中央车站',x:-minX,y:-minY,w:stationSite.p.w,h:stationSite.p.h,platformCells:[],trackCells:[...new Set(roads.filter(r=>r.kind==='station-track').flatMap(r=>r.cells))],role:'bubble-hub',year:0,platforms:stationSite.platforms.map(p=>({...p,stop:point(p.stop),rect:{...p.rect,x:p.rect.x-minX,y:p.rect.y-minY},active:trams.some(t=>t.id===p.lineId)})),lineCount:trams.length,plannedLines:stationSite.lines.map(l=>({id:l.id,mode:l.mode,exitIndices:l.exitIndices,pairAngle:l.pairAngle})),failures:railDesign.failures};for(const platform of stationSite.platforms)for(let y=platform.rect.y;y<platform.rect.y+platform.rect.h;y++)for(let x=platform.rect.x;x<platform.rect.x+platform.rect.w;x++)station.platformCells.push(idx(x,y));
 for(const t of trams){t.points=t.points.map(point);if(t.bufferStop)t.bufferStop=point(t.bufferStop);t.stops=t.stops.map(s=>({...s,x:s.x-minX,y:s.y-minY}));t.cells=[...new Set(roads.filter(r=>r.id===t.roadId||t.activeExitIndices.some(i=>r.id==='rail-external-'+i)).flatMap(r=>r.cells))];}for(const p of portals){p.x-=minX;p.y-=minY;p.trackEnd=point(p.trackEnd);p.externalPoints=p.externalPoints.map(point);}
 const seen=new Uint8Array(N),queue=new Int32Array(N),components=[];for(let i=0;i<N;i++)if(geologyGrid[i]&&!seen[i]){let h=0,t=0;queue[t++]=i;seen[i]=1;while(h<t){const j=queue[h++],x=j%W,y=Math.floor(j/W);for(const k of [x?j-1:-1,x<W-1?j+1:-1,y?j-W:-1,y<H-1?j+W:-1])if(k>=0&&geologyGrid[k]&&!seen[k]){seen[k]=1;queue[t++]=k;}}components.push(t);}components.sort((a,b)=>b-a);
 progress('terrain','地形与街区汇整完成',H,H);
 return{width:W,height:H,worldOrigin:[minX+origin[0],minY+origin[1]],geology:geologyGrid,rock,ground,growth,excavation,cityMask,streetMask,plannedMask,informalMask,roads,tram:trams,portals,station,blocks,regions,spaces,projects:outputProjects,history,warnings,demolitions,planningEvents,settlement:{...demandState(o.years),awaitingResettlement:relocationPending,totalDisplaced,totalResettled},terrainStats:{origin:{x:station.x,y:station.y},caveSystems:components.filter(n=>n>=64).length,caveComponents:components.length,largestCaveShare:components.length?components[0]/components.reduce((n,v)=>n+v,0):0,naturalCells:geologyGrid.reduce((n,v)=>n+!!v,0),developedCells:cityMask.reduce((n,v)=>n+v,0),reusedCells:cityMask.reduce((n,v,i)=>n+(v&&!!geologyGrid[i]),0)}};
}
root.BubblePlanning={plan,geology,groupPlan};if(typeof module!=='undefined')module.exports=root.BubblePlanning;
})(typeof window!=='undefined'?window:globalThis);
