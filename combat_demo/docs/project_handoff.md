# Project Handoff Notes

This document is a compact handoff for future LLM conversations. It captures
the current project shape, preferred engineering style, and near-term modeling
direction.

## Project State

`combat_demo` now implements the Greyport tactical command demo. The authoritative
gameplay specification is `demo_design.md`; v1.4.1 command ownership and AI response rules are centralized in `command_and_ai.md`; measured results and remaining manual
acceptance work are recorded in `validation.md`. The sections below about future
body species and ECS are historical architecture notes, not extra demo requirements.

Current working systems:

- Grid map simulation with edge-mounted environment features.
- Environment features with explicit height and blocking flags.
- Cell-mounted full-cell cover.
- Generic interactables that can be placed on edges or inside cells.
- Actor movement modes: `standing`, `moving`, `acting`, `dead`.
- Manual actor commands for movement, facing, hold, engage intent, suppression
  intent, and timed actions.
- Hitscan projectile resolution with body-region damage.
- Pygame visualization and lightweight scenario checks.

Current command ownership:

- `mission.py`: authored map, doors, furniture, enemy configurations and seeds.
- `orders.py`: per-actor queues, atomic reservation, room task phases, synchronization, whole-task takeover cancellation and explicit suspension/resume validation.
- `items.py`: capabilities shared by inventory, menus, drafts and physical actions.
- `perception.py`: individual vision, team knowledge, coarse sound cues and enemy decisions.
- `world.py` / `world_commands.py`: fixed-step execution and physical action completion.
- `pygame_view.py` / `widgets.py`: UI edits plans and renders known information.

The old autonomous AI modules remain removed. Enemy AI is now implemented by the
explicit state machine in `perception.py`; allies act through player plans and
local firing rules, sound observation and incoming-fire bearings. Do not restore the old member-only takeover behavior: a micro command cancels the whole associated macro task, including when Shift is held. Shift appends only within micro plans. Unknown incoming fire suspends a macro or non-motion personal plan until explicit resume; active micro movement/turning continues with a warning. Active micro movement/turning outranks automatic aim, fire, reload and investigation. Guard setup has priority until first arrival/alignment, then normal defensive fire is allowed. The launcher targets release/v1.4.1/ScarletContract because an old running executable must not be overwritten. Ground right-drag commits a segment angle on release at a 16 screen-pixel threshold. Do not reintroduce legacy grenade/bandage counters or old AI
compatibility paths. Start the released app with the root `Start Demo.cmd`, or run
`combat_demo/main.py` from Python. No legacy scenario selector remains in the UI.

## Engineering Style

Prefer small, explicit systems with clear ownership boundaries.

- Reuse the existing architecture before adding new interfaces.
- Avoid compatibility layers for obsolete data formats; migrate data to the new
  model instead.
- Keep simulation rules data-driven where practical, but do not over-abstract
  before there are two real use cases.
- Scenario checks should describe behavior, not implementation details.
- Keep AI decision making separate from world execution. The world should
  execute explicit commands, not invent high-level intent by itself.
- Avoid clever behavior in the first version of a system. Prove the contract
  first, then improve tactics.

## Environment Model

The map should not treat walls as a fixed enum. Environment data is moving
toward generic features:

- `EnvironmentFeature`
  - Has `kind`, `height`, `placement`, blocking flags, cover value, and optional
    `interactive_id`.
  - Can be placed on a cell edge or inside a cell.
- `Interactable`
  - Has `kind`, `placement`, `state`, supported `actions`, and optional target
    feature metadata.
  - Doors, windows, switches, panels, and future devices should use this common
    concept instead of bespoke per-object systems.
- Edge features
  - Walls, doors, windows, rails, low cover, barriers.
- Cell features
  - Full-cell cover, crates, pillars, machines, obstacles.

The goal is not perfect physical simulation. The goal is a consistent data
shape that lets movement, line of sight, projectile blocking, cover evaluation,
and interaction consume the same environment facts.

## Character Body Direction

Near-term body work should focus on humans only, but leave space for future
humanoid species such as vampires, androids, cyborgs, or synthetic people.

Important design goal:

Different species may have different internal body logic, but the rest of the
simulation should consume one unified combat interface.

The external hit volume can stay simple and humanoid:

- `head`
- `torso`
- `left_arm`
- `right_arm`
- `left_leg`
- `right_leg`

Each external region can later resolve into weighted subparts. For example,
when a projectile hits `left_arm`:

- `upper_arm`: 45%
- `forearm`: 45%
- `hand`: 10%

For humans, likely first-pass subparts:

- `head`: skull, brain, eyes, jaw
- `torso`: thorax, heart, lungs, stomach, spine
- `left_arm` / `right_arm`: upper arm, forearm, hand
- `left_leg` / `right_leg`: thigh, calf, foot

Humans can initially keep conventional vital rules:

- Destroyed brain or head-critical injury causes death.
- Destroyed heart or thorax-critical injury causes death or rapid bleedout.
- Limb damage reduces movement or manipulation.
- Bleeding and pain can later feed into consciousness, aim, and movement.

Future species should be supported through data and rules, not by scattering
`if species == ...` checks across combat code. Examples:

- Vampire: less traditional organ dependency, death more tied to blood loss or
  specific critical destruction.
- Android: no bleeding or pain, but processor, power core, actuator, or EMP
  vulnerability.
- Cyborg: mixed organic and mechanical subparts with different repair rules.

## Suggested Body API Shape

The body system should eventually expose a small interface like:

```text
BodyInstance.resolve_hit(region, damage, damage_type, rng)
BodyInstance.apply_damage(part_id, amount, damage_type)
BodyInstance.derived_stats()
BodyInstance.is_dead()
```

Useful future data types:

```text
SpeciesDefinition
BodyLayout
BodyRegion
BodyPartDefinition
BodyPartState
DeathRule
DerivedStatRule
```

Do not implement every future type at once. For the first human-only milestone,
it is enough to replace the current flat body HP dict with a structure that can
represent regions and weighted subparts.

## Weapon Model Direction

Weapons should be treated as items, even though the demo is not using a full
inventory or ECS architecture yet.

Current conceptual layers:

- `ItemDefinition`
  - Generic item identity and item-level fields.
- `WeaponDefinition`
  - Weapon-specific static data such as damage, range, magazine size, spread,
    recoil, and reload timing.
- `WeaponState`
  - Runtime data such as ammo, cooldown, and accumulated recoil.

Future ECS migration should be able to split these concepts into components,
but the demo should keep the API direct and readable for now.

Shot angle resolution should remain decomposed into separate sources:

```text
final_angle = center_aim_angle
            + random actor aim offset
            + random weapon spread offset
            + random recoil offset
```

The actor owns current aim error and aim settling behavior. The weapon owns
inherent spread and recoil state. This keeps character skill/stance separate
from firearm mechanical accuracy.

## AI Reset

Autonomous AI prototypes have been removed from this working tree. The next AI
implementation should start from a clean design while reusing the existing
`ActorCommand` execution path, map zones, movement, body, and weapon systems.

Keep the separation between decision making and world execution: `World`
executes explicit commands; future AI should explain and choose them.

## First Human Body Milestone

Recommended first implementation target:

1. Keep the six external hit regions stable.
2. Add human subpart definitions with hit weights.
3. Convert projectile hit resolution from direct body-part selection to:

```text
projectile ray -> external region -> weighted subpart -> damage application
```

4. Preserve current gameplay feel while improving data shape.
5. Add scenario checks for:
   - Region-to-subpart weighted resolution is deterministic with seeded RNG.
   - Critical human part damage can kill.
   - Limb damage affects derived stats without requiring AI changes.

## Verification

Useful checks:

```powershell
cd "C:\MyResearch\Scarlet Contract"
python combat_demo\check_ai.py
python -m compileall combat_demo
```
