extends SceneTree

const LEGACY_PATH = "user://emberfield_save.json"

var checks: int = 0
var failures: int = 0
var game
var old_save: String = ""
var had_save: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + title)
	else:
		print("PASS: " + title)

func put(slot: String, id: String) -> void:
	game.equipment.slots[slot] = Gear.new(Catalog.item(id)) if id != "" else null
	game.events.equipment_changed.emit()
	game.abilities.cooldowns[slot] = 0.0

func clear_enemies() -> void:
	for enemy in game.enemies.duplicate():
		game.enemies.erase(enemy)
		enemy.queue_free()
	game.projectiles.clear()

func run() -> void:
	had_save = FileAccess.file_exists(LEGACY_PATH)
	if had_save:
		old_save = FileAccess.get_file_as_string(LEGACY_PATH)
	var legacy_data = {"version": 1, "expedition": 9, "slots": {"weapon": {"id": "iron_blade", "rarity": 2, "level": 9}}, "inventory": [{"id": "frost_orb", "level": 9}]}
	var legacy_file = FileAccess.open(LEGACY_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy_data))
	legacy_file.close()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	seed(12345)
	check(game.equipment.slots.values().all(func(gear): return gear == null), "Launch ignores old save and starts unequipped")
	check(game.equipment.inventory.is_empty() and game.expedition == 1, "Launch starts with empty bag and expedition one")
	check(game.player.health == 140 and game.player.max_health == 140, "Fresh hero has base health")
	game._process(5)
	check(game.wave == 0 and game.enemies.is_empty(), "First wave waits for a manually equipped weapon")
	check(game.pickup_nearby() == 2, "Starter equipment can be collected from spawn")
	check(game.equipment.slots.weapon == null, "Picking up gear does not auto-equip")
	game.equipment.equip(0)
	game._process(3)
	check(game.wave == 1, "Equipping first weapon starts the encounter")
	clear_enemies()
	game.wave = 0
	game.wave_delay = 2
	# Combat fixtures are explicit; they are never granted on a real launch.
	game.equipment.inventory.clear()
	for id in ["iron_blade", "ember_orb", "oak_helm", "ruby_pendant"]:
		var gear = Gear.new(Catalog.item(id))
		game.equipment.slots[gear.definition.slot] = gear
	game.events.equipment_changed.emit()
	game.player.health = game.player.max_health
	check(game.player.max_health == 223, "Toughness and gear contribute to HP")
	for id in Catalog.ITEM_IDS:
		var item = Catalog.item(id)
		check(item != null and item.ability != null, "Resource references: " + id)
	var before: Vector2 = game.player.position
	game.player.tick(0.2, Vector2.RIGHT, game.arena)
	check(game.player.position.x > before.x, "Player moves")
	game.player.tick(100, Vector2.ONE, game.arena)
	check(game.arena.has_point(game.player.position), "Movement bounded by arena")
	game.player.position = Vector2(600, 440)
	var health: float = game.player.health
	game.equipment.unequip("helmet")
	check(game.player.max_health == 140, "Unequipping removes passive and base stats")
	check(game.player.health <= health, "Changing HP gear cannot heal")
	var index: int = game.equipment.inventory.size() - 1
	game.equipment.equip(index)
	check(game.player.max_health == 223, "Equipping restores passive immediately")
	game.player.health = 12
	game.equipment.unequip("helmet")
	check(game.player.health == 12 and not game.player.dead, "Removing HP gear at low HP cannot kill or heal")
	game.equipment.equip(game.equipment.inventory.size() - 1)
	game.player.health = game.player.max_health
	check(not game.equipment.equip(-1), "Invalid bag index is rejected")
	put("weapon", "iron_blade")
	put("offhand", "duelist_guard")
	var first = game.spawn_enemy("melee", game.player.position + Vector2(55, 0))
	var second = game.spawn_enemy("melee", game.player.position + Vector2(75, 10))
	check(game.abilities.use("weapon", first.position), "Basic fires")
	check(first.health < first.max_health and second.health == second.max_health, "Slash hits one target")
	check(not game.abilities.use("weapon", first.position), "Attack speed throttles held Basic")
	check(game.abilities.use("offhand", first.position), "Two Basic slots work independently")
	game.abilities.tick(1)
	check(game.abilities.cooldowns.weapon == 0, "Basic recovery ends")
	clear_enemies()
	put("weapon", "crescent_axe")
	first = game.spawn_enemy("melee", game.player.position + Vector2(70, 0))
	second = game.spawn_enemy("melee", game.player.position + Vector2(75, 25))
	game.abilities.use("weapon", first.position)
	check(first.health < first.max_health and second.health < second.max_health, "Cleave hits multiple enemies")
	put("weapon", "winter_focus")
	put("offhand", "ember_orb")
	check(game.abilities.use("weapon", first.position), "Power works in Weapon")
	check(first.slow_remaining == 3.5 and second.slow_remaining == 3.5, "Frost Nova applies area slow")
	check(game.abilities.use("offhand", Vector2(1000, 440)), "Power works in Offhand")
	check(not game.abilities.use("weapon", Vector2.ZERO) and not game.abilities.use("offhand", Vector2.ZERO), "Dual Power cannot attack with both on cooldown")
	check(game.projectiles.size() == 1, "Fireball creates a projectile")
	game.equipment.inventory.append(Gear.new(Catalog.item("iron_blade")))
	game.equipment.equip(game.equipment.inventory.size() - 1)
	check(game.abilities.cooldowns.weapon > 0 and not game.abilities.use("weapon", Vector2.ZERO), "Swapping cannot bypass cooldown")
	clear_enemies()
	put("weapon", "ember_wand")
	first = game.spawn_enemy("melee", game.player.position + Vector2(140, 0))
	second = game.spawn_enemy("melee", game.player.position + Vector2(155, 40))
	game.abilities.use("weapon", first.position)
	for step in range(30):
		game.tick_projectiles(1.0 / 60)
	check(first.dead and second.dead, "Fireball travels and explodes against a pack")
	check(game.player.bloodlust > 0, "Kill event triggers Bloodlust")
	check(is_equal_approx(game.player.damage_multiplier(), 1.4), "Bloodlust boosts damage")
	game.player.tick(5, Vector2.ZERO, game.arena)
	check(game.player.bloodlust == 0 and game.player.damage_multiplier() == 1, "Bloodlust expires after four seconds")
	game.player.on_kill(null, game.player)
	game.equipment.unequip("necklace")
	check(game.player.bloodlust == 0 and game.player.damage_multiplier() == 1, "Unequipping Bloodlust clears its effect")
	first = game.spawn_enemy("melee", game.player.position + Vector2(250, 0))
	first.slow_remaining = 3.5
	var enemy_start: Vector2 = first.position
	first.tick(0.25)
	check(is_equal_approx(first.position.distance_to(enemy_start), first.speed * 0.4 * 0.25), "Slow reduces AI movement by 60 percent")
	first.tick(4)
	check(first.slow_remaining == 0, "Slow expires")
	game.abilities.tick(10)
	game.toggle_bag()
	await process_frame
	await process_frame
	check(game.inventory_panel.get_global_rect().end.y <= 746, "Equipment panel fits above combat HUD")
	check(game.passive_label.get_global_rect().end.x <= 1392, "Passive text fits the HUD")
	check(not game.abilities.use("weapon", Vector2.ZERO), "Inventory pauses ability execution")
	game.toggle_bag()
	clear_enemies()
	game.drops.clear()
	game.drops.append({"position": game.player.position, "gear": Gear.new(Catalog.item("frost_orb"), 2, 3)})
	game.drops.append({"position": Vector2(1300, 700), "gear": Gear.new(Catalog.item("oak_helm"))})
	check(game.pickup_nearby() == 1 and game.drops.size() == 1, "F only collects nearby drops")
	check(LootSystem.roll(3, true).rarity == 2, "Boss guarantees Epic loot")
	var common = Gear.new(Catalog.item("iron_blade"))
	var epic = Gear.new(Catalog.item("iron_blade"), 2, 3)
	check(epic.stat("attack") > common.stat("attack"), "Quality and level improve attributes")
	game.player.health = game.player.max_health
	first = game.spawn_enemy("ranged", game.player.position + Vector2(230, 0))
	first.cooldown = 0
	first.tick(0.01)
	check(game.projectiles.size() == 1, "Ranged AI fires projectile")
	for step in range(100):
		game.tick_projectiles(0.01)
	check(game.player.health < game.player.max_health, "Enemy projectile damages player")
	clear_enemies()
	game.player.invulnerable = 0
	first = game.spawn_enemy("melee", game.player.position + Vector2(25, 0))
	first.cooldown = 0
	health = game.player.health
	first.tick(0.01)
	check(game.player.health < health, "Melee AI damages player")
	clear_enemies()
	first = game.spawn_enemy("boss", game.player.position + Vector2(200, 0))
	first.cooldown = 0
	first.tick(0.01)
	check(first.boss_windup > 0, "Boss telegraphs strike")
	game.player.invulnerable = 0
	health = game.player.health
	first.tick(1.1)
	check(game.player.health < health, "Boss telegraphed strike deals damage")
	clear_enemies()
	# Verify actual level progression using real death events, including the Boss.
	game.wave = 0
	game.kills = 0
	game.player.dead = false
	game.player.health = game.player.max_health
	for wave in range(1, 4):
		game.spawn_wave()
		check(game.wave == wave and not game.enemies.is_empty(), "Wave %d spawns" % wave)
		if wave == 3:
			check(game.enemies.any(func(e): return e.kind == "boss"), "Final wave contains Boss")
		for enemy in game.enemies.duplicate():
			enemy.take_damage(10000, game.player)
	game.wave_delay = 0
	game._process(0.01)
	check(game.state == "victory" and game.kills == 28, "Killing all 28 enemies completes level")
	check(game.drops.is_empty(), "Completion collects all loot")
	game.restart()
	check(game.expedition == 2 and game.wave == 0 and game.state == "combat", "Victory restart advances expedition")
	check(game.player.health == game.player.max_health, "Restart restores HP")
	game.player.take_damage(9999, null, game.events)
	game._process(0.01)
	check(game.state == "defeat", "Player death reaches defeat screen")
	game.restart()
	check(game.expedition == 2 and not game.player.dead, "Defeat retry keeps expedition and revives")
	check(FileAccess.get_file_as_string(LEGACY_PATH) == JSON.stringify(legacy_data), "Gameplay never overwrites legacy save")
	var fresh = load("res://scenes/main.tscn").instantiate()
	root.add_child(fresh)
	fresh.set_process(false)
	check(fresh.equipment.inventory.is_empty() and fresh.equipment.slots.values().all(func(gear): return gear == null), "Relaunch discards session equipment")
	check(fresh.expedition == 1 and fresh.player.health == 140, "Relaunch discards expedition and stats")
	fresh.queue_free()
	if had_save:
		var file = FileAccess.open(LEGACY_PATH, FileAccess.WRITE)
		file.store_string(old_save)
		file.close()
	else:
		DirAccess.remove_absolute(LEGACY_PATH)
	game.queue_free()
	await process_frame
	print("INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
