from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class WeaponSpec:
    name: str
    damage: float
    fire_interval: float
    magazine_size: int
    reload_time: float
    spread_degrees: float
    max_range: float
    gunshot_radius: float


RIFLE = WeaponSpec(
    name="Rifle",
    damage=35.0,
    fire_interval=0.25,
    magazine_size=30,
    reload_time=2.5,
    spread_degrees=2.0,
    max_range=18.0,
    gunshot_radius=14.0,
)


@dataclass
class WeaponState:
    spec: WeaponSpec
    ammo: int
    cooldown: float = 0.0

    @classmethod
    def create(cls, spec: WeaponSpec) -> "WeaponState":
        return cls(spec=spec, ammo=spec.magazine_size)

    def update(self, dt: float) -> None:
        self.cooldown = max(0.0, self.cooldown - dt)

    def can_fire(self) -> bool:
        return self.cooldown <= 0.0 and self.ammo > 0

    def consume_round(self) -> None:
        self.ammo -= 1
        self.cooldown = self.spec.fire_interval
