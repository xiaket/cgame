extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func fixture(id: String) -> Gear:
	var gear = Gear.new(Catalog.item(id), 0, 1, false)
	var key = "magic_attack" if id in ["ember_wand", "frost_orb"] else "physical_attack"
	gear.primary_affixes.append({"id": "health" if id == "oak_helm" else key, "value": 18.0 if id == "oak_helm" else 7.0})
	return gear

func run() -> void:
	for build in [["crescent_axe", "frost_orb", 713], ["ember_wand", "frost_orb", 713], ["crescent_axe", "frost_orb", 99], ["ember_wand", "frost_orb", 99], ["crescent_axe", "frost_orb", 2026], ["ember_wand", "frost_orb", 2026]]:
		seed(713)
		var game = load("res://scenes/main.tscn").instantiate()
		game.map_seed = build[2]
		root.add_child(game)
		game.set_process(false)
		game.expedition = 1
		game.equipment.slots.helmet = fixture("oak_helm")
		game.equipment.slots.necklace = fixture("ruby_pendant")
		game.equipment.slots.weapon = fixture(build[0])
		game.equipment.slots.offhand = fixture(build[1])
		game.player.recalculate()
		game.player.health = game.player.max_health
		await process_frame
		var dt = 1.0 / 60.0
		var duration = 0.0
		var completed_kills = []
		game.events.level_completed.connect(func(_number): completed_kills.append(game.kills))
		while duration < 360 and game.state == "combat" and game.expedition == 1:
			duration += dt
			var nearest: ArenaEnemy = null
			var nearest_distance = INF
			for enemy in game.enemies:
				var distance = enemy.position.distance_to(game.player.position)
				if distance < nearest_distance:
					nearest = enemy
					nearest_distance = distance
			var destination: Vector2 = game.level.exit_point if game.wave == 3 else Vector2(game.level.encounter_triggers[game.wave] + 100, 439)
			var movement = game.player.position.direction_to(destination) if game.player.position.distance_to(destination) > 6 else Vector2.ZERO
			if nearest != null:
				var toward: Vector2 = game.player.position.direction_to(nearest.position)
				var desired_range = 78.0 if build[0] == "crescent_axe" else 260.0
				if nearest_distance > desired_range + 15:
					movement = toward
				elif nearest_distance < desired_range - 10:
					movement = -toward
				else:
					movement = toward.orthogonal() * 0.6
				# Dodge a telegraphed slam rather than tanking it.
				for enemy in game.enemies:
					if enemy.boss_windup > 0 and game.player.position.distance_to(enemy.boss_target) < 125:
						movement = enemy.boss_target.direction_to(game.player.position)
						if movement.length_squared() < 0.1:
							movement = Vector2.DOWN
				# Steer away from arena edges when retreating.
				var next: Vector2 = game.player.position + movement * 60
				if not game.world_map.contains(next, 35):
					movement = toward.orthogonal()
				game.abilities.use("weapon", nearest.position)
				if nearest_distance < 175:
					game.abilities.use("offhand", nearest.position)
			game.player.tick(dt, movement, game.arena)
			game.abilities.tick(dt)
			for enemy in game.enemies.duplicate():
				enemy.tick(dt)
			game.tick_projectiles(dt)
			if game.player.dead:
				game.finish(false)
			else:
				game.tick_progression(dt)
			# Release queued enemies and avoid accumulating debug effects.
			if int(duration / dt) % 60 == 0:
				game.effects.clear()
				game.numbers.clear()
				await process_frame
		print("BUILD %s + %s: %s / %d kills / %.1fs / %.0f HP" % [build[0], build[1], "next level" if game.expedition == 2 else game.state, completed_kills[0] if not completed_kills.is_empty() else game.kills, duration, game.player.health])
		if game.expedition != 2 or completed_kills != [28]:
			failures += 1
		game.queue_free()
		await process_frame
	print("BUILD SIMULATION: %d failures" % failures)
	quit(1 if failures > 0 else 0)
