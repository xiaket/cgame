class_name Equipment
extends RefCounted

const SLOTS = ["weapon", "offhand", "helmet", "necklace"]
var slots: Dictionary = {"weapon": null, "offhand": null, "helmet": null, "necklace": null}
var inventory: Array[Gear] = []
var events: CombatEvents

func equip(index: int) -> bool:
	if index < 0 or index >= inventory.size():
		return false
	var gear = inventory[index]
	inventory.remove_at(index)
	var old: Gear = slots[gear.definition.slot]
	slots[gear.definition.slot] = gear
	if old != null:
		inventory.append(old)
	events.equipment_changed.emit()
	return true

func unequip(slot: String) -> void:
	if not slots.has(slot) or slots[slot] == null:
		return
	inventory.append(slots[slot])
	slots[slot] = null
	events.equipment_changed.emit()

func bonus(key: String) -> float:
	var total = 0.0
	for gear in slots.values():
		if gear != null:
			total += gear.stat(key)
	return total

func has_passive(id: String) -> bool:
	for slot in ["helmet", "necklace"]:
		var gear: Gear = slots[slot]
		if gear != null and gear.definition.ability.id == id:
			return true
	return false
