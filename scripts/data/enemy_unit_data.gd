class_name EnemyUnitData
extends Resource

## 적 유닛 베이스. 플레이어의 UnitData와 의도적으로 분리(상호 재사용 금지).
## 적은 자체 진영 태그 + 보스 플래그를 가지며, AI/패시브는 향후 확장.

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
@export_range(0.0, 0.95) var defense: float = 0.0
@export_range(0.0, 1.0) var crit_chance: float = 0.0
@export_range(1.0, 5.0) var crit_multiplier: float = 1.5
@export_range(0.0, 1.0) var armor_penetration: float = 0.0
@export_range(0.0, 1.0) var lifesteal: float = 0.0
@export var hp_regen: float = 0.0
@export_range(0.0, 1.0) var accuracy: float = 0.0
@export_range(0.0, 1.0) var attack_variance_pct: float = 0.20

@export_group("Enemy Identity")
## 진영 태그. EnemySynergyRule이 이 값을 기준으로 매칭한다.
## Array로 둔 이유: 추후 다축 시너지(예: 종족 + 직책)로 확장 여지.
@export var faction_tags: Array[StringName] = []
## 보스 마킹. BOSS_AURA 시너지의 중심점이 되며, 시각 강조(아이콘/스케일)도 이 플래그 기반.
@export var is_boss: bool = false

@export_group("Visuals")
@export var icon: Texture2D
@export var sprite: Texture2D


## 인카운터 난이도 산정용 휴리스틱. EncounterTemplate.power_target에 도달하는지 검사할 때 사용.
## 공격 출력 가중치를 가장 높게 잡았다. 밸런싱 단계에서 계수 조정 가능.
func compute_power_score() -> float:
	return (
		max_hp * 0.4
		+ attack * attack_speed * 6.0
		+ attack_range * 0.05
		+ move_speed * 0.05
	)


func has_faction(t: StringName) -> bool:
	return faction_tags.has(t)
