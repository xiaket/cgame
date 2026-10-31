class_name AbilitySystem
extends RefCounted

var game: Node2D
# Slot-bound recovery prevents swapping equipment from bypassing cooldowns.
var cooldowns: Dictionary = {"weapon": 0.0, "offhand": 0.0}

func tick(delta: float) -> void:
	for slot in cooldowns:
		cooldowns[slot] = maxf(0.0, cooldowns[slot] - delta)

func use(slot: String, target: Vector2) -> bool:
	if not cooldowns.has(slot) or game.player.dead or game.state != "combat" or game.bag_open or game.help_open:
		return false
	var gear: Gear = game.equipment.slots[slot]
	if gear == null or cooldowns[slot] > 0:
		return false
	var ability = gear.definition.ability
	if ability.kind == "passive":
		return false
	var hero: Hero = game.player
	var direction = hero.position.direction_to(target)
	if direction == Vector2.ZERO:
		direction = hero.facing
	hero.facing = direction
	var damage = hero.skill_damage(ability)
	cooldowns[slot] = hero.effective_cooldown(ability)
	match ability.id:
		"slash", "cleave":
			var targets: Array[ArenaEnemy] = []
			for enemy in game.enemies:
				if enemy.dead:
					continue
				var offset: Vector2 = enemy.position - hero.position
				if offset.length() <= ability.reach + enemy.radius and (offset.normalized().dot(direction) > (0.25 if ability.id == "cleave" else 0.45) or offset.length() < 30):
					targets.append(enemy)
			targets.sort_custom(func(a, b): return hero.position.distance_squared_to(a.position) < hero.position.distance_squared_to(b.position))
			for enemy in targets:
				enemy.take_damage(damage * (1.0 + hero.equipment.bonus("elite_damage") / 100.0 if enemy.kind == "boss" else 1.0), hero)
				if ability.id == "slash":
					break
			game.effect(hero.position, ability.reach, ability.color, "slash", direction.angle())
		"fireball":
			game.spawn_projectile(hero.position + direction * 25, direction, damage, true, ability.radius, ability.color, hero.equipment.bonus("elite_damage"))
		"frost_nova":
			for enemy in game.enemies.duplicate():
				if not enemy.dead and enemy.position.distance_to(hero.position) <= ability.radius + enemy.radius:
					enemy.slow_remaining = 3.5
					enemy.take_damage(damage * (1.0 + hero.equipment.bonus("elite_damage") / 100.0 if enemy.kind == "boss" else 1.0), hero)
			game.effect(hero.position, ability.radius, ability.color, "ring")
	game.events.ability_used.emit(ability.id)
	return true
