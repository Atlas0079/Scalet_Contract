# Project Handoff Notes

This document is a compact handoff for future LLM conversations. It captures
the current project shape, preferred engineering style, and near-term modeling
direction.

## Project State

V1.7.4 adds the user's requested 0.5-second delay after overlap ends. Actor's
crowd_slow_remaining refreshes on crowd contact, expires in simulation time even
when standing, and freezes while World is paused. It survives clear_movement so
cell arrivals and command changes do not erase the remaining slowdown. The final
timer step prorates movement if expiry occurs inside dt. Launcher: v1.7.4.

V1.7.3 (2026-09-08) supersedes the yielding behavior below at the user's request.
Crowding now only applies a 0.45 multiplier to one mover in each overlapping pair:
the slower effective speed (injury/terrain included), then higher ID for equal
speeds. The other mover keeps full speed, both keep moving, and separation clears
the multiplier immediately. Multipliers do not stack. Snapshot calculation and
existing occupied-final-cell rules remain. Removed movement_yield_* Actor fields,
task priority arbitration, following constraints/cycle resolution, temporary-yield
UI text, and Planner stall exemption. Movement no longer chooses by task order;
the existing doorway release sequence is unchanged. Launcher: v1.7.3.

V1.7.2 (2026-09-08) replaces symmetric moving-body slowdown with snapshot-based
local following and yielding in movement_allowances. World supplies current task
member order for ties and passes distance budgets to the existing actor updater.
The leading actor keeps its effective speed; overlapping followers separate before
following. Crossings yield deterministically; cycles release one mover. Transit
through stationary bodies remains possible at 0.45 speed, walls do not cause
crowding, and requested routes/slots/facing are unchanged. Actor yield state records
the moving queue leader and its prior position; Planner only resets stall timers
when that leader actually moved. UI reports temporary yielding. Launcher: v1.7.2.
See the movement section in command_and_ai.md and validation.md.

V1.7.1 (2026-09-08) applies the user's UI principle: reserve the right-hand
button panel for low-frequency settings and important actions; frequent spatial
interactions belong on the map. Staged station placement now shares ordinary
move_drag press/release handling: left-select, right-click destination, right-drag
from that destination to set facing (0.5-cell threshold). A plain click restores
the planner's default facing. In-place facing uses a right-drag at the existing
station. Position and facing validate/undo atomically. Dedicated position/facing
buttons, tools and the separate plan_drag path were removed. Launcher: v1.7.1.
See the UI principle in demo_design.md and the 1.7.1 interaction revision.

V1.7 (2026-09-08) replaces the global quick/staged toggle with explicit sidebar
choices. Door and room trees use action_focus, including keyboard navigation and
an explicit command/arrangement decision. Staged editing pauses time and focuses
the entrance; stage tabs filter markers. Actor/card/number input chooses the edited
member without changing participants. Dedicated arrows reorder. Draft undo and one
recoverable in-mission draft live in PlanningViewMixin, using the existing planner
for validation. Invalid edits keep valid state with explicit feedback. Editing locks
live command hotkeys and resume controls. Commit remains paused; Space executes.
Events/settings preserve draft context; loot notifications wait until editing ends.
The launcher uses release/v1.7. See the 1.7 section in interaction_and_loot.md and
validation.md. These rules supersede the historical 1.6 UI behavior below.

V1.6 (2026-09-08) adds quick commands and staged plans. UI defaults to quick + hold
after entry; explicit threat-search remains available. `TaskDraft` carries after_entry,
stack/entry overrides and angles; preview and submit validate and preserve these.
Pinned slots never silently relocate; normal auto slots retain existing resolution.
`planning_view.py` contains map-space edit helpers and plan controls. Left-drag markers
to move, right-drag to face; actual actor clicks leave unsubmitted drafts. Entrance
changes reset edits; method/order changes preserve them or reject atomically. Room
guard asks for a legal point rather than using the room center. Map glyph geometry
uses world sizes, fixed readable text/strokes remain screen-space, movement direction
drag threshold is 0.5 world cells. Extraction remains out of scope.

V1.5.4: room labels are display-only, hide near the pointer and highlight with Ctrl.
Ctrl-right-click any zoned map cell opens room actions in the sidebar, preserving
selected participants. Sidebar focus derives from room_inspect, actor-scoped menus,
object menus, selection, loot and draft state; hover does not switch primary focus.
No selected actor means no actor command buttons. Events and pending loot remain
fixed footer entries even in drafts and allocation; events restore previous context.

V1.5.3 implements the first UI clarity pass: task-first sidebar, conditional sync rows,
fixed read-only actor detail entry, contextual loot candidate inspection, explicit
finish-current versus browse-next controls, and single-item reservation cancellation
through the existing `cancel_pickup` used by reassignment. Details preserve selection,
loot context, reservations and pause state. Incremental allocation preserves its source
decision even when replacing the searcher's micro queue. See interaction_and_loot.md
for current UI rules; extraction remains outside this release.

`combat_demo` now implements the Greyport tactical command demo. The authoritative
gameplay specification is `demo_design.md`; v1.5 command ownership and AI response rules are centralized in `command_and_ai.md`; measured results and remaining manual
acceptance work are recorded in `validation.md`. The sections below about future
body species and ECS are historical architecture notes, not extra demo requirements.

Design direction (2026-09-07): Pygame is a functional
prototype; the user intends a later Godot implementation. Preserve the multi-actor
command model and develop a loot/risk/extraction/preparation loop, permanent actor
death, equipment loss and partial extraction while remaining actors stay playable.
`player_experience_review.md` records the accepted direction and existing UI issues.
`interaction_and_loot.md` specifies the latest macro/micro loot search, yellow object
states, automatic pause on search completion, allocation plans and physical pickup.
Container UI now uses a map-anchored window with a tether: double-left-click an item for the named interacting actor, or right-click to choose another carrier. Each click submits a reservation immediately; closing finishes that source decision and keeps time paused. V1.5.2 allows reassignment of reserved items through the same double-click/right-click controls: validate first, remove only the old pickup, preserve other reservations and macro ownership even after reopening. Selecting the same carrier is a no-op preserving action progress. Completed transfers cannot be reassigned from container records. Repeated same-source pickups append; no per-row actor buttons or confirmation draft remain. The current level validates functional correctness, not entertainment or balance.
Search reveals information, allocation reserves work, and completed on-site transfer
changes ownership. If A searches and B is assigned a gun, B must reach the container
and complete pickup. Same-task allocation edits that task; outside-task micro orders
still apply the existing whole-macro takeover rule. Do not implement teleporting loot
or a separate inventory path for each object kind. Corpses occupy a chosen nearby
legal placement cell and slow traversal; loose drops do not block or slow movement.

V1.5 implements that in-raid loot slice in `simulation/loot.py` and
`rendering/loot_view.py`, reusing Planner nodes and World timed actions. Search:
3 seconds for containers, 2 for corpses. Transfer/drop/equip: 0.6 seconds divided
by manipulation efficiency. Capacity: 18 kg. Corpse speed: 0.6; placement radius:
2 geometric path units, y/x tie break, same-cell fallback. Known object contents
are snapshots, equipment instances retain identity and magazine state. Macro
search requires participants already in the zone; guards are excluded from
observation assignment. Results remain accessible with L; inventory with I.
Victory allows returning to the field for looting. Extraction, persistent stash,
recruitment, stack splitting, direct handover and storing back are not implemented.
Do not mistake the future extraction specification for existing code.

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
local firing rules, sound observation and incoming-fire bearings. Do not restore the old member-only takeover behavior: a micro command cancels the whole associated macro task, including when Shift is held. Shift appends only within micro plans. Unknown incoming fire suspends a macro or non-motion personal plan until explicit resume; active micro movement/turning continues with a warning. Active micro movement/turning outranks automatic aim, fire, reload and investigation. Guard setup has priority until first arrival/alignment, then normal defensive fire is allowed. The launcher targets release/v1.6/ScarletContract; older release directories and running sessions are preserved. Ground right-drag commits a segment angle on release at a 0.5 world-cell threshold. Do not reintroduce legacy grenade/bandage counters or old AI
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
