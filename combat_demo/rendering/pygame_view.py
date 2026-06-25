from __future__ import annotations

from dataclasses import replace
from math import cos, sin

import pygame

from simulation.actor import (
    Actor,
    ActorMode,
    ActorState,
    AggressionPolicy,
    AmmoPolicy,
    BODY_MAX_HP,
    CoverPolicy,
    GrenadePolicy,
    MedicalPolicy,
    Team,
)
from simulation.geometry import Vec2, from_angle
from simulation.map import GridMap, WallKind
from simulation.pose import actor_combat_position
from simulation.world import World, create_world


CELL = 42
PANEL_W = 270
TOP_PAD = 18
LEFT_PAD = 18
BG = (22, 24, 27)
GRID = (50, 54, 61)
TEXT = (224, 226, 230)
MUTED = (145, 151, 162)
RED = (218, 78, 78)
BLUE = (78, 130, 224)
LOW = (214, 182, 91)
FULL = (230, 235, 242)
DOOR_CLOSED = (114, 192, 168)
DOOR_OPEN = (77, 112, 105)


class PygameView:
    def __init__(self, world_or_factory=create_world, scenario_name: str = "demo") -> None:
        pygame.init()
        self.world_factory = world_or_factory if callable(world_or_factory) else lambda: world_or_factory
        self.scenario_name = scenario_name
        self.world = self.world_factory()
        self.screen = pygame.display.set_mode(
            (LEFT_PAD * 2 + self.world.grid.width * CELL + PANEL_W, TOP_PAD * 2 + self.world.grid.height * CELL)
        )
        pygame.display.set_caption("Automatic Team Deathmatch Demo")
        self.clock = pygame.time.Clock()
        self.font = pygame.font.SysFont("consolas", 16)
        self.small = pygame.font.SysFont("consolas", 13)
        self.selected_id: int | None = None
        self.paused = False
        self.show_vision = True
        self.show_lines = True

    def run(self) -> None:
        running = True
        while running:
            dt = self.clock.tick(60) / 1000.0
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_SPACE:
                        self.paused = not self.paused
                    elif event.key == pygame.K_v:
                        self.show_vision = not self.show_vision
                    elif event.key == pygame.K_l:
                        self.show_lines = not self.show_lines
                    elif event.key == pygame.K_r:
                        self.world = self.world_factory()
                        self.selected_id = None
                    elif event.key in (pygame.K_1, pygame.K_2, pygame.K_3, pygame.K_4, pygame.K_5):
                        self._cycle_selected_tactic(event.key)
                elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                    self._select_at(Vec2(*event.pos))

            if not self.paused:
                self.world.update(dt)
            self.draw()
        pygame.quit()

    def to_screen(self, pos: Vec2) -> tuple[int, int]:
        return (int(LEFT_PAD + pos.x * CELL), int(TOP_PAD + pos.y * CELL))

    def from_screen(self, pos: Vec2) -> Vec2:
        return Vec2((pos.x - LEFT_PAD) / CELL, (pos.y - TOP_PAD) / CELL)

    def draw(self) -> None:
        self.screen.fill(BG)
        self._draw_grid(self.world.grid)
        if self.show_vision:
            self._draw_vision()
        if self.show_lines:
            self._draw_debug_lines()
        self._draw_effects()
        self._draw_actors()
        self._draw_panel()
        pygame.display.flip()

    def _draw_grid(self, grid: GridMap) -> None:
        rect = pygame.Rect(LEFT_PAD, TOP_PAD, grid.width * CELL, grid.height * CELL)
        pygame.draw.rect(self.screen, (30, 33, 38), rect)
        for x in range(grid.width + 1):
            sx = LEFT_PAD + x * CELL
            pygame.draw.line(self.screen, GRID, (sx, TOP_PAD), (sx, TOP_PAD + grid.height * CELL), 1)
        for y in range(grid.height + 1):
            sy = TOP_PAD + y * CELL
            pygame.draw.line(self.screen, GRID, (LEFT_PAD, sy), (LEFT_PAD + grid.width * CELL, sy), 1)

        for x in range(grid.width):
            for y in range(grid.height):
                cell = (x, y)
                px = LEFT_PAD + x * CELL
                py = TOP_PAD + y * CELL
                self._draw_wall_segment(grid.wall_at(cell, "N"), (px, py), (px + CELL, py))
                self._draw_wall_segment(grid.wall_at(cell, "W"), (px, py), (px, py + CELL))
                if y == grid.height - 1:
                    self._draw_wall_segment(grid.wall_at(cell, "S"), (px, py + CELL), (px + CELL, py + CELL))
                if x == grid.width - 1:
                    self._draw_wall_segment(grid.wall_at(cell, "E"), (px + CELL, py), (px + CELL, py + CELL))

    def _draw_wall_segment(self, kind: WallKind, a: tuple[int, int], b: tuple[int, int]) -> None:
        if kind == WallKind.NONE:
            return
        if kind == WallKind.FULL:
            color = FULL
            width = 5
        elif kind == WallKind.LOW:
            color = LOW
            width = 3
        elif kind == WallKind.DOOR_CLOSED:
            color = DOOR_CLOSED
            width = 5
        else:
            color = DOOR_OPEN
            width = 2
        pygame.draw.line(self.screen, color, a, b, width)

    def _draw_vision(self) -> None:
        red_mask = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
        blue_mask = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
        for actor in self.world.actors:
            if not actor.alive:
                continue
            center = self.to_screen(actor.position)
            points = [center]
            steps = 18
            start = actor.facing - actor.view_angle / 2.0
            for i in range(steps + 1):
                angle = start + actor.view_angle * (i / steps)
                edge = actor.position + from_angle(angle) * actor.view_distance
                points.append(self.to_screen(edge))
            surface = red_mask if actor.team == Team.RED else blue_mask
            pygame.draw.polygon(surface, (255, 255, 255, 255), points)

        red_area = pygame.mask.from_surface(red_mask)
        blue_area = pygame.mask.from_surface(blue_mask)
        overlap_area = red_area.overlap_mask(blue_area, (0, 0))
        red_only = red_area.copy()
        blue_only = blue_area.copy()
        red_only.erase(overlap_area, (0, 0))
        blue_only.erase(overlap_area, (0, 0))

        red_view = red_only.to_surface(setcolor=(218, 78, 78, 14), unsetcolor=(0, 0, 0, 0))
        blue_view = blue_only.to_surface(setcolor=(78, 130, 224, 14), unsetcolor=(0, 0, 0, 0))
        overlap_view = overlap_area.to_surface(setcolor=(150, 104, 190, 22), unsetcolor=(0, 0, 0, 0))

        overlay = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
        overlay.blit(red_view, (0, 0))
        overlay.blit(blue_view, (0, 0))
        overlay.blit(overlap_view, (0, 0))
        self.screen.blit(overlay, (0, 0))

    def _draw_debug_lines(self) -> None:
        overlay = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
        for actor in self.world.actors:
            if not actor.alive:
                continue
            start = self.to_screen(actor_combat_position(actor))
            if actor.target_id is not None:
                target = next((other for other in self.world.actors if other.id == actor.target_id), None)
                if target is not None:
                    pygame.draw.line(overlay, (235, 238, 242, 115), start, self.to_screen(actor_combat_position(target)), 1)
            elif actor.last_known_enemy is not None and actor.last_known_timer > 0.0:
                pygame.draw.line(overlay, (160, 166, 176, 100), start, self.to_screen(actor.last_known_enemy), 1)
            elif actor.heard_position is not None and actor.heard_timer > 0.0:
                pygame.draw.line(overlay, (220, 182, 88, 115), start, self.to_screen(actor.heard_position), 1)
        self.screen.blit(overlay, (0, 0))

    def _draw_effects(self) -> None:
        for sound in self.world.sounds:
            alpha = max(20, int(100 * sound.timer / 0.25))
            surface = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
            pygame.draw.circle(surface, (235, 210, 110, alpha), self.to_screen(sound.position), int(sound.radius * CELL), 1)
            self.screen.blit(surface, (0, 0))
        for explosion in self.world.explosions:
            progress = 1.0 - max(0.0, min(1.0, explosion.timer / explosion.duration))
            alpha = max(20, int(180 * (1.0 - progress)))
            surface = pygame.Surface(self.screen.get_size(), pygame.SRCALPHA)
            radius = int(explosion.radius * CELL * (0.35 + progress * 0.65))
            pygame.draw.circle(surface, (245, 166, 78, alpha), self.to_screen(explosion.position), radius, 2)
            pygame.draw.circle(surface, (255, 224, 132, alpha), self.to_screen(explosion.position), max(4, radius // 4))
            self.screen.blit(surface, (0, 0))
        for shot in self.world.shots:
            color = (255, 235, 125) if not shot.blocked else (170, 170, 176)
            progress = 1.0 - max(0.0, min(1.0, shot.timer / shot.duration))
            head = shot.start + (shot.end - shot.start) * progress
            tail_progress = max(0.0, progress - 0.16)
            tail = shot.start + (shot.end - shot.start) * tail_progress
            pygame.draw.line(self.screen, color, self.to_screen(tail), self.to_screen(head), 3)
            pygame.draw.circle(self.screen, color, self.to_screen(head), 3)
            if shot.blocked and progress > 0.92:
                pygame.draw.circle(self.screen, (230, 230, 220), self.to_screen(shot.end), 5, 1)
        for text in self.world.texts:
            image = self.small.render(text.text, True, (255, 225, 160))
            self.screen.blit(image, self.to_screen(text.position))

    def _draw_actors(self) -> None:
        for actor in self.world.actors:
            color = RED if actor.team == Team.RED else BLUE
            if not actor.alive:
                color = (80, 80, 86)
            combat_center = actor_combat_position(actor)
            center = self.to_screen(combat_center)
            radius = int(actor.radius * CELL)
            if actor.peek_direction is not None:
                pygame.draw.circle(self.screen, (92, 96, 104), self.to_screen(actor.position), radius, 1)
                pygame.draw.line(self.screen, (210, 214, 220), self.to_screen(actor.position), center, 1)
            pygame.draw.circle(self.screen, color, center, radius)
            pygame.draw.circle(self.screen, (14, 15, 18), center, radius, 2)
            if self.selected_id == actor.id:
                pygame.draw.circle(self.screen, (255, 255, 255), center, radius + 5, 2)
            tip = combat_center + Vec2(cos(actor.facing), sin(actor.facing)) * 0.48
            pygame.draw.line(self.screen, (255, 255, 255), center, self.to_screen(tip), 2)
            label = self.small.render(str(actor.id + 1), True, (255, 255, 255))
            self.screen.blit(label, (center[0] - 5, center[1] - 8))

    def _draw_panel(self) -> None:
        x = LEFT_PAD + self.world.grid.width * CELL + 18
        y = TOP_PAD
        fps = int(self.clock.get_fps())
        title = f"Team Deathmatch [{self.scenario_name}]"
        self.screen.blit(self.font.render(title, True, TEXT), (x, y))
        y += 26
        status = "PAUSED" if self.paused else "RUNNING"
        if self.world.winner is not None:
            status = f"{self.world.winner.value.upper()} WINS"
        self.screen.blit(self.small.render(f"{status}  FPS:{fps}", True, MUTED), (x, y))
        y += 24
        ai_text = f"ai: {self.world.ai_system.value}"
        if self.world.breach_memory is not None:
            ai_text += f" {self.world.breach_memory.stage.value}"
        self.screen.blit(self.small.render(ai_text, True, MUTED), (x, y))
        y += 18
        self.screen.blit(self.small.render("R reset | Space pause", True, MUTED), (x, y))
        y += 18
        self.screen.blit(self.small.render("V vision | L lines", True, MUTED), (x, y))
        y += 28
        self.screen.blit(self.small.render("Selected tactics: 1-5 cycle", True, MUTED), (x, y))
        y += 22
        y = self._draw_legend(x, y)
        y += 12

        selected = next((actor for actor in self.world.actors if actor.id == self.selected_id), None)
        if selected is None:
            self.screen.blit(self.font.render("Select an actor", True, TEXT), (x, y))
            y += 26
            for actor in self.world.actors:
                alive = "alive" if actor.alive else "dead"
                line = f"{actor.id + 1} {actor.name}: {actor.mode.value}/{actor.state.value} {alive}"
                self.screen.blit(self.small.render(line, True, TEXT), (x, y))
                y += 18
            return

        self.screen.blit(self.font.render(selected.name, True, TEXT), (x, y))
        y += 24
        self.screen.blit(self.small.render(f"team: {selected.team.value}", True, MUTED), (x, y))
        y += 18
        self.screen.blit(self.small.render(f"role: {selected.role.value}", True, MUTED), (x, y))
        y += 18
        tactic_text = (
            f"tactic: {selected.tactics.aggression.value}/"
            f"{selected.tactics.ammo.value}/"
            f"{selected.tactics.cover.value}"
        )
        self.screen.blit(self.small.render(tactic_text, True, MUTED), (x, y))
        y += 18
        tool_text = f"tools: grenade {selected.tactics.grenade.value}, med {selected.tactics.medical.value}"
        self.screen.blit(self.small.render(tool_text, True, MUTED), (x, y))
        y += 18
        squad = self.world.squads[selected.team]
        self.screen.blit(
            self.small.render(
                f"squad: {squad.posture.value} contacts:{len(squad.contacts)}",
                True,
                MUTED,
            ),
            (x, y),
        )
        y += 18
        assignment = squad.assignment_for(selected)
        self.screen.blit(
            self.small.render(f"assignment: {assignment.value if assignment else 'none'}", True, MUTED),
            (x, y),
        )
        y += 18
        bound_text = squad.bound_actor_id + 1 if squad.bound_actor_id is not None else "none"
        self.screen.blit(
            self.small.render(f"phase: {squad.phase.value} bound:{bound_text}", True, MUTED),
            (x, y),
        )
        y += 18
        self.screen.blit(self.small.render(f"danger zones: {len(squad.danger_zones)}", True, MUTED), (x, y))
        y += 18
        if squad.regroup_reason:
            self.screen.blit(self.small.render(f"regroup: {squad.regroup_reason}", True, MUTED), (x, y))
            y += 18
        self.screen.blit(self.small.render(f"state: {selected.state.value}", True, MUTED), (x, y))
        y += 18
        self.screen.blit(self.small.render(f"mode: {selected.mode.value}", True, MUTED), (x, y))
        y += 18
        peek_text = selected.peek_direction.value if selected.peek_direction is not None else "none"
        self.screen.blit(self.small.render(f"peek: {peek_text}", True, MUTED), (x, y))
        y += 18
        self.screen.blit(self.small.render(f"intent: {selected.intent.label}", True, MUTED), (x, y))
        y += 18
        intent_target = selected.intent.target_cell
        if intent_target is None and selected.intent.target_position is not None:
            intent_target = (
                round(selected.intent.target_position.x, 1),
                round(selected.intent.target_position.y, 1),
            )
        self.screen.blit(self.small.render(f"intent target: {intent_target}", True, MUTED), (x, y))
        y += 18
        action_text = "none"
        if selected.current_action is not None:
            action_text = (
                f"{selected.current_action.type.value} "
                f"{selected.current_action.progress * 100:3.0f}% "
                f"{selected.current_action.interrupt_policy.value}"
            )
        self.screen.blit(self.small.render(f"action: {action_text}", True, MUTED), (x, y))
        y += 18
        self.screen.blit(self.small.render(f"grenades/bandages: {selected.grenades}/{selected.bandages}", True, MUTED), (x, y))
        y += 18
        self.screen.blit(self.small.render(f"ammo: {selected.weapon.ammo}/{selected.weapon.spec.magazine_size}", True, MUTED), (x, y))
        y += 18
        self.screen.blit(
            self.small.render(
                f"fire: {selected.fire_mode.value} ({selected.fire_reason})",
                True,
                MUTED,
            ),
            (x, y),
        )
        y += 18
        self.screen.blit(
            self.small.render(
                f"aim/recoil: {selected.aim_error_degrees:4.1f}/{selected.recoil_error_degrees:4.1f} deg",
                True,
                MUTED,
            ),
            (x, y),
        )
        y += 18
        cell_text = (
            f"occ:{selected.occupied_cell} res:{selected.reserved_cell} "
            f"to:{selected.move_to} p:{selected.move_progress:3.2f}"
        )
        self.screen.blit(self.small.render(cell_text, True, MUTED), (x, y))
        y += 18
        self.screen.blit(self.small.render(f"target cell: {selected.target_cell}", True, MUTED), (x, y))
        y += 18
        self.screen.blit(
            self.small.render(
                f"cover: {selected.cover_score:4.1f} {selected.cover_reason}",
                True,
                MUTED,
            ),
            (x, y),
        )
        y += 18
        self.screen.blit(
            self.small.render(
                f"supp/underfire: {selected.suppression:4.1f}/{selected.under_fire_timer:3.1f}",
                True,
                MUTED,
            ),
            (x, y),
        )
        y += 26
        for part, max_hp in BODY_MAX_HP.items():
            hp = selected.body.hp[part]
            label = f"{part:8} {hp:5.1f}/{max_hp:g}"
            self.screen.blit(self.small.render(label, True, TEXT), (x, y))
            bar_x = x + 124
            bar_y = y + 3
            pygame.draw.rect(self.screen, (62, 66, 74), (bar_x, bar_y, 96, 8))
            fill = int(96 * max(0.0, hp / max_hp))
            pygame.draw.rect(self.screen, (104, 196, 126), (bar_x, bar_y, fill, 8))
            y += 18

    def _draw_legend(self, x: int, y: int) -> int:
        self.screen.blit(self.font.render("Line Legend", True, TEXT), (x, y))
        y += 24
        items = [
            ((235, 238, 242), "white: current target"),
            ((160, 166, 176), "gray: last known enemy"),
            ((220, 182, 88), "yellow: heard gunshot"),
            ((255, 235, 125), "bright yellow: bullet"),
        ]
        for color, label in items:
            pygame.draw.line(self.screen, color, (x, y + 8), (x + 32, y + 8), 2)
            self.screen.blit(self.small.render(label, True, MUTED), (x + 42, y))
            y += 18
        return y

    def _select_at(self, screen_pos: Vec2) -> None:
        world_pos = self.from_screen(screen_pos)
        best: tuple[float, Actor] | None = None
        for actor in self.world.actors:
            distance = actor.position.distance_to(world_pos)
            if distance <= actor.radius + 0.2:
                if best is None or distance < best[0]:
                    best = (distance, actor)
        self.selected_id = best[1].id if best else None

    def _cycle_selected_tactic(self, key: int) -> None:
        actor = next((candidate for candidate in self.world.actors if candidate.id == self.selected_id), None)
        if actor is None:
            return
        if key == pygame.K_1:
            actor.tactics = replace(actor.tactics, aggression=self._next_enum(actor.tactics.aggression, AggressionPolicy))
        elif key == pygame.K_2:
            actor.tactics = replace(actor.tactics, ammo=self._next_enum(actor.tactics.ammo, AmmoPolicy))
        elif key == pygame.K_3:
            actor.tactics = replace(actor.tactics, cover=self._next_enum(actor.tactics.cover, CoverPolicy))
        elif key == pygame.K_4:
            actor.tactics = replace(actor.tactics, grenade=self._next_enum(actor.tactics.grenade, GrenadePolicy))
        elif key == pygame.K_5:
            actor.tactics = replace(actor.tactics, medical=self._next_enum(actor.tactics.medical, MedicalPolicy))

    def _next_enum(self, current, enum_type):
        values = list(enum_type)
        return values[(values.index(current) + 1) % len(values)]
