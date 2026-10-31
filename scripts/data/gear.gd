class_name Gear
extends RefCounted

const RARITIES = ["Common", "Magic", "Rare"]
const COLORS = [Color("eeeeee"), Color("65c5ff"), Color("ffdb58")]
var definition: ItemDefinition
var rarity: int = 0
var level: int = 1
# The fixed granted skill is primary affix #1; these hold numerical rolls only.
var primary_affixes: Array[Dictionary] = []
var secondary_affixes: Array[Dictionary] = []

func _init(template: ItemDefinition = null, quality: int = 0, item_level: int = 1, roll_affixes: bool = true) -> void:
	definition = template
	rarity = clampi(quality, 0, 2)
	level = maxi(1, item_level)
	if template != null and roll_affixes:
		generate_affixes()

func generate_affixes() -> void:
	primary_affixes.clear()
	secondary_affixes.clear()
	var pool = AffixCatalog.PRIMARY.keys()
	pool.shuffle()
	for index in range(2 if rarity == 2 else 1):
		primary_affixes.append(AffixCatalog.roll(pool[index], false, rarity, level, definition.ability.id))
	if rarity > 0:
		secondary_affixes.append(AffixCatalog.roll(AffixCatalog.SECONDARY.keys().pick_random(), true, rarity, level))

func primary_count() -> int:
	return 1 + primary_affixes.size()

func stat(key: String) -> float:
	var total = 0.0
	for affix in primary_affixes + secondary_affixes:
		var stat_id: String = affix.id
		if stat_id == "skill_damage":
			stat_id += ":" + str(affix.skill)
		if stat_id == key:
			total += float(affix.value)
	return total

func display_name() -> String:
	return "%s · %s Lv.%d" % [definition.title, RARITIES[rarity], level]

func details() -> String:
	var lines: PackedStringArray = [display_name(), definition.slot.to_upper(), "PRIMARY AFFIXES (%d)" % primary_count(), "%s — %s" % [definition.ability.title, definition.ability.description]]
	for affix in primary_affixes:
		lines.append(AffixCatalog.describe(affix, false))
	lines.append("SECONDARY AFFIXES (%d)" % secondary_affixes.size())
	for affix in secondary_affixes:
		lines.append(AffixCatalog.describe(affix, true))
	return "\n".join(lines)

func serialize() -> Dictionary:
	return {"id": definition.id, "rarity": rarity, "level": level, "primary_affixes": primary_affixes.duplicate(true), "secondary_affixes": secondary_affixes.duplicate(true)}
