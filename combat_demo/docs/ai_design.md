# Squad AI Design

This document defines the intended squad AI model for the automatic team
deathmatch prototype. It is the target design for future implementation, not a
description of the current code.

## Design Goals

The combat AI should feel like a small group of armed survivors acting under
incomplete information. They should not be omniscient, and they should not feel
like independent arcade enemies.

Core goals:

- Squad members share battlefield information.
- Individual actors make decisions from squad posture, role, equipment, and
  current action limits.
- Getting hit, hearing gunfire, or seeing an ally under fire creates a visible
  reaction.
- Movement remains grid-planned but visually continuous.
- The AI should be believable before it is optimal.
- Decisions should be explainable in the UI later.

## Architecture

AI should be split into three layers:

```text
Squad AI
  Owns shared memory, squad posture, objective, contact list, and formation.

Actor AI
  Chooses personal intent from squad posture, role, perception, ammo, wounds,
  suppression, and current action.

Action System
  Executes time-based actions such as reload, aim, burst fire, throw grenade,
  bandage, open door, vault, or move.
```

The important rule is:

```text
State decides intent.
Action executes intent over time.
Perception updates memory.
```

## Movement Model

The prototype uses grid navigation with continuous movement.

- Actor position is a floating point coordinate.
- The current cell is `floor(position)`.
- Pathfinding operates on cells.
- Waypoints are cell centers.
- Actors move continuously toward each waypoint.
- Walls live on cell edges and determine whether two adjacent cells are
  passable.

This should remain the base model for now. It keeps tactical logic discrete
while making the visual motion smoother than pure tile movement.

## Squad Memory

Each squad should own a `SquadMemory`.

```text
SquadMemory:
  contacts: list[Contact]
  danger_zones: list[DangerZone]
  objective_cell
  rally_cell
  posture
  last_contact_time
```

### Contact

A contact is remembered enemy information. It may be exact or approximate.

```text
Contact:
  position
  confidence: 0.0 - 1.0
  source: visual / ally_report / hit_reaction / gunshot / footsteps
  enemy_id: optional
  last_updated_time
  expires_after
```

Recommended confidence values:

```text
visual:       1.0
ally_report: 0.8
hit_reaction:0.6
gunshot:     0.4
footsteps:   0.2
```

Contacts decay over time. An old visual contact should become a last-known
position, then disappear if not refreshed.

### Danger Zone

A danger zone represents incoming fire, explosions, or repeated near misses.

```text
DangerZone:
  position
  radius
  intensity
  last_updated_time
```

This is separate from contact because fire can come from an uncertain direction
or cover an area without a known visible enemy.

## Squad Posture

The squad posture describes what the whole group believes is happening.

```text
SEARCH
  No meaningful contact. Move in formation toward objective/search points.

CONTACT
  Suspicious or low-confidence contact exists. Slow down, face threat, move
  carefully, and investigate.

ENGAGED
  High-confidence or visual contact exists. Actors take combat roles:
  engage, support, cover, reload, or reposition.

REGROUP
  Squad is scattered, badly hurt, low on ammo, or has lost contact after a
  fight. Move back toward a rally cell and recover.
```

Posture transitions:

```text
No valid contacts -> SEARCH
Low confidence contact -> CONTACT
High confidence / visual contact -> ENGAGED
Casualties, distance spread, or lost contact -> REGROUP
```

## Actor Roles

Roles make the same squad posture produce different behavior.

Initial demo roles:

```text
Pointman
  Leads during SEARCH. Faces likely threat direction. Reacts quickly but should
  avoid overextending once contact occurs.

Rifleman
  General-purpose fighter. Maintains formation, engages visible enemies, and
  moves to reasonable firing positions.

Support
  Stays behind riflemen. Prefers stable firing positions. Later this role can
  suppress, cover movement, or conserve ammo differently.
```

Future roles:

```text
Marksman
Medic
Grenadier
Breacher
```

## Actor Intent

Actor AI should choose an intent before it starts or continues an action.

```text
Intent:
  MoveTo(cell)
  Face(position)
  Engage(contact)
  Reload
  Investigate(contact)
  HoldPosition
  Regroup
  SeekCoverFrom(contact)
  Suppress(contact or zone)
```

An actor should not directly mutate movement and shooting decisions from many
unrelated branches. It should select an intent, then translate that intent into
an action or path.

## Current Action

Actions are time-based execution units.

```text
Action:
  type
  duration
  progress
  target_position
  target_actor_id
  interrupt_policy
```

Examples:

```text
Reload
Aim
FireBurst
ThrowGrenade
Bandage
OpenDoor
VaultLowWall
Move
GoProne
```

Interrupt policy examples:

```text
Reload
  Can be interrupted by close visible enemy, severe hit reaction, or panic.

ThrowGrenade
  Hard to interrupt once started.

Bandage
  Interrupted by most threats.

FireBurst
  Interrupted by losing target, excessive recoil, or friendly in line of fire.
```

## Perception Events

Perception should update squad memory and actor-local state.

### Visual Contact

When an actor sees an enemy:

```text
1. Create or refresh visual contact.
2. Set confidence to 1.0.
3. Share with squad.
4. Actor may enter Engage if the contact is actionable.
```

### Gunshot Heard

When an actor hears a gunshot:

```text
1. Create approximate contact at noisy position.
2. Confidence is low.
3. Actor faces the source if not busy.
4. Squad posture becomes CONTACT unless already ENGAGED.
```

### Hit Reaction

When an actor is hit:

```text
1. Apply damage.
2. Infer attacker position from shooter position or shot direction.
3. Create hit_reaction contact with medium confidence.
4. Increase suppression.
5. Face the threat if not locked in an uninterruptible action.
6. Share "under fire" information with squad.
```

This fixes the current issue where actors can be shot without reacting if they
did not already see the enemy.

### Near Miss

When a bullet passes near an actor:

```text
1. Increase suppression.
2. Create or strengthen danger zone.
3. Actor may crouch, hold, or seek cover in future versions.
```

Near misses are not required for the first squad AI milestone, but the model
should leave room for them.

## Suppression

Each actor should have suppression:

```text
suppression: 0 - 100
```

Initial effects:

```text
Higher aim error.
Lower willingness to advance.
Higher preference for cover.
Possible action interruption under heavy fire.
```

Suppression should decay over time. Personality, training, and injuries can
modify suppression gain and recovery later.

## Formation

The squad should not send everyone to the same point.

Use a squad anchor and role slots:

```text
squad_anchor
squad_facing
role_slot(actor_role, index)
```

SEARCH posture example:

```text
Pointman: 1 cell forward
Rifleman: left/right rear
Support: 1-2 cells rear
```

CONTACT posture example:

```text
Pointman: stop or shift slightly to a safe forward cell
Rifleman: move to side firing cells
Support: hold a stable rear firing cell
```

ENGAGED posture example:

```text
Visible enemy -> Engage
Known contact but no line of sight -> move to firing position
Under fire or badly hurt -> seek cover
No ammo -> reload
```

## Cover And Position Scoring

Cover should not mean "nearest wall." It should be scored from the known threat.

Candidate positions:

```text
Reachable cells within 3 cells of actor
Formation slot cells
Cells near current position
Cells with line of fire to contact
```

Score:

```text
+ cover from contact
+ line of fire to contact
+ good weapon distance
+ near assigned squad slot
+ safe retreat path
- exposed to multiple contacts
- too close to enemy
- too far from squad
- blocks ally line of fire
```

First implementation can be much simpler:

```text
Look at reachable cells within 3 cells.
Prefer cells where a ray to contact crosses a low wall below actor chest height.
Prefer cells that still have line of sight to contact.
Penalize cells far from squad anchor.
```

## Fire Decisions

Actors should not always fire at maximum rate.

Fire modes:

```text
AimedShot
  Wait for aim error to settle. Good for distance or ammo conservation.

RapidFire
  Fire as soon as possible. Useful at close range, but recoil rises quickly.

Suppress
  Fire at a contact or danger zone to reduce enemy effectiveness. Does not
  require exact visible target in future versions.

HoldFire
  Avoid friendly fire, save ammo, or wait for a better shot.
```

Initial selection:

```text
Clear target + medium/long range -> AimedShot
Close target -> RapidFire
Ally moving under threat -> Suppress
Friendly in line of fire -> HoldFire
Low ammo -> AimedShot or Reload
```

## Friendly Fire

The current shot resolver can hit any actor except the shooter, including
allies. This is useful, but AI should eventually consider it.

Minimum rule:

```text
If an ally is close to the firing ray before the target, prefer HoldFire or
reposition.
```

## Explainability

Each actor should eventually expose a short reason for its current intent.

Examples:

```text
"Engage: visual contact at 7.4m"
"Move: seeking low-wall firing position"
"Reload: magazine empty"
"Face: hit from east"
"Investigate: gunshot heard"
"Regroup: squad spread too far"
```

This is important because the player is judging AI through observation.

## Implementation Milestones

### Milestone 1: Shared Awareness And Hit Reaction

Target:

```text
SquadMemory
Contact confidence and decay
Hit reaction writes contact
Gunshot writes contact
Actors without a visible target react to shared contact
Panel/debug display for current intent/reason
```

Expected visible result:

```text
An actor who is shot turns toward the threat.
Nearby teammates also react and move/focus toward the fight.
The squad feels aware of contact instead of isolated.
```

### Milestone 2: Roles And Formation

Target:

```text
Assign Pointman / Rifleman / Support
SEARCH formation slots
CONTACT formation behavior
Actors avoid choosing the exact same target cell
```

Expected visible result:

```text
The team moves as a loose group instead of six independent units walking to
the center.
```

### Milestone 3: Basic Cover Seeking

Target:

```text
Nearby cell scoring
Low-wall firing positions
Fallback hiding positions
Movement to cover when under fire or suppressed
```

Expected visible result:

```text
Actors stop standing in the open when a better nearby low-wall position exists.
```

### Milestone 4: Fire Modes

Target:

```text
AimedShot
RapidFire
HoldFire for friendly fire risk
Simple suppressive fire placeholder
```

Expected visible result:

```text
Close fights feel frantic, longer fights feel more deliberate, and actors do
not always dump rounds at the same cadence.
```

### Milestone 5: Advanced Actions

Target:

```text
ThrowGrenade
Bandage
VaultLowWall
OpenDoor
Action interruption rules
```

Expected visible result:

```text
The action system becomes the shared foundation for tactical behaviors.
```

