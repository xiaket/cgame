class_name Hero
extends Node2D

var equipment: Equipment
var world_map: JourneyMap
var health: float = 140.0
var max_health: float = 140.0
var physical_attack: float = 0.0
var magic_attack: float = 0.0
var armor: float = 0.0
var magic_resist: float = 0.0
var cooldown_reduction: float = 0.0
var move_speed: float = 245.0
var attack_speed: float = 1.0
var bloodlust: float = 0.0
var invulnerable: float = 0.0
var facing = Vector2.RIGHT
var walk_time: float = 0.0
var dead: bool = false

func recalculate() -> void:
	max_health = 140.0 + equipment.bonus("health")
	if equipment.has_passive("toughness"):
		max_health += 65.0
	physical_attack = equipment.bonus("physical_attack")
	magic_attack = equipment.bonus("magic_attack")
	armor = equipment.bonus("armor")
	magic_resist = equipment.bonus("magic_resist")
	cooldown_reduction = clampf(equipment.bonus("cooldown_reduction") / 100.0, 0.0, 0.4)
	move_speed = 245.0 + equipment.bonus("speed")
	attack_speed = 1.0
	# Preserve current HP, capped at the new maximum. Gear swaps never heal.
	health = clampf(health, 0.0, max_health)
	if not equipment.has_passive("bloodlust"):
		bloodlust = 0.0
	queue_redraw()

func tick(delta: float, direction: Vector2, arena: Rect2) -> void:
	bloodlust = maxf(0.0, bloodlust - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	if dead:
		return
	health = minf(max_health, health + equipment.bonus("health_regen") * delta)
	var displacement = direction.normalized() * move_speed * delta
	if world_map != null:
		position = world_map.move_actor(position, displacement, 18)
	else:
		position = (position + displacement).clamp(arena.position + Vector2(18, 18), arena.end - Vector2(18, 18))
	if direction.length_squared() > 0:
		walk_time += delta * 12.0
	queue_redraw()

func damage_multiplier() -> float:
	return 1.4 if bloodlust > 0 else 1.0

func skill_damage(ability: AbilityDefinition) -> float:
	var attack = physical_attack if ability.id in ["slash", "cleave"] else magic_attack
	var base = (ability.damage + attack) * (1.0 + equipment.bonus("skill_damage:" + ability.id) / 100.0)
	return (base + equipment.bonus("added_physical") + equipment.bonus("added_magic")) * damage_multiplier()

func effective_cooldown(ability: AbilityDefinition) -> float:
	return 1.0 / (2.4 * attack_speed) if ability.kind == "basic" else ability.cooldown * (1.0 - cooldown_reduction)

func pickup_radius() -> float:
	return 92.0 + equipment.bonus("pickup_radius")

func take_damage(amount: float, source: Node, events: CombatEvents, damage_type: String = "physical", attack_kind: String = "melee", elite: bool = false) -> void:
	if dead or invulnerable > 0:
		return
	var defense = magic_resist if damage_type == "magic" else armor
	amount *= 100.0 / (100.0 + maxf(0.0, defense))
	amount *= 1.0 - clampf(equipment.bonus(attack_kind + "_reduction") / 100.0, 0.0, 0.6)
	if elite:
		amount *= 1.0 - clampf(equipment.bonus("elite_reduction") / 100.0, 0.0, 0.35)
	health = maxf(0.0, health - amount)
	invulnerable = 0.18
	dead = health <= 0
	events.damaged.emit(self, amount, source)

func on_kill(_enemy: Node, source: Node) -> void:
	if source == self and equipment.has_passive("bloodlust"):
		bloodlust = 4.0

func _draw() -> void:
	draw_ellipse_shadow()
	if bloodlust > 0:
		draw_arc(Vector2.ZERO, 27, 0, TAU, 32, Color("ffb46b"), 2.0)
	var tint = Color("eff7ee") if invulnerable <= 0 else Color("ffb8ac")
	var stride = sin(walk_time) * 3
	draw_line(Vector2(-7, 8), Vector2(-8, 20 + stride), Color("465e70"), 7)
	draw_line(Vector2(7, 8), Vector2(8, 20 - stride), Color("465e70"), 7)
	draw_colored_polygon(PackedVector2Array([Vector2(-17, 10), Vector2(-12, -12), Vector2(0, -19), Vector2(13, -11), Vector2(17, 10)]), Color("54b9bd"))
	draw_circle(Vector2(0, -15), 9, tint)
	draw_line(facing * 13, facing * 34, Color("ffe2a7"), 5)
	draw_circle(facing * 13, 5, Color("d4a66a"))

func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0, 18), 0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 24, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO)
