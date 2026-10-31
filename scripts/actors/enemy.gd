class_name ArenaEnemy
extends Node2D

var game: Node2D
var kind: String = "melee"
var health: float = 60.0
var max_health: float = 60.0
var power: float = 10.0
var speed: float = 95.0
var cooldown: float = 0.8
var slow_remaining: float = 0.0
var flash: float = 0.0
var dead: bool = false
var boss_windup: float = 0.0
var boss_target: Vector2
var radius: float = 17.0

func configure(owner_game: Node2D, enemy_kind: String, strength: float) -> void:
	game = owner_game
	kind = enemy_kind
	if kind == "ranged":
		max_health = 48.0 * strength
		speed = 85.0
		power = 11.0 * strength
	elif kind == "boss":
		max_health = 520.0 * strength
		speed = 65.0
		power = 23.0 * strength
		radius = 34.0
	else:
		max_health = 65.0 * strength
		power = 9.0 * strength
	health = max_health
	cooldown = randf_range(0.4, 1.1)

func tick(delta: float) -> void:
	if dead or game.player.dead:
		return
	cooldown -= delta
	slow_remaining = maxf(0.0, slow_remaining - delta)
	flash = maxf(0.0, flash - delta)
	var offset: Vector2 = game.player.position - position
	var distance = offset.length()
	if boss_windup > 0:
		boss_windup -= delta
		if boss_windup <= 0:
			game.effect(boss_target, 100, Color("ef805c"), "ring")
			if game.player.position.distance_to(boss_target) < 116:
				game.player.take_damage(power * 1.6, self, game.events, "physical", "melee", true)
		queue_redraw()
		return
	var movement = game.world_map.steer(position, game.player.position, radius)
	if kind == "ranged":
		if distance < 190:
			movement = -movement
		elif distance < 340:
			movement = Vector2.ZERO
		if cooldown <= 0 and distance < 600 and game.world_map.line_clear(position, game.player.position):
			game.spawn_projectile(position, offset.normalized(), power, false, 0, Color("ff8b88"))
			cooldown = 1.9
	elif kind == "boss" and cooldown <= 0 and distance < 430:
		boss_target = game.player.position
		boss_windup = 1.0
		cooldown = 3.0
	elif distance < radius + 23 and cooldown <= 0:
		game.player.take_damage(power, self, game.events)
		cooldown = 0.85
	if distance > radius + 16 or kind == "ranged":
		var separation = Vector2.ZERO
		for other in game.enemies:
			if other != self and not other.dead:
				var difference: Vector2 = position - other.position
				if difference.length_squared() < pow(radius + other.radius + 5, 2):
					separation += difference.normalized() * 0.7
		var displacement = (movement + separation).limit_length() * speed * (0.4 if slow_remaining > 0 else 1.0) * delta
		position = game.world_map.move_actor(position, displacement, radius)
	queue_redraw()

func take_damage(amount: float, source: Node) -> void:
	if dead:
		return
	health = maxf(0.0, health - amount)
	flash = 0.12
	game.events.damaged.emit(self, amount, source)
	if health <= 0:
		dead = true
		game.events.enemy_killed.emit(self, source)
		queue_free()
	queue_redraw()

func _draw() -> void:
	var tint = Color("c88769")
	if kind == "ranged":
		tint = Color("b295cf")
	elif kind == "boss":
		tint = Color("d1a159")
	if slow_remaining > 0:
		tint = Color("85d8ed")
	if flash > 0:
		tint = Color.WHITE
	draw_circle(Vector2(0, 8), radius + 3, Color(0, 0, 0, 0.2))
	var points = PackedVector2Array()
	for i in range(6):
		points.append(Vector2.from_angle(i * TAU / 6 - PI / 2) * radius)
	draw_colored_polygon(points, tint)
	draw_circle(Vector2(-radius * 0.3, -3), 3, Color("302d36"))
	draw_circle(Vector2(radius * 0.3, -3), 3, Color("302d36"))
	if kind == "ranged":
		draw_arc(Vector2.ZERO, radius + 5, -1, 1, 12, tint, 3)
	if kind == "boss":
		draw_polyline(PackedVector2Array([Vector2(-27, -20), Vector2(-29, -43), Vector2(-12, -30), Vector2(0, -47), Vector2(12, -30), Vector2(29, -43), Vector2(27, -20)]), Color("ffe1a1"), 4)
	if health < max_health or kind == "boss":
		draw_rect(Rect2(-radius, -radius - 14, radius * 2, 4), Color("282a34"))
		draw_rect(Rect2(-radius, -radius - 14, radius * 2 * health / max_health, 4), Color("ef9a7a"))
