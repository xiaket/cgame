class_name AimAssist
extends RefCounted

static func choose(hero: Hero, ability: AbilityDefinition, enemies: Array[ArenaEnemy], world_map: JourneyMap, direction: Vector2, automatic: bool) -> ArenaEnemy:
	if ability.id == "frost_nova":
		return null
	var front: ArenaEnemy = null
	var fallback: ArenaEnemy = null
	var front_distance = INF
	var fallback_distance = INF
	var cone = cos(deg_to_rad(60.0 if automatic else 35.0))
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var offset = enemy.position - hero.position
		var distance = offset.length()
		var reach = ability.reach + (enemy.radius if ability.id in ["slash", "cleave"] else 0.0)
		if distance > reach or not world_map.line_clear(hero.position, enemy.position):
			continue
		if distance < fallback_distance:
			fallback = enemy
			fallback_distance = distance
		if offset.normalized().dot(direction) >= cone and distance < front_distance:
			front = enemy
			front_distance = distance
	return front if front != null else (fallback if automatic else null)
