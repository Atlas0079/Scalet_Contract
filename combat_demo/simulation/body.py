from __future__ import annotations

from dataclasses import dataclass, field
from random import Random


ExternalRegionId = str
BodyPartId = str
DamageType = str


@dataclass(frozen=True)
class BodyPartDefinition:
    id: BodyPartId
    region: ExternalRegionId
    max_hp: float
    hit_weight: float
    tags: frozenset[str] = frozenset()
    damage_multiplier: float = 1.0


@dataclass(frozen=True)
class BodyRegionDefinition:
    id: ExternalRegionId
    parts: tuple[BodyPartDefinition, ...]


@dataclass(frozen=True)
class SpeciesDefinition:
    id: str
    display_name: str
    regions: tuple[BodyRegionDefinition, ...]

    @property
    def parts(self) -> tuple[BodyPartDefinition, ...]:
        return tuple(part for region in self.regions for part in region.parts)

    def part(self, part_id: BodyPartId) -> BodyPartDefinition:
        for part in self.parts:
            if part.id == part_id:
                return part
        raise KeyError(part_id)

    def region(self, region_id: ExternalRegionId) -> BodyRegionDefinition:
        for region in self.regions:
            if region.id == region_id:
                return region
        raise KeyError(region_id)


@dataclass
class BodyPartState:
    definition: BodyPartDefinition
    hp: float

    @property
    def missing_hp(self) -> float:
        return self.definition.max_hp - self.hp

    @property
    def destroyed(self) -> bool:
        return self.hp <= 0.0


@dataclass(frozen=True)
class BodyHit:
    region_id: ExternalRegionId
    part_id: BodyPartId
    damage: float
    killed: bool


@dataclass(frozen=True)
class DerivedBodyStats:
    movement_efficiency: float = 1.0
    manipulation_efficiency: float = 1.0
    vision_efficiency: float = 1.0
    pain: float = 0.0
    bleeding_rate: float = 0.0


@dataclass
class BodyInstance:
    species: SpeciesDefinition
    parts: dict[BodyPartId, BodyPartState] = field(default_factory=dict)

    @classmethod
    def create(cls, species: SpeciesDefinition) -> "BodyInstance":
        return cls(
            species=species,
            parts={
                part.id: BodyPartState(definition=part, hp=part.max_hp)
                for part in species.parts
            },
        )

    @property
    def dead(self) -> bool:
        brain = self.parts.get("brain")
        heart = self.parts.get("heart")
        return bool(
            (brain is not None and brain.destroyed)
            or (heart is not None and heart.destroyed)
            or self.region_hp_fraction("head") <= 0.0
            or self.region_hp_fraction("torso") <= 0.0
        )

    def max_hp(self, part_id: BodyPartId) -> float:
        return self.parts[part_id].definition.max_hp

    def hp(self, part_id: BodyPartId) -> float:
        return self.parts[part_id].hp

    def damage_part(self, part_id: BodyPartId, amount: float, damage_type: DamageType = "generic") -> BodyHit:
        state = self.parts[part_id]
        damage = amount * state.definition.damage_multiplier
        state.hp = max(0.0, state.hp - damage)
        return BodyHit(state.definition.region, part_id, damage, self.dead)

    def resolve_hit(
        self,
        region_id: ExternalRegionId,
        damage: float,
        damage_type: DamageType,
        rng: Random,
    ) -> BodyHit:
        part = self.choose_part(region_id, rng)
        return self.damage_part(part.id, damage, damage_type)

    def choose_part(self, region_id: ExternalRegionId, rng: Random) -> BodyPartDefinition:
        region = self.species.region(region_id)
        total = sum(max(0.0, part.hit_weight) for part in region.parts)
        if total <= 0.0:
            return region.parts[0]
        roll = rng.uniform(0.0, total)
        current = 0.0
        for part in region.parts:
            current += max(0.0, part.hit_weight)
            if roll <= current:
                return part
        return region.parts[-1]

    def heal_part(self, part_id: BodyPartId, amount: float) -> float:
        state = self.parts[part_id]
        before = state.hp
        state.hp = min(state.definition.max_hp, state.hp + amount)
        return state.hp - before

    def region_hp_fraction(self, region_id: ExternalRegionId) -> float:
        region = self.species.region(region_id)
        current = sum(self.parts[part.id].hp for part in region.parts)
        maximum = sum(part.max_hp for part in region.parts)
        if maximum <= 0.0:
            return 1.0
        return max(0.0, current / maximum)

    def display_parts(self) -> list[BodyPartState]:
        return [self.parts[part.id] for part in self.species.parts]

    def wounded_parts(self, tag: str | None = None) -> list[BodyPartState]:
        return [
            state
            for state in self.parts.values()
            if state.missing_hp > 0.0 and (tag is None or tag in state.definition.tags)
        ]

    def derived_stats(self) -> DerivedBodyStats:
        left_leg = self.region_hp_fraction("left_leg")
        right_leg = self.region_hp_fraction("right_leg")
        left_arm = self.region_hp_fraction("left_arm")
        right_arm = self.region_hp_fraction("right_arm")
        head = self.region_hp_fraction("head")
        total_missing = sum(state.missing_hp for state in self.parts.values())
        total_max = sum(state.definition.max_hp for state in self.parts.values())
        bleeding = sum(
            state.missing_hp / max(1.0, state.definition.max_hp)
            for state in self.parts.values()
            if "bleeds" in state.definition.tags
        )
        return DerivedBodyStats(
            movement_efficiency=max(0.15, (left_leg + right_leg) * 0.5),
            manipulation_efficiency=max(0.15, (left_arm + right_arm) * 0.5),
            vision_efficiency=max(0.1, head),
            pain=0.0 if total_max <= 0.0 else min(100.0, 100.0 * total_missing / total_max),
            bleeding_rate=bleeding,
        )


def part(
    part_id: str,
    region: str,
    max_hp: float,
    hit_weight: float,
    *tags: str,
    damage_multiplier: float = 1.0,
) -> BodyPartDefinition:
    return BodyPartDefinition(
        id=part_id,
        region=region,
        max_hp=max_hp,
        hit_weight=hit_weight,
        tags=frozenset(tags),
        damage_multiplier=damage_multiplier,
    )


HUMAN_SPECIES = SpeciesDefinition(
    id="human",
    display_name="Human",
    regions=(
        BodyRegionDefinition(
            "head",
            (
                part("skull", "head", 35.0, 55.0, "bone", "head"),
                part("brain", "head", 20.0, 20.0, "vital", "brain", "head", damage_multiplier=2.0),
                part("eyes", "head", 12.0, 15.0, "vision", "head"),
                part("jaw", "head", 18.0, 10.0, "head"),
            ),
        ),
        BodyRegionDefinition(
            "torso",
            (
                part("thorax", "torso", 85.0, 35.0, "torso", "bleeds"),
                part("heart", "torso", 25.0, 10.0, "vital", "heart", "torso", "bleeds", damage_multiplier=1.5),
                part("lungs", "torso", 45.0, 20.0, "lung", "torso", "bleeds"),
                part("stomach", "torso", 70.0, 25.0, "torso", "bleeds"),
                part("spine", "torso", 35.0, 10.0, "spine", "torso"),
            ),
        ),
        BodyRegionDefinition(
            "left_arm",
            (
                part("left_upper_arm", "left_arm", 35.0, 45.0, "limb", "arm", "manipulation", "bleeds"),
                part("left_forearm", "left_arm", 32.0, 45.0, "limb", "arm", "manipulation", "bleeds"),
                part("left_hand", "left_arm", 22.0, 10.0, "limb", "hand", "manipulation", "bleeds"),
            ),
        ),
        BodyRegionDefinition(
            "right_arm",
            (
                part("right_upper_arm", "right_arm", 35.0, 45.0, "limb", "arm", "manipulation", "bleeds"),
                part("right_forearm", "right_arm", 32.0, 45.0, "limb", "arm", "manipulation", "bleeds"),
                part("right_hand", "right_arm", 22.0, 10.0, "limb", "hand", "manipulation", "bleeds"),
            ),
        ),
        BodyRegionDefinition(
            "left_leg",
            (
                part("left_thigh", "left_leg", 45.0, 45.0, "limb", "leg", "locomotion", "bleeds"),
                part("left_calf", "left_leg", 38.0, 45.0, "limb", "leg", "locomotion", "bleeds"),
                part("left_foot", "left_leg", 24.0, 10.0, "limb", "foot", "locomotion", "bleeds"),
            ),
        ),
        BodyRegionDefinition(
            "right_leg",
            (
                part("right_thigh", "right_leg", 45.0, 45.0, "limb", "leg", "locomotion", "bleeds"),
                part("right_calf", "right_leg", 38.0, 45.0, "limb", "leg", "locomotion", "bleeds"),
                part("right_foot", "right_leg", 24.0, 10.0, "limb", "foot", "locomotion", "bleeds"),
            ),
        ),
    ),
)


def create_human_body() -> BodyInstance:
    return BodyInstance.create(HUMAN_SPECIES)
