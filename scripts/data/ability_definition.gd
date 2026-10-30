class_name AbilityDefinition
extends Resource

@export var id: String = ""
@export var title: String = ""
@export_enum("basic", "power", "passive") var kind: String = "basic"
@export var description: String = ""
@export var damage: float = 0.0
@export var cooldown: float = 0.0
@export var reach: float = 100.0
@export var radius: float = 50.0
@export var color: Color = Color.WHITE
