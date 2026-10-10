# 《铁眼》游戏设定 Wiki

内容入口为 [首页](docs/index.md)。词条使用 Markdown，网页由 MkDocs Material 生成，采用百科式导语、分节、目录和资料表，支持中文搜索、分类导航及源文件查看。

## 启动

需要 Python 3.9 或更新版本。macOS 双击项目根目录的 `Open Wiki.command`；Windows 安装 Python 后双击 `Open Wiki.cmd`。

也可以在项目根目录运行：

```sh
python3 wiki/start.py
```

首次启动会联网安装 `wiki/.venv/` 内的依赖，随后打开 `http://127.0.0.1:8765/`。安装完成后，本地阅读与搜索无需互联网。终端保持运行，按 Ctrl+C 停止服务。端口被占用时可运行 `python3 wiki/start.py --port 8766`。

## 内容范围

首页和导航分为“游戏与系统”“世界观”“创作草案”“编辑说明”和英文版“English”。游戏与系统记录玩法及角色规则，世界观记录人物、地点、组织与事件。词条呈现游戏设计；运行版本与验证状态见项目交接文档。

全部词条以 [深红殖民地世界观设定整理](../docs/深红殖民地世界观设定整理.md) 为唯一内容来源。设定变更时先更新该文件，再同步维护相关词条。

英文版镜像全部词条与草案，位于 `docs/en/`；专名与系统术语的固定译法见 [术语对照表](docs/terminology.md)，修改术语时先改该表，再同步英文版词条。

## 编辑

直接修改 `wiki/docs/` 下的 Markdown 文件，保存后网页自动刷新。新增词条后，在 `mkdocs.yml` 的 `nav` 中添加入口，并用相对 Markdown 链接连接相关页面。浏览器用于阅读，正文在文件中编辑。

`docs/深红殖民地世界观设定整理.md` 已改为入口索引，游戏与世界观词条在本 Wiki 中维护。已定内容与草案保持各自的状态；尚未确定的内容集中在 [待讨论事项](docs/drafts/questions.md)。

## 导出与后续托管

在项目根目录运行：

```sh
python3 wiki/start.py build
```

生成的 `wiki/site/` 是静态网站，可由静态托管服务发布。迁移到 MediaWiki 或其他在线写作平台时，以 `wiki/docs/` 为源，按目标平台转换格式。内容中的普通 Markdown 链接和表格可独立于主题使用。

`requirements.txt` 固定本次安装的依赖版本。`.venv/`、`site/` 和本地验证材料已通过当前 checkout 的 `.git/info/exclude` 排除；迁到其他 checkout 时需同样排除这些生成目录。

## 中文搜索维护

`search-dictionary.txt` 收录游戏与世界观专名。`search_fix.py` 在构建时修正 Material 9.7.7 搜索分词遗漏完整词尾的问题，避免“中继防务”退化为单字“中”。升级主题时需重新核对该修正。

## 词条写作与布局

编辑遵循 [Wiki 写作规范](docs/writing-guide.md)。正文记录具体事实，删除通用常识和未决定的可能性；短词条不凑固定栏目。时间轴独立标记非公开事件，不配套添加内幕解说。

词条开头的 YAML 元数据包含 `description`、`category` 和可选的 `infobox`。每个资料表字段使用 `label` 和 `value`，可通过 `link` 连接站内页面。Markdown 正文仍是唯一内容源，构建时自动生成资料表和可查看的源文件。

版式参考 Wikipedia 的百科阅读结构，使用白底、蓝色链接、细线分节和侧栏目录。站点名称、词条和标识为本项目内容。
