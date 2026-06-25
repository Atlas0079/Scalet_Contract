from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from math import hypot
from typing import TYPE_CHECKING

from .geometry import Vec2

if TYPE_CHECKING:
    from .actor import Actor


class SquadPosture(Enum):
    SEARCH = "search"
    CONTACT = "contact"
    ENGAGED = "engaged"
    REGROUP = "regroup"


class SquadAssignment(Enum):
    CONTACT_LEAD = "contact_lead"
    BASE_OF_FIRE = "base_of_fire"
    FLANK = "flank"
    RECOVER = "recover"


class SquadPhase(Enum):
    IDLE = "idle"
    SET_FIRE_BASE = "set_fire_base"
    BOUNDING = "bounding"
    CONSOLIDATE = "consolidate"


@dataclass
class Contact:
    position: Vec2
    confidence: float
    source: str
    last_updated_time: float
    enemy_id: int | None = None
    expires_after: float = 5.0

    def refresh(self, position: Vec2, confidence: float, now: float) -> None:
        self.position = position
        self.confidence = max(self.confidence, confidence)
        self.last_updated_time = now

    def alive(self, now: float) -> bool:
        return self.confidence > 0.05 and now - self.last_updated_time <= self.expires_after

    def decay(self, dt: float) -> None:
        decay_rate = {
            "visual": 0.08,
            "ally_report": 0.12,
            "hit_reaction": 0.18,
            "gunshot": 0.18,
            "footsteps": 0.25,
        }.get(self.source, 0.16)
        self.confidence = max(0.0, self.confidence - decay_rate * dt)


@dataclass
class DangerZone:
    position: Vec2
    radius: float
    intensity: float
    last_updated_time: float

    def alive(self, now: float) -> bool:
        return now - self.last_updated_time <= 4.0


@dataclass
class SquadMemory:
    team_name: str
    objective_cell: tuple[int, int]
    rally_cell: tuple[int, int]
    posture: SquadPosture = SquadPosture.SEARCH
    contacts: list[Contact] = field(default_factory=list)
    danger_zones: list[DangerZone] = field(default_factory=list)
    assignments: dict[int, SquadAssignment] = field(default_factory=dict)
    phase: SquadPhase = SquadPhase.IDLE
    phase_timer: float = 0.0
    bound_actor_id: int | None = None
    last_bound_actor_id: int | None = None
    last_contact_time: float = -999.0
    regroup_timer: float = 0.0
    regroup_reason: str = ""

    def update(self, now: float, dt: float) -> None:
        for contact in self.contacts:
            contact.decay(dt)
        self.contacts = [contact for contact in self.contacts if contact.alive(now)]
        self.danger_zones = [zone for zone in self.danger_zones if zone.alive(now)]
        self.regroup_timer = max(0.0, self.regroup_timer - dt)

        best = self.best_contact()
        if best is None:
            self.posture = SquadPosture.REGROUP if self.regroup_timer > 0.0 else SquadPosture.SEARCH
            self.assignments.clear()
            self._clear_tempo()
            return

        self.last_contact_time = best.last_updated_time
        if best.confidence >= 0.9:
            self.posture = SquadPosture.ENGAGED
        elif best.confidence >= 0.35:
            self.posture = SquadPosture.CONTACT
        else:
            self.posture = SquadPosture.SEARCH

    def update_assignments(self, actors: list["Actor"]) -> None:
        contact = self.best_contact()
        alive = [actor for actor in actors if actor.alive]
        if contact is None or self.posture not in (SquadPosture.CONTACT, SquadPosture.ENGAGED):
            self.assignments.clear()
            return

        assignments: dict[int, SquadAssignment] = {}
        available = alive.copy()

        recover = [
            actor
            for actor in available
            if self._is_wounded(actor)
            or actor.suppression >= 70.0
            or actor.weapon.ammo <= max(2, actor.weapon.spec.magazine_size // 10)
        ]
        for actor in recover[:1]:
            assignments[actor.id] = SquadAssignment.RECOVER
            available.remove(actor)

        base = self._pick_by_role(available, "support") or self._pick_by_role(available, "rifleman")
        if base is not None:
            assignments[base.id] = SquadAssignment.BASE_OF_FIRE
            available.remove(base)

        lead = self._pick_by_role(available, "pointman") or self._closest_to_contact(available, contact)
        if lead is not None:
            assignments[lead.id] = SquadAssignment.CONTACT_LEAD
            available.remove(lead)

        for actor in available:
            assignments[actor.id] = SquadAssignment.FLANK

        self.assignments = assignments

    def assignment_for(self, actor: "Actor") -> SquadAssignment | None:
        return self.assignments.get(actor.id)

    def update_tempo(self, actors: list["Actor"], dt: float) -> None:
        contact = self.best_contact()
        alive = [actor for actor in actors if actor.alive]
        if contact is None or self.posture not in (SquadPosture.CONTACT, SquadPosture.ENGAGED):
            self._clear_tempo()
            return
        if not alive:
            self._clear_tempo()
            return

        self.phase_timer = max(0.0, self.phase_timer - dt)
        if self.phase == SquadPhase.IDLE:
            self._set_phase(SquadPhase.SET_FIRE_BASE, 0.8)
            return

        if self.phase == SquadPhase.SET_FIRE_BASE:
            base = self._actor_with_assignment(alive, SquadAssignment.BASE_OF_FIRE)
            base_ready = base is None or (base.mode.value != "moving" and not base.route)
            if base_ready and self.phase_timer <= 0.0:
                self._begin_next_bound(alive)
            return

        if self.phase == SquadPhase.BOUNDING:
            bound = next((actor for actor in alive if actor.id == self.bound_actor_id), None)
            bound_done = bound is None or (bound.mode.value != "moving" and not bound.route)
            if self.phase_timer <= 0.0 or (bound_done and self.phase_timer <= 1.6):
                if bound is not None:
                    self.last_bound_actor_id = bound.id
                self._set_phase(SquadPhase.CONSOLIDATE, 0.7)
            return

        if self.phase == SquadPhase.CONSOLIDATE and self.phase_timer <= 0.0:
            self._begin_next_bound(alive)

    def actor_can_bound(self, actor: "Actor") -> bool:
        return self.phase == SquadPhase.BOUNDING and self.bound_actor_id == actor.id

    def _begin_next_bound(self, actors: list["Actor"]) -> None:
        candidates = [
            actor
            for actor in actors
            if self.assignments.get(actor.id)
            in (SquadAssignment.CONTACT_LEAD, SquadAssignment.FLANK)
            and actor.suppression < 70.0
            and actor.weapon.ammo > 0
        ]
        if not candidates:
            self.bound_actor_id = None
            self._set_phase(SquadPhase.SET_FIRE_BASE, 0.8)
            return

        preferred = [actor for actor in candidates if actor.id != self.last_bound_actor_id]
        pool = preferred or candidates
        flank = next((actor for actor in pool if self.assignments.get(actor.id) == SquadAssignment.FLANK), None)
        lead = next((actor for actor in pool if self.assignments.get(actor.id) == SquadAssignment.CONTACT_LEAD), None)
        bound = flank or lead or pool[0]
        self.bound_actor_id = bound.id
        self._set_phase(SquadPhase.BOUNDING, 2.4)

    def _set_phase(self, phase: SquadPhase, timer: float) -> None:
        self.phase = phase
        self.phase_timer = timer
        if phase != SquadPhase.BOUNDING:
            self.bound_actor_id = None

    def _clear_tempo(self) -> None:
        self.phase = SquadPhase.IDLE
        self.phase_timer = 0.0
        self.bound_actor_id = None

    def _actor_with_assignment(
        self,
        actors: list["Actor"],
        assignment: SquadAssignment,
    ) -> "Actor" | None:
        return next((actor for actor in actors if self.assignments.get(actor.id) == assignment), None)

    def evaluate_posture(self, actors: list["Actor"], now: float) -> None:
        alive = [actor for actor in actors if actor.alive]
        if not alive:
            return
        if self.best_contact() is not None:
            return
        spread = self._spread(alive)
        wounded = sum(1 for actor in alive if self._is_wounded(actor))
        low_ammo = sum(1 for actor in alive if actor.weapon.ammo <= max(3, actor.weapon.spec.magazine_size // 8))
        recently_contacted = now - self.last_contact_time <= 7.0
        if spread > 7.0:
            self._begin_regroup("spread too far")
        elif recently_contacted and (wounded >= 1 or low_ammo >= 2):
            self._begin_regroup("recover after contact")
        elif recently_contacted and spread > 4.5:
            self._begin_regroup("reform after contact")

    def _begin_regroup(self, reason: str) -> None:
        self.posture = SquadPosture.REGROUP
        self.regroup_timer = max(self.regroup_timer, 5.0)
        self.regroup_reason = reason

    def _spread(self, actors: list["Actor"]) -> float:
        if len(actors) <= 1:
            return 0.0
        max_distance = 0.0
        for index, actor in enumerate(actors):
            for other in actors[index + 1 :]:
                max_distance = max(
                    max_distance,
                    hypot(actor.position.x - other.position.x, actor.position.y - other.position.y),
                )
        return max_distance

    def _is_wounded(self, actor: "Actor") -> bool:
        return any(actor.body.hp[part] < max_hp * 0.65 for part, max_hp in {
            "head": 35.0,
            "thorax": 85.0,
            "stomach": 70.0,
            "leftArm": 60.0,
            "rightArm": 60.0,
            "leftLeg": 65.0,
            "rightLeg": 65.0,
        }.items())

    def _pick_by_role(self, actors: list["Actor"], role_value: str) -> "Actor" | None:
        return next((actor for actor in actors if actor.role.value == role_value), None)

    def _closest_to_contact(self, actors: list["Actor"], contact: Contact) -> "Actor" | None:
        if not actors:
            return None
        return min(actors, key=lambda actor: actor.position.distance_to(contact.position))

    def add_contact(
        self,
        position: Vec2,
        source: str,
        confidence: float,
        now: float,
        enemy_id: int | None = None,
        expires_after: float = 5.0,
    ) -> None:
        if enemy_id is not None:
            existing = next((contact for contact in self.contacts if contact.enemy_id == enemy_id), None)
            if existing is not None:
                previous_confidence = existing.confidence
                existing.refresh(position, confidence, now)
                if confidence >= previous_confidence:
                    existing.source = source
                existing.expires_after = max(existing.expires_after, expires_after)
                return
        self.contacts.append(
            Contact(
                position=position,
                confidence=confidence,
                source=source,
                last_updated_time=now,
                enemy_id=enemy_id,
                expires_after=expires_after,
            )
        )

    def add_danger_zone(self, position: Vec2, radius: float, intensity: float, now: float) -> None:
        self.danger_zones.append(
            DangerZone(position=position, radius=radius, intensity=intensity, last_updated_time=now)
        )

    def best_contact(self) -> Contact | None:
        if not self.contacts:
            return None
        return max(self.contacts, key=lambda contact: (contact.confidence, contact.last_updated_time))
