# Scarlet Contract

当前运行入口是 Godot 角色与射击测试场。根目录 `Start Demo.cmd`、`Start Godot.cmd` 和 `Open Tactical Preview.cmd` 均可进入测试场；`Open Godot Editor.cmd` 用于打开工程。

`Open Machinery Room.cmd` 打开独立的设备与材质小样：实际压缩机模型、混凝土地面、墙体和现有角色，使用 Forward+ 渲染与严格正交顶视，不加终端滤镜。WASD 移动，鼠标瞄准、左键射击，R 换弹，空格暂停；滚轮缩放，中键平移，Home 复位，Tab 隐藏界面。它用于验证材质与风格，不是完整战术关卡。

本目录保留 Python 模拟逻辑，供规则对照与仍适用的底层检查使用。实际游戏开发与运行以 `godot/` 为准；当前尚未完成按最新美学搭建的正式战场。

## 当前设计

游戏目标是硬核俯视角战术射击，采用多角色指挥、实时推进与自由战术暂停。美学方向是克制的工业设计、保留颜色与材质的场景、微妙的三渲二角色，以及复古终端画面质感和两千年代复古科幻 UI。

战斗画面采用严格的正交纯顶视，相机垂直向下，不露出物体侧面。场景可用静态二维美术搭建，也可借助三维模型制作，按最终画面与制作便利性选择。具体材质、画面尺度与滤镜参数以小样验证后确定。

## 文档入口

- [美学方向](../docs/art-direction.md)：场景、角色、滤镜和 UI 的统一依据。
- [Godot 配置说明](../godot/LOCAL_CONFIGURATION.md)：当前入口、配置、测试场操作和实现范围。
- [角色、技能与能力架构](../godot/LOCAL_CHARACTER_ARCHITECTURE.md)：现行角色与能力契约。
- [当前射击机制](../godot/LOCAL_SHOOTING_FACTORS.md)：射击链路与数值。
- [战术玩法与表现设计](docs/demo_design.md)：战术规则与功能验证关卡。
- [指挥与 AI](docs/command_and_ai.md)：指挥权、队列、挂起、感知与移动规则。
- [交互与现场转移](docs/interaction_and_loot.md)：搜索、预约、分配和现场拿取。
- [撤离循环与体验目标](docs/player_experience_review.md)：已确认循环及待定体验细则。
- [项目交接](docs/project_handoff.md)：当前状态与职责入口。

## 验证资料

[验证记录](docs/validation.md)描述其标注版本的实际检查结果，不能作为当前测试场或新美学已经完成的证明。Godot 迁移阶段的测量结果见 [迁移验证说明](../godot/LOCAL_MIGRATION.md)。

界面专用测试源码保存在本地 `.art-preview-local/retired-greyport-tests-20260930`，不用于当前测试场入口。新增辅助测试、脚本与验证文档的提交范围遵循用户级 `AGENTS.md`。
