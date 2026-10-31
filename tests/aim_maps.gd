extends SceneTree
var failures = 0
var checks = 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)
	else:
		print("PASS: " + title)
func run() -> void:
	var template = load("res://data/ashen_garden.tres")
	var original = template.walkable_regions.duplicate()
	var valid = true
	var layouts = {}
	seed(99)
	var expected_random = randf()
	seed(99)
	for number in range(100):
		var level = JourneyMap.generate(template, number)
		var map = JourneyMap.new(level)
		layouts[str(level.walkable_regions)] = true
		valid = valid and map.contains(level.spawn_point, 34) and map.contains(level.exit_point, 34)
		valid = valid and map.line_clear(level.spawn_point, level.exit_point, 34)
		valid = valid and level.walkable_regions == JourneyMap.generate(template, number).walkable_regions
		for center in level.encounter_centers:
			for step in range(12):
				valid = valid and map.contains(center + Vector2(cos(step * TAU / 12) * 280, sin(step * TAU / 12) * 170), 34)
	check(valid and layouts.size() == 100, "100 seeds are distinct, deterministic, connected and safe for spawns")
	check(randf() == expected_random and template.walkable_regions == original, "Map generation preserves loot RNG and shared template")
	var game = load("res://scenes/main.tscn").instantiate()
	game.map_seed = 99
	root.add_child(game)
	game.set_process(false)
	game.player.position = game.level.encounter_centers[0]
	var hero: Hero = game.player
	var slash = load("res://data/abilities/slash.tres")
	var fireball = load("res://data/abilities/fireball.tres")
	var nova = load("res://data/abilities/frost_nova.tres")
	var front = game.spawn_enemy("melee", hero.position + Vector2(85, 10))
	var back = game.spawn_enemy("melee", hero.position + Vector2(-45, 0))
	check(AimAssist.choose(hero, slash, game.enemies, game.world_map, Vector2.RIGHT, false) == front, "Mouse assistance chooses a nearby enemy inside the forward cone")
	front.position = hero.position + Vector2(0, 85)
	check(AimAssist.choose(hero, slash, game.enemies, game.world_map, Vector2.RIGHT, false) == null, "Mouse assistance does not snap to side or rear enemies")
	check(AimAssist.choose(hero, slash, game.enemies, game.world_map, Vector2.RIGHT, true) == back, "Automatic aiming falls back to nearest surrounding enemy")
	front.position = hero.position + Vector2(100, 0)
	check(AimAssist.choose(hero, slash, game.enemies, game.world_map, Vector2.RIGHT, true) == front, "Automatic aiming prefers forward enemies")
	front.dead = true
	check(AimAssist.choose(hero, slash, game.enemies, game.world_map, Vector2.RIGHT, false) == null, "Dead targets are ignored")
	front.dead = false
	front.position = hero.position + Vector2(400, 0)
	check(AimAssist.choose(hero, slash, game.enemies, game.world_map, Vector2.RIGHT, false) == null and AimAssist.choose(hero, fireball, game.enemies, game.world_map, Vector2.RIGHT, false) == front, "Melee and ranged assistance use their own reach")
	check(AimAssist.choose(hero, nova, game.enemies, game.world_map, Vector2.RIGHT, true) == null, "Frost Nova keeps its self-centered behavior")
	front.position = hero.position + Vector2(700, 0)
	check(AimAssist.choose(hero, fireball, game.enemies, game.world_map, Vector2.RIGHT, false) == null, "Out-of-range enemies are excluded")
	var room: Rect2 = game.level.walkable_regions[1]
	hero.position = Vector2(room.end.x - 60, room.position.y + 60)
	front.position = hero.position + Vector2(170, 0)
	check(AimAssist.choose(hero, fireball, game.enemies, game.world_map, Vector2.RIGHT, false) == null, "Targets across nonwalkable terrain are excluded")
	game.equipment.slots.weapon = Gear.new(Catalog.item("iron_blade"))
	game.clear_attack_input()
	check(not game.assisted_attack("weapon"), "Clearing held inputs blocks accidental casts after pause or transition")
	game.input_blocked = false
	game.bag_open = true
	check(not game.assisted_attack("weapon"), "Paused inventory blocks assisted attacks")
	game.bag_open = false
	var regions = game.level.walkable_regions.duplicate()
	var saved_seed: int = game.map_seed
	game.state = "defeat"
	game.restart()
	check(game.map_seed == saved_seed and game.level.walkable_regions == regions, "Defeat retry keeps the exact layout and seed")
	game.state = "victory"
	game.restart()
	check(game.map_seed != saved_seed and game.level.walkable_regions != regions and game.player.world_map == game.world_map, "Successful exit regenerates layout and reconnects hero collision map")
	game.queue_free()
	await process_frame
	print("AIM/MAPS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
