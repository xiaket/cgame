class_name Catalog
extends RefCounted

const ITEM_IDS = ["iron_blade", "crescent_axe", "ember_wand", "winter_focus", "duelist_guard", "sweeping_guard", "ember_orb", "frost_orb", "oak_helm", "hunter_helm", "ruby_pendant", "stone_pendant"]

static func item(id: String) -> ItemDefinition:
	if not id in ITEM_IDS:
		return null
	return load("res://data/items/%s.tres" % id) as ItemDefinition

static func gear_from(data: Dictionary) -> Gear:
	var template = item(str(data.get("id", "")))
	if template == null:
		return null
	var gear = Gear.new(template, int(data.get("rarity", 0)), int(data.get("level", 1)), false)
	# Legacy records without rolled affixes are intentionally unsupported.
	if not data.has("primary_affixes") or not data.has("secondary_affixes"):
		return null
	for affix in data.primary_affixes:
		gear.primary_affixes.append(affix.duplicate(true))
	for affix in data.secondary_affixes:
		gear.secondary_affixes.append(affix.duplicate(true))
	return gear
