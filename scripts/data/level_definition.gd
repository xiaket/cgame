class_name LevelDefinition
extends Resource

@export var title: String = "The Ashen Garden"
@export var wave_sizes: PackedInt32Array = [7, 9, 11]
@export var ranged_interval: int = 3
@export var boss_wave: int = 3
@export var wave_break: float = 2.8
@export var enemy_growth: float = 0.25

# Connected clearings and trails, from the western camp to the eastern exit.
@export var walkable_regions: Array[Rect2] = [
	Rect2(48, 280, 740, 320), Rect2(600, 142, 800, 594),
	Rect2(1300, 330, 500, 220), Rect2(1700, 190, 850, 510),
	Rect2(2450, 330, 550, 220), Rect2(2900, 142, 1000, 594),
	Rect2(3800, 330, 450, 220),
]
@export var spawn_point: Vector2 = Vector2(220, 439)
@export var encounter_centers: PackedVector2Array = [Vector2(1000, 439), Vector2(2100, 439), Vector2(3400, 439)]
@export var encounter_triggers: PackedFloat32Array = [650, 1780, 2980]
@export var exit_point: Vector2 = Vector2(4100, 439)
@export var exit_radius: float = 62.0
@export var exit_hold_seconds: float = 2.5
