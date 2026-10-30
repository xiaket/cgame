class_name ItemDefinition
extends Resource

@export var id: String = ""
@export var title: String = ""
@export_enum("weapon", "offhand", "helmet", "necklace") var slot: String = "weapon"
@export var ability: AbilityDefinition
@export var health: float = 0.0
@export var attack: float = 0.0
@export var speed: float = 0.0
@export var attack_speed: float = 0.0
