from __future__ import annotations

import sys

from rendering.pygame_view import PygameView
from simulation.world import create_breach_world, create_world


def main() -> None:
    scenario = sys.argv[1] if len(sys.argv) > 1 else "demo"
    factory = create_breach_world if scenario == "breach" else create_world
    view = PygameView(factory, scenario)
    view.run()


if __name__ == "__main__":
    main()
