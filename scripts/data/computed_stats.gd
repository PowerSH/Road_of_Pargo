class_name ComputedStats
extends Resource

## Final stats after synergy bonuses are applied. Produced by SynergyEngine
## (player) or EnemySynergyEngine (enemy) and consumed by CombatUnit when battle starts.

## UnitData (player) 또는 EnemyUnitData (enemy). UI 툴팁/디버그용 — 시뮬레이션에는 안 쓰임.
@export var source: Resource

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


static func from_enemy(unit: EnemyUnitData) -> ComputedStats:
	var s := ComputedStats.new()
	s.source = unit
	s.max_hp = unit.max_hp
	s.attack = unit.attack
	s.attack_speed = unit.attack_speed
	s.attack_range = unit.attack_range
	s.move_speed = unit.move_speed
	return s
