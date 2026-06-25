from __future__ import annotations

from dataclasses import dataclass, field
from math import radians
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


def body_part_from_height(height: float, rng: Random) -> str:
    if height >= 1.50:
        return "head"
    if height >= 1.05:
        return "leftArm" if rng.random() < 0.10 else "thorax"
    if height >= 0.75:
        return "rightArm" if rng.random() < 0.20 else "stomach"
    return "leftLeg" if rng.random() < 0.5 else "rightLeg"


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
    shooter: Actor,
    target_point: Vec2,
    grid: GridMap,
    actors: list[Actor],
    rng: Random,
    total_error_degrees: float,
) -> ShotEvent:
    spec = shooter.weapon.spec
    shooter.weapon.consume_round()

    origin = actor_combat_position(shooter)
    aim_height = 1.25
    base_angle = angle_to(origin, target_point)
    spread = radians(total_error_degrees) * (0.35 + origin.distance_to(target_point) / spec.max_range)
    shot_angle = base_angle + rng.uniform(-spread, spread)
    end = origin + from_angle(shot_angle) * spec.max_range

    best_actor: Actor | None = None
    best_height: float | None = None
    best_distance = 99999.0
    for actor in actors:
        if not actor.alive or actor.id == shooter.id:
            continue
        hit_height = segment_circle_intersection_height(
            origin,
            end,
            actor_combat_position(actor),
            actor.radius,
            shooter.eye_height,
            aim_height,
        )
        if hit_height is None or hit_height < 0.0 or hit_height > actor.height:
            continue
        distance = origin.distance_to(actor_combat_position(actor))
        if distance < best_distance:
            best_actor = actor
            best_height = hit_height
            best_distance = distance

    event = ShotEvent(start=origin, end=end, team=shooter.team.value)
    if best_actor is None or best_height is None:
        event.near_misses = near_misses_for_segment(origin, end, shooter.id, actors)
        return event

    best_position = actor_combat_position(best_actor)
    wall_height = grid.ray_wall_height(origin, best_position)
    if wall_height >= 2.0 or wall_height >= best_height:
        event.blocked = True
        event.end = best_position
        event.near_misses = near_misses_for_segment(origin, end, shooter.id, actors)
        return event

    part = body_part_from_height(best_height, rng)
    multiplier = {
        "head": 2.0,
        "thorax": 1.0,
        "stomach": 0.8,
        "leftArm": 0.5,
        "rightArm": 0.5,
        "leftLeg": 0.6,
        "rightLeg": 0.6,
    }[part]
    damage = spec.damage * multiplier
    best_actor.body.damage(part, damage)
    best_actor.mark_dead_if_needed()

    event.end = best_position
    event.hit_actor_id = best_actor.id
    event.hit_part = part
    event.damage = damage
    event.near_misses = near_misses_for_segment(origin, end, shooter.id, actors, exclude_id=best_actor.id)
    return event
