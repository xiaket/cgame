class_name LootSystem
extends RefCounted

static func roll(expedition: int, boss: bool = false) -> Gear:
	if not boss and randf() > 0.6:
		return null
	var rarity_roll = randf()
	var rarity = 2 if rarity_roll > 0.92 else (1 if rarity_roll > 0.55 else 0)
	if boss:
		rarity = 2
	return Gear.new(Catalog.item(Catalog.ITEM_IDS.pick_random()), rarity, expedition)
