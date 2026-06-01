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

@export_group("Combat Stats v2 — 받는/주는 데미지 보정")
## 받는 데미지 감산율 (0.10 = 10% 감산). 캡은 CombatUnit에서 0.95.
@export_range(0.0, 0.95) var defense: float = 0.0
## 크리티컬 발동 확률.
@export_range(0.0, 1.0) var crit_chance: float = 0.0
## 크리티컬 시 데미지 곱셈자.
@export_range(1.0, 5.0) var crit_multiplier: float = 1.5
## 대상의 defense를 (1 - armor_penetration) 만큼 무력화.
@export_range(0.0, 1.0) var armor_penetration: float = 0.0
## 가한 데미지 × lifesteal 만큼 자기 회복.
@export_range(0.0, 1.0) var lifesteal: float = 0.0
## 초당 HP 회복량 (절대값).
@export var hp_regen: float = 0.0
## 데미지 분산 축소 비율 (0=풀 분산, 1=정확). attack_variance_pct와 페어.
@export_range(0.0, 1.0) var accuracy: float = 0.0
## 데미지 기본 분산 폭 (0.20 = ±20%).
##   effective_spread = attack_variance_pct × (1 - accuracy)
##   damage = attack × random[1-spread, 1+spread]
@export_range(0.0, 1.0) var attack_variance_pct: float = 0.20

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


## Returns the unit's class tag (보병/창병/궁병/석궁병), or &"" if none/multiple set.
## Named *_tag to avoid clashing with Object.get_class() (which returns the script type).
func get_class_tag() -> StringName:
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
	if get_class_tag() == &"":
		problems.append("class tag missing or duplicated")
	if get_type_tag() == &"":
		problems.append("type tag missing or duplicated")
	return problems
