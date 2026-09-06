from __future__ import annotations

from dataclasses import dataclass
from math import radians
from random import Random


@dataclass(frozen=True)
class ItemDefinition:
    id: str
    name: str
    item_kind: str
    mass: float = 0.0


@dataclass(frozen=True)
class WeaponDefinition:
    item: ItemDefinition
    damage: float
    fire_interval: float
    magazine_size: int
    reload_time: float
    range: float
    gunshot_radius: float
    weapon_spread_degrees: float
    recoil_per_shot_degrees: float
    recoil_recovery_degrees_per_second: float
    max_recoil_degrees: float

    @property
    def id(self) -> str:
        return self.item.id

    @property
    def name(self) -> str:
        return self.item.name


@dataclass(frozen=True)
class ShotAngleBreakdown:
    center_angle: float
    aim_offset: float
    weapon_offset: float
    recoil_offset: float

    @property
    def final_angle(self) -> float:
        return self.center_angle + self.aim_offset + self.weapon_offset + self.recoil_offset


RIFLE = WeaponDefinition(
    item=ItemDefinition(id="rifle", name="步枪", item_kind="weapon", mass=3.8),
    damage=35.0,
    fire_interval=0.25,
    magazine_size=30,
    reload_time=2.5,
    range=18.0,
    gunshot_radius=14.0,
    weapon_spread_degrees=2.0,
    recoil_per_shot_degrees=1.2,
    recoil_recovery_degrees_per_second=4.0,
    max_recoil_degrees=10.0,
)


@dataclass
class WeaponState:
    definition: WeaponDefinition
    ammo: int
    cooldown: float = 0.0
    recoil_error_degrees: float = 0.0
    reserve_ammo: int = 90

    @property
    def spec(self) -> WeaponDefinition:
        return self.definition

    @classmethod
    def create(cls, definition: WeaponDefinition) -> "WeaponState":
        return cls(definition=definition, ammo=definition.magazine_size)

    def update(self, dt: float) -> None:
        self.cooldown = max(0.0, self.cooldown - dt)
        self.recoil_error_degrees = max(
            0.0,
            self.recoil_error_degrees - self.definition.recoil_recovery_degrees_per_second * dt,
        )

    def can_fire(self) -> bool:
        return self.cooldown <= 0.0 and self.ammo > 0

    def consume_round(self) -> None:
        self.ammo -= 1
        self.cooldown = self.definition.fire_interval
        self.recoil_error_degrees = min(
            self.definition.max_recoil_degrees,
            self.recoil_error_degrees + self.definition.recoil_per_shot_degrees,
        )

    def sample_shot_angle(
        self,
        center_angle: float,
        aim_error_degrees: float,
        rng: Random,
    ) -> ShotAngleBreakdown:
        aim_offset = radians(rng.uniform(-aim_error_degrees, aim_error_degrees))
        weapon_offset = radians(rng.uniform(-self.definition.weapon_spread_degrees, self.definition.weapon_spread_degrees))
        recoil_offset = radians(rng.uniform(-self.recoil_error_degrees, self.recoil_error_degrees))
        return ShotAngleBreakdown(
            center_angle=center_angle,
            aim_offset=aim_offset,
            weapon_offset=weapon_offset,
            recoil_offset=recoil_offset,
        )
