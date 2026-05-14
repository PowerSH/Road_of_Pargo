class_name SynergyRule
extends Resource

## A data-driven synergy: "if a unit of type X has N adjacent units of type Y,
## grant it these percent bonuses." Adjacency uses 8-direction neighbors on the
## 5x3 board (computed by SynergyEngine).

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

@export_group("Match")
## Empty StringName ("") matches any unit. Otherwise only units carrying this
## type in their UnitData.types receive the bonus.
@export var applies_to_type: StringName = &""
## The adjacent type that must be present. Empty matches any neighbor.
@export var requires_adjacent_type: StringName = &""
@export_range(1, 8) var min_adjacent: int = 1

@export_group("Effects (percent, 0.10 == +10%)")
@export var attack_bonus_pct: float = 0.0
@export var hp_bonus_pct: float = 0.0
@export var attack_speed_bonus_pct: float = 0.0
@export var move_speed_bonus_pct: float = 0.0
@export var range_bonus_pct: float = 0.0


func matches_self(unit: UnitData) -> bool:
	if applies_to_type == &"":
		return true
	return unit.has_type(applies_to_type)


func count_qualifying(neighbors: Array[UnitData]) -> int:
	if requires_adjacent_type == &"":
		return neighbors.size()
	var n: int = 0
	for u in neighbors:
		if u != null and u.has_type(requires_adjacent_type):
			n += 1
	return n
