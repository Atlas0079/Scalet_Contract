(function(root){'use strict';
function corridorWidth(R,kind,available,options){
 const values=kind==='private'?[2,2,3]:kind==='apartment'?[2,3,3,4]:[3,3,4,4,5],limit=Math.min(available,options[kind==='private'?'privateCorridorMax':kind==='apartment'?'apartmentCorridorMax':'publicCorridorMax']);
 for(let width=Math.max(...values)+1;width<=limit;width++)values.push(width);
 const allowed=values.filter(n=>n<=limit);if(!allowed.length)throw Error('场地不足以容纳通廊');return allowed[Math.floor(R()*allowed.length)];
}
// Rooms remain rectangles on the existing grid. A building is their union, not its bounding box.
function fitted(id,w,h,program,R,options,variant=0){
 const rooms=[],links=[],exits=[],outdoors=[],ri=(a,b)=>Math.floor(a+R()*(b-a+1));
 const add=(name,x,y,w,h,extra={})=>{if(w<1||h<1)throw Error('无效房间尺寸 '+id);rooms.push({name,x,y,w,h,...extra});return rooms.length-1;};
 const link=(a,b,width=1)=>links.push([a,b,{width}]);
 let entry=[Math.floor(w/2),0],type='apartment',name,layout,households=['housing','dorm'].includes(program)?1:null,special=false,wholeBlock=false;
 // Each dwelling has a day room and a bounded service core; extra area becomes living units.
 function unit(x,y,uw,uh,mirror=false){
  const first=rooms.length,day=Math.min(4,Math.max(3,Math.floor(uh*.4))),living=add(uw*uh<40?'起居卧室':'起居餐室',x,y,uw,day);
  if(uh>=13&&uw>=8){rooms[living].name='起居厨房';
   const back=uh-day,passage=corridorWidth(R,'private',uw-5,options),walk=add('户内过道',x+uw-2-passage,y+day,passage,back,{circulation:'private'}),wet=add('卫生间',x+uw-2,y+day,2,3);link(living,walk);link(living,wet);
   const rows=Math.ceil(back/6);for(let i=0;i<rows;i++){const top=Math.floor(back*i/rows),bottom=Math.floor(back*(i+1)/rows),trim=i===rows-1&&variant%2?Math.min(2,uw-5-passage):0,room=add(i===rows-1&&rows>2?'工作间':'卧室',x+trim,y+day+top,uw-2-passage-trim,bottom-top);link(walk,room);}
   let top=3;while(top<back){const depth=Math.min(4,back-top),room=add('储藏间',x+uw-2,y+day+top,2,depth);link(walk,room);top+=depth;}return first;
  }
  rooms[living].name='起居厨房';
  if(uh-day>=3){const back=uh-day,wet=add('卫生间',x+uw-2,y+day,2,3);link(living,wet);
   const bedWidth=uw-2,split=bedWidth>=9?Math.floor(bedWidth*.53):bedWidth;
   const bed=add('卧室',x,y+day,split,back);link(living,bed);
   if(split<bedWidth){const second=add(variant%2?'工作间':'卧室',x+split,y+day,bedWidth-split,back);link(living,second);}
   if(back>3){const kitchen=add('储藏间',x+uw-2,y+day+3,2,back-3);link(bedWidth===split?bed:rooms.length-2,kitchen);}
   else{rooms[living].name='起居厨房';}
  }
  if(mirror)for(const room of rooms.slice(first))room.y=y+uh-(room.y-y)-room.h;
  return first;
 }
 if(['production','transport'].includes(program)&&w>=16&&h>=18){
  type=program==='production'?'production_complex':'logistics_complex';name=program==='production'?(options.industry==='robotics'?'机器人制造厂':options.industry==='food'?'食品加工厂':'联合生产厂'):'物流与分拣中心';special=wholeBlock=true;layout='人员服务带、错落作业翼与独立收发货区';
  const front=4,passage=corridorWidth(R,'public',h-12,options),workY=front+passage,walk=add('人员通道',0,front,w,passage,{circulation:'staff'}),officeWidth=Math.max(5,Math.floor(w*.42));
  const reception=add('接待与人员通廊',0,0,officeWidth,front),office=add('办公室',officeWidth,0,w-officeWidth-2,front),bath=add('卫生间',w-2,0,2,3);
  link(reception,walk,2);link(office,walk);link(office,bath);if(w-2>officeWidth)link(reception,office);entry=[Math.floor(w/2),0];
  const bays=Math.max(2,Math.floor(w/16)),widths=[];let left=w;
  for(let i=0;i<bays;i++){const width=i===bays-1?left:Math.round(left/(bays-i)+(R()-.5)*4);widths.push(width);left-=width;}
  let x=0,previous=-1;
  widths.forEach((width,i)=>{const rear=5,step=i===0?0:ri(0,Math.min(5,h-18)),end=h-step,workH=end-workY-rear;
   const hall=add(program==='transport'?'货物库房':options.industry==='food'?(i%2?'包装分拣':'食品加工'):options.industry==='robotics'?(i%2?'机器人检测':'机器人装配'):i%2?'装配与检验':'机加工车间',x,workY,width,workH,{capacity:Math.max(1,Math.floor(width*workH/24))});link(walk,hall,2);
   const store=add(i%2?'成品暂存':'材料准备',x,end-rear,width,rear);link(hall,store,3);if(previous>=0)link(previous,hall,3);previous=hall;x+=width;
  });
 }else if(program==='hospital'||program==='clinic'){
  type=program;name=program==='hospital'?'综合医院':'社区诊所';special=wholeBlock=program==='hospital';layout='公共通廊连接诊疗单元、病区与护理配套';
  const passage=corridorWidth(R,'public',w-6,options),walk=Math.floor(w/2)-Math.floor(passage/2),hall=add('公共过道',walk,0,passage,h,{circulation:'public'});entry=[Math.floor(w/2),0];
  for(const side of [0,1]){const maxWidth=side?w-walk-passage:walk;let y=0,row=0;
   while(y<h){const remain=h-y,depth=remain>=10?ri(5,Math.min(8,remain-5)):remain,trim=row>0?ri(0,Math.min(3,maxWidth-5)):0,width=maxWidth-trim,x=side?walk+passage:walk-width;
    const roomName=row===0?'接待与候诊':row%3===1?(side?(program==='hospital'?'病房':'处置室'):'诊室'):row%3===2?'处置室':'护理准备';
    if(width>11&&roomName!=='病房'&&(row>0||side===1)&&depth>=5){const branch=add('诊疗支廊',x,y,width,2,{circulation:'public'});link(hall,branch,2);const count=Math.ceil(width/8);for(let k=0;k<count;k++){const start=Math.floor(width*k/count),end=Math.floor(width*(k+1)/count),a=add(row===0?(k===0?'药房':'护理准备'):roomName==='护理准备'?(k===0?'护理准备':'药品库'):k===count-1&&row%2===0?'消毒准备':roomName,x+start,y+2,end-start,depth-2);link(branch,a);}}
    else if(row===0&&width>11){const service=3,a=add(roomName,side?x+service:x,y,width-service,depth),b=add('分诊',side?x:x+width-service,y,service,depth);link(hall,b,2);link(b,a,2);}
    else{const a=add(roomName,x,y,width,depth,{capacity:roomName==='病房'?Math.max(1,Math.floor(width*depth/14)):undefined});link(hall,a,2);}
    y+=depth;row++;
   }
  }
 }else if(program==='housing'&&w>=16&&h>=6||program==='dorm'){
  type=program==='dorm'?'housing_complex':'apartment';name=program==='dorm'?'集中式工人宿舍':variant%2?'错落共廊住宅':'双侧多户住宅';layout='共用通廊与不同进深的独立住宅';households=0;
  const passage=corridorWidth(R,program==='dorm'?'public':'apartment',w-12,options),walk=Math.floor(w/2)-Math.floor(passage/2),hall=add('公共过道',walk,0,passage,h,{circulation:'public'});entry=[Math.floor(w/2),0];
  for(const side of [0,1]){const maxWidth=side?w-walk-passage:walk;let y=0,row=0;
   while(y<h){const remain=h-y,depth=remain>=12?ri(6,Math.min(9,remain-6)):remain,trim=variant%3!==0&&row>0?ri(0,Math.min(3,maxWidth-6)):0,width=maxWidth-trim,x=side?walk+passage:walk-width;
    if(program==='dorm'&&side===1&&y+depth===h&&R()<options.sharedHousing){const front=Math.max(3,Math.floor(depth/2)),a=add('公共厨房',x,y,width,front),b=add('公共洗浴',x,y+front,3,depth-front),c=add('洗衣烘干',x+3,y+front,width-3,depth-front);link(hall,a);link(hall,b);link(a,c);y+=depth;row++;continue;}
    // The day room adjoins the shared corridor; beds and wet rooms stay inside each household.
    const base=rooms.length,day=Math.min(4,Math.max(3,Math.floor(width*.5))),dayX=side?x:x+width-day;
    const a=add('起居厨房',dayX,y,day,depth);link(hall,a);const bx=side?x+day:x,bw=width-day;
    if(bw>=2){const bed=add(depth>10?'双人寝室':'卧室',bx,y,bw,depth-3);link(a,bed);
     const wetX=side?bx:bx+bw-2,wet=add('卫生间',wetX,y+depth-3,2,3);link(a,wet);
     if(bw>2){const kitchen=add('储藏间',side?bx+2:bx,y+depth-3,bw-2,3);link(bed,kitchen);}
    }
    // Very narrow wings remain single studios with their wet core along the corridor.
    if(rooms.length===base+1)rooms[a].name='起居卧室';
    households++;y+=depth;row++;
   }
  }
 }else if(program==='school'||program==='lodging'){
  type=program;name=program==='school'?'社区学校':'短住旅舍';special=program==='school';wholeBlock=special;households=null;layout=program==='school'?'教学通廊、教室和公共阅览':'接待与公共通廊连接不同大小客房';
  const passage=corridorWidth(R,program==='school'?'public':'apartment',w-6,options),walk=Math.floor(w/2)-Math.floor(passage/2),hall=add('公共过道',walk,0,passage,h,{circulation:'public'});entry=[Math.floor(w/2),0];
  for(const side of [0,1]){const width=side?w-walk-passage:walk,x=side?walk+passage:0;let y=0,row=0;while(y<h){const remain=h-y,depth=remain>=10?ri(5,Math.min(8,remain-5)):remain;const roomName=program==='school'?(side&&row===0?'办公室':side&&row===1?'图书室':'教室'):(row===0?(side?'公共卫生间':'接待室'):width*depth>=24?'双人客房':'单人客房');const a=add(roomName,x,y,width,depth);link(hall,a,program==='school'?2:1);y+=depth;row++;}}
 }else if(program==='bath'){
  type='bath';name='公共浴室洗衣店';layout='更衣、洗浴与洗衣分区';const passage=corridorWidth(R,'public',h-6,options),front=3,main=add('更衣室',0,0,w,front),hall=add('公共过道',0,front,w,passage,{circulation:'public'}),split=Math.max(3,Math.floor(w*.6)),a=add('公共洗浴',0,front+passage,split,h-front-passage),b=add('洗衣烘干',split,front+passage,w-split,h-front-passage);link(main,hall,2);link(hall,a,2);link(hall,b,2);
 }else if(program==='housing'){
  name='独立家庭住宅';layout='起居前厅、生活分室与局部退让';unit(0,0,w,h);
 }else{
  const descriptions={fabrication:['factory','小型加工工坊',options.industry==='robotics'?'机器人装配':options.industry==='food'?'食品加工':'加工车间'],grocery:['grocery','食品杂货店','售货区'],diner:['diner','小餐馆','用餐区'],bakery:['bakery','食品加工与供应店','食品加工'],warehouse:['warehouse','沿街货栈','货物库房'],robot:['robot','机器人检修站','机器人维修工位'],security:['security','治安与消防站','值班室'],office:['office','行政办事处','办公室'],recreation:['recreation','社区活动馆','活动室'],commerce:['shop','街边商店','售货区'],workshop:['workshop','修造作坊','维修工位'],utility:['utility','空气与供水维护站','空气处理'],food:['diner','社区食堂','用餐区']},[t,n,main]=descriptions[program]||descriptions.commerce;
  type=t;name=n;special=['utility','security'].includes(program);layout='营业或作业空间、服务核心与后部支翼';
  const back=Math.min(5,Math.max(3,Math.floor(h*.3))),a=add(main,0,0,w,h-back),split=Math.max(3,Math.min(w-3,Math.floor(w*.6))),rear=variant%2&&back>=4?back-1:back;
  const b=add(['food','diner','bakery'].includes(program)?'厨房':program==='utility'?'水处理':program==='robot'?'零件库':program==='security'?'装备间':program==='recreation'?'阅览室':program==='office'?'会议室':program==='warehouse'?'收货间':program==='grocery'?'冷藏与备货':'后仓',0,h-back,split,back),c=add(program==='utility'?'控制室':['food','diner','bakery','grocery'].includes(program)?'食品库':program==='robot'?'检测室':program==='security'?'休息室':program==='office'?'档案室':'办公室',split,h-back,w-split,rear);link(a,b);link(a,c);
 }
 return{id,program,templateId:'fitted-'+program+'-'+variant,name,type,wallMode:'edge',rooms,links,entry,front:'north',exits,outdoors,households,layout,special,wholeBlock,operations:special?layout:null};
}
root.BubbleRoomLayouts={fitted,corridorWidth};if(typeof module!=='undefined')module.exports=root.BubbleRoomLayouts;
})(typeof window!=='undefined'?window:globalThis);
