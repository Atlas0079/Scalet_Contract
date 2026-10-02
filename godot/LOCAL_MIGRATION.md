# Godot 运行说明与迁移验证

当前入口进入角色与射击测试场，运行状态以 [配置说明](LOCAL_CONFIGURATION.md)为准。场景、角色、滤镜与 UI 的设计统一见 [美学方向](../docs/art-direction.md)。下面的迁移测量对应其注明日期的实际运行，不表示当前正式战场或新美学已经完成。

验证日期：2026-09-28。使用本机 Godot `4.7.1.stable.official.a13da4feb`。

## 启动

- 根目录 `Start Demo.cmd` / `Start Godot.cmd`：运行新的 Godot 项目。首次运行会导入资源。
- `Open Godot Editor.cmd`：在 Godot 编辑器中打开工程。
- `godot/project.godot`：可直接从 Godot 项目管理器导入。
- 引擎实际位于 `C:\MyResearch\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe`；用户提供的上一级路径是文件夹。启动器支持该相邻目录，也支持环境变量 `GODOT_BIN` 指定可执行文件。

## 迁移范围

运行时使用 GDScript。当前主场景为 `presentation/tactical/tactical.tscn`，以角色、动作、能力与射击验证为中心。

- 模拟层位于 `simulation/`，对应原来的世界、地图、角色、移动、战斗、感知、命令、房间任务及物资模块。
- `data/greyport.json` 存放任务与关卡数据，`data/catalog.json` 存放基础物品及物资定义。武器、弹药、配件、角色、身体、表现、单位、技能与属性来源分别存放在 `weapons.json`、`ammunition.json`、`attachments.json`、`characters.json`、`bodies.json`、`presentation.json`、`units.json`、`skills.json` 与 `attribute_sources.json`，由 `simulation/data.gd` 加载；武器对应的物品与物资条目、弹药物资条目由所属定义派生。这些文件是原生运行数据，不是运行时转换层。
- 角色与测试场表现位于 `presentation/tactical/`，共享能力说明位于 `presentation/interface.gd`。
- 战斗模拟逻辑保留，完整战场与正式界面的接入范围以配置说明为准。

## 验证

- 原版数据对照：2,794 项通过。覆盖 1,728 个格子的通行及邻接、984 条不同高度/类型的射线、80 条路径成本及初始视野/门状态。
- 原生模拟回归：118 项通过，覆盖编排、站位、同步挂起/恢复、微操优先、物资预约/改派/到场转移、武器身份和弹匣保留、伤势、尸体、战斗与胜利。
- 界面回归：36 项通过；实际 OpenGL 窗口包含 7 次截图检查，共 43 项通过。测试了键盘激活、右键/Shift/拖动、Esc、草稿撤销、详情冻结时间、个人指挥范围、物资窗口、弹出菜单打开时一键暂停等。
- 使用实际 GPU 在 1280×720 检查了标题、编排、物资、伤势、帮助和设置面板；启动捕获也在 1440×900 检查。
- A/B/C 各连续模拟 60 秒实战，通过；视野优化前后射击数/存活数/敌人数一致。优化后本机模拟 tick 的 P95 为约 9.6–9.9 ms（优化前约 24–26 ms）。这是无窗口模拟耗时，不是完整渲染 FPS 承诺。
- 无 `.godot` 缓存的独立副本，通过启动器首次导入和启动验证。
- 导出 `release/godot/ScarletContract.pck`，在工程目录外使用引擎加载验证。包不含本地测试和交接文档。

2026-09-30 按用户要求，`godot/tests/` 中的测试源码与本文一并纳入 main。日志、截图与一次性导出/格式工具所在的 `.migration-local/` 继续仅保留本地。

## 边界

- 当前入口可验证角色与射击；正式场景和界面仍需按统一美学设计建设。
- 使用 Godot 原生随机数发生器。同一配置在 Godot 内可重现，但不保证逐发随机结果与 Python 版本一致。
- 已准备 Windows 导出配置并验证 PCK。当前机器未发现对应导出模板，因此没有声称生成独立 Windows 游戏 EXE；现有启动器使用用户已安装的 Godot。安装对应模板后可从编辑器导出。
- 尚未做长期游玩平衡测试；未新增撤离、仓库、招募等后续系统。
