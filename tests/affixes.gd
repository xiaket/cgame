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

func set_stats(primary: Array, secondary: Array = [], id: String = "iron_blade") -> Gear:
	for slot in Equipment.SLOTS:
		game.equipment.slots[slot] = null
	var gear = Gear.new(Catalog.item(id), 2, 1, false)
	for affix in primary:
		gear.primary_affixes.append(affix)
	for affix in secondary:
		gear.secondary_affixes.append(affix)
	game.equipment.slots[gear.definition.slot] = gear
	game.player.bloodlust = 0
	game.events.equipment_changed.emit()
	game.abilities.cooldowns = {"weapon": 0.0, "offhand": 0.0}
	return gear

func incoming(damage_type: String, attack_kind: String, elite: bool = false) -> float:
	game.player.health = game.player.max_health
	game.player.invulnerable = 0
	game.player.take_damage(20, null, game.events, damage_type, attack_kind, elite)
	return game.player.max_health - game.player.health

func run() -> void:
	seed(8231)
	var counts_ok = true
	var ranges_ok = true
	var unique_ok = true
	var seen_primary = {}
	var seen_secondary = {}
	for rarity in range(3):
		for id in Catalog.ITEM_IDS:
			for sample in range(40):
				var level = 1 + sample % 5
				var gear = Gear.new(Catalog.item(id), rarity, level)
				counts_ok = counts_ok and gear.primary_count() == (3 if rarity == 2 else 2) and gear.secondary_affixes.size() == (0 if rarity == 0 else 1)
				var keys = []
				for secondary in [false, true]:
					for affix in gear.secondary_affixes if secondary else gear.primary_affixes:
						var pool: Dictionary = AffixCatalog.SECONDARY if secondary else AffixCatalog.PRIMARY
						if not pool.has(affix.id):
							ranges_ok = false
							continue
						var info: Array = pool[affix.id]
						var scale = 1.0 + rarity * 0.25
						if not secondary and not info[3]:
							scale *= 1.0 + (level - 1) * 0.16
						ranges_ok = ranges_ok and affix.value >= info[1] * scale - 0.051 and affix.value <= info[2] * scale + 0.051
						if secondary:
							seen_secondary[affix.id] = true
						else:
							unique_ok = unique_ok and not affix.id in keys
							keys.append(affix.id)
							seen_primary[affix.id] = true
						if affix.id == "skill_damage":
							ranges_ok = ranges_ok and affix.skill in AffixCatalog.DAMAGE_SKILLS
	check(counts_ok, "1440 rolls across all templates obey white 2/0, blue 2/1, yellow 3/1")
	check(ranges_ok and unique_ok, "All rolls respect category, range, level scaling and distinct primary stats")
	check(seen_primary.size() == 9 and seen_secondary.size() == 8, "Every supported affix can drop")
	check(Gear.COLORS[2] == Color("ffdb58") and Gear.RARITIES == ["Common", "Magic", "Rare"], "Highest quality is yellow Rare")
	var boss_loot_ok = true
	for index in range(100):
		var loot = LootSystem.roll(4, true)
		boss_loot_ok = boss_loot_ok and loot.rarity == 2 and loot.primary_count() == 3 and loot.secondary_affixes.size() == 1
	check(boss_loot_ok, "Boss always drops yellow equipment with 3 primary and 1 secondary")
	var original = Gear.new(Catalog.item("ember_orb"), 2, 3)
	var record = original.serialize()
	var restored = Catalog.gear_from(JSON.parse_string(JSON.stringify(record)))
	check(restored != null and JSON.stringify(restored.serialize()) == JSON.stringify(record), "Serialized rolls survive JSON round trip unchanged")
	var details = original.details()
	original.details()
	original.stat("health")
	check(original.serialize() == record and "PRIMARY AFFIXES (3)" in details and "SECONDARY AFFIXES (1)" in details and "Lv.3" in details, "Inspecting gear preserves rolls and exposes separate categories")
	restored.primary_affixes[0].value += 1
	check(original.serialize() == record, "Restored gear does not share mutable affixes")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	# Fixed geometry isolates existing combat and UI regression fixtures.
	game.level = game.LEVEL_TEMPLATE.duplicate(true)
	game.world_map = JourneyMap.new(game.level)
	game.arena = game.world_map.bounds
	game.player.world_map = game.world_map
	await process_frame
	check(game.drops.all(func(drop): return drop.gear.primary_count() == 2 and drop.gear.secondary_affixes.is_empty()), "Starter gear also obeys white affix counts")
	var hero: Hero = game.player
	var slash: AbilityDefinition = load("res://data/abilities/slash.tres")
	var fireball: AbilityDefinition = load("res://data/abilities/fireball.tres")
	set_stats([
		{"id": "physical_attack", "value": 10.0}, {"id": "magic_attack", "value": 20.0},
		{"id": "added_physical", "value": 3.0}, {"id": "added_magic", "value": 4.0},
		{"id": "skill_damage", "skill": "slash", "value": 20.0},
	])
	check(is_equal_approx(hero.skill_damage(slash), 53.8) and is_equal_approx(hero.skill_damage(fireball), 89.0), "Physical/spell attack and targeted skill damage apply only to matching skills; added damage applies to both")
	set_stats([{"id": "cooldown_reduction", "value": 25.0}], [], "ember_wand")
	check(is_equal_approx(hero.effective_cooldown(fireball), 2.1) and is_equal_approx(hero.effective_cooldown(slash), 1.0 / 2.4), "Cooldown reduction affects Power but not Basic")
	game.abilities.use("weapon", hero.position + Vector2.RIGHT * 100)
	check(is_equal_approx(game.abilities.cooldowns.weapon, 2.1), "Casting Power stores the reduced cooldown")
	set_stats([{"id": "cooldown_reduction", "value": 90.0}], [], "ember_wand")
	check(is_equal_approx(hero.cooldown_reduction, 0.4), "Cooldown reduction is capped at 40 percent")
	game.abilities.cooldowns.weapon = 2.1
	game.equipment.inventory.append(Gear.new(Catalog.item("iron_blade")))
	game.equipment.equip(game.equipment.inventory.size() - 1)
	check(is_equal_approx(game.abilities.cooldowns.weapon, 2.1) and not game.abilities.use("weapon", Vector2.RIGHT), "Swapping CDR gear preserves running cooldown")
	game.projectiles.clear()
	set_stats([{"id": "armor", "value": 100.0}, {"id": "magic_resist", "value": 25.0}])
	check(is_equal_approx(incoming("physical", "melee"), 10) and is_equal_approx(incoming("magic", "ranged"), 16), "Armor and magic resistance mitigate the corresponding incoming damage")
	set_stats([], [{"id": "melee_reduction", "value": 25.0}, {"id": "ranged_reduction", "value": 10.0}, {"id": "elite_reduction", "value": 20.0}])
	check(is_equal_approx(incoming("physical", "melee"), 15) and is_equal_approx(incoming("magic", "ranged"), 18) and is_equal_approx(incoming("physical", "melee", true), 12), "Melee, ranged and elite reductions apply to the corresponding attack categories")
	set_stats([], [{"id": "melee_reduction", "value": 200.0}, {"id": "elite_reduction", "value": 200.0}])
	check(is_equal_approx(incoming("physical", "melee", true), 5.2), "Reduction caps prevent immunity")
	set_stats([], [{"id": "speed", "value": 12.0}, {"id": "pickup_radius", "value": 30.0}, {"id": "health_regen", "value": 1.5}, {"id": "life_on_kill", "value": 2.0}])
	check(is_equal_approx(hero.move_speed, 257) and is_equal_approx(hero.pickup_radius(), 122), "Secondary movement and pickup range update character totals")
	hero.health = 50
	hero.tick(2, Vector2.ZERO, game.arena)
	check(is_equal_approx(hero.health, 53), "Health regeneration follows simulation time")
	game.drops.clear()
	game.drops.append({"position": hero.position + Vector2(115, 0), "gear": original})
	check(game.pickup_nearby() == 1 and game.equipment.inventory.back() == original and original.serialize() == record, "Pickup range collects farther equipment without changing its rolls")
	var enemy = game.spawn_enemy("melee", hero.position + Vector2(100, 0))
	enemy.take_damage(10000, hero)
	check(is_equal_approx(hero.health, 59), "Kill recovery adds secondary bonus to base four HP")
	hero.health = hero.max_health - 0.1
	hero.tick(1, Vector2.ZERO, game.arena)
	check(is_equal_approx(hero.health, hero.max_health), "Regeneration is capped at maximum HP")
	set_stats([], [{"id": "elite_damage", "value": 50.0}], "ember_wand")
	var boss = game.spawn_enemy("boss", hero.position + Vector2(140, 0))
	game.abilities.use("weapon", boss.position)
	var shot_damage: float = game.projectiles[0].damage
	set_stats([], [], "iron_blade")
	for step in range(30):
		game.tick_projectiles(1.0 / 60)
	check(is_equal_approx(boss.max_health - boss.health, shot_damage * 1.5), "Fireball snapshots damage and elite bonus across equipment swaps")
	boss.queue_free()
	game.enemies.clear()
	set_stats([], [{"id": "elite_damage", "value": 50.0}], "winter_focus")
	boss = game.spawn_enemy("boss", hero.position + Vector2(100, 0))
	var normal = game.spawn_enemy("melee", hero.position + Vector2(110, 0))
	game.abilities.use("weapon", boss.position)
	check(is_equal_approx(boss.max_health - boss.health, 69) and is_equal_approx(normal.max_health - normal.health, 46), "Instant AoE applies elite bonus only to Boss")
	game.equipment.inventory.clear()
	game.equipment.inventory.append(original)
	game.toggle_bag()
	await process_frame
	await process_frame
	check(game.character_panel.size.x <= 680 and game.character_panel.get_global_rect().end.y <= 746, "Expanded character stats fit the panel with scrolling")
	check(game.inventory_panel.get_global_rect().end.x <= 1392 and "3P / 1S" in game.inventory_list.get_child(0).text, "Bag identifies affix counts and fits the viewport")
	check(game.character_values.physical_attack.text == "+0.0 / +0.0" and "46.0 damage" in game.character_skills[0].text, "Character panel shows actual equipped stats and calculated skill damage")
	game.equipment.equip(0)
	game.equipment.unequip("offhand")
	check(original.serialize() == record, "Equipping and removing equipment never rerolls affixes")
	set_stats([], [{"id": "health_regen", "value": 1.5}])
	hero.health = 50
	game._process(2)
	check(is_equal_approx(hero.health, 50), "Inventory pause also pauses health regeneration")
	game.queue_free()
	await process_frame
	print("AFFIXES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
