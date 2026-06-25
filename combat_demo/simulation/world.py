from __future__ import annotations

from dataclasses import dataclass, field
from math import fabs, pi, radians
from random import Random

from .actor import (
    ActionType,
    Actor,
    ActorAction,
    ActorMode,
    ActorIntent,
    ActorRole,
    ActorState,
    AggressionPolicy,
    AmmoPolicy,
    CoverPolicy,
    FireMode,
    GrenadePolicy,
    IntentType,
    InterruptPolicy,
    MedicalPolicy,
    TacticProfile,
    Team,
)
from .ai_v2.commander import update_breach_ai
from .ai_v2.orders import AISystem, BreachMemory, BreachPlan
from .ai import can_see, update_ai
from .commands import ActorCommand
from .combat import ExplosionEvent, FloatingText, ShotEvent, SoundEvent, resolve_shot
from .geometry import Vec2, angle_difference, angle_to, rotate_toward
from .map import GridMap, create_breach_map, create_demo_map
from .movement import is_moving_between_cells, update_actor_movement
from .pose import actor_combat_position
from .squad import SquadMemory
from .weapon import RIFLE, WeaponState
from .world_commands import apply_actor_command, set_intent


@dataclass
class World:
    grid: GridMap
    actors: list[Actor]
    squads: dict[Team, SquadMemory]
    shots: list[ShotEvent] = field(default_factory=list)
    texts: list[FloatingText] = field(default_factory=list)
    sounds: list[SoundEvent] = field(default_factory=list)
    explosions: list[ExplosionEvent] = field(default_factory=list)
    time: float = 0.0
    tick_index: int = 0
    winner: Team | None = None
    rng: Random = field(default_factory=lambda: Random(7))
    ai_system: AISystem = AISystem.LEGACY
    breach_memory: BreachMemory | None = None

    def update(self, dt: float) -> None:
        if self.winner is not None:
            self._update_effects(dt)
            return

        self.time += dt
        self.tick_index += 1

        for squad in self.squads.values():
            squad.update(self.time, dt)
        for team, squad in self.squads.items():
            team_actors = [actor for actor in self.actors if actor.team == team]
            squad.evaluate_posture(team_actors, self.time)
            squad.update_assignments(team_actors)
            squad.update_tempo(team_actors, dt)

        for actor in self.actors:
            self._update_action(actor, dt)

        for actor in self.actors:
            if self.ai_system == AISystem.BREACH and self.breach_memory is not None:
                command = update_breach_ai(actor, self.actors, self.grid, self.breach_memory, dt)
            else:
                command = update_ai(actor, self.actors, self.grid, self.squads[actor.team], dt, self.tick_index, self.time)
            if command is not None:
                self.apply_command(command, dt)

        for actor in self.actors:
            if not actor.alive:
                continue
            if is_moving_between_cells(actor, self.grid):
                update_actor_movement(actor, self.grid, self.actors, dt)
            elif actor.mode == ActorMode.STANDING and actor.state == ActorState.ENGAGE and actor.target_id is not None:
                target = next((other for other in self.actors if other.id == actor.target_id), None)
                if target is not None and target.alive:
                    self._update_engagement(actor, target, dt)
            elif actor.mode == ActorMode.STANDING and actor.intent.type == IntentType.SUPPRESS and actor.intent.target_position is not None:
                self._update_suppression_fire(actor, actor.intent.target_position, dt)
            elif actor.current_action is not None:
                continue
            else:
                update_actor_movement(actor, self.grid, self.actors, dt)

        self._update_contact_sharing()
        self._update_effects(dt)
        self._check_winner()

    def apply_command(self, command: ActorCommand, dt: float = 0.0) -> None:
        actor = next((candidate for candidate in self.actors if candidate.id == command.actor_id), None)
        if actor is None or not actor.alive:
            return
        apply_actor_command(actor, self.actors, self.grid, command, dt)

    def _update_engagement(self, actor: Actor, target: Actor, dt: float) -> None:
        actor_position = actor_combat_position(actor)
        target_position = actor_combat_position(target)
        target_angle = angle_to(actor_position, target_position)
        actor.facing = rotate_toward(actor.facing, target_angle, actor.turn_speed * dt)
        self._update_aim(actor, target, dt)
        if not can_see(actor, target, self.grid):
            actor.state = ActorState.CHASE
            actor.last_known_enemy = target.position
            actor.last_known_timer = 5.0
            return
        if actor.weapon.ammo <= 0:
            self._begin_action(
                actor,
                ActorAction(
                    ActionType.RELOAD,
                    actor.weapon.spec.reload_time,
                    interrupt_policy=InterruptPolicy.HIT,
                ),
            )
            return
        if actor.current_action is not None:
            return
        if self._should_throw_grenade(actor, target):
            self._begin_action(
                actor,
                ActorAction(
                    ActionType.THROW_GRENADE,
                    duration=1.2,
                    target_position=target.position,
                    target_actor_id=target.id,
                    interrupt_policy=InterruptPolicy.NONE,
                ),
            )
            set_intent(actor, IntentType.ACTION, "throw grenade clustered threat", target_position=target.position, target_actor_id=target.id)
            return
        fire_mode, fire_reason = self._choose_fire_mode(actor, target)
        actor.fire_mode = fire_mode
        actor.fire_reason = fire_reason
        if fire_mode == FireMode.HOLD_FIRE:
            return
        aim_error = fabs(angle_difference(actor.facing, target_angle))
        aim_threshold = self._aim_threshold_for_mode(fire_mode)
        recoil_limit = self._recoil_limit_for_mode(fire_mode)
        if actor.recoil_error_degrees > recoil_limit:
            actor.fire_reason = "recovering recoil"
            return
        if aim_error < radians(aim_threshold) and actor.weapon.can_fire():
            total_error = (
                actor.weapon.spec.spread_degrees
                + actor.aim_error_degrees
                + actor.recoil_error_degrees * self._recoil_error_multiplier(fire_mode)
                + actor.suppression * 0.03
            )
            if fire_mode == FireMode.SUPPRESS:
                total_error += 2.5
            shot = resolve_shot(actor, target_position, self.grid, self.actors, self.rng, total_error)
            self.shots.append(shot)
            self.sounds.append(SoundEvent(actor.position, actor.team.value, actor.weapon.spec.gunshot_radius))
            actor.recoil_error_degrees = min(
                actor.max_recoil_degrees,
                actor.recoil_error_degrees + actor.recoil_per_shot_degrees * self._recoil_gain_multiplier(fire_mode),
            )
            if shot.hit_actor_id is not None and shot.hit_part is not None:
                victim = next(other for other in self.actors if other.id == shot.hit_actor_id)
                self._apply_hit_reaction(victim, actor, shot)
                self.texts.append(
                    FloatingText(victim.position + Vec2(0.0, -0.4), f"{shot.hit_part} -{shot.damage:g}")
                )
            self._apply_near_misses(actor, shot)
            self._notify_gunshot(actor)

    def _update_suppression_fire(self, actor: Actor, target_position: Vec2, dt: float) -> None:
        actor_position = actor_combat_position(actor)
        target_angle = angle_to(actor_position, target_position)
        actor.facing = rotate_toward(actor.facing, target_angle, actor.turn_speed * dt)
        actor.fire_mode = FireMode.SUPPRESS
        actor.fire_reason = "area suppression"
        if actor.weapon.ammo <= 0:
            self._begin_action(
                actor,
                ActorAction(
                    ActionType.RELOAD,
                    actor.weapon.spec.reload_time,
                    interrupt_policy=InterruptPolicy.HIT,
                ),
            )
            return
        if actor.current_action is not None:
            return
        if actor.recoil_error_degrees > self._recoil_limit_for_mode(FireMode.SUPPRESS):
            actor.fire_reason = "recovering recoil"
            return
        actor.aim_error_degrees = max(0.0, actor.aim_error_degrees - actor.aim_settle_degrees_per_second * dt)
        aim_error = fabs(angle_difference(actor.facing, target_angle))
        if aim_error < radians(self._aim_threshold_for_mode(FireMode.SUPPRESS)) and actor.weapon.can_fire():
            total_error = (
                actor.weapon.spec.spread_degrees
                + actor.aim_error_degrees
                + actor.recoil_error_degrees * self._recoil_error_multiplier(FireMode.SUPPRESS)
                + actor.suppression * 0.03
                + 2.5
            )
            shot = resolve_shot(actor, target_position, self.grid, self.actors, self.rng, total_error)
            self.shots.append(shot)
            self.sounds.append(SoundEvent(actor.position, actor.team.value, actor.weapon.spec.gunshot_radius))
            actor.recoil_error_degrees = min(
                actor.max_recoil_degrees,
                actor.recoil_error_degrees + actor.recoil_per_shot_degrees * self._recoil_gain_multiplier(FireMode.SUPPRESS),
            )
            if shot.hit_actor_id is not None and shot.hit_part is not None:
                victim = next(other for other in self.actors if other.id == shot.hit_actor_id)
                self._apply_hit_reaction(victim, actor, shot)
                self.texts.append(
                    FloatingText(victim.position + Vec2(0.0, -0.4), f"{shot.hit_part} -{shot.damage:g}")
                )
            self._apply_near_misses(actor, shot)
            self._notify_gunshot(actor)

    def _should_throw_grenade(self, actor: Actor, target: Actor) -> bool:
        if actor.grenades <= 0:
            return False
        if actor.tactics.grenade == GrenadePolicy.DISABLED:
            return False
        if actor.role == ActorRole.POINTMAN:
            return False
        if actor.suppression > 60.0:
            return False
        distance = actor_combat_position(actor).distance_to(actor_combat_position(target))
        max_distance = 10.0 if actor.tactics.grenade == GrenadePolicy.AGGRESSIVE else 8.5
        min_distance = 3.8 if actor.tactics.grenade == GrenadePolicy.AGGRESSIVE else 4.5
        if distance < min_distance or distance > max_distance:
            return False
        if self._friendly_in_blast_radius(actor, target.position, radius=2.1):
            return False
        nearby_enemies = [
            other
            for other in self.actors
            if other.alive and other.team != actor.team and other.position.distance_to(target.position) <= 2.1
        ]
        required_enemies = 1 if actor.tactics.grenade == GrenadePolicy.AGGRESSIVE else 2
        return len(nearby_enemies) >= required_enemies

    def _friendly_in_blast_radius(self, actor: Actor, position: Vec2, radius: float) -> bool:
        return any(
            other.alive
            and other.team == actor.team
            and other.id != actor.id
            and other.position.distance_to(position) <= radius + 0.25
            for other in self.actors
        )

    def _choose_fire_mode(self, actor: Actor, target: Actor) -> tuple[FireMode, str]:
        if self._friendly_fire_risk(actor, target):
            return FireMode.HOLD_FIRE, "friendly in line"
        distance = actor_combat_position(actor).distance_to(actor_combat_position(target))
        low_ammo_threshold = max(3, actor.weapon.spec.magazine_size // 8)
        if actor.tactics.ammo == AmmoPolicy.CONSERVE:
            low_ammo_threshold = max(low_ammo_threshold, actor.weapon.spec.magazine_size // 3)
        if actor.weapon.ammo <= low_ammo_threshold:
            return FireMode.AIMED_SHOT, "low ammo"
        rapid_distance = 5.5 if actor.tactics.aggression == AggressionPolicy.AGGRESSIVE else 4.0
        if actor.tactics.aggression == AggressionPolicy.CONSERVATIVE:
            rapid_distance = 2.8
        if distance <= rapid_distance and actor.tactics.ammo != AmmoPolicy.CONSERVE:
            return FireMode.RAPID_FIRE, "close target"
        if (
            (actor.role == ActorRole.SUPPORT or actor.tactics.ammo == AmmoPolicy.SUPPRESS)
            and actor.tactics.ammo != AmmoPolicy.CONSERVE
            and distance <= 12.0
            and actor.suppression < 45.0
        ):
            return FireMode.SUPPRESS, "support suppressing"
        aim_wait = 1.5 if actor.tactics.aggression == AggressionPolicy.AGGRESSIVE else 2.5
        if actor.tactics.aggression == AggressionPolicy.CONSERVATIVE:
            aim_wait = 3.5
        if actor.aim_error_degrees > aim_wait:
            return FireMode.AIMED_SHOT, "settling aim"
        return FireMode.AIMED_SHOT, "clear target"

    def _friendly_fire_risk(self, actor: Actor, target: Actor) -> bool:
        start = actor_combat_position(actor)
        end = actor_combat_position(target)
        segment = end - start
        length_sq = segment.x * segment.x + segment.y * segment.y
        if length_sq <= 0.00001:
            return False
        target_distance = start.distance_to(end)
        for ally in self.actors:
            if not ally.alive or ally.team != actor.team or ally.id == actor.id:
                continue
            to_ally = ally.position - start
            t = (to_ally.x * segment.x + to_ally.y * segment.y) / length_sq
            if t <= 0.0 or t >= 1.0:
                continue
            closest = start + segment * t
            if start.distance_to(ally.position) >= target_distance:
                continue
            if closest.distance_to(ally.position) <= ally.radius + 0.18:
                return True
        return False

    def _aim_threshold_for_mode(self, mode: FireMode) -> float:
        if mode == FireMode.RAPID_FIRE:
            return 14.0
        if mode == FireMode.SUPPRESS:
            return 12.0
        return 7.0

    def _recoil_limit_for_mode(self, mode: FireMode) -> float:
        if mode == FireMode.RAPID_FIRE:
            return 9.0
        if mode == FireMode.SUPPRESS:
            return 7.5
        return 4.0

    def _recoil_gain_multiplier(self, mode: FireMode) -> float:
        if mode == FireMode.RAPID_FIRE:
            return 1.35
        if mode == FireMode.SUPPRESS:
            return 1.15
        return 0.8

    def _recoil_error_multiplier(self, mode: FireMode) -> float:
        if mode == FireMode.RAPID_FIRE:
            return 1.25
        if mode == FireMode.SUPPRESS:
            return 1.35
        return 0.8

    def _begin_action(self, actor: Actor, action: ActorAction) -> None:
        if actor.current_action is None:
            actor.current_action = action
            actor.mode = ActorMode.ACTING

    def _update_action(self, actor: Actor, dt: float) -> None:
        if not actor.alive:
            return
        action = actor.current_action
        if action is None:
            return
        action.timer += dt
        if action.timer < action.duration:
            return
        if action.type == ActionType.RELOAD:
            actor.weapon.ammo = actor.weapon.spec.magazine_size
        elif action.type == ActionType.BANDAGE:
            self._complete_bandage(actor)
        elif action.type == ActionType.THROW_GRENADE and action.target_position is not None:
            self._complete_grenade(actor, action.target_position)
        elif action.type == ActionType.VAULT_LOW_WALL and action.target_position is not None:
            actor.position = action.target_position
            actor.aim_error_degrees = actor.max_aim_error_degrees
            actor.occupied_cell = self.grid.cell_of(action.target_position)
        elif action.type == ActionType.OPEN_DOOR and action.target_position is not None:
            self.grid.open_door_between(self.grid.cell_of(actor.position), self.grid.cell_of(action.target_position))
            actor.occupied_cell = self.grid.cell_of(actor.position)
        actor.current_action = None
        if actor.alive:
            actor.mode = ActorMode.STANDING
            actor.occupied_cell = actor.occupied_cell or self.grid.cell_of(actor.position)
            actor.position = self.grid.cell_center(actor.occupied_cell)

    def _complete_bandage(self, actor: Actor) -> None:
        if actor.bandages <= 0:
            return
        wounded_parts = [
            (part, max_hp - actor.body.hp[part])
            for part, max_hp in {
                "stomach": 70.0,
                "leftArm": 60.0,
                "rightArm": 60.0,
                "leftLeg": 65.0,
                "rightLeg": 65.0,
            }.items()
            if actor.body.hp[part] < max_hp
        ]
        if not wounded_parts:
            return
        part, missing = max(wounded_parts, key=lambda item: item[1])
        actor.body.hp[part] = min(actor.body.hp[part] + min(22.0, missing), actor.body.hp[part] + missing)
        actor.bandages -= 1
        actor.suppression = max(0.0, actor.suppression - 12.0)
        self.texts.append(FloatingText(actor.position + Vec2(0.0, -0.45), f"bandage {part} +{min(22.0, missing):g}"))

    def _complete_grenade(self, actor: Actor, position: Vec2) -> None:
        if actor.grenades <= 0:
            return
        actor.grenades -= 1
        radius = 2.1
        self.explosions.append(ExplosionEvent(position=position, radius=radius))
        self.sounds.append(SoundEvent(position, actor.team.value, radius=10.0, timer=0.45))
        for target in self.actors:
            if not target.alive:
                continue
            distance = target.position.distance_to(position)
            if distance > radius:
                continue
            damage = max(18.0, 72.0 * (1.0 - distance / radius))
            part = "thorax" if distance <= 0.9 else "stomach"
            target.body.damage(part, damage)
            target.suppression = min(100.0, target.suppression + 35.0)
            target.mark_dead_if_needed()
            self.texts.append(FloatingText(target.position + Vec2(0.0, -0.45), f"blast {part} -{damage:.0f}"))
            if target.team != actor.team:
                self.squads[target.team].add_contact(
                    actor.position,
                    source="explosion",
                    confidence=0.6,
                    now=self.time,
                    enemy_id=actor.id,
                    expires_after=4.0,
                )
                self.squads[target.team].add_danger_zone(position, radius=radius, intensity=1.0, now=self.time)

    def _update_aim(self, actor: Actor, target: Actor, dt: float) -> None:
        if actor.aim_target_id != target.id:
            actor.aim_target_id = target.id
            actor.aim_error_degrees = actor.max_aim_error_degrees
        actor.aim_error_degrees = max(
            0.0,
            actor.aim_error_degrees - actor.aim_settle_degrees_per_second * dt,
        )

    def _apply_hit_reaction(self, victim: Actor, shooter: Actor, shot: ShotEvent) -> None:
        victim.under_fire_position = shooter.position
        victim.under_fire_timer = 4.0
        victim.heard_position = shooter.position
        victim.heard_timer = max(victim.heard_timer, 3.0)
        victim.last_known_enemy = shooter.position
        victim.last_known_timer = max(victim.last_known_timer, 4.0)
        victim.suppression = min(100.0, victim.suppression + 18.0 + shot.damage * 0.25)
        victim.aim_error_degrees = min(
            victim.max_aim_error_degrees,
            victim.aim_error_degrees + 2.0,
        )
        if victim.current_action is not None and victim.current_action.interrupt_policy in (
            InterruptPolicy.HIT,
            InterruptPolicy.THREAT,
        ):
            interrupted = victim.current_action.type.value
            victim.current_action = None
            set_intent(victim, IntentType.ACTION, f"{interrupted} interrupted: hit")
        if victim.team != shooter.team:
            self.squads[victim.team].add_contact(
                shooter.position,
                source="hit_reaction",
                confidence=0.6,
                now=self.time,
                enemy_id=shooter.id,
                expires_after=4.0,
            )
            self.squads[victim.team].add_danger_zone(
                shooter.position,
                radius=2.0,
                intensity=0.7,
                now=self.time,
            )

    def _apply_near_misses(self, shooter: Actor, shot: ShotEvent) -> None:
        for near_miss in shot.near_misses:
            actor = next((candidate for candidate in self.actors if candidate.id == near_miss.actor_id), None)
            if actor is None or not actor.alive:
                continue
            suppression_gain = 4.0 + 14.0 * near_miss.intensity
            actor.suppression = min(100.0, actor.suppression + suppression_gain)
            actor.heard_position = shooter.position
            actor.heard_timer = max(actor.heard_timer, 2.0)
            if actor.under_fire_timer <= 0.0:
                actor.under_fire_position = shooter.position
                actor.under_fire_timer = 1.2
            self.squads[actor.team].add_danger_zone(
                shooter.position,
                radius=2.0,
                intensity=near_miss.intensity,
                now=self.time,
            )
            self.texts.append(FloatingText(actor.position + Vec2(0.0, -0.3), "near miss"))

    def _notify_gunshot(self, shooter: Actor) -> None:
        teams_that_heard: set[Team] = set()
        for actor in self.actors:
            if not actor.alive or actor.team == shooter.team:
                continue
            distance = actor.position.distance_to(shooter.position)
            if distance <= shooter.weapon.spec.gunshot_radius:
                error = Vec2(self.rng.uniform(-0.8, 0.8), self.rng.uniform(-0.8, 0.8))
                actor.heard_position = shooter.position + error
                actor.heard_timer = 6.0
                teams_that_heard.add(actor.team)
        for team in teams_that_heard:
            error = Vec2(self.rng.uniform(-0.8, 0.8), self.rng.uniform(-0.8, 0.8))
            self.squads[team].add_contact(
                shooter.position + error,
                source="gunshot",
                confidence=0.4,
                now=self.time,
                enemy_id=shooter.id,
                expires_after=4.0,
            )

    def _update_contact_sharing(self) -> None:
        for actor in self.actors:
            if not actor.alive:
                continue
            for other in self.actors:
                if can_see(actor, other, self.grid):
                    self.squads[actor.team].add_contact(
                        other.position,
                        source="ally_report",
                        confidence=0.8,
                        now=self.time,
                        enemy_id=other.id,
                        expires_after=5.0,
                    )

    def _update_effects(self, dt: float) -> None:
        for shot in self.shots:
            shot.timer -= dt
        self.shots = [shot for shot in self.shots if shot.timer > 0.0]
        for text in self.texts:
            text.timer -= dt
            text.position = text.position + Vec2(0.0, -0.25 * dt)
        self.texts = [text for text in self.texts if text.timer > 0.0]
        for sound in self.sounds:
            sound.timer -= dt
        self.sounds = [sound for sound in self.sounds if sound.timer > 0.0]
        for explosion in self.explosions:
            explosion.timer -= dt
        self.explosions = [explosion for explosion in self.explosions if explosion.timer > 0.0]

    def _check_winner(self) -> None:
        red_alive = any(actor.alive and actor.team == Team.RED for actor in self.actors)
        blue_alive = any(actor.alive and actor.team == Team.BLUE for actor in self.actors)
        if red_alive and not blue_alive:
            self.winner = Team.RED
        elif blue_alive and not red_alive:
            self.winner = Team.BLUE


def create_world() -> World:
    grid = create_demo_map()
    actors = [
        Actor(
            0,
            "Red 1",
            Team.RED,
            Vec2(1.5, 4.5),
            0.0,
            role=ActorRole.POINTMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.AGGRESSIVE, cover=CoverPolicy.CHASE),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            1,
            "Red 2",
            Team.RED,
            Vec2(1.5, 6.5),
            0.0,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            2,
            "Red 3",
            Team.RED,
            Vec2(2.5, 8.5),
            0.0,
            role=ActorRole.SUPPORT,
            tactics=TacticProfile(ammo=AmmoPolicy.SUPPRESS, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            3,
            "Blue 1",
            Team.BLUE,
            Vec2(18.5, 4.5),
            pi,
            role=ActorRole.POINTMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.CONSERVATIVE, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            4,
            "Blue 2",
            Team.BLUE,
            Vec2(18.5, 6.5),
            pi,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(grenade=GrenadePolicy.AGGRESSIVE),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            5,
            "Blue 3",
            Team.BLUE,
            Vec2(17.5, 8.5),
            pi,
            role=ActorRole.SUPPORT,
            tactics=TacticProfile(ammo=AmmoPolicy.CONSERVE, medical=MedicalPolicy.IGNORE_LIGHT),
            weapon=WeaponState.create(RIFLE),
        ),
    ]
    squads = {
        Team.RED: SquadMemory("red", objective_cell=(9, 6), rally_cell=(2, 6)),
        Team.BLUE: SquadMemory("blue", objective_cell=(10, 6), rally_cell=(17, 6)),
    }
    for actor in actors:
        actor.occupied_cell = grid.cell_of(actor.position)
        actor.position = grid.cell_center(actor.occupied_cell)
    return World(grid=grid, actors=actors, squads=squads)


def create_breach_world() -> World:
    grid = create_breach_map()
    actors = [
        Actor(
            0,
            "Breach 1",
            Team.RED,
            Vec2(3.5, 5.5),
            0.0,
            role=ActorRole.POINTMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.AGGRESSIVE, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            1,
            "Breach 2",
            Team.RED,
            Vec2(2.5, 5.5),
            0.0,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            2,
            "Breach 3",
            Team.RED,
            Vec2(3.5, 7.5),
            0.0,
            role=ActorRole.SUPPORT,
            tactics=TacticProfile(ammo=AmmoPolicy.SUPPRESS, cover=CoverPolicy.COVER_FIRST),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            3,
            "Trainee 1",
            Team.BLUE,
            Vec2(9.5, 3.5),
            pi,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.CONSERVATIVE, cover=CoverPolicy.COVER_FIRST, grenade=GrenadePolicy.DISABLED),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            4,
            "Trainee 2",
            Team.BLUE,
            Vec2(12.5, 5.5),
            pi,
            role=ActorRole.RIFLEMAN,
            tactics=TacticProfile(aggression=AggressionPolicy.CONSERVATIVE, cover=CoverPolicy.COVER_FIRST, grenade=GrenadePolicy.DISABLED),
            weapon=WeaponState.create(RIFLE),
        ),
        Actor(
            5,
            "Trainee 3",
            Team.BLUE,
            Vec2(10.5, 8.5),
            pi,
            role=ActorRole.SUPPORT,
            tactics=TacticProfile(aggression=AggressionPolicy.CONSERVATIVE, cover=CoverPolicy.COVER_FIRST, grenade=GrenadePolicy.DISABLED),
            weapon=WeaponState.create(RIFLE),
        ),
    ]
    squads = {
        Team.RED: SquadMemory("red", objective_cell=(9, 6), rally_cell=(3, 6)),
        Team.BLUE: SquadMemory("blue", objective_cell=(11, 6), rally_cell=(12, 6)),
    }
    for actor in actors:
        actor.occupied_cell = grid.cell_of(actor.position)
        actor.position = grid.cell_center(actor.occupied_cell)

    room_cells = tuple((x, y) for x in range(6, 15) for y in range(2, 10))
    plan = BreachPlan(
        team=Team.RED.value,
        stack_cells=((5, 5), (4, 5), (5, 7)),
        door_outside=(5, 5),
        door_inside=(6, 5),
        window_outside=(5, 7),
        window_inside=(6, 7),
        entry_cells=((7, 4), (7, 6), (6, 7)),
        room_cover_cells=((8, 4), (8, 6), (12, 6)),
        room_cells=room_cells,
        focus=Vec2(10.5, 5.8),
    )
    return World(
        grid=grid,
        actors=actors,
        squads=squads,
        ai_system=AISystem.BREACH,
        breach_memory=BreachMemory(plan),
    )
