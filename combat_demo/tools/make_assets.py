"""Build deterministic original UI sounds and a static Regular font."""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1] / "assets"


def main():
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont
    source = ROOT / "NotoSansSC-Variable.ttf"
    if source.exists():
        font = instantiateVariableFont(TTFont(source), {"wght": 400}, inplace=True)
        font.save(ROOT / "NotoSansSC-Regular.ttf")
    rng = random.Random(7)
    for name, frequency, duration in [("hover",900,.045),("confirm",620,.13),("reject",160,.18),
            ("ready",1100,.22),("rifle",80,.13),("door",240,.18),("kick",55,.28),
            ("reload",400,.35),("flash",65,.48),("hit",130,.12)]:
        samples=[]
        for i in range(int(22050*duration)):
            t=i/22050; envelope=(1-t/duration)**2
            value=math.sin(2*math.pi*frequency*t)
            if name in {"rifle","kick","flash","hit"}: value=.75*rng.uniform(-1,1)+.25*value
            if name=="reload": envelope*=1 if int(t*25)%3==0 else .08
            samples.append(struct.pack("<h",int(10000*envelope*value)))
        with wave.open(str(ROOT/(name+".wav")),"wb") as output:
            output.setparams((1,2,22050,0,"NONE","not compressed"));output.writeframes(b"".join(samples))


if __name__ == "__main__": main()
