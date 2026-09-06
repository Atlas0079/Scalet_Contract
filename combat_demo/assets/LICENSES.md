# Bundled assets

- `NotoSansSC-Regular.ttf`: Noto Sans SC, weight 400 instantiated from the official Google Fonts variable font. Licensed under SIL Open Font License 1.1; see `OFL.txt`. Source: https://github.com/google/fonts/tree/main/ofl/notosanssc . Font generation: `tools/make_assets.py` using fontTools.
- Ten `.wav` files: original deterministic synthesized audio generated for this project by `tools/make_assets.py`; no sampled recordings or third-party sound assets.
- All game visuals are rendered by project code with geometric primitives. No raster artwork or external image assets.
- pygame-ce 2.5.7 is bundled as a shared library distribution. Its LGPL text and package metadata are in `pygame-LGPL.txt` and `pygame-METADATA.txt`. Upstream source: https://github.com/pygame-community/pygame-ce/tree/2.5.7 . The SDL and codec DLLs remain separate under `_internal/pygame`; they can be replaced independently. Python's license is in `Python-LICENSE.txt`.
- PyInstaller 6.19.0 builds the executable using its GPL-2.0-or-later bootloader exception. Source: https://github.com/pyinstaller/pyinstaller/tree/v6.19.0 . No PyInstaller API is used by the running game.
