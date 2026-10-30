class_name Gear
extends RefCounted

const RARITIES = ["Common", "Rare", "Epic"]
const COLORS = [Color("a7b6bd"), Color("65c5ff"), Color("d6a0ff")]
var definition: ItemDefinition
var rarity: int = 0
var level: int = 1

func _init(template: ItemDefinition = null, quality: int = 0, item_level: int = 1) -> void:
	definition = template
	rarity = clampi(quality, 0, 2)
	level = maxi(1, item_level)

func multiplier() -> float:
	return (1.0 + rarity * 0.35) * (1.0 + (level - 1) * 0.16)

func stat(key: String) -> float:
	return float(definition.get(key)) * multiplier()

func display_name() -> String:
	return "%s · %s +%d" % [definition.title, RARITIES[rarity], level]

func details() -> String:
	var parts: PackedStringArray = []
	for key in ["health", "attack", "speed", "attack_speed"]:
		if stat(key) > 0:
			parts.append("+%s %s" % [str(snappedf(stat(key), 0.1)), key.replace("_", " ")])
	return "%s\n%s\n%s — %s\n%s" % [display_name(), definition.slot.to_upper(), definition.ability.title, definition.ability.description, " / ".join(parts)]

func serialize() -> Dictionary:
	return {"id": definition.id, "rarity": rarity, "level": level}
