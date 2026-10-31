class_name JourneyMap
extends RefCounted

var definition: LevelDefinition
var bounds: Rect2

func _init(level: LevelDefinition) -> void:
	definition = level
	bounds = level.walkable_regions[0]
	for region in level.walkable_regions:
		bounds = bounds.merge(region)

func contains(point: Vector2, radius: float = 0.0) -> bool:
	for region in definition.walkable_regions:
		if region.grow(-radius).has_point(point):
			return true
	return false

func move_actor(point: Vector2, displacement: Vector2, radius: float) -> Vector2:
	# Small steps prevent tunnelling across the grass; axes slide along trail edges.
	var steps = maxi(1, ceili(displacement.length() / 10.0))
	var step = displacement / steps
	for index in range(steps):
		var next = point + Vector2(step.x, 0)
		if contains(next, radius):
			point = next
		next = point + Vector2(0, step.y)
		if contains(next, radius):
			point = next
	return point

func line_clear(from: Vector2, to: Vector2, radius: float = 0.0) -> bool:
	var steps = maxi(1, ceili(from.distance_to(to) / 20.0))
	for index in range(steps + 1):
		if not contains(from.lerp(to, float(index) / steps), radius):
			return false
	return true

func steer(from: Vector2, to: Vector2, radius: float) -> Vector2:
	if line_clear(from, to, radius):
		return from.direction_to(to)
	# All trails meet the central road. Use it when a direct route crosses grass.
	var road_y = definition.spawn_point.y
	if absf(from.y - road_y) > 12:
		return from.direction_to(Vector2(from.x, road_y))
	return from.direction_to(Vector2(to.x, road_y))

static func generate(template: LevelDefinition, map_seed: int) -> LevelDefinition:
	var result = template.duplicate(true) as LevelDefinition
	var rng = RandomNumberGenerator.new()
	rng.seed = map_seed
	result.walkable_regions.clear()
	result.walkable_regions.append(Rect2(48, 279, 520, 320))
	result.encounter_centers = PackedVector2Array()
	result.encounter_triggers = PackedFloat32Array()
	var left = 472.0
	for index in range(3):
		var width = rng.randi_range(720, 960)
		var height = rng.randi_range(440, 594)
		var room = Rect2(left, 439 - height / 2.0, width, height)
		result.walkable_regions.append(room)
		result.encounter_centers.append(room.get_center())
		result.encounter_triggers.append(left + 60)
		if index < 2:
			var gap = rng.randi_range(180, 360)
			var trail_width = rng.randi_range(200, 280)
			result.walkable_regions.append(Rect2(room.end.x - 96, 439 - trail_width / 2.0, gap + 192, trail_width))
			left = room.end.x + gap
		else:
			var exit_region = Rect2(room.end.x - 96, 329, 450, 220)
			result.walkable_regions.append(exit_region)
			result.exit_point = Vector2(exit_region.end.x - 150, 439)
	return result
