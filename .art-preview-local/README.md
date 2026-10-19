# 原型与美术草案

这些原型独立于 Godot 运行，用于讨论空间结构和界面方向。

- [单泡地图生成器](bubble-generator/README.md)：运行 `python3 .art-preview-local/bubble-generator/serve.py`，浏览器打开 http://127.0.0.1:8770/?view=tiles 。需要 Python 3；命令行导出地图另需 Node.js。页面使用本地脚本和图标。
- [阿利贝三维空间草模](alibe-study/alibe-city.html)：展示不规则泡、公路与跨层电梯。四层和泡的数量仅作示意。可直接打开 HTML；页面通过 CDN 加载 Three.js，需要网络。`alibe-city.glb` 可导入建模软件；运行 `python3 .art-preview-local/alibe-study/build.py` 可重新生成模型、场景数据与页面，仅使用 Python 标准库。
- [CRT 界面方向草案](crt-study/crt-directions.html)：保存边缘式与侧栏式两种布局的原始 HTML 草案。可直接用浏览器查看默认布局，轮播切换由可视化宿主提供。作为独立界面研究，不表示已经接入游戏。

目录名沿用本地原型工作区。上述交付文件已经纳入版本管理；测试、临时截图、页面包装器、日志及导出缓存仍仅保留本地。
