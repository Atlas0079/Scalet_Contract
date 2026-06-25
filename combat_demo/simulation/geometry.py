from __future__ import annotations

from dataclasses import dataclass
from math import atan2, cos, degrees, hypot, pi, sin, sqrt


TAU = pi * 2.0


@dataclass(frozen=True)
class Vec2:
    x: float
    y: float

    def __add__(self, other: "Vec2") -> "Vec2":
        return Vec2(self.x + other.x, self.y + other.y)

    def __sub__(self, other: "Vec2") -> "Vec2":
        return Vec2(self.x - other.x, self.y - other.y)

    def __mul__(self, value: float) -> "Vec2":
        return Vec2(self.x * value, self.y * value)

    def length(self) -> float:
        return hypot(self.x, self.y)

    def normalized(self) -> "Vec2":
        length = self.length()
        if length <= 0.00001:
            return Vec2(0.0, 0.0)
        return Vec2(self.x / length, self.y / length)

    def distance_to(self, other: "Vec2") -> float:
        return (self - other).length()

    def angle(self) -> float:
        return atan2(self.y, self.x)


@dataclass(frozen=True)
class Ray2:
    origin: Vec2
    direction: Vec2


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def normalize_angle(angle: float) -> float:
    while angle <= -pi:
        angle += TAU
    while angle > pi:
        angle -= TAU
    return angle


def angle_to(a: Vec2, b: Vec2) -> float:
    return atan2(b.y - a.y, b.x - a.x)


def angle_difference(a: float, b: float) -> float:
    return normalize_angle(b - a)


def rotate_toward(current: float, target: float, max_delta: float) -> float:
    diff = angle_difference(current, target)
    if abs(diff) <= max_delta:
        return normalize_angle(target)
    return normalize_angle(current + max_delta * (1.0 if diff > 0 else -1.0))


def from_angle(angle: float) -> Vec2:
    return Vec2(cos(angle), sin(angle))


def segment_circle_intersection_height(
    start: Vec2,
    end: Vec2,
    circle_center: Vec2,
    radius: float,
    start_height: float,
    end_height: float,
) -> float | None:
    d = end - start
    f = start - circle_center
    a = d.x * d.x + d.y * d.y
    b = 2.0 * (f.x * d.x + f.y * d.y)
    c = f.x * f.x + f.y * f.y - radius * radius
    discriminant = b * b - 4.0 * a * c
    if discriminant < 0.0 or a <= 0.00001:
        return None
    root = sqrt(discriminant)
    t1 = (-b - root) / (2.0 * a)
    t2 = (-b + root) / (2.0 * a)
    candidates = [t for t in (t1, t2) if 0.0 <= t <= 1.0]
    if not candidates:
        return None
    t = min(candidates)
    return start_height + (end_height - start_height) * t


def angle_degrees(angle: float) -> float:
    return degrees(normalize_angle(angle))
