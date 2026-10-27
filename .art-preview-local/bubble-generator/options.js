(function(root){'use strict';
const fields=[
 ['人口与居住','initialPopulation','初始常住人口',320,40,5000,10,'人'],['人口与居住','populationGrowth','人口年增长率',1.5,-2,8,.1,'%'],['人口与居住','familyShare','家庭人口比例',.5,0,1,.05,''],['人口与居住','transientShare','流动人口比例',.1,0,1,.05,''],['人口与居住','livingStandard','居住宽裕程度',1,.7,1.6,.05,'倍'],
 ['产业与交通','employmentRate','就业需求比例',.6,.1,.9,.05,''],['产业与交通','passengerFlow','日均客流需求',120,0,2000,20,'人次'],['产业与交通','freightFlow','日均货运需求',100,0,2000,20,'单位'],
 ['政府开发','governmentInterval','规划机会间隔',8,2,24,1,'年'],['政府开发','governmentJitter','间隔随机浮动',2,0,6,1,'年'],['政府开发','projectsPerPeriod','每期规划项目上限',1,0,3,1,'个'],['政府开发','renewalBias','旧区改造倾向',.45,0,1,.05,''],['政府开发','executionStrength','政府执行力度',.65,0,1,.05,''],['政府开发','resettlementSupport','安置投入',.5,0,1,.05,''],
 ['社会与服务','resistanceLevel','居民组织与拆迁阻力',.6,0,1,.05,''],['社会与服务','serviceLevel','公共服务配置',1,.4,2,.1,'倍'],
 ['建筑','privateCorridorMax','户内过道最大宽',3,2,4,1,'米'],['建筑','apartmentCorridorMax','公寓主廊最大宽',4,2,6,1,'米'],['建筑','publicCorridorMax','宿舍与公共主廊最大宽',5,3,7,1,'米'],
 ['基础','years','发展年数',32,0,80,1,'年'],['施工与改建','growthRate','居民施工速度',1,.25,3,.05,'倍'],
 ['政府开发','publicInvestment','公共投入',1,.25,3,.05,'倍'],['社会与服务','selfActivity','自建活跃度',1,0,3,.05,'倍'],
 ['地质','caveDensity','天然空腔发育程度',.7,.1,1,.05,''],['地质','tunnelWidth','天然主洞道宽',13,6,22,1,'米'],['地质','chamberRatio','弱层扩张程度',.4,0,1,.05,''],['地质','hardRock','保留硬岩强度',.12,0,.35,.01,''],['地质','excavationCost','人工开凿成本',1,.4,3,.1,'倍'],
 ['建筑','sharedHousing','共用生活设施倾向',.3,0,.8,.05,''],['建筑','homeMin','单户建筑最小面积',24,18,160,5,'㎡'],['建筑','homeMax','单户建筑最大面积',240,80,400,10,'㎡'],['建筑','groupMin','住宅组团最小面积',180,100,800,10,'㎡'],['建筑','groupMax','住宅组团最大面积',1600,300,2400,50,'㎡'],['建筑','households','住宅组团户数',8,3,20,1,'户'],['建筑','smallShare','小型住宅倾向',.55,0,.8,.02,''],['建筑','largeShare','大型住宅倾向',.18,0,.6,.02,''],['建筑','factoryScale','工厂体量',1,.65,1.5,.05,'倍'],
 ['街道','plannedBlocks','初期规划街坊',4,2,6,1,'块'],['街道','residentInfill','居民沿街填充倾向',.65,.25,1,.05,''],['街道','mainWidth','主街宽度',8,6,8,1,'米'],['街道','streetMin','规划街道最小宽',4,3,7,1,'米'],['街道','streetMax','规划街道最大宽',6,3,8,1,'米'],['街道','alleyMin','自建巷道最小宽',2,2,6,1,'米'],['街道','alleyMax','自建巷道最大宽',3,2,8,1,'米'],['街道','blockScale','规划街坊尺度',54,24,90,2,'米'],['街道','alleyLength','自建扩挖距离',32,6,60,1,'米'],['街道','branchChance','自建巷道折行倾向',.6,0,.8,.05,''],
 ['电车','railCoverage','泡内电车覆盖',.65,0,1,.05,''],['电车','stopSpacing','站间距',180,80,350,10,'米'],['电车','minRailLength','泡内线路最短长度',260,120,500,10,'米'],['电车','turnRadius','最小转弯半径',24,12,50,1,'米'],
 ['施工与改建','alterationShare','居民改建倾向',.4,0,.8,.05,''],
 ['公共项目','parkCount','规划公园数量',1,0,3,1,'处'],['公共项目','plazaCount','路口广场数量',1,0,4,1,'处'],
 ['室外用地','courtMax','共用院面积上限',96,0,240,4,'㎡'],['室外用地','junctionMax','车站集散面积',48,0,96,4,'㎡']
];
const schema=fields.map(([group,key,label,value,min,max,step,unit])=>({group,key,label,value,min,max,step,unit}));
schema.unshift({group:'基础',key:'role',label:'泡的主要职能',value:'mixed',choices:{mixed:'综合生活与生产',production:'生产为主',logistics:'物流为主',residential:'居住为主',administrative:'行政服务为主'}},{group:'产业与交通',key:'industry',label:'主导产业',value:'machining',choices:{machining:'机械加工',robotics:'机器人制造与检修',food:'食品加工',logistics:'仓储与转运'}});
const cityGroups=['基础','人口与居住','产业与交通','政府开发','社会与服务','公共项目'];
for(const field of schema){field.level=cityGroups.includes(field.group)?'city':'advanced';if(['familyShare','transientShare','employmentRate'].includes(field.key)){field.displayScale=100;field.displayUnit='%';}}
const defaults=Object.fromEntries(schema.map(f=>[f.key,f.value]));
defaults.exits=[{bearing:270,offset:-25,year:0},{bearing:90,offset:35,year:0}];defaults.facilityRules=[];
function normalize(input={}){
 if(typeof input!=='object'||input===null||Array.isArray(input))throw Error('生成参数需要为对象');const known=new Set([...schema.map(f=>f.key),'exits','facilityRules']);for(const key of Object.keys(input))if(!known.has(key))throw Error('未知参数 '+key+'，请使用当前版本的参数结构');const o={};
 for(const f of schema){const value=input[f.key]??f.value;if(f.choices){if(!Object.hasOwn(f.choices,value))throw Error(f.label+'选项无效');o[f.key]=value;continue;}const v=Number(value);if(!Number.isFinite(v)||v<f.min||v>f.max)throw Error(f.label+'需在 '+f.min+'–'+f.max+' 之间');o[f.key]=f.step===1?Math.round(v):v;}
 for(const[a,b]of [['homeMin','homeMax'],['groupMin','groupMax'],['streetMin','streetMax'],['alleyMin','alleyMax']])if(o[a]>o[b])throw Error('最小值不能大于最大值：'+schema.find(f=>f.key===a).label);
 if(o.familyShare+o.transientShare>1.000001)throw Error('家庭和流动人口比例之和不能超过 100%');if(o.governmentJitter>=o.governmentInterval)throw Error('规划间隔浮动必须小于间隔年数');if(o.smallShare+o.largeShare>.9)throw Error('小型与大型比例之和不能超过 0.9');
 const content=typeof module!=='undefined'?require('./content.js'):root.BubbleContent;
 o.facilityRules=(input.facilityRules??defaults.facilityRules).map(rule=>{if(!content.programs[rule.program]||!['required','forbidden'].includes(rule.mode))throw Error('指定设施的用途或模式无效');const count=Number(rule.count??1);if(!Number.isInteger(count)||count<1||count>8)throw Error('必建设施数量需在 1–8 之间');return{program:rule.program,mode:rule.mode,count};});
 if(new Set(o.facilityRules.map(r=>r.program)).size!==o.facilityRules.length)throw Error('同一种用途只能指定一条规则');
 o.exits=(input.exits??defaults.exits).map((e,i)=>{const v={bearing:Number(e.bearing),offset:Number(e.offset),year:Number(e.year)};if(!Number.isFinite(v.bearing)||v.bearing<0||v.bearing>=360||!Number.isFinite(v.offset)||Math.abs(v.offset)>180||!Number.isInteger(v.year)||v.year<0||v.year>80)throw Error('铁路出口 '+(i+1)+' 参数无效');return v;});if(o.exits.length>8)throw Error('最多支持8个铁路出口');return o;
}
root.BubbleOptions={schema,defaults,normalize};if(typeof module!=='undefined')module.exports=root.BubbleOptions;
})(typeof window!=='undefined'?window:globalThis);
