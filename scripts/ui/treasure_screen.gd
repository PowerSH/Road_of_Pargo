extends Control

## 보물 노드. 전투 없이 보상 획득. 아이템 1개를 자동으로 카고에 넣는다.
## 카고 공간이 없으면 골드로 환산해 지급.

const ITEMS_DIR: String = "res://resource/items/"
## 카고 공간 부족 시 받는 골드 (sell_value 기준 배수).
const GOLD_FALLBACK_RATIO: float = 0.8

var _reward: CargoItem = null
var _placed: bool = false


func _ready() -> void:
	ScreenHelpers.add_background(self, "res://resource/bg_img/bg_canyon.jpg")
	_pick_reward()
	_update_subtitle()


func _pick_reward() -> void:
	var pool: Array[CargoItem] = _load_pool()
	if pool.is_empty():
		return
	# 챕터 tier 이하 + 희귀도 가중치 (간단: COMMON 60% / UNCOMMON 30% / RARE 8% / EPIC 2%)
	var filtered: Array[CargoItem] = []
	for item in pool:
		if item.chapter_tier == 0 or item.chapter_tier <= GameState.run.chapter:
			filtered.append(item)
	if filtered.is_empty():
		return
	_reward = filtered[randi() % filtered.size()]


func _load_pool() -> Array[CargoItem]:
	var out: Array[CargoItem] = []
	var dir: DirAccess = DirAccess.open(ITEMS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res: Resource = load(ITEMS_DIR + fname)
			if res is CargoItem:
				out.append(res)
		fname = dir.get_next()
	return out


func _update_subtitle() -> void:
	var sub: Node = find_child("Subtitle", true, false)
	if not (sub is Label):
		return
	if _reward == null:
		sub.text = "아이템 카탈로그가 비어 있어 보상이 없다."
	else:
		sub.text = "발견: %s (%d셀, 가치 %d g)" % [
			_reward.display_name, _reward.shape_cells.size(), _reward.sell_value,
		]


func _on_take_pressed() -> void:
	if _placed:
		return
	if _reward == null:
		print("[Treasure] 보상 없음 — 떠난다")
		_leave()
		return
	# 카고 공간 있으면 자동 배치, 없으면 골드로 환산.
	var slot: Dictionary = GameState.run.cargo.find_slot_for(_reward)
	if slot.is_empty():
		var gold: int = int(round(float(_reward.sell_value) * GOLD_FALLBACK_RATIO))
		GameState.run.gold += gold
		print("[Treasure] 카고 만석 — %d 골드로 환산" % gold)
	else:
		GameState.run.cargo.place(_reward, slot["anchor"], slot["rotation"])
		print("[Treasure] %s 획득" % _reward.display_name)
	_placed = true
	_leave()


func _leave() -> void:
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


func _on_leave_pressed() -> void:
	_leave()
