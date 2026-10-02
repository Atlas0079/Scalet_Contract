# Project Handoff Notes

Updated: 2026-10-02. This document gives the current project state and routes to the authoritative design documents. Design changes replace superseded descriptions in place; keep the documentation consistent with the latest confirmed decisions.

## Runtime and implementation state

The active project is `godot/`, using GDScript. The launchers open the character and shooting test range; `godot/project.godot` starts `presentation/tactical/tactical.tscn`. The Python simulation in `combat_demo/` remains available for rule comparison. The full battlefield and interface under the current art direction have not yet been built.

The character test range already provides animated movement, weapon handling and shooting. Ability sources, species conversion and independent skill accounts feed a shared ability snapshot. Consumers use the resulting abilities. Current implementation details and outstanding work are recorded in [configuration](../../godot/LOCAL_CONFIGURATION.md), [character architecture](../../godot/LOCAL_CHARACTER_ARCHITECTURE.md), and [shooting mechanics](../../godot/LOCAL_SHOOTING_FACTORS.md).

## Cabin monitor experiment and terminology

`presentation/cabin/cabin.tscn` (`Open CRT Cabin.command` / `.cmd`) embeds live maintenance and shooting-range scenes in Poly Haven's Television 02. The outer application/cabin canvas stays 2560×1440 (16:9). The physical CRT glass is approximately 4:3; game-source and CRT-composite textures use 1920×1440, and the scene signal is 720×540, preserving 540 rows. These are distinct layers, defined in art-direction section 3; do not call all of them “screen resolution”.

Focus moves the cabin camera close to the actual glass and keeps a narrow bezel. There is no fullscreen overlay or internal 16:9 letterbox. The physical glass supplies curvature; the reused CRT shader has warp 0 in the cabin, with other effect parameters unchanged. The standalone maintenance tool below retains its own 16:9/960×540/warp-0.30 configuration. Its dated measurements are not evidence for this new aspect-ratio revision.

Controls: 1 switches live source, 2 toggles CRT, Enter/click glass focuses, Esc returns to desk, F8 controls monitor power. Maintenance preserves separate scene/text layers; the embedded range currently samples its combined scene/tool UI. Alarm clock, audio player and multiple usable devices are not implemented.

## Art direction

The character/shooting range remains the default. The independent maintenance study is `presentation/maintenance/maintenance.tscn`, launched by `Open Maintenance Preview.command` (macOS) or `Open Maintenance Preview.cmd` (Windows). Its current design uses route A only: a clean 2560×1440 render sampled by CRT at an independent 960×540 signal resolution, then composed with readable pixel-font text at 2K adapted from c64cosmin’s Realistic CRT shader: horizontal Gaussian sampling, scanline beams, RGB grille, radial curvature, visible RGB separation, vignette, low-amplitude noise and rolling/line interference. There is no separate pixelation pass. Environment footprints and door cells share the metre grid and movement blockers.

Controls: WASD moves; mouse aims; wheel zooms; E inspects nearby clues; O opens/closes the nearby door; V toggles CRT; F bypasses all post-processing and restores previous settings; N toggles shared outlines; brackets tune CRT strength; Space pauses the character and signal clock. Closing a door on the character is prevented. Curved-screen mouse coordinates use the same mapping as the shader. Movement is local presentation using the existing sweep helper; mission state, firing, perception and inventory are not integrated.

The preceding 2K revision rendered CRT, pixel-only and unfiltered output at 2560×1440; checked Chinese glyph coverage, separate text composition, full bypass/restoration, independent effect toggles, curved input mapping, footprint/blocker agreement, open/closed doors and safe closing. A collision-sweep BFS found 73 reachable grid cells including both doors, work areas and inspection positions. Those results and captures remain local under `.art-preview-local/maintenance-v2/` and do not validate the new shader’s appearance. The reference-based CRT and revised pixel filter passed separate checks under `.art-preview-local/maintenance-v3/`: 2K native captures, fine/coarse presets, matching radial input mapping, full bypass/restoration and scene regression. Pixel-only captures preserve the header glyph pixels exactly relative to the clean image; both preset outputs and CRT output are distinct. Layout and collision behavior are unchanged; user visual acceptance remains pending. The current CRT-only revision passed native checks for no extra pixel material, independent signal resolution, RGB separation settings, animated noise and isolated rolling interference, pixel-identical clean frames across signal times, bypass/restoration and pause under `.art-preview-local/maintenance-v4/`; earlier separate-pixel captures only describe their previous shader conditions.

The current outline target is the outer boundary of each complete object's projection only. Character body/weapon parts share one identity, and each environment object is grouped as a whole. Internal material/color seams, height steps and closed holes receive no added ink; part colors and lighting remain unchanged. `object_outline.gd` reuses source geometry/skins in an identity render; `outline.gdshader` composites exterior contours, using height only for occlusion ordering. N toggles the result. Width is 3 design pixels at 2K, scaled with zoom. Current bounded hole rejection needs rechecking for new silhouettes or a larger zoom range.

Checks in `.art-preview-local/maintenance-v8/` cover exterior contours, a closed ring, an open concavity, color/height seams and exact disabled-pass equality. The shared animated skeleton and focused object comparisons were also checked. Layout, palette and CRT settings are unchanged; user visual approval remains pending. Earlier per-part outline measurements in `.art-preview-local/maintenance-v5/` belong to that old method.

The latest maintenance asset revision uses 21 externally authored model types (58 instances), including 14 newly integrated types. Custom prop geometry has been replaced with a drawer cabinet, tool carts, welding carts, a hand truck, stool, crates, radio/meter instruments, lamp modules, cable/pipe modules and three-metre rolling shutters. Only wall/floor structure and occupancy/threshold markings remain primitive geometry. Source vertices/buffers and triangle counts were checked during material conversion; provenance is in `godot/assets/LICENSES.md`.

Current checks: 2K output / 960×540 CRT; all 21 source types present; 26 ground-object footprints inside their occupied cells; shared outline materials and on/off comparison; both three-cell shutters passable when open and blocked when closed; 70 reachable cells including all inspection positions. Captures and checks are local in `.art-preview-local/maintenance-v6/`; visual approval remains pending. Earlier layout measurements above refer only to their stated revisions.

### Historical preview verification

The first maintenance revision was rendered in A, B and clean modes and passed checks for vertical projection, filter defaults/toggles, both render modes, both doorways, wall/bench/cabinet blocking, clue selection and pause. These results refer to the earlier layout and compositor only; its captures and checks remain local in `.art-preview-local/maintenance/` and do not validate the current 2K/CRT revision.

Previous verification: the 2026-09-30 equipment sample passed local vertical projection, movement blocking, projectile collision, firing (6 shots / 6 blocked by wall), reload and pause checks. Earlier 2026-10-01 captures checked flat-color presentation, 0.5x/2x sampling, movement and one shot. These measurements belong to their earlier layouts and do not validate the revised grid room. The final assembly-room check before removal passed reachability for all 18 free cells, access to five service positions, aisle movement and assembly blocking, entrance/wall/receiver projectile probes, pump-to-table contact and 0.5x/1x/2x captures. These checks described the removed preview, not an approved layout or full mission integration. Auxiliary checks and captures remain local in `.art-preview-local/room-assets/` and `.art-preview-local/room-design/`.

[美学方向](../../docs/art-direction.md) is the authoritative source for the selected route, 2K sampling, pixel-font composition, subtle CRT treatment, grid-aligned scene design and narrative purpose. Keep strict overhead projection, credible proportions, outlines and rich lighting; avoid toy-like styling. The reference roles of Holstin, SIGNALIS, The Last Night and CONSCRIPT remain there. Detailed parameters can be tuned after visual review; do not restore superseded rendering alternatives.

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
