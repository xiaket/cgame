class_name CombatEvents
extends Node

signal damaged(target: Node, amount: float, source: Node)
signal enemy_killed(enemy: Node, source: Node)
signal equipment_changed
signal ability_used(id: String)
signal level_completed(expedition: int)
