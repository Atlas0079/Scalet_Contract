(function(root){'use strict';
const C=typeof module!=='undefined'?require('./content.js'):root.BubbleContent;
Object.assign(C.catalog,{hospital:{label:'公司医院',category:'civic'},housing_complex:{label:'公司宿舍综合体',category:'housing'},production_complex:{label:'联合生产厂房',category:'industry'},logistics_complex:{label:'物流综合体',category:'industry'},robot_shop:{label:'私营机器人维修铺',category:'commerce'},robot_parts:{label:'机器人配件店',category:'commerce'},power_shop:{label:'电源检测与更换店',category:'commerce'},salvage:{label:'二手机体拆件行',category:'industry'},android_clinic:{label:'地下仿生人诊所',category:'civic'},bakery:{label:'食品加工与供应店',category:'commerce'}});
 C.catalog.pharmacy={label:'社区药房',category:'commerce'};
const extras=[
 {id:'pharmacy',name:'社区药房',type:'pharmacy',entry:[3,0],rooms:[{name:'药品售货',x:0,y:0,w:7,h:4},{name:'药品库',x:0,y:4,w:7,h:4}],links:[[0,1]]},
 {id:'robot-private',name:'私营机器人维修铺',type:'robot_shop',entry:[4,0],rooms:[{name:'接单与配件',x:0,y:0,w:8,h:4},{name:'机器人维修工位',x:0,y:4,w:8,h:6}],links:[[0,1]]},
 {id:'robot-parts',name:'执行器与传感器店',type:'robot_parts',entry:[4,0],rooms:[{name:'配件售货区',x:0,y:0,w:8,h:5},{name:'零件库',x:0,y:5,w:5,h:4},{name:'电子检测',x:5,y:5,w:3,h:4}],links:[[0,1],[0,2]]},
 {id:'power-service',name:'电源检测与更换店',type:'power_shop',entry:[3,0],rooms:[{name:'接待室',x:0,y:0,w:6,h:4},{name:'电源检测',x:0,y:4,w:6,h:5}],links:[[0,1]]},
 {id:'robot-salvage',name:'二手机体拆件行',type:'salvage',entry:[4,0],rooms:[{name:'二手机体陈列',x:0,y:0,w:9,h:5},{name:'拆件工位',x:0,y:5,w:6,h:6},{name:'零件库',x:6,y:5,w:3,h:6}],links:[[0,1],[1,2]]},
 {id:'food-supply',name:'食品加工与供应店',type:'bakery',entry:[4,0],rooms:[{name:'售货区',x:0,y:0,w:8,h:4},{name:'厨房',x:0,y:4,w:5,h:5},{name:'食品库',x:5,y:4,w:3,h:5}],links:[[0,1],[1,2]]},
 {id:'hidden-android',name:'私营诊所隐蔽整备间',type:'android_clinic',special:true,entry:[3,0],rooms:[{name:'诊室',x:0,y:0,w:6,h:4},{name:'仿生人组织修复',x:0,y:4,w:6,h:5,access:'非正规隐蔽业务'},{name:'专用耗材库',x:6,y:4,w:3,h:5}],links:[[0,1],[1,2]],legalStatus:'非正规',requires:'低治安片区与专用耗材渠道'}
];
C.catalog.robot={label:'机器人综合检修站',category:'industry'};
for(const p of extras)p.wallMode='edge';
function complex(block){
 const R=C.random(block.designSeed),ri=(a,b)=>Math.floor(a+R()*(b-a+1)),scale=block.scale,dim=(a,b,min=8)=>Math.max(min,Math.round(ri(a,b)*scale)),rooms=[],links=[],openLinks=[],masses=[];
 const add=(name,x,y,w,h,extra={})=>{rooms.push({name,x,y,w,h,...extra});return rooms.length-1;};
 const overlap=(A,B)=>A.x<B.x+B.w&&A.x+A.w>B.x&&A.y<B.y+B.h&&A.y+A.h>B.y;
 const occupied=(x,y)=>rooms.some(r=>x>=r.x&&x<r.x+r.w&&y>=r.y&&y<r.y+r.h);
 const industrial=['production','transport'].includes(block.program),type={planned_housing:'housing_complex',hospital:'hospital',production:'production_complex',transport:'logistics_complex'}[block.program];
 function attach(parent,name,w,h,zone,open=false){const A=rooms[parent],directions=[0,1,2,3];for(let k=3;k>0;k--){const j=ri(0,k);[directions[k],directions[j]]=[directions[j],directions[k]];}
  for(const direction of directions)for(let attempt=0;attempt<18;attempt++){
   const gap=open?0:R()<.65?0:ri(4,7),vertical=direction%2===0;
   const offset=vertical?ri(-w+6,A.w-6):ri(-h+6,A.h-6),B={x:vertical?A.x+offset:direction===1?A.x+A.w+gap:A.x-gap-w,y:vertical?(direction===0?A.y-gap-h:A.y+A.h+gap):A.y+offset,w,h};
   const lo=vertical?Math.max(A.x,B.x):Math.max(A.y,B.y),hi=vertical?Math.min(A.x+A.w,B.x+B.w):Math.min(A.y+A.h,B.y+B.h),axis=Math.floor((lo+hi-4)/2);
   const corridor=vertical?{x:axis,y:direction===0?B.y+B.h:A.y+A.h,w:4,h:gap}:{x:direction===1?A.x+A.w:B.x+B.w,y:axis,w:gap,h:4};
   if(rooms.some(r=>overlap(B,r))||gap&&rooms.some(r=>overlap(corridor,r)))continue;
   const id=add(name,B.x,B.y,w,h,{zone,openHall:open}),m={name,x:B.x,y:B.y,w,h};masses.push(m);
   if(open){rooms[parent].openHall=true;openLinks.push([parent,id]);}else if(gap){const c=add('货运连接通廊',corridor.x,corridor.y,corridor.w,corridor.h,{circulation:'cargo'});links.push([parent,c,{width:3,role:'货运门'}],[c,id,{width:3,role:'货运门'}]);}else links.push([parent,id,{width:3,role:'工序转运门'}]);return id;
  }throw Error('功能体量无法组合 '+name);
 }
 let mainRoom,receive,dispatch,layout,operations;
 if(industrial){
  receive=add(block.program==='production'?'材料准备':'收货与分拣',0,0,dim(20,29),dim(16,23),{zone:'materials'});masses.push({...rooms[receive]});
  const workshop=attach(receive,block.program==='production'?'机加工车间':'货物库房',dim(29,43,16),dim(25,36,14),'production');
  if(block.variant!==0)attach(workshop,block.program==='production'?'机加工延伸区':'仓储延伸区',dim(13,21),dim(12,22),'production',true);
  const assembly=attach(workshop,block.program==='production'?'装配与检验':'发货整备',dim(22,34,14),dim(18,29,12),'assembly');
  dispatch=attach(assembly,'成品暂存',dim(17,24),dim(12,20),'dispatch');
  const top=rooms.reduce((a,b)=>a.y<b.y?a:b),staffW=dim(32,48,24),staffH=ri(9,12),x=top.x+Math.floor(top.w/2)-1,y=top.y-staffH-5;
  const spine=add('人员通道',x,y,3,staffH,{circulation:'staff'});mainRoom=add('接待与人员通廊',x+3,y,staffW-3,3,{circulation:'staff'});links.push([spine,mainRoom,{width:2,role:'人员通廊'}]);
  const connector=add('人员连接通廊',x,top.y-5,3,5,{circulation:'staff'}),topId=rooms.indexOf(top);links.push([spine,connector,{width:2,role:'人员通廊'}],[connector,topId,{width:2,role:'作业区入口'}]);
  add('卫生间',x+3,y+3,2,3);add('洗手间',x+5,y+3,3,staffH-3);if(staffH>6)add('清洁间',x+3,y+6,2,staffH-6);
  let xx=x+8,n=0;while(xx<x+staffW){const remain=x+staffW-xx,w=remain>16?ri(6,10):remain;add(['更衣室','办公室','休息室'][n++%3],xx,y+3,w,staffH-3,{zone:'staff'});xx+=w;}
  masses.push({name:'人员服务翼',x,y,w:staffW,h:staffH});layout='工序体量组合 · '+masses.length+' 个体量';operations='收货 → 材料 / 分拣 → 加工 / 仓储 → 装配 / 整备 → 成品暂存 → 发货；人员服务翼独立接入';
 }else{
  const length=dim(66,94,48),spine=add('公共主通廊',0,0,length,4,{circulation:'public'}),hubW=dim(16,23,12),hx=Math.floor((length-hubW)/2);
  mainRoom=add(block.program==='hospital'?'接待与候诊':'公共门厅',hx,-10,hubW,10,{circulation:'public',zone:'lobby'});links.push([mainRoom,spine,{width:3,role:'公共入口'}]);masses.push({name:'公共中枢',x:hx,y:-10,w:hubW,h:14});
  const wings=[];for(const side of [1,-1]){let x=ri(0,3);while(x<length-15){const left=ri(6,9),right=ri(6,9),w=left+3+right;if(x+w>length)break;if(side<0&&x<hx+hubW+3&&x+w>hx-3){x=hx+hubW+ri(3,7);continue;}
    const depth=dim(24,42,18),top=side>0?4:-depth,walk=add('翼部公共通廊',x+left,top,3,depth,{circulation:'public'});links.push([spine,walk,{width:2,role:'翼部入口'}]);
    let y=top,row=0;while(y<top+depth){const remaining=top+depth-y,h=remaining>15?ri(6,8):remaining;for(const [xx,width,idx]of [[x,left,0],[x+left+3,right,1]]){let name=block.program==='hospital'?['诊室','处置室','病房','药房','办公室'][(row+idx+wings.length)%5]:row===0&&idx===0?'公共厨房':row%4===3&&idx===1?'活动室':'宿舍';
      if(row===1&&idx===0){add('卫生间',xx+width-2,y,2,3);add(block.program==='hospital'?'消毒准备':'洗衣房',xx,y,width-2,h);if(h>3)add('备品间',xx+width-2,y+3,2,h-3);}else add(name,xx,y,width,h);
     }y+=h;row++;}
    wings.push({x,y:top,w,h:depth});masses.push({name:'功能翼',x,y:top,w,h:depth});x+=w+ri(4,9);
   }}
  if(block.program==='hospital'){const candidates=rooms.filter(r=>!r.circulation&&!['卫生间','消毒准备','备品间'].includes(r.name));const a=candidates.at(-1),b=candidates.at(-2);a.name='仿生人组织修复';a.access='企业管制区域';b.name='专用耗材库';b.access='企业管制区域';}
  layout='公共中枢与'+wings.length+'个长短翼部';operations='主入口 → 公共中枢 → 分支通廊 → 独立功能房间';dispatch=spine;
 }
 function shared(a,b){const A=rooms[a],B=rooms[b];if(A.x+A.w===B.x||B.x+B.w===A.x)return Math.max(0,Math.min(A.y+A.h,B.y+B.h)-Math.max(A.y,B.y));if(A.y+A.h===B.y||B.y+B.h===A.y)return Math.max(0,Math.min(A.x+A.w,B.x+B.w)-Math.max(A.x,B.x));return 0;}
 const hall=i=>!!rooms[i].circulation,has=(a,b)=>[...links,...openLinks].some(e=>e[0]===a&&e[1]===b||e[0]===b&&e[1]===a);
 for(let a=0;a<rooms.length;a++)if(hall(a))for(let b=a+1;b<rooms.length;b++)if(hall(b)&&shared(a,b)&&!has(a,b))links.push([a,b,{width:Math.min(2,shared(a,b)),role:'通廊连接'}]);
 const linked=new Set(links.flatMap(e=>e.slice(0,2)).concat(openLinks.flat()));
 for(let a=0;a<rooms.length;a++)if(!linked.has(a)){
  const candidates=rooms.map((_,i)=>i).filter(b=>b!==a&&shared(a,b)&&rooms[b].name!=='卫生间').sort((b,c)=>(hall(c)?1000:0)+shared(a,c)-(hall(b)?1000:0)-shared(a,b));const b=candidates[0];if(b===undefined)throw Error('功能房间没有连接 '+rooms[a].name);links.push([a,b,{width:1,role:'房间门'}]);
 }
 function door(roomId,width,role,preferred='north'){
  const r=rooms[roomId],directions=[preferred,...['north','east','south','west'].filter(d=>d!==preferred)];
  for(const front of directions){const vertical=front==='east'||front==='west',span=vertical?r.h:r.w;const order=Array.from({length:span-width+1},(_,i)=>i).sort((a,b)=>Math.abs(a-(span-width)/2)-Math.abs(b-(span-width)/2));
   for(const pos of order){const x=vertical?(front==='east'?r.x+r.w:r.x):r.x+pos,y=vertical?r.y+pos:(front==='south'?r.y+r.h:r.y),dx=front==='east'?1:front==='west'?-1:0,dy=front==='south'?1:front==='north'?-1:0;let clear=true;
    for(let a=-1;a<=width&&clear;a++)for(let depth=1;depth<=7;depth++){const xx=x+(vertical?0:a)+(dx>0?depth-1:dx*depth),yy=y+(vertical?a:0)+(dy>0?depth-1:dy*depth);if(occupied(xx,yy)){clear=false;break;}}
    if(clear)return{x,y,front,width,role};
   }
  }throw Error('功能体量没有外部门净空 '+r.name);
 }
 const primary=door(mainRoom,1,'人员入口'),exits=industrial?[door(receive,3,'收货门','west'),door(dispatch,3,'装卸门','east')]:[door(dispatch,2,'后勤出口','east')];
 const minX=Math.min(...rooms.map(r=>r.x)),minY=Math.min(...rooms.map(r=>r.y)),maxX=Math.max(...rooms.map(r=>r.x+r.w)),maxY=Math.max(...rooms.map(r=>r.y+r.h));
 for(const r of rooms){r.x-=minX;r.y-=minY;}for(const r of masses){r.x-=minX;r.y-=minY;}for(const d of [primary,...exits]){d.x-=minX;d.y-=minY;}
 return{id:'complex-'+block.id,name:block.kind,type,special:true,wallMode:'edge',entry:[primary.x,primary.y],front:primary.front,exits,rooms,links,openLinks,blockId:block.id,wholeBlock:true,layout,operations,masses,w:maxX-minX,h:maxY-minY};
}

root.BubbleComplexes={complex,extras};if(typeof module!=='undefined')module.exports=root.BubbleComplexes;
})(typeof window!=='undefined'?window:globalThis);
