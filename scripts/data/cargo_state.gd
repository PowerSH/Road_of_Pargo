class_name CargoState
extends Resource

## 적재 그리드 모델. width × height 셀에 CargoItem을 배치한다.
## 한 셀은 최대 1개 placement에만 속한다 (겹침 X).
## cargo-and-mortality.md §1 + battle-flow.md §3 참조.
##
## CargoItem 회전은 0/1/2/3 (각 90° CW). UI에서 R 키로 회전 후 anchor 이동시키는 흐름.
## 자동 정렬은 명시 호출만 (auto_sort) — 실시간 자동 X.
##
## Resource를 extends한 이유: ResourceSaver로 RunState 저장 시 같이 직렬화되기 위함.

const DEFAULT_WIDTH: int = 4
const DEFAULT_HEIGHT: int = 3

@export var width: int = DEFAULT_WIDTH
@export var height: int = DEFAULT_HEIGHT

## CargoItem -> {anchor: Vector2i, rotation: int}
@export var _placements: Dictionary = {}


func _init(w: int = DEFAULT_WIDTH, h: int = DEFAULT_HEIGHT) -> void:
	width = w
	height = h


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


func is_cell_occupied(cell: Vector2i) -> bool:
	for item in _placements:
		var data: Dictionary = _placements[item]
		var cells: Array[Vector2i] = item.compute_occupied_cells(data["anchor"], data["rotation"])
		for c in cells:
			if c == cell:
				return true
	return false


## item이 anchor+rotation에 들어갈 수 있는지 검사 (모든 셀이 in_bounds + 비어있음).
func can_place(item: CargoItem, anchor: Vector2i, rotation: int = 0) -> bool:
	if item == null:
		return false
	if _placements.has(item):
		return false  ## 이미 배치됨
	if not item.rotatable and rotation != 0:
		return false
	var cells: Array[Vector2i] = item.compute_occupied_cells(anchor, rotation)
	for c in cells:
		if not in_bounds(c):
			return false
		if is_cell_occupied(c):
			return false
	return true


## 배치 성공 시 true, 실패 시 false. caller가 can_place로 미리 검사해도 됨.
func place(item: CargoItem, anchor: Vector2i, rotation: int = 0) -> bool:
	if not can_place(item, anchor, rotation):
		return false
	_placements[item] = {"anchor": anchor, "rotation": rotation}
	return true


## 좌상단부터 First-Fit로 빈 슬롯 찾기. 회전이 허용되면 4방향 모두 시도.
## 찾으면 {"anchor": Vector2i, "rotation": int}, 못 찾으면 빈 Dictionary.
func find_slot_for(item: CargoItem) -> Dictionary:
	if item == null:
		return {}
	var rotations: Array[int] = [0]
	if item.rotatable:
		rotations = [0, 1, 2, 3]
	for y in height:
		for x in width:
			for r in rotations:
				if can_place(item, Vector2i(x, y), r):
					return {"anchor": Vector2i(x, y), "rotation": r}
	return {}


## 자동 배치 — find_slot_for + place. 실패 시 false (공간 부족).
func auto_place(item: CargoItem) -> bool:
	var slot: Dictionary = find_slot_for(item)
	if slot.is_empty():
		return false
	return place(item, slot["anchor"], slot["rotation"])


## 명시 호출용. 좌상단부터 큰 아이템 먼저 채우는 First-Fit Decreasing.
## 자동 정렬 후 원본 배치는 잃는다 (사용자가 다시 손으로 옮길 수 있음).
func auto_sort() -> void:
	var items: Array[CargoItem] = placed_items()
	items.sort_custom(func(a: CargoItem, b: CargoItem) -> bool:
		return a.shape_cells.size() > b.shape_cells.size())
	_placements.clear()
	for item in items:
		auto_place(item)


func remove(item: CargoItem) -> bool:
	if not _placements.has(item):
		return false
	_placements.erase(item)
	return true


func contains(item: CargoItem) -> bool:
	return _placements.has(item)


func get_placement(item: CargoItem) -> Dictionary:
	return _placements.get(item, {})


func placed_items() -> Array[CargoItem]:
	var out: Array[CargoItem] = []
	for item in _placements:
		out.append(item)
	return out


## 모든 placement 정보. UI 렌더링 / iteration용.
##  Returns: Array[{item, anchor: Vector2i, rotation: int}]
func iter_placements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in _placements:
		var data: Dictionary = _placements[item]
		out.append({
			"item": item,
			"anchor": data["anchor"],
			"rotation": data["rotation"],
		})
	return out


## 셀별 점유 매트릭스 (UI 렌더링용). grid[y][x] = CargoItem 또는 null.
func occupancy_grid() -> Array:
	var grid: Array = []
	for y in height:
		var row: Array = []
		row.resize(width)
		grid.append(row)
	for item in _placements:
		var data: Dictionary = _placements[item]
		for c in item.compute_occupied_cells(data["anchor"], data["rotation"]):
			if in_bounds(c):
				grid[c.y][c.x] = item
	return grid


func empty_cells_count() -> int:
	var occupied: int = 0
	for item in _placements:
		var data: Dictionary = _placements[item]
		occupied += item.compute_occupied_cells(data["anchor"], data["rotation"]).size()
	return maxi(width * height - occupied, 0)


## 그리드 확장만 허용 (축소는 기존 placement가 잘릴 수 있어 거부).
## 도시 거래의 그리드 업그레이드에서 사용.
func resize(new_width: int, new_height: int) -> bool:
	if new_width < width or new_height < height:
		return false
	width = new_width
	height = new_height
	return true
