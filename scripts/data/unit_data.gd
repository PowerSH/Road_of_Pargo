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
## Synergy tags. Each unit carries one tag per axis (nation/class/type) plus
## any item-granted tags. See SynergyTypes for the canonical constants and
## docs/design/synergy-axes.md for the axis taxonomy.
@export var types: Array[StringName] = []

@export_group("Economy")
@export var cost: int = 1
@export var tier: int = 1

@export_group("Visuals")
@export var icon: Texture2D
@export var sprite: Texture2D


func has_type(t: StringName) -> bool:
	return types.has(t)


## Returns the unit's nation tag, or &"" if none/multiple set (which is a data bug).
func get_nation() -> StringName:
	return _single_from_axis(SynergyTypes.ALL_NATIONS)


func get_class() -> StringName:
	return _single_from_axis(SynergyTypes.ALL_CLASSES)


func get_type_tag() -> StringName:
	return _single_from_axis(SynergyTypes.ALL_TYPES)


func _single_from_axis(axis: Array[StringName]) -> StringName:
	var found: StringName = &""
	for t in types:
		if axis.has(t):
			if found != &"":
				return &""
			found = t
	return found


## Returns a list of axis-completeness problems for this unit. Empty list ==
## valid. Use in editor tooling / dev assertions, not in hot paths.
func validate_axes() -> Array[String]:
	var problems: Array[String] = []
	if get_nation() == &"":
		problems.append("nation tag missing or duplicated")
	if get_class() == &"":
		problems.append("class tag missing or duplicated")
	if get_type_tag() == &"":
		problems.append("type tag missing or duplicated")
	return problems
