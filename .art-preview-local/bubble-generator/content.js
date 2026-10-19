(function(root){
'use strict';
const round=n=>Math.round(n*100)/100;
function random(seed){let a=2166136261;for(const c of String(seed))a=Math.imul(a^c.charCodeAt(0),16777619);return()=>{a+=0x6D2B79F5;let t=Math.imul(a^a>>>15,1|a);t^=t+Math.imul(t^t>>>7,61|t);return((t^t>>>14)>>>0)/4294967296;};}
const catalog={
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
 robot:{label:'机器人与仿生人服务站',category:'industry',rooms:['维修工位','检测室','充电维护','零件库']}
};
// Label, footprint in metres, visual family. These are inferred prototype contents.
const items={
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
 '起居室':['sofa','table','tv','fridge','stove','sink','bin'], '卧室':['doublebed','wardrobe','desk','chair'], '卫生间':['toilet','shower','sink'],
 '宿舍':['bunk','bunk','locker','locker','table'], '公共厨房':['stove','stove','sink','fridge','table','shelf'], '公共洗浴':['shower','shower','sink','toilet'], '洗衣房':['washer','washer','sink','shelf'],
 '店面':['counter','shelf','shelf','shelf','computer'], '后仓':['shelf','crates','cart'], '员工间':['table','locker','sink'],
 '售货区':['shelf','shelf','shelf','fridge','counter'], '冷藏与备货':['fridge','fridge','shelf'], '收货间':['pallet','cart','crates'],
 '用餐区':['table','chair','table','chair','counter'], '厨房':['stove','stove','sink','fridge','workbench'], '食品库':['shelf','fridge','crates'], '洗消间':['sink','sink','shelf'],
 '候诊':['bench','bench','counter'], '诊室':['desk','chair','medbed','monitor'], '药房':['medicine','medicine','counter'], '处置室':['medbed','tools','sink','monitor'], '病房':['medbed','medbed','locker'],
 '教室':['desk','desk','desk','desk','books'], '办公室':['computer','chair','books','shelf'], '图书室':['books','books','table','chair'],
 '更衣室':['locker','locker','bench'], '设备间':['electric','pump','tools'], '活动室':['table','chair','sofa','tv'], '游戏厅':['arcade','arcade','arcade','vending'], '阅览室':['books','books','desk','chair'],
 '维修工位':['workbench','tools','cart'], '零件库':['shelf','shelf','crates'], '工具间':['tools','tools','shelf'], '加工车间':['lathe','cutter','workbench'], '装配区':['robotarm','workbench','crates'],
 '货物库房':['pallet','pallet','crates','shelf'], '分拣区':['workbench','cart','crates'], '配电间':['electric','electric','tools'], '空气处理':['air','air','electric'], '水处理':['pump','tank','sink'], '控制室':['computer','computer','electric'], '备件库':['shelf','tools','crates'],
 '回收暂存':['crates','crates','bin','cart'], '值班室':['computer','desk','chair'], '装备间':['rack','fire','tools'], '休息室':['sofa','tv','table'], '接待室':['counter','bench'], '档案室':['shelf','shelf','computer'], '会议室':['table','chair','chair','computer'], '检测室':['synthbed','monitor','computer'], '充电维护':['robotdock','robotdock','electric']
};
function inside(poly,x,y){let c=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++){const a=poly[i],b=poly[j];if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])c=!c;}return c;}

root.BubbleContent={catalog,items,furnishings,random,inside};
if(typeof module!=='undefined')module.exports=root.BubbleContent;
})(typeof window!=='undefined'?window:globalThis);
