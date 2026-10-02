# Scarlet Contract

当前运行入口是 Godot 角色与射击测试场。根目录 `Start Demo.cmd`、`Start Godot.cmd` 和 `Open Tactical Preview.cmd` 均可进入测试场；`Open Godot Editor.cmd` 用于打开工程。


本目录保留 Python 模拟逻辑，供规则对照与仍适用的底层检查使用。实际游戏开发与运行以 `godot/` 为准；当前尚未完成按最新美学搭建的正式战场。

## 当前设计

硬核俯视角战术射击采用多角色指挥、实时推进与自由战术暂停。美术采用方案 A：三维制作干净矢量画感底图，文字采用中文像素字体，干净场景直接进入 CRT，文字保留清晰独立合成，由其内部采样形成像素感。项目输出为 2560×1440，CRT 内部场景信号为独立的 960×540，物体与门按一米格组织，场景保持严格正交纯顶视、丰富光影与叙事性布局。具体要求见 [美学方向](../docs/art-direction.md)。

## 地下维护站美术小样

根目录 `Open Maintenance Preview.command`（macOS）或 `Open Maintenance Preview.cmd`（Windows）打开独立场景。macOS 支持 `GODOT_BIN`，或桌面、Applications 中的 Godot。原有启动器仍进入角色射击测试场。

WASD 移动，鼠标朝向，滚轮缩放，E 查看附近现场说明，O 开关附近门；V 开关 CRT，F 切换完全无滤镜原图并恢复之前状态，N 开关描边对照，方括号调整 CRT 强度，空格同时暂停角色、噪声和滚动干扰。CRT 包含信号采样、扫描线、RGB 栅格与通道分离、曲率、暗角、低强度噪声和滚动干扰；没有额外像素化层。

场景道具使用现成模型，统一色块与描边；卷帘门按原模型合理尺寸占三格。墙地、占格底板与门槛标记保留基础几何。

本场景用于布局、光影与画面处理验看，复用现有角色动作，未接入正式任务、物资、感知或射击结算。

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
