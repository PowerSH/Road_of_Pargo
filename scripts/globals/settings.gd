extends Node

## 사용자 옵션 autoload. battle-flow.md §8 참조.
## 저장/불러오기는 후순위 — 일단 메모리만 (앱 재시작 시 기본값으로 돌아감).

signal hp_bar_mode_changed(mode: HpBarMode)
signal damage_number_mode_changed(mode: DamageNumberMode)
signal combat_speed_changed(speed: float)

enum HpBarMode {
	ALWAYS,      ## CombatUnit 위 HP 바 상시 표시
	ON_HOVER,    ## 마우스 오버 시만
}

enum DamageNumberMode {
	ALL,         ## 모든 데미지 숫자 띄움
	NONE,        ## 표시 안 함
}

var hp_bar_mode: HpBarMode = HpBarMode.ALWAYS:
	set(value):
		if hp_bar_mode == value:
			return
		hp_bar_mode = value
		hp_bar_mode_changed.emit(value)

var damage_number_mode: DamageNumberMode = DamageNumberMode.ALL:
	set(value):
		if damage_number_mode == value:
			return
		damage_number_mode = value
		damage_number_mode_changed.emit(value)

## 전투 배속. 1.0 또는 2.0 (UI에서 토글).
var combat_speed: float = 1.0:
	set(value):
		var clamped: float = clampf(value, 1.0, 2.0)
		if is_equal_approx(combat_speed, clamped):
			return
		combat_speed = clamped
		combat_speed_changed.emit(clamped)


func toggle_combat_speed() -> void:
	combat_speed = 2.0 if is_equal_approx(combat_speed, 1.0) else 1.0
