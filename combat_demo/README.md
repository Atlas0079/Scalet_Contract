# Scarlet Contract / 灰港档案室

四人小队、顶视角、实时推进与自由暂停的 Windows 战术指挥 Demo。用门口行动组织集结和突入，用个人指令调整位置、朝向与物品使用。关卡目标是消灭全部 10 名敌人。

## 直接启动

双击项目根目录的 `Start Demo.cmd`，或打开 `release/v1.4.1/ScarletContract/ScarletContract.exe`。发布包已包含 Python、中文字体和音效，无须安装依赖，也不需要联网。复制给另一台电脑时，请复制整个 `ScarletContract` 文件夹，保留 `_internal`。

先选配置 A，点击“开始行动”→“进入关卡”。开局处于暂停状态，可以先下达计划。

## 第一条命令

1. 默认已选全队。右键队员北侧的 S–R 门。
2. 悬停“突入”，选择“直接突入”。右侧检查进入顺序，点击“下达”。
3. 按空格恢复时间。队员集结、开门、依次进入并搜索。
4. 右键队员卡可单独查看这个人的物品，原来的全队选择会保留。

闪光突入需要指定落点。橙色范围表示可能震撼友军；闪光不会区分阵营。长走廊与未搜索的侧面需要额外警戒，不能把“已搜索”当作永久安全。

## 操作

| 输入 | 行为 |
|---|---|
| 左键 / Shift+左键 | 单选 / 增减选择 |
| 空地左键拖动 | 框选 |
| 1–4；快速按两次同键 | 选队员；镜头居中 |
| Ctrl+A | 全选存活队员 |
| F1 / F2；Ctrl+F1 / F2 | 选择编组；保存当前编组 |
| 右键地面 | 松开移动；按住拖出至少 16 像素指定整段朝向；多人分配不同落点 |
| 右键门 / 房间名称 | 打开分级行动菜单 |
| 右键队员 / 队员卡 | 仅向此人使用物品 |
| 空格 / Tab | 暂停恢复 / 0.5 与 1 倍速 |
| Shift+提交微操 | 追加微操路段；有关联宏观行动时仍先接管取消；每人最多 8 项 |
| Q | 选择警戒位置，然后选择朝向 |
| R / H / G | 换弹 / 自行包扎 / 选择闪光投掷者 |
| X | 取消所选队员未来计划 |
| WASD / 中键拖动 / 滚轮 | 平移 / 平移 / 缩放 |
| Esc | 逐层返回选点、菜单、草稿，最后进入暂停菜单 |
| F12 | 在启动工作目录保存截图 |

A、B 同步标签需要手动放行：在两个任务的草稿中选同一标签，全部就绪后点击右栏“放行”。暂停中也可预约放行。挂起任务显示原因，提供继续和取消；伤亡后可检查剩余成员再继续。单人仍能移动、开门、踹门、射击和使用物品。

## 指挥权与自主反应

- **1.4.1：微操优先于自动交战。** 交火中提交移动或转向后立即执行；有效移动期间不自动停步射击、不自动换弹，来弹只提示。到达后恢复自动交战。定点警戒先到位并转向，再允许自动防御。


- **微操接管取消整组关联宏观行动**：例如四人准备突入，移动其中一人会取消这次突入。Shift 不绕过接管规则；预览会提示影响成员。
- **意外挂起计划**：未知方向命中或近失让宏观行动及非移动／转向个人节点挂起；当前有效微操移动／转向继续执行。搜索结束后须在行动面板点击继续；不会自行恢复突入。
- **正常交战继续计划**：已确认敌人的交战属于行动执行；声音只提供区域线索，不能揭示隐藏敌人。
- 普通移动结束保留到达朝向。右键拖拽指定的是固定方向；每个 Shift 路段可指定不同方向。Esc 或地图外松开取消拖拽。

完整规则见 [指挥与 AI 执行规范](docs/command_and_ai.md)。

## 从源码运行

Python 3.12。运行时依赖只有 pygame-ce 2.5.7。

```powershell
cd combat_demo
python -m pip install -r requirements.txt
python main.py
```

`python main.py --config B` 指定初始配置。`python main.py --headless --capture artifacts/start.png` 运行真实渲染器生成开局截图后退出。

## 检查与打包

在项目根目录执行：

```powershell
.\.venv\Scripts\python.exe combat_demo/check_ai.py
.\.venv\Scripts\python.exe -m unittest discover -s combat_demo/tests -v
.\.venv\Scripts\python.exe combat_demo/tools/playthrough.py A --variant 1
.\.venv\Scripts\python.exe combat_demo/tools/playthrough.py B --variant 4
.\.venv\Scripts\python.exe combat_demo/tools/playthrough.py C --variant 0
.\.venv\Scripts\python.exe -m PyInstaller --noconfirm --distpath release/v1.4.1 --workpath build combat_demo/ScarletContract.spec
```

打包开发依赖为 PyInstaller 6.19.0。字体与音效已经生成并随源码提供；重新制作资源才需要 fontTools 4.61.1 和 `tools/make_assets.py`。

## 文件与验证边界

- `docs/demo_design.md`：设计规格。
- `docs/command_and_ai.md`：1.4 指挥权、挂起恢复与 AI 反应规范。
- `docs/validation.md`：本次检查、通关、性能、限制与已知问题。
- `artifacts/`：真实渲染截图、自动化检查和通关记录。
- `assets/LICENSES.md`：字体、音效和运行库说明。

1.4.1 的验证见验证记录顶部；原 1.3 的三配置通关与性能数据保留为历史证据，不自动作为新版本结论。外部真人首次体验、另一台 Windows 机器的兼容性、真实显示器呈现延迟与扬声器听感尚未验证；不把这些项目记作已通过。
