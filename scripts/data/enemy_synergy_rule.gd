class_name EnemySynergyRule
extends Resource

## 적 진영 시너지. 플레이어의 SynergyRule(인접 친화 단일 메카닉)과 의도적으로 다른 형태.
## 5개 패턴을 effect_type으로 구분하고, 트리거/계산은 별도 엔진에서 effect_type 분기로 처리한다.
## 자세한 패턴 정의·통합 포인트는 docs/design/encounters.md.

enum EffectType {
	GLOBAL_TRAIT,       ## 진영 N마리 이상이면 그 진영 전체 보너스 (pre-battle)
	BOSS_AURA,          ## 보스 인접 시 부하 강화 (pre-battle)
	DEATH_TRIGGER,      ## 아군 1마리 사망 시 생존 적 전체 누적 보너스 (combat-time)
	HP_THRESHOLD,       ## 자신의 HP가 임계 이하일 때 자기 강화 (combat-time)
	NUMBER_ADVANTAGE,   ## 적이 플레이어보다 N마리 많을 때 보너스 (combat-time)
}

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var effect_type: EffectType = EffectType.GLOBAL_TRAIT

@export_group("Trigger")
## 매칭할 진영 태그. EffectType에 따라 의미가 다르다:
##  - GLOBAL_TRAIT: 보너스를 받을 진영
##  - BOSS_AURA: 보스의 어떤 진영 부하에게 적용할지 (빈 값이면 전 진영)
##  - DEATH_TRIGGER: 사망 시 생존 진영 (빈 값이면 진영 무관)
##  - HP_THRESHOLD / NUMBER_ADVANTAGE: 적용 진영(빈 값이면 전 진영)
@export var trigger_faction: StringName = &""
## GLOBAL_TRAIT의 최소 마리 수, NUMBER_ADVANTAGE의 우위 격차.
@export_range(1, 15) var trigger_count: int = 1
## HP_THRESHOLD의 임계 비율 (0.5 = 50% 이하일 때 발동).
@export_range(0.0, 1.0) var hp_threshold: float = 0.5

@export_group("Effects (percent, 0.10 == +10%)")
@export var attack_bonus_pct: float = 0.0
@export var hp_bonus_pct: float = 0.0
@export var attack_speed_bonus_pct: float = 0.0
@export var move_speed_bonus_pct: float = 0.0
@export var range_bonus_pct: float = 0.0


## 전투 시작 전에 ComputedStats로 합쳐지는 규칙(true)인지,
## 전투 중 매 틱 평가되어야 하는 규칙(false)인지 구분.
func is_pre_battle() -> bool:
	return effect_type == EffectType.GLOBAL_TRAIT or effect_type == EffectType.BOSS_AURA
