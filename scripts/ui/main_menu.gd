extends Control

## 메인 메뉴. 버튼 시그널은 에디터의 Signals 탭에서 _on_start_pressed / _on_quit_pressed
## 핸들러에 직접 연결할 것. (스크립트 안에서 connect 안 함 — 노드 경로 변경에 안 깨짐)


func _ready() -> void:
	print("[MainMenu] _ready 호출됨 — 스크립트가 정상 부착됨")


func _on_start_pressed() -> void:
	print("[MainMenu] 새 런 시작 요청")
	GameState.start_new_run()
	get_tree().change_scene_to_file("res://scenes/story_screen.tscn")


func _on_quit_pressed() -> void:
	print("[MainMenu] 종료")
	get_tree().quit()
