(function(root){
'use strict';
const round=n=>Math.round(n*100)/100;
function random(seed){let a=2166136261;for(const c of String(seed))a=Math.imul(a^c.charCodeAt(0),16777619);return()=>{a+=0x6D2B79F5;let t=Math.imul(a^a>>>15,1|a);t^=t+Math.imul(t^t>>>7,61|t);return((t^t>>>14)>>>0)/4294967296;};}
const catalog={
 station:{label:'中央车站',category:'civic',rooms:['共用站厅','候车大厅','站台','站务室','信号控制室','供电设备间']},
 lodging:{label:'短住旅舍',category:'housing',rooms:['客房','接待室','公共卫生间']},
 apartment:{label:'分户住宅',category:'housing',rooms:['起居室','卧室','卫生间']},
 dorm:{label:'工人宿舍',category:'housing',rooms:['宿舍','公共厨房','公共洗浴','洗衣房']},
 shop:{label:'前店后宅',category:'commerce',rooms:['店面','后仓','员工间']},
 grocery:{label:'食品杂货店',category:'commerce',rooms:['售货区','冷藏与备货','收货间','员工间']},
 diner:{label:'食堂与餐馆',category:'commerce',rooms:['用餐区','厨房','食品库','洗消间']},
 clinic:{label:'社区诊疗所',category:'civic',rooms:['候诊','诊室','药房','处置室','病房','卫生间']},
 school:{label:'社区学校',category:'civic',rooms:['教室','教室','办公室','图书室','卫生间']},
 bath:{label:'公共浴室洗衣店',category:'civic',rooms:['更衣室','公共洗浴','洗衣房','设备间']},
 recreation:{label:'娱乐与社区中心',category:'civic',rooms:['活动室','游戏厅','阅览室','办公室']},
 workshop:{label:'维修作坊',category:'industry',rooms:['维修工位','零件库','工具间','办公室']},
 factory:{label:'轻型加工厂',category:'industry',rooms:['加工车间','零件库','装配区','更衣室']},
 warehouse:{label:'仓储转运站',category:'industry',rooms:['货物库房','分拣区','收货间','办公室']},
 utility:{label:'环境与供电维护站',category:'utility',rooms:['配电间','空气处理','水处理','控制室','备件库']},
 recycling:{label:'回收清运站',category:'utility',rooms:['分拣区','回收暂存','维修工位','办公室']},
 security:{label:'治安与消防站',category:'civic',rooms:['值班室','装备间','办公室','休息室']},
 office:{label:'公司办事处',category:'civic',rooms:['接待室','办公室','档案室','会议室']},
 robot:{label:'机器人综合检修站',category:'industry',rooms:['维修工位','检测室','充电维护','零件库']}
};
Object.assign(catalog,{hospital:{label:'公司医院',category:'civic'},housing_complex:{label:'公司宿舍综合体',category:'housing'},production_complex:{label:'联合生产厂房',category:'industry'},logistics_complex:{label:'物流综合体',category:'industry'},robot_shop:{label:'私营机器人维修铺',category:'commerce'},robot_parts:{label:'机器人配件店',category:'commerce'},power_shop:{label:'电源检测与更换店',category:'commerce'},salvage:{label:'二手机体拆件行',category:'industry'},android_clinic:{label:'地下仿生人诊所',category:'civic'},bakery:{label:'食品加工与供应店',category:'commerce'}});
catalog.pharmacy={label:'社区药房',category:'commerce'};
catalog.robot={label:'机器人综合检修站',category:'industry'};
// Label, footprint in metres, visual family. These are inferred prototype contents.
const items={
 planter:['公园种植池',2,2,'plant'],
 bed:['单人床',.95,2,'bed'],doublebed:['双人床',1.6,2,'bed'],bunk:['双层床',1,2.1,'bed'],
 desk:['书桌',1.2,.65,'table'],chair:['椅子',.5,.5,'seat'],wardrobe:['衣柜',1.2,.6,'storage'],locker:['个人储物柜',.6,.55,'storage'],
 sofa:['沙发',1.8,.8,'seat'],table:['餐桌',1.2,.8,'table'],tv:['显像管电视柜',.9,.55,'screen'],phone:['翻盖手机',.12,.08,'small'],
 computer:['台式电脑工作台',1.3,.7,'screen'],shelf:['货架',1.4,.55,'storage'],counter:['柜台',1.5,.65,'table'],
 fridge:['冰箱',.7,.7,'machine'],stove:['灶台',.7,.65,'machine'],sink:['水槽',.7,.6,'water'],toilet:['坐便器',.65,.8,'water'],shower:['淋浴位',.9,.9,'water'],
 washer:['洗衣机',.7,.7,'machine'],bin:['垃圾桶',.45,.45,'small'],books:['书架',1.3,.35,'storage'],
 medbed:['诊疗床',.85,2,'bed'],medicine:['药品柜',1,.5,'storage'],monitor:['诊疗仪器',.65,.65,'screen'],
 workbench:['工作台',1.8,.8,'table'],tools:['工具柜',1.1,.55,'storage'],lathe:['机床',2.3,1.25,'machine'],cutter:['热能切割设备',1.7,1,'scifi'],
 robotarm:['装配机械臂',1.7,1.5,'scifi'],robotdock:['机器人维护位',1.3,1.2,'scifi'],synthbed:['仿生人检修台',1.1,2.3,'scifi'],
 crates:['货箱',1.1,1,'storage'],pallet:['货盘',1.2,1,'storage'],cart:['搬运小车',.7,1.2,'machine'],
 electric:['配电柜',1.3,.65,'machine'],pump:['循环泵',1.4,1,'water'],air:['空气处理机组',2.1,1.2,'machine'],tank:['储液罐',1.4,1.4,'water'],
 arcade:['街机',.75,.8,'screen'],fire:['消防装备柜',1.4,.6,'storage'],rack:['装备柜',1.3,.6,'storage'],
 bicycle:['自行车',.55,1.8,'bike'],motorcycle:['摩托车',.8,2,'bike'],bench:['长椅',1.7,.55,'seat'],lamp:['路灯',.3,.3,'small'],
 vending:['自动售货机',.85,.8,'screen'],hydrant:['消防栓',.4,.4,'small'],bollard:['隔车柱',.3,.3,'small'],sign:['站牌',.35,.35,'small'],
 tram:['有轨电车',2.4,14,'tram'],car:['公务汽车',1.8,4.4,'car'],parcel:['纸箱与包裹',.6,.5,'storage']
};
const furnishings={
 '起居室':['sofa','table','tv','chair','books'], '卧室':['doublebed','wardrobe','desk','chair'], '卫生间':['toilet','shower','sink'],
 '宿舍':['bunk','bunk','locker','locker','table'], '公共厨房':['stove','stove','sink','fridge','table','shelf'], '公共洗浴':['shower','shower','sink','toilet'], '洗衣房':['washer','washer','sink','shelf'],
 '店面':['counter','shelf','shelf','shelf','computer'], '后仓':['shelf','crates','cart'], '员工间':['table','locker','sink'],
 '售货区':['shelf','shelf','shelf','fridge','counter'], '冷藏与备货':['fridge','fridge','shelf'], '收货间':['pallet','cart','crates'],
 '用餐区':['table','chair','table','chair','counter'], '厨房':['stove','stove','sink','fridge','workbench'], '食品库':['shelf','fridge','crates'], '洗消间':['sink','sink','shelf'],
 '候诊':['bench','bench','counter'], '诊室':['desk','chair','medbed','monitor'], '药房':['medicine','medicine','counter'], '处置室':['medbed','tools','sink','monitor'], '病房':['medbed','medbed','locker'],
 '教室':['desk','desk','desk','desk','books'], '办公室':['computer','chair','books','shelf'], '图书室':['books','books','table','chair'],
 '更衣室':['locker','locker','bench'], '设备间':['electric','pump','tools'], '活动室':['table','chair','sofa','tv'], '游戏厅':['arcade','arcade','arcade','vending'], '阅览室':['books','books','desk','chair'],
 '维修工位':['workbench','tools','cart'], '零件库':['shelf','shelf','crates'], '工具间':['tools','tools','shelf'], '加工车间':['lathe','cutter','workbench'], '装配区':['robotarm','workbench','crates'],
 '货物库房':['pallet','pallet','crates','shelf'], '分拣区':['workbench','cart','crates'], '配电间':['electric','electric','tools'], '空气处理':['air','air','electric'], '水处理':['pump','tank','sink'], '控制室':['computer','computer','electric'], '备件库':['shelf','tools','crates'],
 '回收暂存':['crates','crates','bin','cart'], '值班室':['computer','desk','chair'], '装备间':['rack','fire','tools'], '休息室':['sofa','tv','table'], '接待室':['counter','bench'], '档案室':['shelf','shelf','computer'], '会议室':['table','chair','chair','computer'], '检测室':['workbench','monitor','computer'], '充电维护':['robotdock','robotdock','electric']
};
Object.assign(furnishings,{
 '玄关':['locker','bench'],'起居餐室':['sofa','table','chair','tv'],'餐厨':['table','chair','stove','sink','fridge'],
 '前室工作间':['desk','computer','tools'],'个人储藏':['locker','shelf'],'储藏间':['shelf','crates'],'共用起居':['table','sofa','tv'],
 '单人寝室':['bed','locker','desk'],'双人寝室':['bed','bed','locker'],'洗衣烘干':['washer','washer','shelf','sink'],'淋浴间':['shower','shower','sink'],'公共卫生间':['toilet','toilet','sink'],
 '备餐间':['workbench','stove','shelf'],'冷藏库':['fridge','fridge','shelf'],'干货库':['shelf','crates'],'垃圾暂存':['bin','cart'],'账房':['desk','computer','shelf'],
 '机器人拆解':['workbench','tools','robotdock'],'台架检测':['workbench','computer','tools'],'老化测试':['robotdock','electric','computer'],'废件暂存':['crates','bin'],
 '消毒间':['sink','medicine','shelf'],'清洁耗材':['shelf','sink'],'分诊':['counter','computer'],'电脑营业区':['computer','computer','chair'],'打印装订':['workbench','computer','shelf'],'维修备品':['tools','shelf']
});
// Capacities are planning units for this prototype, not real-world service standards.
const programs={
 housing:{label:'家庭住宅',key:'family',area:150,minW:6,minH:6,actors:['government','resident']},
 dorm:{label:'集体宿舍',key:'workers',area:600,minW:18,minH:12,actors:['government','resident']},
 lodging:{label:'短住旅舍',key:'guests',area:260,minW:12,minH:12,actors:['government','resident']},
 production:{label:'加工制造厂',key:'industry',area:1200,minW:18,minH:18,actors:['government']},
 fabrication:{label:'小型加工工坊',key:'industry',area:220,minW:8,minH:10,actors:['government','resident']},
 workshop:{label:'综合维修作坊',key:'repair',area:150,minW:6,minH:8,actors:['government','resident']},
 robot:{label:'机器人检修站',key:'repair',area:220,minW:10,minH:10,actors:['government','resident']},
 transport:{label:'物流分拣中心',key:'logistics',area:1000,minW:18,minH:18,actors:['government']},
 warehouse:{label:'沿街货栈',key:'logistics',area:220,minW:8,minH:8,actors:['government','resident']},
 grocery:{label:'食品杂货店',key:'retail',area:130,minW:6,minH:8,actors:['government','resident']},
 food:{label:'公共食堂',key:'meals',area:300,minW:10,minH:10,actors:['government','resident']},
 diner:{label:'小餐馆',key:'meals',area:110,minW:6,minH:8,actors:['government','resident']},
 bakery:{label:'食品加工与供应店',key:'retail',area:180,minW:8,minH:8,actors:['government','resident']},
 clinic:{label:'社区诊所',key:'health',area:180,minW:12,minH:12,actors:['government','resident']},
 hospital:{label:'综合医院',key:'health',area:1000,minW:18,minH:18,actors:['government']},
 school:{label:'社区学校',key:'education',area:360,minW:14,minH:14,actors:['government']},
 bath:{label:'公共浴室洗衣店',key:'hygiene',area:180,minW:12,minH:10,actors:['government','resident']},
 utility:{label:'空气与供水维护站',key:'utilities',area:240,minW:10,minH:10,actors:['government']},
 security:{label:'治安与消防站',key:'safety',area:180,minW:12,minH:10,actors:['government']},
 office:{label:'行政与办事处',key:'administration',area:180,minW:12,minH:10,actors:['government']},
 recreation:{label:'社区活动馆',key:'leisure',area:220,minW:12,minH:10,actors:['government','resident']}
};
const demandLabels={family:'家庭居住',workers:'工人居住',guests:'短住床位',industry:'生产岗位',repair:'维修岗位',logistics:'货物处理',retail:'日常供应',meals:'餐食供应',health:'医疗服务',education:'教育席位',hygiene:'共用洗浴',utilities:'环境供给',safety:'治安消防',administration:'行政服务',leisure:'休闲活动'};
function planningCapacity(p,o){
 const area=p.rooms.reduce((n,r)=>n+r.w*r.h,0),program=p.program||({apartment:'housing',housing_complex:'dorm',factory:'production',production_complex:'production',logistics_complex:'transport',robot_shop:'robot',robot_parts:'robot',salvage:'workshop',power_shop:'robot',pharmacy:'clinic',android_clinic:'clinic',shop:'grocery'}[p.type]||p.type),capacity={};
 const key=programs[program]?.key;if(!key)return capacity;
 const beds=p.rooms.filter(r=>/卧室|寝室|宿舍|客房|起居卧室|出租单间/.test(r.name)).reduce((n,r)=>n+Math.max(1,Math.floor(r.w*r.h/(program==='dorm'?10:12)/o.livingStandard)),0);
 const rates={industry:1/16,repair:1/14,logistics:1.1,retail:2.5,meals:1.2,health:program==='hospital'?4:2,education:1/5,hygiene:1.2,utilities:3,safety:4,administration:4,leisure:1.5};
 capacity[key]=Math.max(1,Math.round(['family','workers','guests'].includes(key)?beds||area/(program==='dorm'?16:24)/o.livingStandard:key==='education'?p.rooms.filter(r=>r.name==='教室').reduce((n,r)=>n+r.w*r.h/3,0):area*rates[key]));
 if(program==='dorm')capacity.hygiene=p.rooms.filter(r=>/公共卫生|淋浴|公共洗浴/.test(r.name)).reduce((n,r)=>n+r.w*r.h*2,0);
 return capacity;
}
function populationNeeds(o,year){
 const population=Math.max(1,Math.round(o.initialPopulation*Math.pow(1+o.populationGrowth/100,year))),families=Math.round(population*o.familyShare),guests=Math.round(population*o.transientShare+o.passengerFlow*.08),workers=Math.max(0,population-families-Math.round(population*o.transientShare));
 const industryFactor={mixed:1,production:1.4,logistics:.75,residential:.5,administrative:.45}[o.role],jobs=population*o.employmentRate*industryFactor,repairShare=o.industry==='robotics'?.4:.22;
 return {population,targets:{family:families,workers,guests,industry:Math.round(jobs*(1-repairShare)),repair:Math.round(jobs*repairShare),logistics:Math.round(o.freightFlow*(o.role==='logistics'?1.6:1)),retail:Math.round(population+o.passengerFlow*.25),meals:Math.round(workers*.7+guests+o.passengerFlow*.25),health:Math.round(population*o.serviceLevel),education:Math.round(families*.22*o.serviceLevel),hygiene:Math.round(workers*(.2+o.sharedHousing)*o.serviceLevel),utilities:population,safety:Math.round(population*o.serviceLevel),administration:Math.round(population*(o.role==='administrative'?2.5:.55)),leisure:Math.round(population*.4*o.serviceLevel)}};
}

function roomMinimum(room){
 if(room.circulation||/过道|通道|通廊|支廊/.test(room.name))return 2;
 if(/卫生|洗手|淋浴|储藏|杂物|储物|个人储藏|清洁|耗材|食品库|工具间|备品|备件|零件库|冷藏|干货|后仓/.test(room.name))return 1;
 return 3;
}
function inside(poly,x,y){let c=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++){const a=poly[i],b=poly[j];if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])c=!c;}return c;}

// Narrow exterior openings are selected by use and role, without consuming the city's random stream.
function exteriorMinimum(p,role='主入口'){
 const area=p.rooms.reduce((n,r)=>n+r.w*r.h,0),collective=(p.households||1)>1||p.type==='dorm';
 if(p.type==='station'||collective||/装卸|收货|分流|共用通廊/.test(role))return 2;
 if(role==='主入口')return !p.special&&area<=180&&((p.program==='housing'&&(p.households||1)===1)||p.program==='workshop'||p.program==='fabrication')?1:2;
 return /侧后出口|后勤出入口|副门/.test(role)?1:2;
}
function exteriorWidth(p,role='主入口',token='primary'){return exteriorMinimum(p,role)===1&&random(p.id+'-'+role+'-'+token)()<.55?1:2;}
root.BubbleContent={exteriorMinimum,exteriorWidth,catalog,items,furnishings,random,inside,roomMinimum,programs,demandLabels,planningCapacity,populationNeeds};
if(typeof module!=='undefined')module.exports=root.BubbleContent;
})(typeof window!=='undefined'?window:globalThis);
