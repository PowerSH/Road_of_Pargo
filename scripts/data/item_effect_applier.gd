class_name ItemEffectApplier
extends RefCounted

## 슬롯에 채워진 ItemEffect들을 받아 전투 직전 ComputedStats를 변형하는 서비스.
## battle-flow.md §3 통합 흐름 — 같은 effect_type은 max(strength_score) 1개만 적용.
##
## 사용:
##   var consolidated := ItemEffectApplier.consolidate(slot_effects)
##   player_stats = ItemEffectApplier.apply_to_player(player_stats, player_owned, consolidated)
##   enemy_stats  = ItemEffectApplier.apply_to_enemy(enemy_stats, enemy_sources, consolidated)
##   var fake_rules := ItemEffectApplier.collect_fake_rules(consolidated)
##   var temp_units := ItemEffectApplier.collect_temp_units(consolidated)


## 같은 effect_type 그룹별로 strength_score가 가장 높은 1개만 남긴다.
## 다른 effect_type끼리는 독립적으로 누적된다.
static func consolidate(effects: Array[ItemEffect]) -> Array[ItemEffect]:
	var best_by_type: Dictionary = {}  ## EffectType -> ItemEffect
	for ef in effects:
		if ef == null:
			continue
		var t: int = ef.effect_type
		var prev: ItemEffect = best_by_type.get(t)
		if prev == null or ef.strength_score() > prev.strength_score():
			best_by_type[t] = ef
	var out: Array[ItemEffect] = []
	for v in best_by_type.values():
		out.append(v)
	return out


## STAT_BOOST + SHIELD를 플레이어 ComputedStats에 적용. ENEMY_DEBUFF는 enemy에서.
## owned 배열은 stats와 parallel — target_filter_tag 매칭에 사용.
## stats 객체를 in-place 수정한다 (호출자가 fresh ComputedStats 가져온 상태라 가정).
static func apply_to_player(stats_list: Array[ComputedStats],
		owned_list: Array[OwnedUnit],
		effects: Array[ItemEffect]) -> void:
	for ef in effects:
		match ef.effect_type:
			ItemEffect.EffectType.STAT_BOOST:
				_apply_stat_boost(stats_list, owned_list, ef)
			ItemEffect.EffectType.SHIELD:
				# SHIELD는 ComputedStats가 표현 못 함 — caller가 CombatUnit.shield로 처리해야 함.
				# 여기선 노옵. collect_shield()로 별도 수집 권장.
				pass
			_:
				# FAKE_SYNERGY / TEMP_UNIT / ENEMY_DEBUFF — 다른 경로 처리
				pass


## ENEMY_DEBUFF만 enemy ComputedStats에 적용. enemy_sources는 stats와 parallel
## EnemyUnitData 배열 — target_filter_tag(진영) 매칭에 사용.
static func apply_to_enemy(stats_list: Array[ComputedStats],
		enemy_sources: Array[EnemyUnitData],
		effects: Array[ItemEffect]) -> void:
	for ef in effects:
		if ef.effect_type != ItemEffect.EffectType.ENEMY_DEBUFF:
			continue
		for i in stats_list.size():
			if ef.target_filter_tag != &"":
				var src: EnemyUnitData = enemy_sources[i] if i < enemy_sources.size() else null
				if src == null or not src.has_faction(ef.target_filter_tag):
					continue
			# 디버프 = 음의 보너스로 작용
			var s: ComputedStats = stats_list[i]
			s.attack = s.attack * (1.0 - ef.attack_bonus_pct)
			s.max_hp = s.max_hp * (1.0 - ef.hp_bonus_pct)
			s.attack_speed = s.attack_speed * (1.0 - ef.attack_speed_bonus_pct)
			s.move_speed = s.move_speed * (1.0 - ef.move_speed_bonus_pct)
			s.attack_range = s.attack_range * (1.0 - ef.range_bonus_pct)


## FAKE_SYNERGY 효과들에서 가상 SynergyRule을 추출. SynergyEngine.compute 재호출 시
## active_rules와 함께 합쳐 넘기면 된다.
static func collect_fake_rules(effects: Array[ItemEffect]) -> Array[SynergyRule]:
	var out: Array[SynergyRule] = []
	for ef in effects:
		if ef.effect_type == ItemEffect.EffectType.FAKE_SYNERGY and ef.fake_rule != null:
			out.append(ef.fake_rule)
	return out


## TEMP_UNIT 효과들에서 임시 OwnedUnit 인스턴스를 만든다. battle_screen이 보드에 끼워 넣을 것.
## 이 OwnedUnit들은 전투 종료 후 폐기 (run에 영구 추가하지 말 것).
static func collect_temp_units(effects: Array[ItemEffect]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []  ## [{owned, row, col}, ...]
	for ef in effects:
		if ef.effect_type != ItemEffect.EffectType.TEMP_UNIT or ef.temp_unit == null:
			continue
		var owned := OwnedUnit.new()
		owned.source = ef.temp_unit
		out.append({"owned": owned, "row": ef.temp_unit_row, "col": ef.temp_unit_col})
	return out


## SHIELD 효과들에서 (target_filter_tag, shield_amount) 페어를 모은다.
## battle_screen 또는 CombatManager가 매칭되는 CombatUnit에 shield 부여.
static func collect_shields(effects: Array[ItemEffect]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []  ## [{filter_tag, amount}, ...]
	for ef in effects:
		if ef.effect_type == ItemEffect.EffectType.SHIELD and ef.shield_amount > 0.0:
			out.append({"filter_tag": ef.target_filter_tag, "amount": ef.shield_amount})
	return out


# ─────────────────────────────────────────────────────────────
# Internal
# ─────────────────────────────────────────────────────────────
static func _apply_stat_boost(stats_list: Array[ComputedStats],
		owned_list: Array[OwnedUnit],
		ef: ItemEffect) -> void:
	for i in stats_list.size():
		if ef.target_filter_tag != &"":
			var owned: OwnedUnit = owned_list[i] if i < owned_list.size() else null
			if owned == null or owned.source == null:
				continue
			if not owned.source.has_type(ef.target_filter_tag):
				continue
		var s: ComputedStats = stats_list[i]
		s.attack = s.attack * (1.0 + ef.attack_bonus_pct)
		s.max_hp = s.max_hp * (1.0 + ef.hp_bonus_pct)
		s.attack_speed = s.attack_speed * (1.0 + ef.attack_speed_bonus_pct)
		s.move_speed = s.move_speed * (1.0 + ef.move_speed_bonus_pct)
		s.attack_range = s.attack_range * (1.0 + ef.range_bonus_pct)
