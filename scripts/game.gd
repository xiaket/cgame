extends Node2D

const ARENA = Rect2(48, 142, 1344, 594)
const BG = Color("101d24")
const INK = Color("dce6e4")
const MUTED = Color("8caaa9")
const GOLD = Color("eac687")
var arena = ARENA
var level: LevelDefinition = preload("res://data/ashen_garden.tres")
var events: CombatEvents
var equipment: Equipment
var abilities: AbilitySystem
var player: Hero
var enemies: Array[ArenaEnemy] = []
var projectiles: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var numbers: Array[Dictionary] = []
var expedition: int = 1
var wave: int = 0
var state: String = "combat"
var wave_delay: float = 2.0
var elapsed: float = 0.0
var kills: int = 0
var bag_open: bool = false
var help_open: bool = false
var loading: bool = true
var message_time: float = 0.0
var message: String = ""
var ui: CanvasLayer
var hp_bar: ProgressBar
var hp_label: Label
var objective: Label
var stat_label: Label
var info_label: Label
var toast_label: Label
var skill_buttons: Array[Button] = []
var passive_label: Label
var inventory_panel: PanelContainer
var inventory_list: VBoxContainer
var equipped_list: VBoxContainer
var character_panel: PanelContainer
var character_values: Dictionary = {}
var character_skills: Array[Label] = []
var character_passives: Label
var end_panel: PanelContainer
var end_title: Label
var end_detail: Label
var help_panel: PanelContainer

func _ready() -> void:
	events = CombatEvents.new()
	add_child(events)
	equipment = Equipment.new()
	equipment.events = events
	player = Hero.new()
	player.equipment = equipment
	player.position = arena.get_center()
	add_child(player)
	abilities = AbilitySystem.new()
	abilities.game = self
	events.equipment_changed.connect(_on_equipment_changed)
	events.enemy_killed.connect(_on_enemy_killed)
	events.enemy_killed.connect(player.on_kill)
	events.damaged.connect(_on_damaged)
	place_starting_supplies()
	player.recalculate()
	player.health = player.max_health
	build_ui()
	loading = false
	refresh_inventory()
	toast("Fresh start · F to collect starter gear · I to equip it · WASD to move", 10)

func place_starting_supplies() -> void:
	# Equipment grants all attacks, so a fresh, unequipped hero needs a first weapon.
	if equipment.slots.weapon != null or equipment.slots.offhand != null:
		return
	for gear in equipment.inventory:
		if gear.definition.slot in ["weapon", "offhand"]:
			return
	for index in range(2):
		var id = "iron_blade" if index == 0 else "ember_orb"
		drops.append({"position": player.position + Vector2(-35 + index * 70, 35), "gear": Gear.new(Catalog.item(id))})

func _process(delta: float) -> void:
	if loading:
		return
	message_time = maxf(0, message_time - delta)
	toast_label.text = message if message_time > 0 else ""
	# Inventory and help pause the simulation, including cooldowns and AI.
	if not bag_open and not help_open and state == "combat":
		elapsed += delta
		var direction = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		direction += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		player.tick(delta, direction, arena)
		var mouse = get_global_mouse_position()
		player.facing = player.position.direction_to(mouse)
		abilities.tick(delta)
		if arena.has_point(mouse) and not pointer_over_ui():
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				abilities.use("weapon", mouse)
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				abilities.use("offhand", mouse)
		if Input.is_physical_key_pressed(KEY_Q):
			abilities.use("weapon", mouse)
		if Input.is_physical_key_pressed(KEY_E):
			abilities.use("offhand", mouse)
		for enemy in enemies.duplicate():
			if not enemy.dead:
				enemy.tick(delta)
		tick_projectiles(delta)
		if player.dead:
			finish(false)
		elif enemies.is_empty() and (wave > 0 or equipment.slots.weapon != null or equipment.slots.offhand != null):
			wave_delay -= delta
			if wave_delay <= 0:
				if wave >= level.wave_sizes.size():
					finish(true)
				else:
					spawn_wave()
	for i in range(effects.size() - 1, -1, -1):
		effects[i].life -= delta
		if effects[i].life <= 0:
			effects.remove_at(i)
	for i in range(numbers.size() - 1, -1, -1):
		numbers[i].life -= delta
		numbers[i].position.y -= delta * 36
		if numbers[i].life <= 0:
			numbers.remove_at(i)
	update_ui()
	queue_redraw()

func pointer_over_ui() -> bool:
	var hovered = get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_I, KEY_TAB:
			toggle_bag()
		KEY_F:
			if not bag_open and not help_open:
				pickup_nearby()
		KEY_R:
			if state != "combat":
				restart()
		KEY_H:
			help_open = not help_open
			help_panel.visible = help_open
		KEY_ESCAPE:
			if help_open:
				help_open = false
				help_panel.hide()
			elif bag_open:
				toggle_bag()
			else:
				help_open = true
				help_panel.show()
	get_viewport().set_input_as_handled()

func spawn_wave() -> void:
	wave += 1
	var strength = 1.0 + (expedition - 1) * level.enemy_growth
	var count = level.wave_sizes[wave - 1]
	for i in range(count):
		var angle = TAU * float(i) / count + wave * 0.4
		var point = arena.get_center() + Vector2(cos(angle) * 560, sin(angle) * 230)
		if point.distance_to(player.position) < 180:
			point = arena.get_center() - (point - arena.get_center())
		spawn_enemy("ranged" if i % level.ranged_interval == 0 else "melee", point, strength)
	if wave == level.boss_wave:
		spawn_enemy("boss", Vector2(1220, 440) if player.position.x < 720 else Vector2(220, 440), strength)
	wave_delay = level.wave_break
	toast("WAVE %d / %d  —  %s" % [wave, level.wave_sizes.size(), "The Warden has arrived" if wave == level.boss_wave else "Clear the arena"], 3)

func spawn_enemy(kind: String, point: Vector2, strength: float = 1.0) -> ArenaEnemy:
	var enemy = ArenaEnemy.new()
	enemy.configure(self, kind, strength)
	enemy.position = point
	add_child(enemy)
	enemies.append(enemy)
	return enemy

func _on_enemy_killed(enemy: Node, _source: Node) -> void:
	kills += 1
	enemies.erase(enemy)
	var gear = LootSystem.roll(expedition, enemy.kind == "boss")
	if gear != null:
		drops.append({"position": enemy.position, "gear": gear})
	if enemy.kind == "boss":
		toast("The Warden falls. An Epic item awaits — clear the remaining enemies!", 4)
	# A little sustain rewards finishing enemies without making gear swaps a heal.
	if not player.dead:
		player.health = minf(player.max_health, player.health + 4)
	effect(enemy.position, enemy.radius + 12, Color("e7b273"), "ring")

func _on_damaged(target: Node, amount: float, _source: Node) -> void:
	numbers.append({"position": target.position + Vector2(randf_range(-10, 10), -28), "value": str(ceili(amount)), "life": 0.7, "color": Color("ff8e88") if target == player else Color("f8dfad")})

func _on_equipment_changed() -> void:
	player.recalculate()
	if not loading:
		refresh_inventory()

func pickup_nearby(all: bool = false) -> int:
	var count = 0
	for i in range(drops.size() - 1, -1, -1):
		if all or player.position.distance_to(drops[i].position) <= 92:
			equipment.inventory.append(drops[i].gear)
			drops.remove_at(i)
			count += 1
	if count > 0:
		refresh_inventory()
		toast("%d item%s collected · I to inspect and equip" % [count, "s" if count > 1 else ""], 3)
	else:
		toast("Move close to a glowing drop and press F", 2)
	return count

func spawn_projectile(point: Vector2, direction: Vector2, damage: float, friendly: bool, blast_radius: float, color: Color) -> void:
	projectiles.append({"position": point, "velocity": direction * (510 if friendly else 230), "damage": damage, "friendly": friendly, "radius": blast_radius, "life": 1.6 if friendly else 4.0, "color": color})

func tick_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var shot = projectiles[i]
		shot.life -= delta
		var previous: Vector2 = shot.position
		shot.position += shot.velocity * delta
		var hit = false
		if shot.friendly:
			for enemy in enemies:
				if not enemy.dead and Geometry2D.get_closest_point_to_segment(enemy.position, previous, shot.position).distance_to(enemy.position) < enemy.radius + 8:
					hit = true
					break
		else:
			hit = Geometry2D.get_closest_point_to_segment(player.position, previous, shot.position).distance_to(player.position) < 22
		if hit or shot.life <= 0 or not arena.has_point(shot.position):
			if shot.friendly:
				for enemy in enemies.duplicate():
					if not enemy.dead and enemy.position.distance_to(shot.position) <= shot.radius + enemy.radius:
						enemy.take_damage(shot.damage, player)
				effect(shot.position, shot.radius, shot.color, "ring")
			elif hit:
				player.take_damage(shot.damage, self, events)
			projectiles.remove_at(i)

func effect(point: Vector2, radius: float, color: Color, kind: String, angle: float = 0.0) -> void:
	effects.append({"position": point, "radius": radius, "color": color, "kind": kind, "angle": angle, "life": 0.32})

func finish(victory: bool) -> void:
	state = "victory" if victory else "defeat"
	projectiles.clear()
	if victory:
		pickup_nearby(true)
		events.level_completed.emit(expedition)
		end_title.text = "THE FIELD IS YOURS"
		end_detail.text = "Expedition %d complete · %d defeated · %ds\nAll drops collected. Inspect your gear, then face a stronger field.\nNext expedition: enemy strength +%d%% · higher item levels" % [expedition, kills, int(elapsed), int(level.enemy_growth * 100)]
	else:
		pickup_nearby(true)
		end_title.text = "RISE FROM THE ASHES"
		end_detail.text = "Reached wave %d · %d defeated\nYour equipment and collected loot are safe.\nTry Cleave + Frost Nova for close combat, or two Power skills for kiting." % [wave, kills]
	end_panel.show()

func restart() -> void:
	if state == "victory":
		expedition += 1
	for enemy in enemies:
		enemy.queue_free()
	enemies.clear()
	projectiles.clear()
	drops.clear()
	effects.clear()
	wave = 0
	kills = 0
	elapsed = 0
	wave_delay = 2.0
	state = "combat"
	player.position = arena.get_center()
	player.dead = false
	player.recalculate()
	player.health = player.max_health
	player.bloodlust = 0
	player.invulnerable = 0
	abilities.cooldowns = {"weapon": 0.0, "offhand": 0.0}
	end_panel.hide()
	if bag_open:
		toggle_bag()
	place_starting_supplies()
	toast("Expedition %d · The next wave approaches" % expedition, 3)

func toast(text: String, duration: float = 3.0) -> void:
	message = text
	message_time = duration

func _draw() -> void:
	draw_rect(arena.grow(8), Color("293c40"))
	draw_rect(arena, BG)
	# A quiet stone grid, inset garden beds, and ritual markings give the arena scale.
	for x in range(48, 1393, 48):
		draw_line(Vector2(x, 142), Vector2(x, 736), Color("18272e"), 1)
	for y in range(142, 737, 48):
		draw_line(Vector2(48, y), Vector2(1392, y), Color("18272e"), 1)
	var center = arena.get_center()
	draw_arc(center, 165, 0, TAU, 96, Color("25373b"), 2)
	draw_arc(center, 155, 0, TAU, 96, Color("1c2d33"), 1)
	for i in range(12):
		var direction = Vector2.from_angle(i * TAU / 12)
		draw_line(center + direction * 148, center + direction * 170, Color("34474a"), 2)
	for point in [Vector2(60, 154), Vector2(1380, 154), Vector2(60, 724), Vector2(1380, 724)]:
		draw_circle(point, 7, GOLD)
		draw_circle(point, 16, Color(0.9, 0.65, 0.3, 0.06))
	for drop in drops:
		var point: Vector2 = drop.position
		var tint: Color = Gear.COLORS[drop.gear.rarity]
		draw_circle(point, 17, Color(tint, 0.12))
		draw_line(point + Vector2(0, -8), point + Vector2(0, -34), Color(tint, 0.45), 2)
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -9), point + Vector2(7, 0), point + Vector2(0, 9), point + Vector2(-7, 0)]), tint)
		if is_instance_valid(player) and point.distance_to(player.position) < 92:
			draw_string(ThemeDB.fallback_font, point + Vector2(-65, -40), "[F] " + drop.gear.definition.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tint)
	for enemy in enemies:
		if enemy.boss_windup > 0:
			var point: Vector2 = enemy.boss_target
			draw_circle(point, 100, Color(0.9, 0.27, 0.18, 0.12))
			draw_arc(point, 100 * (1.0 - enemy.boss_windup), 0, TAU, 48, Color("f19774"), 3)
			draw_arc(point, 100, 0, TAU, 48, Color("a76053"), 1)
	for shot in projectiles:
		var point: Vector2 = shot.position
		draw_line(point, point - shot.velocity.normalized() * 22, Color(shot.color, 0.35), 7)
		draw_circle(point, 8 if shot.friendly else 5, shot.color)
		draw_circle(point, 3, Color("fff0ce"))
	for fx in effects:
		var progress: float = 1.0 - fx.life / 0.32
		var tint = Color(fx.color, 1.0 - progress)
		if fx.kind == "slash":
			draw_arc(fx.position, fx.radius * (0.6 + progress * 0.4), fx.angle - 0.9, fx.angle + 0.9, 24, tint, 6.0 * (1.0 - progress) + 1)
		else:
			draw_arc(fx.position, maxf(1, fx.radius * progress), 0, TAU, 48, tint, 4)
	for number in numbers:
		draw_string(ThemeDB.fallback_font, number.position, number.value, HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color(number.color, minf(1, number.life * 3)))

func style(bg: Color, border: Color = Color("324a50"), width: int = 1) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(8)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func label(text: String, size: int = 16, color: Color = INK) -> Label:
	var result = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func button(text: String, callback: Callable, color: Color = INK) -> Button:
	var result = Button.new()
	result.text = text
	result.add_theme_font_size_override("font_size", 15)
	result.add_theme_color_override("font_color", color)
	result.add_theme_stylebox_override("normal", style(Color("1b3038")))
	result.add_theme_stylebox_override("hover", style(Color("2b444c"), GOLD))
	result.add_theme_stylebox_override("pressed", style(Color("39555a"), GOLD))
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(callback)
	return result

func panel(point: Vector2, dimensions: Vector2, color: Color = Color("14252d")) -> PanelContainer:
	var result = PanelContainer.new()
	result.position = point
	result.size = dimensions
	result.add_theme_stylebox_override("panel", style(color))
	ui.add_child(result)
	return result

func build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var heading = label("EMBERFIELD", 30, GOLD)
	heading.position = Vector2(48, 24)
	ui.add_child(heading)
	var subtitle = label("THE ASHEN GARDEN    /    EQUIPMENT IS YOUR BUILD", 12, MUTED)
	subtitle.position = Vector2(50, 64)
	ui.add_child(subtitle)
	objective = label("", 18)
	objective.position = Vector2(500, 29)
	ui.add_child(objective)
	info_label = label("", 14, MUTED)
	info_label.position = Vector2(500, 63)
	ui.add_child(info_label)
	var bag_button = button("EQUIPMENT  [I]", toggle_bag, GOLD)
	bag_button.position = Vector2(1070, 30)
	bag_button.size = Vector2(190, 48)
	ui.add_child(bag_button)
	var help_button = button("HELP [H]", func():
		help_open = not help_open
		help_panel.visible = help_open)
	help_button.position = Vector2(1272, 30)
	help_button.size = Vector2(120, 48)
	ui.add_child(help_button)
	toast_label = label("", 15, GOLD)
	toast_label.position = Vector2(48, 105)
	ui.add_child(toast_label)
	var health_panel = panel(Vector2(48, 758), Vector2(350, 100))
	var health_box = VBoxContainer.new()
	health_panel.add_child(health_box)
	hp_label = label("", 15)
	health_box.add_child(hp_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 14)
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("background", style(Color("2b3037")))
	hp_bar.add_theme_stylebox_override("fill", style(Color("c46e63"), Color("c46e63"), 0))
	health_box.add_child(hp_bar)
	stat_label = label("", 12, MUTED)
	health_box.add_child(stat_label)
	for index in range(2):
		var slot = "weapon" if index == 0 else "offhand"
		var skill = button("", func(): abilities.use(slot, get_global_mouse_position()), GOLD)
		skill.position = Vector2(414 + index * 250, 758)
		skill.size = Vector2(236, 100)
		ui.add_child(skill)
		skill_buttons.append(skill)
	var passive_panel = panel(Vector2(914, 758), Vector2(478, 100))
	passive_label = label("", 14)
	passive_panel.add_child(passive_label)
	var foot = label("WASD / ARROWS  move     LMB / Q  weapon     RMB / E  offhand     F  collect     I  equipment & pause", 13, MUTED)
	foot.position = Vector2(48, 874)
	ui.add_child(foot)
	var session_label = label("NEW SESSION ON LAUNCH", 11, MUTED)
	session_label.position = Vector2(1214, 875)
	ui.add_child(session_label)
	build_inventory_ui()
	end_panel = panel(Vector2(350, 270), Vector2(740, 280), Color("192e35"))
	var end_box = VBoxContainer.new()
	end_box.add_theme_constant_override("separation", 20)
	end_panel.add_child(end_box)
	end_title = label("", 29, GOLD)
	end_box.add_child(end_title)
	end_detail = label("", 17)
	end_box.add_child(end_detail)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	end_box.add_child(row)
	row.add_child(button("CONTINUE / RETRY  [R]", restart, GOLD))
	row.add_child(button("INSPECT EQUIPMENT  [I]", toggle_bag))
	end_panel.hide()
	help_panel = panel(Vector2(340, 225), Vector2(760, 466), Color("192e35"))
	var help_box = VBoxContainer.new()
	help_box.add_theme_constant_override("separation", 18)
	help_panel.add_child(help_box)
	help_box.add_child(label("A FIELD GUIDE", 28, GOLD))
	help_box.add_child(label("Move with WASD or arrows. Aim with the mouse.\nHold LMB / Q for Weapon; hold RMB / E for Offhand.\nF collects nearby drops. I opens equipment and pauses combat.\nClick a bag item to equip it. Click worn gear to remove it.\n\nBasic skills attack continuously. Power skills have a cooldown.\nBoth active slots accept either kind — try any combination.\nToughness adds 65 HP. Bloodlust grants +40% damage after kills.\n\nClear 3 waves and defeat the Warden. Avoid its orange warning circle.\nKills restore 4 HP. On completion, all loot is collected.\nR continues with your gear. Closing the game resets all progress.", 17))
	help_box.add_child(button("RETURN TO THE FIELD  [H / ESC]", func():
		help_open = false
		help_panel.hide(), GOLD))
	help_panel.hide()

func build_inventory_ui() -> void:
	build_character_ui()
	inventory_panel = panel(Vector2(744, 145), Vector2(648, 590), Color("152830"))
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	inventory_panel.add_child(outer)
	var row = HBoxContainer.new()
	outer.add_child(row)
	var title = label("EQUIPMENT", 24, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(button("CLOSE [I]", toggle_bag))
	outer.add_child(label("PAUSED · Click gear to equip / remove. Hover for stats.", 13, MUTED))
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 270
	columns.add_child(left)
	left.add_child(label("WORN  /  4 SLOTS", 13, MUTED))
	equipped_list = VBoxContainer.new()
	left.add_child(equipped_list)
	var advice = label("TRY THESE BUILDS\nCleave + Frost Nova\nSweep packs, slow, keep moving.\n\nFireball + Frost Nova\nBurst, retreat during cooldowns.\n\nTwo Basics / two Powers\nBoth active slots are equal.", 13, MUTED)
	left.add_child(advice)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(label("BAG  /  CLICK TO EQUIP", 13, MUTED))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 370
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	inventory_list = VBoxContainer.new()
	inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inventory_list)
	inventory_panel.hide()

func build_character_ui() -> void:
	character_panel = panel(Vector2(48, 145), Vector2(680, 590), Color("152830"))
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	character_panel.add_child(box)
	box.add_child(label("CHARACTER", 24, GOLD))
	box.add_child(label("Your current totals · All equipped items and passives included", 13, MUTED))
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	var titles = {
		"health": "Health",
		"attack": "Equipment attack bonus",
		"attack_speed": "Attack speed",
		"move_speed": "Movement speed",
		"damage_multiplier": "Damage multiplier",
	}
	for key in titles:
		var heading = label(titles[key], 16, MUTED)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(heading)
		var value = label("", 16)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(value)
		character_values[key] = value
	box.add_child(HSeparator.new())
	box.add_child(label("ACTIVE SKILLS  /  FINAL DAMAGE PER HIT", 13, GOLD))
	for index in range(2):
		var skill = label("", 15)
		box.add_child(skill)
		character_skills.append(skill)
	box.add_child(HSeparator.new())
	box.add_child(label("PASSIVE EFFECTS", 13, GOLD))
	character_passives = label("", 14, MUTED)
	box.add_child(character_passives)
	character_panel.hide()

func refresh_character_stats() -> void:
	if not is_instance_valid(character_panel):
		return
	character_values.health.text = "%.1f / %.1f" % [player.health, player.max_health]
	character_values.health.tooltip_text = "Maximum: 140 base + %.1f equipment + %d Toughness" % [equipment.bonus("health"), 65 if equipment.has_passive("toughness") else 0]
	character_values.attack.text = "+%.1f" % player.attack
	character_values.attack.tooltip_text = "Added to each active skill's base damage before the damage multiplier."
	character_values.attack_speed.text = "%.2fx  (+%.1f%%)" % [player.attack_speed, equipment.bonus("attack_speed")]
	character_values.attack_speed.tooltip_text = "Basic attacks: %.2f attacks per second. Power cooldowns are fixed." % (2.4 * player.attack_speed)
	character_values.move_speed.text = "%.1f px/s" % player.move_speed
	character_values.move_speed.tooltip_text = "245 base + %.1f equipment" % equipment.bonus("speed")
	character_values.damage_multiplier.text = "%.2fx" % player.damage_multiplier()
	character_values.damage_multiplier.tooltip_text = "Bloodlust grants +40% damage while active."
	for index in range(2):
		var slot = "weapon" if index == 0 else "offhand"
		var gear: Gear = equipment.slots[slot]
		if gear == null:
			character_skills[index].text = "%s: Empty\nEquip an item to gain an active skill." % slot.capitalize()
			continue
		var ability = gear.definition.ability
		var damage = (ability.damage + player.attack) * player.damage_multiplier()
		var timing = "%.2f attacks/s" % (2.4 * player.attack_speed) if ability.kind == "basic" else "%.1fs cooldown" % ability.cooldown
		character_skills[index].text = "%s: %s  ·  %.1f damage  ·  %s\n(%.1f skill + %.1f equipment) x %.2f" % [slot.capitalize(), ability.title, damage, timing, ability.damage, player.attack, player.damage_multiplier()]
	var toughness = "+65 maximum health" if equipment.has_passive("toughness") else "Not equipped"
	var bloodlust = "On kill: +40% damage for 4s" if equipment.has_passive("bloodlust") else "Not equipped"
	if player.bloodlust > 0:
		bloodlust = "ACTIVE: +40%% damage · %.1fs remaining" % player.bloodlust
	character_passives.text = "Toughness: %s\nBloodlust: %s" % [toughness, bloodlust]

func toggle_bag() -> void:
	bag_open = not bag_open
	inventory_panel.visible = bag_open
	character_panel.visible = bag_open
	end_panel.visible = state != "combat" and not bag_open
	if bag_open:
		refresh_inventory()

func refresh_inventory() -> void:
	refresh_character_stats()
	if not is_instance_valid(inventory_list):
		return
	for list in [inventory_list, equipped_list]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	for slot in Equipment.SLOTS:
		var gear: Gear = equipment.slots[slot]
		var text = slot.to_upper() + "\n"
		text += gear.definition.title + " · " + gear.definition.ability.title if gear != null else "Empty — no skill"
		var entry = button(text, func(): equipment.unequip(slot), Gear.COLORS[gear.rarity] if gear != null else MUTED)
		entry.add_theme_font_size_override("font_size", 13)
		entry.tooltip_text = gear.details() + "\nClick to remove" if gear != null else "Equip an item from the bag"
		equipped_list.add_child(entry)
	for index in range(equipment.inventory.size()):
		var gear = equipment.inventory[index]
		var text = "%s  +%d\n%s · %s" % [gear.definition.title, gear.level, gear.definition.slot.capitalize(), gear.definition.ability.title]
		var entry = button(text, func(): equipment.equip(index), Gear.COLORS[gear.rarity])
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.add_theme_font_size_override("font_size", 13)
		var worn: Gear = equipment.slots[gear.definition.slot]
		entry.tooltip_text = gear.details() + "\n\nCURRENTLY EQUIPPED\n" + (worn.details() if worn != null else "Empty")
		inventory_list.add_child(entry)
	if equipment.inventory.is_empty():
		inventory_list.add_child(label("No spare gear. Hunt for drops.", 13, MUTED))

func update_ui() -> void:
	if bag_open:
		refresh_character_stats()
	hp_bar.max_value = player.max_health
	hp_bar.value = player.health
	hp_label.text = "VITALITY     %d / %d" % [ceili(player.health), ceili(player.max_health)]
	stat_label.text = "+%d damage   ·   %.2fx attack speed   ·   %d move" % [int(player.attack), player.attack_speed, int(player.move_speed)]
	objective.text = "EXPEDITION %02d    /    WAVE %d OF %d" % [expedition, wave, level.wave_sizes.size()]
	if state == "combat":
		info_label.text = "%d enemies remain  ·  %d defeated  ·  %s" % [enemies.size(), kills, "PAUSED" if bag_open or help_open else ("Collect [F] and equip [I] a weapon to begin" if wave == 0 and equipment.slots.weapon == null and equipment.slots.offhand == null else ("Next wave in %.1fs" % maxf(0, wave_delay) if enemies.is_empty() else "Clear the field"))]
	else:
		info_label.text = "FIELD CLEARED · [R] NEXT EXPEDITION" if state == "victory" else "DEFEATED · [R] RETRY"
	for index in range(2):
		var slot = "weapon" if index == 0 else "offhand"
		var gear: Gear = equipment.slots[slot]
		var key = "LMB / Q" if index == 0 else "RMB / E"
		if gear == null:
			skill_buttons[index].text = "%s  ·  %s\nEmpty slot\nEquip gear to gain a skill" % [key, slot.to_upper()]
			skill_buttons[index].tooltip_text = "Empty equipment slot"
		else:
			var ability = gear.definition.ability
			var recovery: float = abilities.cooldowns[slot]
			skill_buttons[index].text = "%s  ·  %s\n%s\n%s" % [key, ability.kind.to_upper(), ability.title, "READY" if recovery <= 0 else "%.1fs" % recovery]
			skill_buttons[index].tooltip_text = gear.details()
	var passives: PackedStringArray = []
	for slot in ["helmet", "necklace"]:
		var gear: Gear = equipment.slots[slot]
		passives.append("%s: %s" % [slot.capitalize(), gear.definition.ability.title if gear != null else "Empty"])
	passive_label.text = "PASSIVES   /   " + "  ·  ".join(passives) + "\n" + ("BLOODLUST  +40%% damage  ·  %.1fs" % player.bloodlust if player.bloodlust > 0 else "Collect glowing drops with F · Clear all 3 waves to advance")
