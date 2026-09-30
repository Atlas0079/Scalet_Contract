# Project Handoff Notes

Updated: 2026-09-30. This document gives the current project state and routes to the authoritative design documents. Design changes replace superseded descriptions in place; keep the documentation consistent with the latest confirmed decisions.

## Runtime and implementation state

The active project is `godot/`, using GDScript. The launchers open the character and shooting test range; `godot/project.godot` starts `presentation/tactical/tactical.tscn`. The Python simulation in `combat_demo/` remains available for rule comparison. The full battlefield and interface under the current art direction have not yet been built.

The character test range already provides animated movement, weapon handling and shooting. Ability sources, species conversion and independent skill accounts feed a shared ability snapshot. Consumers use the resulting abilities. Current implementation details and outstanding work are recorded in [configuration](../../godot/LOCAL_CONFIGURATION.md), [character architecture](../../godot/LOCAL_CHARACTER_ARCHITECTURE.md), and [shooting mechanics](../../godot/LOCAL_SHOOTING_FACTORS.md).

## Art direction

### Resumable equipment study (2026-09-30)

Run `Open Machinery Room.cmd` with Godot 4.7.1. The launcher selects Forward+ for this sample only; the default project entry remains the shooting range. `presentation/machinery/machinery.tscn` contains a strict overhead orthographic equipment sample, with a Poly Haven compressor at original scale, a 3 m tiled concrete material, wall geometry and the existing animated character. All runtime assets are bundled under `godot/assets/environment/`; no external download is needed after checkout. Asset provenance is in `godot/assets/LICENSES.md`.

This is an intermediate art study awaiting user review, not an approved final look or a completed room/office level. Judge the material realism and the relationship between the existing stylized character and the PBR equipment before expanding the scene. No terminal filter is applied. Colors come from each material rather than a shared scene tint. Character presentation still uses a separate viewport and silhouette shadow; full shared lighting/occlusion is unfinished.

Controls: WASD move, mouse aim, left button fire, R reload, Space pause, wheel zoom, middle-button drag pan, Home reset, Tab hide HUD. Local checks passed for vertical orthographic projection, wall/equipment movement blocking, open-floor movement, projectile collision, firing (6 shots / 6 blocked by the wall), reload and pause. Rendered preview was inspected on Forward+; the latest resolution-sampling adjustment has not yet received another visual pass. Auxiliary checks and screenshots remain local under `.art-preview-local/room-design/` and are not part of the transfer.

[美学方向](../../docs/art-direction.md) is the single source for scene, character, filter and UI aesthetics:

- Restrained industrial design with colored, simplified but recognizable materials.
- Strict orthographic overhead projection for combat scenes and their art previews: the camera points vertically down, with no visible object side faces; walls appear only as plan-view cross-sections.
- Static 2D scene art, 3D-assisted asset production and models as needed for the final image; no mandatory scene-production method.
- Existing character animation with a subtle 2D appearance developed through form, color, shading and material treatment.
- A retro-terminal viewing impression and early-2000s retro-futuristic UI.
- Readable tactical information at normal gameplay scale and consistent art proportions across resolutions and zoom levels.

Palette, filter parameters, panel design and the exact character rendering treatment remain to be established through samples. These targets do not claim implementation completion.

## Gameplay direction and rules

Players command multiple actors with real-time execution and free tactical pause. Explicit micro orders have priority. Taking over one participant cancels the associated macro task; invalid submission preserves existing plans and reservations. Movement, guard setup, perception and automatic engagement follow [command and AI rules](command_and_ai.md).

The game-loop direction is loot collection, risk assessment, extraction, preparation and another deployment. Permanent actor loss, equipment loss and partial extraction are design goals. The first extracted group does not end a battle while other actors remain. Extraction and the persistent preparation loop are not yet implemented; their confirmed scope and pending details are in [experience goals](player_experience_review.md).

Searching reveals information, allocation reserves work, and physical transfer changes ownership. The assigned carrier must reach the source and complete pickup. Macro and micro search use the same interaction and reservation rules. See [interaction and loot](interaction_and_loot.md).

The Greyport scenario in [tactical design](demo_design.md) defines a functional rule-validation level. Its mission-specific victory rules are not the universal ending rules for the extraction loop.

## Current ownership

- `godot/data/`: native configuration for characters, bodies, abilities, equipment, presentation and scenario data.
- `godot/simulation/`: world execution, grid, actors, movement, perception, planning, room tasks, loot, combat, skills and ability evaluation.
- `godot/presentation/tactical/`: character rendering, gait, shooting effects, range targets and range controls.
- `godot/presentation/interface.gd`: shared ability explanation text.
- `godot/tests/`: applicable simulation and range verification sources.

## Engineering agreements

Reuse existing architecture and interfaces. Migrate data to the current model rather than introducing compatibility paths. Keep decision making, world execution and presentation responsibilities clear. Simulation determines valid information; rendering must not reveal hidden facts.

Explain intended code changes and obtain the user's agreement before implementation. Before deleting or replacing design descriptions, identify the files and content involved. Global working and commit rules are in the user's `AGENTS.md`.

## Verification

[Migration verification](../../godot/LOCAL_MIGRATION.md) and [demo verification](validation.md) record the results and limitations of their stated runs. Use the current configuration and relevant checks for new work; dated results do not prove newly designed presentation or features are complete.
