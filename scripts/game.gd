extends Node2D

const PLAY_AREA = Rect2(48, 142, 1344, 594)
const BG = Color("101d24")
const INK = Color("dce6e4")
const MUTED = Color("8caaa9")
const GOLD = Color("eac687")
var arena: Rect2
var world_map: JourneyMap
var camera: Camera2D
var exit_hold: float = 0.0
var inventory_filter: String = ""
var inventory_filter_picker: OptionButton
const LEVEL_TEMPLATE = preload("res://data/ashen_garden.tres")
var level: LevelDefinition
var map_seed: int = -1
var map_rng = RandomNumberGenerator.new()
var aim_target: ArenaEnemy
var last_mouse: Vector2
var input_blocked: bool = false
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
	map_rng.randomize()
	generate_map(map_seed if map_seed >= 0 else map_rng.randi())
	camera = Camera2D.new()
	add_child(camera)
	events = CombatEvents.new()
	add_child(events)
	equipment = Equipment.new()
	equipment.events = events
	player = Hero.new()
	player.equipment = equipment
	player.world_map = world_map
	player.position = level.spawn_point
	add_child(player)
	update_camera()
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
	last_mouse = get_viewport().get_mouse_position()
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
		var starter = Gear.new(Catalog.item(id), 0, 1, false)
		starter.primary_affixes.append({"id": "physical_attack" if id == "iron_blade" else "magic_attack", "value": 7.0})
		drops.append({"position": player.position + Vector2(-35 + index * 70, 35), "gear": starter})

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
		update_camera()
		var mouse = get_global_mouse_position()
		var screen_mouse = get_viewport().get_mouse_position()
		var mouse_attack = (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) and not pointer_over_ui()
		var key_attack = Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_E)
		var any_attack = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or key_attack
		if input_blocked and not any_attack:
			input_blocked = false
		if screen_mouse.distance_to(last_mouse) > 4 and not pointer_over_ui() and PLAY_AREA.has_point(screen_mouse) and mouse.distance_to(player.position) > 12:
			player.facing = player.position.direction_to(mouse)
		elif not any_attack and direction.length_squared() > 0:
			player.facing = direction.normalized()
		if screen_mouse.distance_to(last_mouse) > 4:
			last_mouse = screen_mouse
		abilities.tick(delta)
		aim_target = null
		if not input_blocked:
			if mouse_attack and PLAY_AREA.has_point(screen_mouse):
				if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					assisted_attack("weapon", false)
				if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
					assisted_attack("offhand", false)
			if Input.is_physical_key_pressed(KEY_Q):
				assisted_attack("weapon", true)
			if Input.is_physical_key_pressed(KEY_E):
				assisted_attack("offhand", true)
		for enemy in enemies.duplicate():
			if not enemy.dead:
				enemy.tick(delta)
		tick_projectiles(delta)
		if player.dead:
			finish(false)
		else:
			tick_progression(delta)
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_attack_input()

func generate_map(next_seed: int) -> void:
	map_seed = next_seed
	level = JourneyMap.generate(LEVEL_TEMPLATE, map_seed)
	world_map = JourneyMap.new(level)
	arena = world_map.bounds
	if player != null:
		player.world_map = world_map

func clear_attack_input() -> void:
	aim_target = null
	input_blocked = true

func assisted_attack(slot: String, automatic: bool = true) -> bool:
	if bag_open or help_open or player.dead or state != "combat" or input_blocked:
		return false
	var gear: Gear = equipment.slots[slot]
	if gear == null:
		return false
	var direction = player.facing
	if not automatic and player.position.distance_to(get_global_mouse_position()) > 12:
		direction = player.position.direction_to(get_global_mouse_position())
	aim_target = AimAssist.choose(player, gear.definition.ability, enemies, world_map, direction, automatic)
	var target = aim_target.position if aim_target != null else player.position + direction * 100
	return abilities.use(slot, target)

func update_camera() -> void:
	camera.position = Vector2(clampf(player.position.x, PLAY_AREA.get_center().x, arena.end.x - PLAY_AREA.size.x / 2.0), 450)
	camera.force_update_scroll()

func exit_ready() -> bool:
	return wave >= level.wave_sizes.size() and enemies.is_empty() and not player.dead

func tick_progression(delta: float) -> void:
	if state != "combat" or bag_open or help_open or player.dead:
		return
	if enemies.is_empty() and wave < level.wave_sizes.size() and (equipment.slots.weapon != null or equipment.slots.offhand != null):
		if player.position.x >= level.encounter_triggers[wave]:
			wave_delay -= delta
			if wave_delay <= 0:
				spawn_wave()
	if exit_ready() and player.position.distance_to(level.exit_point) <= level.exit_radius:
		exit_hold += delta
		if exit_hold >= level.exit_hold_seconds:
			finish(true)
			restart()
	else:
		exit_hold = 0.0

func pointer_over_ui() -> bool:
	var hovered = get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode in [KEY_I, KEY_TAB, KEY_H, KEY_ESCAPE]:
		clear_attack_input()
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
			clear_attack_input()
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
		var center = level.encounter_centers[wave - 1]
		var point = center + Vector2(cos(angle) * 280, sin(angle) * 170)
		if point.distance_to(player.position) < 180:
			point = center - (point - center)
		spawn_enemy("ranged" if i % level.ranged_interval == 0 else "melee", point, strength)
	if wave == level.boss_wave:
		spawn_enemy("boss", level.encounter_centers[wave - 1] + Vector2(270, 0), strength)
	wave_delay = level.wave_break
	toast("WAVE %d / %d  —  %s" % [wave, level.wave_sizes.size(), "The Warden has arrived" if wave == level.boss_wave else "Clear this garden"], 3)

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
		toast("The Warden falls. A yellow Rare item awaits — reach the eastern exit!", 4)
	# A little sustain rewards finishing enemies without making gear swaps a heal.
	if not player.dead:
		player.health = minf(player.max_health, player.health + 4 + equipment.bonus("life_on_kill"))
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
		if all or player.position.distance_to(drops[i].position) <= player.pickup_radius():
			equipment.inventory.append(drops[i].gear)
			drops.remove_at(i)
			count += 1
	if count > 0:
		refresh_inventory()
		toast("%d item%s collected · I to inspect and equip" % [count, "s" if count > 1 else ""], 3)
	else:
		toast("Move close to a glowing drop and press F", 2)
	return count

func spawn_projectile(point: Vector2, direction: Vector2, damage: float, friendly: bool, blast_radius: float, color: Color, elite_bonus: float = 0.0) -> void:
	projectiles.append({"position": point, "velocity": direction * (510 if friendly else 230), "damage": damage, "elite_bonus": elite_bonus, "friendly": friendly, "radius": blast_radius, "life": 1.6 if friendly else 4.0, "color": color})

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
		if hit or shot.life <= 0 or not world_map.line_clear(previous, shot.position):
			if shot.friendly:
				for enemy in enemies.duplicate():
					if not enemy.dead and enemy.position.distance_to(shot.position) <= shot.radius + enemy.radius:
						enemy.take_damage(shot.damage * (1.0 + shot.elite_bonus / 100.0 if enemy.kind == "boss" else 1.0), player)
				effect(shot.position, shot.radius, shot.color, "ring")
			elif hit:
				player.take_damage(shot.damage, self, events, "magic", "ranged")
			projectiles.remove_at(i)

func effect(point: Vector2, radius: float, color: Color, kind: String, angle: float = 0.0) -> void:
	effects.append({"position": point, "radius": radius, "color": color, "kind": kind, "angle": angle, "life": 0.32})

func finish(victory: bool) -> void:
	clear_attack_input()
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
		generate_map(map_rng.randi())
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
	clear_attack_input()
	exit_hold = 0.0
	numbers.clear()
	player.position = level.spawn_point
	update_camera()
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
	toast("Expedition %d · Follow the road east" % expedition, 3)

func toast(text: String, duration: float = 3.0) -> void:
	message = text
	message_time = duration

func _draw() -> void:
	if level == null:
		return
	# Trails join three clearings, with grass outside the traversable map.
	draw_rect(arena.grow(60), Color("0c191a"))
	for region in level.walkable_regions:
		draw_rect(region.grow(6), Color("344740"))
	for region in level.walkable_regions:
		draw_rect(region, BG)
		for x in range(int(region.position.x) + 24, int(region.end.x), 48):
			for y in range(int(region.position.y) + 24, int(region.end.y), 48):
				draw_circle(Vector2(x, y), 2, Color("263939"))
	for index in range(level.encounter_centers.size()):
		var center = level.encounter_centers[index]
		draw_arc(center, 150, 0, TAU, 64, Color("2e4143"), 3)
		draw_string(ThemeDB.fallback_font, center + Vector2(-80, -205), ["I · OUTER GARDEN", "II · STONE CROSSING", "III · WARDEN'S COURT"][index], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MUTED)
	for x in range(390, int(level.exit_point.x) - 120, 330):
		var point = Vector2(x, level.spawn_point.y)
		draw_polyline(PackedVector2Array([point + Vector2(-10, -10), point, point + Vector2(-10, 10)]), Color("58716a"), 3)
	draw_string(ThemeDB.fallback_font, level.spawn_point + Vector2(-65, -100), "CAMP · HEAD EAST →", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)
	var exit_color = GOLD if exit_ready() else MUTED
	draw_circle(level.exit_point, level.exit_radius, Color(exit_color, 0.09))
	draw_arc(level.exit_point, level.exit_radius, 0, TAU, 64, exit_color, 3)
	if exit_hold > 0:
		draw_arc(level.exit_point, level.exit_radius - 8, -PI / 2, -PI / 2 + TAU * exit_hold / level.exit_hold_seconds, 64, GOLD, 6)
	var exit_text = "STAND HERE · %.1fs" % maxf(0, level.exit_hold_seconds - exit_hold) if exit_ready() else "EXIT LOCKED · CLEAR THE GARDENS"
	draw_string(ThemeDB.fallback_font, level.exit_point + Vector2(-145, -85), exit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, exit_color)
	if is_instance_valid(aim_target) and not aim_target.dead:
		draw_arc(aim_target.position, aim_target.radius + 7, 0, TAU, 32, GOLD, 2)
	for drop in drops:
		var point: Vector2 = drop.position
		var tint: Color = Gear.COLORS[drop.gear.rarity]
		draw_circle(point, 17, Color(tint, 0.12))
		draw_line(point + Vector2(0, -8), point + Vector2(0, -34), Color(tint, 0.45), 2)
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -9), point + Vector2(7, 0), point + Vector2(0, 9), point + Vector2(-7, 0)]), tint)
		if is_instance_valid(player) and point.distance_to(player.position) <= player.pickup_radius():
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
	# Keep the scrolling world behind fixed HUD bands.
	for rect in [Rect2(0, 0, 1440, 142), Rect2(0, 736, 1440, 164)]:
		var mask = ColorRect.new()
		mask.position = rect.position
		mask.size = rect.size
		mask.color = Color("0c171d")
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(mask)
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
		clear_attack_input()
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
		var skill = button("", func(): assisted_attack(slot), GOLD)
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
	help_box.add_child(label("Move with WASD or arrows. Mouse attacks assist nearby targets. Q / E auto-aim.\nHold LMB / Q for Weapon; hold RMB / E for Offhand.\nF collects nearby drops. I opens equipment and pauses combat.\nClick a slot to filter the bag. Use its x button to remove gear.\n\nBasic skills attack continuously. Power skills have a cooldown.\nBoth active slots accept either kind — try any combination.\nToughness adds 65 HP. Bloodlust grants +40% damage after kills.\n\nFollow the road east through 3 gardens. Defeat the Warden.\nKills restore 4 HP plus gear bonuses. On completion, all loot is collected.\nStand in the eastern exit for 2.5s to advance. R retries after defeat.", 17))
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
	outer.add_child(label("PAUSED · Select a slot to filter. Click bag gear to equip.", 13, MUTED))
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
	inventory_filter_picker = OptionButton.new()
	inventory_filter_picker.add_item("ALL EQUIPMENT")
	for slot in Equipment.SLOTS:
		inventory_filter_picker.add_item(slot.to_upper())
	inventory_filter_picker.item_selected.connect(func(index): select_inventory_slot("" if index == 0 else Equipment.SLOTS[index - 1]))
	right.add_child(inventory_filter_picker)
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
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	var titles = {
		"health": "Health",
		"physical_attack": "Physical / spell attack",
		"armor": "Armor / magic resistance",
		"added_damage": "Added physical / spell damage",
		"cooldown_reduction": "Power cooldown reduction",
		"pickup_radius": "Pickup radius",
		"recovery": "Regen / health per kill",
		"elite": "Elite damage / reduction",
		"reduction": "Melee / ranged reduction",
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
	content.add_child(HSeparator.new())
	content.add_child(label("ACTIVE SKILLS  /  FINAL DAMAGE PER HIT", 13, GOLD))
	for index in range(2):
		var skill = label("", 15)
		content.add_child(skill)
		character_skills.append(skill)
	content.add_child(HSeparator.new())
	content.add_child(label("PASSIVE EFFECTS", 13, GOLD))
	character_passives = label("", 14, MUTED)
	content.add_child(character_passives)
	character_panel.hide()

func refresh_character_stats() -> void:
	if not is_instance_valid(character_panel):
		return
	character_values.health.text = "%.1f / %.1f" % [player.health, player.max_health]
	character_values.health.tooltip_text = "Maximum: 140 base + %.1f equipment + %d Toughness" % [equipment.bonus("health"), 65 if equipment.has_passive("toughness") else 0]
	character_values.physical_attack.text = "+%.1f / +%.1f" % [player.physical_attack, player.magic_attack]
	character_values.armor.text = "%.1f / %.1f" % [player.armor, player.magic_resist]
	character_values.armor.tooltip_text = "Damage taken = incoming damage x 100 / (100 + armor or magic resistance)."
	character_values.added_damage.text = "+%.1f / +%.1f" % [equipment.bonus("added_physical"), equipment.bonus("added_magic")]
	character_values.cooldown_reduction.text = "%.1f%% (cap 40%%)" % (player.cooldown_reduction * 100)
	character_values.pickup_radius.text = "%.1f px" % player.pickup_radius()
	character_values.recovery.text = "%.1f/s / %.1f" % [equipment.bonus("health_regen"), 4.0 + equipment.bonus("life_on_kill")]
	character_values.elite.text = "+%.1f%% / %.1f%%" % [equipment.bonus("elite_damage"), minf(35, equipment.bonus("elite_reduction"))]
	character_values.reduction.text = "%.1f%% / %.1f%%" % [minf(60, equipment.bonus("melee_reduction")), minf(60, equipment.bonus("ranged_reduction"))]
	character_values.attack_speed.text = "%.2f attacks/s" % (2.4 * player.attack_speed)
	character_values.move_speed.text = "%.1f px/s" % player.move_speed
	character_values.damage_multiplier.text = "%.2fx" % player.damage_multiplier()
	character_values.damage_multiplier.tooltip_text = "Bloodlust grants +40% damage while active."
	for index in range(2):
		var slot = "weapon" if index == 0 else "offhand"
		var gear: Gear = equipment.slots[slot]
		if gear == null:
			character_skills[index].text = "%s: Empty\nEquip an item to gain an active skill." % slot.capitalize()
			continue
		var ability = gear.definition.ability
		var damage = player.skill_damage(ability)
		var timing = "%.2f attacks/s" % (2.4 * player.attack_speed) if ability.kind == "basic" else "%.2fs cooldown" % player.effective_cooldown(ability)
		character_skills[index].text = "%s: %s · %.1f damage · %s\n%s damage + %.1f%% skill bonus; elite damage +%.1f%%" % [slot.capitalize(), ability.title, damage, timing, "Physical" if ability.id in ["slash", "cleave"] else "Spell", equipment.bonus("skill_damage:" + ability.id), equipment.bonus("elite_damage")]
	var toughness = "+65 maximum health" if equipment.has_passive("toughness") else "Not equipped"
	var bloodlust = "On kill: +40% damage for 4s" if equipment.has_passive("bloodlust") else "Not equipped"
	if player.bloodlust > 0:
		bloodlust = "ACTIVE: +40%% damage · %.1fs remaining" % player.bloodlust
	character_passives.text = "Toughness: %s\nBloodlust: %s" % [toughness, bloodlust]

func toggle_bag() -> void:
	clear_attack_input()
	bag_open = not bag_open
	inventory_panel.visible = bag_open
	character_panel.visible = bag_open
	end_panel.visible = state != "combat" and not bag_open
	if bag_open:
		refresh_inventory()

func select_inventory_slot(slot: String) -> void:
	if slot != "" and not slot in Equipment.SLOTS:
		return
	inventory_filter = slot
	inventory_filter_picker.select(0 if slot == "" else Equipment.SLOTS.find(slot) + 1)
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
		var row = HBoxContainer.new()
		equipped_list.add_child(row)
		var entry = button(text, func(): select_inventory_slot(slot), Gear.COLORS[gear.rarity] if gear != null else MUTED)
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.clip_text = true
		entry.custom_minimum_size.x = 225
		if inventory_filter == slot:
			entry.add_theme_stylebox_override("normal", style(Color("2b444c"), GOLD))
		entry.add_theme_font_size_override("font_size", 13)
		entry.tooltip_text = gear.details() + "\nClick to show matching items" if gear != null else "Click to show matching items"
		row.add_child(entry)
		var remove = button("×", func(): equipment.unequip(slot), MUTED)
		remove.tooltip_text = "Unequip " + slot
		remove.disabled = gear == null
		row.add_child(remove)
	var shown = 0
	for index in range(equipment.inventory.size()):
		var gear = equipment.inventory[index]
		if inventory_filter != "" and gear.definition.slot != inventory_filter:
			continue
		shown += 1
		var text = "%s  Lv.%d · %dP / %dS\n%s · %s" % [gear.definition.title, gear.level, gear.primary_count(), gear.secondary_affixes.size(), gear.definition.slot.capitalize(), gear.definition.ability.title]
		var entry = button(text, func(): equipment.equip(index), Gear.COLORS[gear.rarity])
		entry.clip_text = true
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.add_theme_font_size_override("font_size", 13)
		var worn: Gear = equipment.slots[gear.definition.slot]
		entry.tooltip_text = gear.details() + "\n\nCURRENTLY EQUIPPED\n" + (worn.details() if worn != null else "Empty")
		inventory_list.add_child(entry)
	if shown == 0:
		inventory_list.add_child(label("No matching items." if inventory_filter != "" else "No spare gear. Hunt for drops.", 13, MUTED))

func update_ui() -> void:
	if bag_open:
		refresh_character_stats()
	hp_bar.max_value = player.max_health
	hp_bar.value = player.health
	hp_label.text = "VITALITY     %d / %d" % [ceili(player.health), ceili(player.max_health)]
	stat_label.text = "ATK %.0f / spell %.0f   ·   %d move" % [player.physical_attack, player.magic_attack, int(player.move_speed)]
	objective.text = "EXPEDITION %02d    /    GARDEN %d OF %d" % [expedition, wave, level.wave_sizes.size()]
	if state == "combat":
		var hint = "Head east → next garden"
		if bag_open or help_open:
			hint = "PAUSED"
		elif wave == 0 and equipment.slots.weapon == null and equipment.slots.offhand == null:
			hint = "Collect [F] and equip [I] a weapon"
		elif not enemies.is_empty():
			hint = "Clear this garden · %d enemies" % enemies.size()
		elif exit_ready():
			hint = "Exit → stand %.1fs to advance" % maxf(0, level.exit_hold_seconds - exit_hold)
		info_label.text = "%d defeated · %d%% explored · %s" % [kills, clampi(int(100 * (player.position.x - level.spawn_point.x) / (level.exit_point.x - level.spawn_point.x)), 0, 100), hint]
	else:
		info_label.text = "DEFEATED · [R] RETRY"
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
	passive_label.text = "PASSIVES   /   " + "  ·  ".join(passives) + "\n" + ("BLOODLUST  +40%% damage  ·  %.1fs" % player.bloodlust if player.bloodlust > 0 else "Collect glowing drops with F · Head east to the exit")
