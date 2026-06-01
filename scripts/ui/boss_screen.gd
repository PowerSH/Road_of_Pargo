extends Control

## 챕터 보스 전투. 승리 시 다음 거점, 패배 시 런 종료.
## 최종 챕터 보스 처치 = 게임 클리어 (별도 처리 필요, 후순위).


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_canyon.jpg")


func _on_victory_pressed() -> void:
	# 챕터 카운터 증가 + 다음 챕터 맵 재생성.
	# 최종 챕터(3) 클리어 시 GameState가 run_cleared 발신 + end_run(true) 처리 → run=null.
	var prev_chapter: int = GameState.run.chapter if GameState.run != null else 0
	GameState.advance_chapter()
	if GameState.run == null:
		print("[Boss] 최종 챕터 클리어 — 게임 클리어")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	print("[Boss] 승리 — 챕터 %d → %d, 다음 거점" % [prev_chapter, GameState.run.chapter])
	get_tree().change_scene_to_file("res://scenes/hub_screen.tscn")


func _on_defeat_pressed() -> void:
	print("[Boss] 패배 — 런 종료")
	GameState.end_run(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
