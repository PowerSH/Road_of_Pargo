extends Control

## 챕터 보스 전투. 승리 시 다음 거점, 패배 시 런 종료.
## 최종 챕터 보스 처치 = 게임 클리어 (별도 처리 필요, 후순위).


func _on_victory_pressed() -> void:
	print("[Boss] 승리 — 다음 거점")
	# TODO: 챕터 카운터 증가, 다음 챕터 맵 재생성 (RunState 확장 필요)
	get_tree().change_scene_to_file("res://scenes/hub_screen.tscn")


func _on_defeat_pressed() -> void:
	print("[Boss] 패배 — 런 종료")
	GameState.end_run(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
