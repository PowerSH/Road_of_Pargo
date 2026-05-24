extends Control

## 상점 노드. 골드로 아이템/유닛 구매. 도중 노드에 한정 (챕터 사이 거점 상점과 별개).


func _on_buy_item_pressed() -> void:
	print("[Shop] 아이템 구매 — 미구현")


func _on_buy_unit_pressed() -> void:
	print("[Shop] 유닛 구매 — 미구현")


func _on_leave_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")
