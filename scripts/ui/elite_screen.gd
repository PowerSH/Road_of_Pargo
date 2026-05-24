extends Control

## 엘리트 전투 화면. 일반 전투보다 강한 적 + 더 좋은 보상.
## 현재는 placeholder.


func _on_victory_pressed() -> void:
	print("[Elite] 승리 — 맵으로 복귀")
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


func _on_defeat_pressed() -> void:
	print("[Elite] 패배 — 런 종료")
	GameState.end_run(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
