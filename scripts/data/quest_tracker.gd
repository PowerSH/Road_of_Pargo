class_name QuestTracker
extends RefCounted

## 퀘스트 진행도 자동 누적 서비스. 게임 이벤트 발생 시점에 RunState.active_quests를
## 훑어 해당하는 종류의 퀘스트의 progress를 올린다.
##
## 호출 시점:
##   on_battle_won:  battle_screen 의 _on_battle_ended (PLAYER_WIN 시)
##   on_unit_hired:  RunState.add_unit_data (영입 직후)
##   grant_reward:   NPC 조우에서 보상 수령 버튼 클릭 시 (caller가 active_quests에서 제거)


## PLAYER_WIN 결과 시 호출. was_boss는 챕터 보스였는지 여부.
static func on_battle_won(run: RunState, was_boss: bool) -> void:
	if run == null:
		return
	for q: Quest in run.active_quests:
		match q.kind:
			Quest.Kind.WIN_BATTLES:
				q.progress = mini(q.progress + 1, q.target_value)
			Quest.Kind.DEFEAT_BOSS:
				if was_boss:
					q.progress = mini(q.progress + 1, q.target_value)


## RunState.add_unit_data에서 호출. 영입 1건당 progress 1.
static func on_unit_hired(run: RunState) -> void:
	if run == null:
		return
	for q: Quest in run.active_quests:
		if q.kind == Quest.Kind.HIRE_UNITS:
			q.progress = mini(q.progress + 1, q.target_value)


## 보상 지급 — 완료된 퀘스트에 한해 골드 지급. 성공 시 true.
## active_quests에서 제거 + completed_quest_ids에 추가는 caller가 처리.
static func grant_reward(run: RunState, q: Quest) -> bool:
	if run == null or q == null:
		return false
	if not q.is_complete():
		return false
	run.gold += q.reward_gold
	return true
