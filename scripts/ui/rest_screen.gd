extends Control

## 휴식 화면 (여관/모닥불). HP 회복 / 카드(시너지) 강화 / 떠나기.


const HEAL_AMOUNT: int = 30


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_forest.jpg")


func _on_heal_pressed() -> void:
	if GameState.run == null:
		return
	GameState.run.heal(HEAL_AMOUNT)
	print("[Rest] HP +%d → %d/%d" % [
		HEAL_AMOUNT, GameState.run.health, GameState.run.max_health
	])


func _on_upgrade_pressed() -> void:
	print("[Rest] 카드 강화 — 미구현")


func _on_leave_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")
