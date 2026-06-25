# Combat Demo

Small Python prototype for an automatic team deathmatch combat system.

## Run

```powershell
cd "C:\MyResearch\Scarlet Contract\combat_demo"
python -m pip install -r requirements.txt
python main.py
```

Run the AI scenario checks without opening the pygame view:

```powershell
python check_ai.py
```

## Controls

- Left click an actor to inspect body-part HP.
- `R` resets the match.
- `Space` pauses/resumes.
- `V` toggles vision cones.
- `L` toggles debug target/last-known lines.
- With an actor selected:
  - `1` cycles aggression policy.
  - `2` cycles ammo policy.
  - `3` cycles cover policy.
  - `4` cycles grenade policy.
  - `5` cycles medical policy.

## Prototype Scope

- 20x12 grid map.
- Walls live on cell edges.
- Red team vs blue team, 3 actors each.
- Actor movement is mode-based:
  - `standing` actors occupy a grid cell and may execute tactical actions.
  - `moving` actors interpolate from one cell center to the next, can pass
    through others, and slow down when crowded.
  - moving actors can still update tactical intent, but the execution result
    must be a new legal destination cell rather than firing from between cells.
  - `acting` actors stay on their occupied cell while timed actions resolve.
- Facing angle and vision cone.
- Visual detection, gunshot hearing, and team-shared last known positions.
- Lightweight AI scenario checks for hit reactions, gunshots, suppression,
  friendly fire, and bandaging.
- Hitscan rifle fire.
- Cylindrical body hit checks with height-based body-part damage.
- Low walls block low hit heights; full walls block movement and sight.
