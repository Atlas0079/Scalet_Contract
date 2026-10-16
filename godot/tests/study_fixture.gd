extends RefCounted

# Local isolated stage for kinematics/ballistics tests; arena integration has
# its own tests using the actual targets, dimensions and collision geometry.
static func target_fixture() -> Dictionary:
	return {"id":"calibration", "label":"校准靶", "position":Vector2(0, -2.5), "radius":0.23, "height":1.8, "hits":0}

static func reset(scene):
	scene.reset()
	scene.arena_bounds = Rect2(-20, -20, 50, 40)
	scene.simulation.grid.bounds=scene.arena_bounds
	for id in scene.simulation.entities.keys():
		if scene.simulation.entities[id].actor==null: scene.simulation.entities.erase(id)
	for y in range(-20,20):
		for x in range(-20,30): scene.simulation.grid.cells[Vector2i(x,y)]={"passable":true,"movement_multiplier":1.0,"ground_height_m":0.0,"cover_height_m":0.0}
	scene.world_position = Vector2.ZERO
	scene.facing = -PI / 2
	scene.desired_facing = scene.facing
	scene.target = Vector2(0, -2.5)
	for unit in scene.units:
		unit.effects.obstacles.clear()
		if unit.effects.target_by_id("calibration").is_empty(): unit.effects.targets.append(target_fixture())
		unit.effects.target_by_id("calibration").position = scene.target
		unit.effects.selected_target_id = "calibration"
	scene.update_visual_positions()

static func configure_fx(fx):
	fx.targets.assign([target_fixture()])
	fx.obstacles.clear()
	fx.simulation.entities.clear()

static func zero_aim(actor):
	for key in ["aim_unsettled_degrees","aim_settled_degrees"]:
		var c := SCAbilityRules.contribution(key,"capability",key,0,"bonus","factor")
		actor.sources.append(SCAbilityRules.source("test:zero:"+key,"actor",actor.identity,"trait","body",[c]))
	actor.refresh_capabilities()

static func zero_capacity(actor):
	var c := SCAbilityRules.contribution("capacity","capability","carry_capacity_kg",0,"bonus","factor")
	actor.sources.append(SCAbilityRules.source("test:capacity","actor",actor.identity,"trait","body",[c]))
	actor.refresh_capabilities()
