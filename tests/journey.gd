extends SceneTree

var checks = 0
var failures = 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, title: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func clear_enemies() -> void:
	for enemy in game.enemies.duplicate():
		enemy.queue_free()
	game.enemies.clear()
	game.projectiles.clear()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	# Fixed geometry isolates existing combat and UI regression fixtures.
	game.level = game.LEVEL_TEMPLATE.duplicate(true)
	game.world_map = JourneyMap.new(game.level)
	game.arena = game.world_map.bounds
	game.player.world_map = game.world_map
	await process_frame
	var map: JourneyMap = game.world_map
	check(game.arena.size.x > 3 * game.PLAY_AREA.size.x, "Journey spans more than three screen widths")
	check(map.contains(game.level.spawn_point, 18) and map.contains(game.level.exit_point, 18), "Camp and exit are traversable")
	check(not map.contains(Vector2(1500, 200)) and map.contains(Vector2(1500, 439)), "Trails have real boundaries instead of a rectangular arena")
	var point: Vector2 = game.level.spawn_point
	for step in range(400):
		point = map.move_actor(point, Vector2(10, 0), 18)
	check(point.x > game.level.exit_point.x, "The road connects camp to the exit without invisible barriers")
	point = map.move_actor(Vector2(1350, 200), Vector2(300, 0), 18)
	check(point.x < 1400 and map.contains(point, 18), "Actors cannot tunnel through grass when a clearing narrows")
	var enemy = game.spawn_enemy("melee", Vector2(1200, 200))
	game.player.position = Vector2(1850, 650)
	var route_ok = true
	for step in range(1500):
		enemy.tick(1.0 / 60)
		route_ok = route_ok and map.contains(enemy.position, enemy.radius)
	check(route_ok and enemy.position.distance_to(game.player.position) < 60, "Enemies navigate through the connecting trail while respecting map boundaries")
	clear_enemies()
	game.player.dead = false
	game.player.health = game.player.max_health
	game.player.position = Vector2(2200, 439)
	game.update_camera()
	check(is_equal_approx(game.camera.position.x, 2200), "Camera follows forward progress")
	await process_frame
	var screen_point: Vector2 = game.player.get_global_transform_with_canvas().origin
	check(absf(screen_point.x - 720) < 1 and absf(screen_point.y - 439) < 1, "World camera places hero in the play area beneath the fixed HUD")
	game.player.position = game.level.spawn_point
	game.update_camera()
	check(is_equal_approx(game.camera.position.x, 720), "Camera clamps at the western edge")
	game.player.position = game.level.exit_point
	game.update_camera()
	check(game.camera.position.x < game.player.position.x, "Camera clamps at the eastern edge so the exit stays visible")
	game.wave = 0
	game.tick_progression(5)
	check(game.expedition == 1 and game.exit_hold == 0, "Reaching an uncleared exit cannot skip encounters")
	game.equipment.inventory.clear()
	for id in ["oak_helm", "iron_blade", "ember_orb", "crescent_axe", "ruby_pendant"]:
		game.equipment.inventory.append(Gear.new(Catalog.item(id)))
	game.toggle_bag()
	game.equipped_list.get_child(0).get_child(0).pressed.emit()
	check(game.inventory_filter == "weapon" and game.inventory_list.get_child_count() == 2, "Clicking the empty weapon slot filters the bag to weapons")
	var axe: Gear = game.equipment.inventory[3]
	game.inventory_list.get_child(1).pressed.emit()
	check(game.equipment.slots.weapon == axe and game.equipment.inventory[0].definition.id == "oak_helm", "A filtered button equips the correct original inventory item")
	check(game.inventory_filter == "weapon" and game.inventory_list.get_child_count() == 1, "Equipping preserves the active filter")
	game.equipped_list.get_child(0).get_child(0).pressed.emit()
	check(game.equipment.slots.weapon == axe, "Selecting an occupied slot filters without unequipping")
	game.equipped_list.get_child(0).get_child(1).pressed.emit()
	check(game.equipment.slots.weapon == null and game.inventory_list.get_child_count() == 2, "The separate remove button returns worn gear to the filtered list")
	game.equipped_list.get_child(1).get_child(0).pressed.emit()
	check(game.inventory_filter == "offhand" and game.inventory_list.get_child_count() == 1, "Offhand selects its own category")
	game.equipped_list.get_child(2).get_child(0).pressed.emit()
	check(game.inventory_filter == "helmet" and game.inventory_list.get_child_count() == 1, "Helmet selects its own category")
	game.equipped_list.get_child(3).get_child(0).pressed.emit()
	check(game.inventory_filter == "necklace" and game.inventory_list.get_child_count() == 1, "Necklace selects its own category")
	game.inventory_filter_picker.item_selected.emit(0)
	check(game.inventory_filter == "" and game.inventory_list.get_child_count() == 5, "All equipment clears the slot filter")
	game.equipment.inventory.clear()
	game.select_inventory_slot("weapon")
	check(game.inventory_list.get_child(0) is Label and "No matching" in game.inventory_list.get_child(0).text, "Empty filtered lists show a useful empty state")
	await process_frame
	await process_frame
	check(game.inventory_panel.get_global_rect().end.x <= 1392 and game.inventory_panel.get_global_rect().end.y <= 746, "Filter and remove controls fit the fixed inventory panel")
	game.toggle_bag()
	game.equipment.slots.weapon = axe
	game.events.equipment_changed.emit()
	game.wave = 0
	game.wave_delay = 0
	for index in range(3):
		game.player.position = Vector2(game.level.encounter_triggers[index] - 20, 439)
		game.tick_progression(5)
		check(game.wave == index, "Garden %d waits until its approach is reached" % (index + 1))
		game.player.position.x += 40
		game.tick_progression(5)
		check(game.wave == index + 1 and not game.enemies.is_empty() and game.enemies.all(func(e): return map.contains(e.position, e.radius)), "Garden %d spawns enemies inside its clearing" % (index + 1))
		for target in game.enemies.duplicate():
			target.take_damage(10000, game.player)
	game.tick_progression(1)
	check(game.exit_ready() and game.expedition == 1 and game.state == "combat", "Clearing the final garden unlocks the exit without ending exploration")
	game.player.position = game.level.exit_point
	game.tick_progression(1)
	check(is_equal_approx(game.exit_hold, 1), "Exit requires a continuous hold rather than immediate transition")
	game.player.position.x -= 100
	game.tick_progression(0.1)
	check(game.exit_hold == 0, "Leaving the exit resets its countdown")
	game.player.position = game.level.exit_point
	game.tick_progression(1)
	game.toggle_bag()
	game._process(5)
	check(is_equal_approx(game.exit_hold, 1) and game.expedition == 1, "Inventory pause freezes the exit countdown")
	game.toggle_bag()
	game.help_open = true
	game._process(5)
	check(is_equal_approx(game.exit_hold, 1) and game.expedition == 1, "Help pause freezes the exit countdown")
	game.help_open = false
	game.player.dead = true
	game.tick_progression(5)
	check(game.expedition == 1, "A dead hero cannot advance through the exit")
	game.player.dead = false
	var completed = []
	game.events.level_completed.connect(func(number): completed.append(number))
	var loot_count: int = game.equipment.inventory.size() + game.drops.size()
	game.tick_progression(1.49)
	check(game.expedition == 1, "Exit does not advance before 2.5 seconds")
	game.tick_progression(0.02)
	check(game.expedition == 2 and game.wave == 0 and game.state == "combat" and completed == [1], "2.5 seconds advances exactly one level and emits completion")
	check(game.player.position == game.level.spawn_point and game.exit_hold == 0 and game.enemies.is_empty() and game.projectiles.is_empty(), "The next level resets map progress, combat and exit timer")
	check(game.equipment.slots.weapon == axe and game.equipment.inventory.size() == loot_count, "Transition preserves worn equipment and collects all remaining loot")
	check(game.player.health == game.player.max_health and game.camera.position.x == 720, "New level restores health and resets the camera")
	game.tick_progression(10)
	check(game.expedition == 2 and game.wave == 0, "The new level waits for forward exploration without repeated transitions")
	game.player.take_damage(99999, null, game.events)
	game._process(0.1)
	game.restart()
	check(game.expedition == 2 and not game.player.dead and game.player.position == game.level.spawn_point, "Defeat retry stays on the same level and returns to camp")
	game.queue_free()
	await process_frame
	print("JOURNEY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
