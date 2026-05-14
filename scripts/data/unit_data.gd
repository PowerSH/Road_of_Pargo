class_name UnitData
extends Resource

@export var id: StringName
@export var display_name: String

@export_group("Combat Stats")
@export var max_hp: float = 100.0
@export var attack: float = 10.0
## Attacks per second.
@export var attack_speed: float = 1.0
## World-space units (pixels) at which this unit can hit a target.
@export var attack_range: float = 80.0
## World-space units per second.
@export var move_speed: float = 120.0

@export_group("Synergy")
## Synergy tags. Single-axis for now; designed as an Array so future axes
## (e.g. race + class) can be added without changing the data model.
@export var types: Array[StringName] = []

@export_group("Economy")
@export var cost: int = 1
@export var tier: int = 1

@export_group("Visuals")
@export var icon: Texture2D
@export var sprite: Texture2D


func has_type(t: StringName) -> bool:
	return types.has(t)
