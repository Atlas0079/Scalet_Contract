(function(root){'use strict';
const room=(name,x,y,w,h,extra={})=>({name,x,y,w,h,...extra});
const plans=[
 {id:'compact-home',name:'紧凑单人户',type:'apartment',entry:[2, 0],rooms:[room("起居厨房",0,0,6,3),room("卧室",0,3,3,4),room("卫生间",3,3,2,2)]},
 {id:'family-home',name:'家庭两居户',type:'apartment',entry:[5, 0],rooms:[room("起居厨房",0,0,10,4),room("卧室",0,4,4,4),room("卧室",4,4,5,4),room("卫生间",10,0,2,3)]},
 {id:'long-home',name:'窄面深宅',type:'apartment',entry:[3, 0],rooms:[room("起居室",0,0,6,4),room("厨房",0,4,3,3),room("卫生间",3,4,2,3),room("卧室",0,7,6,4)]},
 {id:'yard-home',name:'三面围小院住宅',type:'apartment',entry:[2, 0],rooms:[room("起居室",0,0,4,4),room("过厅",0,4,4,4),room("厨房",0,8,12,3),room("卧室",8,4,4,4),room("卫生间",8,1,2,3)]},
 {id:'wide-home',name:'横向连间住宅',type:'apartment',entry:[3, 0],rooms:[room("起居厨房",0,0,7,5),room("卧室",7,0,5,5),room("卫生间",7,5,2,3)]},
 {id:'side-entry-home',name:'侧门小宅',type:'apartment',entry:[0, 2],front:'west',rooms:[room("起居厨房",0,0,7,4),room("卧室",0,4,4,4),room("卫生间",4,4,2,3)]},
 {id:'shop-home',name:'前店后宅',type:'shop',entry:[3, 0],rooms:[room("店面",0,0,8,5),room("起居厨房",0,5,4,4),room("卧室",0,9,4,4),room("卫生间",4,5,2,3)]},
 {id:'corner-shop',name:'转角杂货铺',type:'grocery',entry:[4, 0],rooms:[room("售货区",0,0,9,6),room("后仓",0,6,5,4),room("员工间",5,6,3,4),room("卫生间",9,0,2,2)]},
 {id:'lane-diner',name:'深巷小食堂',type:'diner',entry:[4, 0],rooms:[room("用餐区",0,0,8,6),room("厨房",0,6,5,4),room("食品库",5,6,2,4),room("卫生间",8,0,2,2)]},
 {id:'small-repair',name:'带后间的维修铺',type:'workshop',entry:[4, 0],rooms:[room("维修工位",0,0,9,7),room("零件库",0,7,4,4),room("工具间",4,7,4,4)]},
 {id:'annex-workshop',name:'折角作坊',type:'workshop',entry:[5, 0],rooms:[room("加工车间",0,0,11,8),room("工具间",11,0,4,4),room("办公室",11,4,4,3),room("零件库",0,8,5,4)]},
 {id:'small-store',name:'巷内货栈',type:'warehouse',entry:[5, 0],rooms:[room("货物库房",0,0,10,9),room("收货间",10,0,5,5),room("办公室",10,5,5,3)]},
 {id:'shared-dorm',name:'共用设施宿舍',type:'dorm',entry:[6, 0],rooms:[room("公共过道",5,0,2,15),room("宿舍",0,0,5,4),room("宿舍",0,4,5,4),room("公共厨房",0,8,5,5),room("宿舍",7,0,5,4),room("宿舍",7,4,5,4),room("公共洗浴",7,8,3,3),room("洗衣房",7,11,3,2)]},
 {id:'clinic',name:'社区诊疗院',type:'clinic',special:true,entry:[5,0],rooms:[room('候诊',1,1,10,4),room('公共过道',1,6,10,2),room('诊室',1,9,4,4),room('处置室',6,9,5,4),room('药房',12,1,4,4),room('卫生间',12,6,2,3),room('备件库',12,10,4,3)]},
 {id:'school',name:'三教室社区学校',type:'school',special:true,entry:[0,9],front:'west',rooms:[room('公共过道',1,8,29,2),room('教室',1,1,8,6),room('教室',10,1,8,6),room('教室',19,1,11,6),room('办公室',1,11,6,5),room('图书室',8,11,9,5),room('公共洗浴',18,11,3,3),room('设备间',22,11,8,5)]},
 {id:'bathhouse',name:'澡堂与洗衣院',type:'bath',special:true,entry:[4,0],rooms:[room('接待室',1,1,6,3),room('更衣室',8,1,8,3),room('公共过道',1,5,15,2),room('公共洗浴',1,8,6,6),room('卫生间',8,8,3,3),room('洗衣房',12,8,4,6)]},
 {id:'tram-depot',name:'旧电车维修站',type:'depot',special:true,entry:[11,0],rooms:[room('电车检修库',1,1,22,10),room('维修工位',1,12,7,5),room('零件库',9,12,7,5),room('控制室',17,12,6,5)]},
 {id:'machine-factory',name:'机加工大车间',type:'factory',special:true,entry:[8,0],rooms:[room('加工车间',1,1,14,13),room('办公室',16,1,5,4),room('工具间',16,6,5,4),room('更衣室',16,11,5,3)]},
 {id:'covered-market',name:'旧市集棚厅',type:'market',special:true,entry:[7,0],rooms:[room('市场大厅',1,1,14,10),room('食品库',16,1,4,5),room('收货间',16,7,4,4)]},
 {id:'air-water',name:'空气与供水维护站',type:'utility',special:true,entry:[5,0],rooms:[room('控制室',1,1,9,4),room('空气处理',1,6,9,8),room('水处理',11,6,8,8),room('配电间',11,1,8,4)]},
 {id:'robot-service',name:'机器人综合检修站',type:'robot',special:true,entry:[6,0],rooms:[room('维修工位',1,1,12,8),room('检测室',14,1,6,4),room('充电维护',14,6,6,3),room('零件库',1,10,7,4),room('办公室',9,10,4,4)]},
 {id:'community-club',name:'街机与社区活动馆',type:'recreation',special:true,entry:[6,0],rooms:[room('活动室',1,1,11,6),room('游戏厅',1,8,7,6),room('阅览室',9,8,8,6),room('卫生间',13,1,2,3)]},
 {id:'security-post',name:'社区治安消防站',type:'security',special:true,entry:[4,0],rooms:[room('值班室',1,1,7,4),room('装备间',9,1,8,7),room('休息室',1,6,7,4),room('办公室',9,9,8,4)]},
 {id:'office-court',name:'公司办事长屋',type:'office',special:true,entry:[4,0],rooms:[room('接待室',1,1,7,4),room('办公室',9,1,6,4),room('会议室',1,6,7,5),room('档案室',9,6,6,5)]},
 {id:'recycling-yard',name:'回收清运站',type:'recycling',special:true,entry:[6,0],rooms:[room('分拣区',1,1,11,8),room('回收暂存',13,1,6,8),room('维修工位',1,10,6,4),room('办公室',8,10,4,4)]}
];
const links={
 'compact-home':[[0,1],[0,2]],'family-home':[[0,1],[0,2],[0,3]],'long-home':[[0,1],[0,2],[1,3]],
 'yard-home':[[0,1],[1,2],[2,3],[3,4]],'wide-home':[[0,1],[1,2]],'side-entry-home':[[0,1],[0,2]],
 'shop-home':[[0,1],[1,2],[1,3]],'corner-shop':[[0,1],[0,2],[0,3]],'lane-diner':[[0,1],[1,2],[0,3]],
 'small-repair':[[0,1],[0,2]],'annex-workshop':[[0,1],[0,2],[0,3]],'small-store':[[0,1],[0,2]],
 'shared-dorm':[[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[0,7]],
 'clinic':[[0,1],[1,2],[1,3],[0,4],[1,5],[3,6]],
 'school':[[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[0,7]],
 'bathhouse':[[0,2],[1,2],[2,3],[2,4],[2,5]],
 'tram-depot':[[0,1],[0,2],[0,3]],'machine-factory':[[0,1],[0,2],[0,3]],'covered-market':[[0,1],[0,2]],
 'air-water':[[0,1],[0,3],[1,2],[2,3]],'robot-service':[[0,1],[0,2],[0,3],[0,4]],
 'community-club':[[0,1],[0,2],[0,3]],'security-post':[[0,1],[0,2],[1,3]],
 'office-court':[[0,1],[0,2],[1,3]],'recycling-yard':[[0,1],[0,2],[0,3]]
};
for(const p of plans){p.links=links[p.id];p.wallMode=p.special?'solid':'edge';}
root.BubbleBlueprints=plans;if(typeof module!=='undefined')module.exports=plans;
})(typeof window!=='undefined'?window:globalThis);
