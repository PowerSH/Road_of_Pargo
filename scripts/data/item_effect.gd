class_name ItemEffect
extends Resource

## 아이템 사용 효과. 전투 시작 직전에만 적용 (전투 중 발동 X).
## 5개 effect_type별로 다른 파라미터를 사용한다.
## 같은 effect_type의 슬롯이 여러 개일 때는 max만 적용(합산 X) — battle-flow.md §3 참조.

enum EffectType {
	STAT_BOOST,      ## 플레이어 측 ComputedStats에 % 보너스
	FAKE_SYNERGY,    ## SynergyEngine 실행 시 가상 룰 1회 추가
	TEMP_UNIT,       ## 임시 유닛을 플레이어 보드에 추가 (전투 후 폐기)
	ENEMY_DEBUFF,    ## 적 측 ComputedStats에 % 차감
	SHIELD,          ## 모든/특정 플레이어 유닛에 보호막 absolute 값 부여
}

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var effect_type: EffectType = EffectType.STAT_BOOST

@export_group("Bonuses v1 (multiplicative, 0.10 == +10% / -10%)")
@export var attack_bonus_pct: float = 0.0
@export var hp_bonus_pct: float = 0.0
@export var attack_speed_bonus_pct: float = 0.0
@export var move_speed_bonus_pct: float = 0.0
@export var range_bonus_pct: float = 0.0

@export_group("Bonuses v2 (additive — 절대값)")
@export var defense_bonus: float = 0.0
@export var crit_chance_bonus: float = 0.0
@export var crit_multiplier_bonus: float = 0.0
@export var armor_penetration_bonus: float = 0.0
@export var lifesteal_bonus: float = 0.0
@export var hp_regen_bonus: float = 0.0
@export var accuracy_bonus: float = 0.0
@export var attack_variance_pct_bonus: float = 0.0

@export_group("Filter / Target")
## STAT_BOOST / ENEMY_DEBUFF / SHIELD: 특정 태그 보유 유닛에만 적용.
## 빈 값(&"")이면 자기 진영 전 유닛.
@export var target_filter_tag: StringName = &""

@export_group("TEMP_UNIT")
@export var temp_unit: UnitData
@export var temp_unit_row: int = 0
@export var temp_unit_col: int = 0

@export_group("FAKE_SYNERGY")
## FAKE_SYNERGY일 때 SynergyEngine에 끼울 가상 SynergyRule.
@export var fake_rule: SynergyRule

@export_group("SHIELD")
@export var shield_amount: float = 0.0


## 같은 effect_type의 두 ItemEffect 중 "더 강한" 것을 고르는 비교용 점수.
## 1차안: attack_bonus_pct 기준. 필요 시 가중 조정 (battle-flow.md §9 TBD).
func strength_score() -> float:
	return absf(attack_bonus_pct) + absf(hp_bonus_pct) * 0.5 + absf(attack_speed_bonus_pct) + absf(shield_amount) * 0.001
