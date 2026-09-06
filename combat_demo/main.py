from __future__ import annotations
import argparse
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description="Scarlet Contract · 灰港档案室")
    parser.add_argument("--config",choices=("A","B","C"),default="A")
    parser.add_argument("--capture",type=Path,help="Render a deterministic initial mission screenshot and exit")
    parser.add_argument("--headless",action="store_true")
    args=parser.parse_args()
    if args.headless:
        import os
        os.environ["SDL_VIDEODRIVER"]="dummy";os.environ["SDL_AUDIODRIVER"]="dummy"
    import pygame
    from rendering.pygame_view import PygameView
    view=PygameView(args.config)
    if args.capture:
        view.start_mission();view.draw();args.capture.parent.mkdir(parents=True,exist_ok=True)
        pygame.image.save(view.screen,str(args.capture));pygame.quit()
    else:view.run()


if __name__=="__main__":main()
