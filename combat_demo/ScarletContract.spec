# Build with: python -m PyInstaller --noconfirm ScarletContract.spec
from pathlib import Path
root=Path(SPECPATH)
assets=root/'assets'
datas=[(str(p),'assets') for p in assets.iterdir() if p.is_file() and p.name!='NotoSansSC-Variable.ttf']
a=Analysis([str(root/'main.py')],pathex=[str(root)],binaries=[],datas=datas,hiddenimports=[],
           hookspath=[],hooksconfig={},runtime_hooks=[],excludes=['tkinter','numpy','fontTools'],noarchive=False)
pyz=PYZ(a.pure)
exe=EXE(pyz,a.scripts,[],exclude_binaries=True,name='ScarletContract',debug=False,
        bootloader_ignore_signals=False,strip=False,upx=False,console=False,disable_windowed_traceback=False)
coll=COLLECT(exe,a.binaries,a.datas,strip=False,upx=False,name='ScarletContract')
