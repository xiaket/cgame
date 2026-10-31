class_name AffixCatalog
extends RefCounted

# Categories follow doc/affixes. Only mechanics available in this game can roll.
const PRIMARY = {
	"physical_attack": ["Physical attack", 5.0, 10.0, false],
	"magic_attack": ["Spell attack", 5.0, 10.0, false],
	"armor": ["Armor", 8.0, 16.0, false],
	"magic_resist": ["Magic resistance", 8.0, 16.0, false],
	"health": ["Maximum health", 15.0, 30.0, false],
	"skill_damage": ["Skill damage", 8.0, 16.0, true],
	"cooldown_reduction": ["Cooldown reduction", 3.0, 6.0, true],
	"added_physical": ["Added physical damage", 3.0, 6.0, false],
	"added_magic": ["Added spell damage", 3.0, 6.0, false],
}
const SECONDARY = {
	"elite_damage": ["Damage to elites", 5.0, 10.0, true],
	"elite_reduction": ["Damage reduction from elites", 3.0, 6.0, true],
	"speed": ["Movement speed", 8.0, 16.0, false],
	"pickup_radius": ["Pickup radius", 15.0, 30.0, false],
	"health_regen": ["Health per second", 0.5, 1.5, false],
	"life_on_kill": ["Health per kill", 1.0, 3.0, false],
	"melee_reduction": ["Melee damage reduction", 3.0, 6.0, true],
	"ranged_reduction": ["Ranged damage reduction", 3.0, 6.0, true],
}
const DAMAGE_SKILLS = ["slash", "cleave", "fireball", "frost_nova"]

static func roll(key: String, secondary: bool, rarity: int, level: int, skill: String = "") -> Dictionary:
	var info: Array = (SECONDARY if secondary else PRIMARY)[key]
	var scale = 1.0 + rarity * 0.25
	if not info[3] and not secondary:
		scale *= 1.0 + (level - 1) * 0.16
	var affix = {"id": key, "value": snappedf(randf_range(info[1], info[2]) * scale, 0.1)}
	if key == "skill_damage":
		affix["skill"] = skill if skill in DAMAGE_SKILLS else DAMAGE_SKILLS.pick_random()
	return affix

static func describe(affix: Dictionary, secondary: bool) -> String:
	var info: Array = (SECONDARY if secondary else PRIMARY)[affix.id]
	var title: String = info[0]
	if affix.id == "skill_damage":
		title = str(affix.skill).replace("_", " ").capitalize() + " damage"
	return "+%s%s %s" % [str(affix.value), "%" if info[3] else "", title]
