from __future__ import annotations

from dataclasses import dataclass, field
from random import Random

from .actor import Actor
from .geometry import Vec2, angle_to, from_angle, segment_circle_intersection_height
from .map import GridMap
from .pose import actor_combat_position


@dataclass
class ShotEvent:
    start: Vec2
    end: Vec2
    team: str
    timer: float = 0.09
    duration: float = 0.09
    hit_actor_id: int | None = None
    hit_part: str | None = None
    damage: float = 0.0
    blocked: bool = False
    near_misses: list["NearMissEvent"] = field(default_factory=list)
    shooter_id: int | None = None


@dataclass
class FloatingText:
    position: Vec2
    text: str
    timer: float = 0.9


@dataclass
class SoundEvent:
    position: Vec2
    team: str
    radius: float
    timer: float = 0.25
    kind: str = "rifle"
    audible: bool = False
    area: tuple[int, int] | None = None
    id: int = 0


@dataclass
class NearMissEvent:
    actor_id: int
    distance: float
    intensity: float


@dataclass
class ExplosionEvent:
    position: Vec2
    radius: float
    timer: float = 0.45
    duration: float = 0.45


def body_region_from_height(height: float, rng: Random) -> str:
    if height >= 1.50:
        return "head"
    if height >= 1.05:
        return "left_arm" if rng.random() < 0.10 else "torso"
    if height >= 0.75:
        return "right_arm" if rng.random() < 0.20 else "torso"
    return "left_leg" if rng.random() < 0.5 else "right_leg"


def point_segment_distance(point: Vec2, start: Vec2, end: Vec2) -> tuple[float, float]:
    segment = end - start
    length_sq = segment.x * segment.x + segment.y * segment.y
    if length_sq <= 0.00001:
        return point.distance_to(start), 0.0
    t = ((point.x - start.x) * segment.x + (point.y - start.y) * segment.y) / length_sq
    t = max(0.0, min(1.0, t))
    closest = Vec2(start.x + segment.x * t, start.y + segment.y * t)
    return point.distance_to(closest), t


def near_misses_for_segment(
    start: Vec2,
    end: Vec2,
    shooter_id: int,
    actors: list[Actor],
    exclude_id: int | None = None,
) -> list[NearMissEvent]:
    misses: list[NearMissEvent] = []
    for actor in actors:
        if not actor.alive or actor.id == shooter_id or actor.id == exclude_id:
            continue
        distance, _ = point_segment_distance(actor_combat_position(actor), start, end)
        threshold = actor.radius + 0.2
        if distance <= threshold:
            intensity = max(0.15, 1.0 - distance / max(0.0001, threshold))
            misses.append(NearMissEvent(actor_id=actor.id, distance=distance, intensity=intensity))
    return misses


def resolve_shot(
    shooter: Actor, target_point: Vec2, grid: GridMap, actors: list[Actor],
    rng: Random, aim_error_degrees: float,
) -> ShotEvent:
    """Resolve the first physical collision, including misses into the environment."""
    from math import sqrt
    definition = shooter.weapon.definition
    origin = shooter.position
    nominal_distance = max(.01, origin.distance_to(target_point))
    angle = shooter.weapon.sample_shot_angle(angle_to(origin, target_point), aim_error_degrees, rng)
    shooter.weapon.consume_round()
    delta = from_angle(angle.final_angle) * definition.range
    end = origin + delta
    end_height = shooter.eye_height + (1.25 - shooter.eye_height) * definition.range / nominal_distance
    wall_t, wall = grid.raycast(origin, end, shooter.eye_height, end_height, "projectile")
    best_t, best = wall_t, None
    for actor in sorted(actors, key=lambda candidate: candidate.id):
        if not actor.alive or actor.id == shooter.id:
            continue
        f = origin - actor.position
        a = delta.x * delta.x + delta.y * delta.y
        b = 2 * (f.x * delta.x + f.y * delta.y)
        c = f.x * f.x + f.y * f.y - actor.radius * actor.radius
        disc = b * b - 4 * a * c
        if disc < 0 or a <= 1e-9:
            continue
        t = (-b - sqrt(disc)) / (2 * a)
        z = shooter.eye_height + (end_height - shooter.eye_height) * t
        if 0 <= t < best_t and 0 <= z <= actor.height:
            best_t, best = t, actor
    event = ShotEvent(origin, origin + delta * best_t, shooter.team.value, blocked=best is None and wall is not None)
    event.shooter_id = shooter.id
    if best is not None:
        z = shooter.eye_height + (end_height - shooter.eye_height) * best_t
        hit = best.body.resolve_hit(body_region_from_height(z, rng), definition.damage, "ballistic", rng)
        best.mark_dead_if_needed()
        best.hit_flash = .12
        event.hit_actor_id, event.hit_part, event.damage = best.id, hit.part_id, hit.damage
    event.near_misses = near_misses_for_segment(origin, event.end, shooter.id, actors, exclude_id=event.hit_actor_id)
    return event
