extends Control

## 일반 전투 화면. 5x3 편성 + 자동 전투 시뮬레이션.
## 현재는 placeholder — 승리/패배 버튼만.


func _on_victory_pressed() -> void:
	print("[Battle] 승리 — 맵으로 복귀")
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


func _on_defeat_pressed() -> void:
	print("[Battle] 패배 — 런 종료")
	GameState.end_run(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
