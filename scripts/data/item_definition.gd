class_name ItemDefinition
extends Resource

@export var id: String = ""
@export var title: String = ""
@export_enum("weapon", "offhand", "helmet", "necklace") var slot: String = "weapon"
@export var ability: AbilityDefinition
