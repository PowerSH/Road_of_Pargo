class_name ComputedStats
extends Resource

## Final stats after synergy bonuses are applied. Produced by SynergyEngine
## and consumed by CombatUnit when battle starts.

@export var source: UnitData
@export var max_hp: float
@export var attack: float
@export var attack_speed: float
@export var attack_range: float
@export var move_speed: float

## Names of synergies that contributed to this unit's bonuses. Useful for UI
## tooltips ("+10% atk from Warrior, +20% hp from Pack").
@export var applied_synergies: Array[StringName] = []


static func from_base(unit: UnitData) -> ComputedStats:
	var s := ComputedStats.new()
	s.source = unit
	s.max_hp = unit.max_hp
	s.attack = unit.attack
	s.attack_speed = unit.attack_speed
	s.attack_range = unit.attack_range
	s.move_speed = unit.move_speed
	return s
