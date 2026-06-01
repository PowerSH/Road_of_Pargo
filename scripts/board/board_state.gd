class_name BoardState
extends Resource

## In-memory model of the 5x3 placement grid. Pure data, no nodes.
## Rows are 0..ROWS-1 (top to bottom); cols are 0..COLS-1 (left to right).
## 셀에 들어가는 값은 OwnedUnit 참조. UnitData(type)는 OwnedUnit.source로 접근.
## 적군 보드는 이 클래스를 재사용하되 셀 값으로 EnemyUnitData를 직접 보관할 수도 있어
## get_unit/place_unit의 타입은 Resource로 받아 양쪽 호환.
##
## Resource를 extends한 이유: RunState 저장 시 SubResource로 같이 직렬화됨.

const ROWS: int = 3
const COLS: int = 5

@export var _cells: Array = []  ## Array[Array[Resource|null]], shape ROWS x COLS


func _init() -> void:
	clear()


func clear() -> void:
	_cells.clear()
	for r in ROWS:
		var row: Array = []
		row.resize(COLS)
		_cells.append(row)


func in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < ROWS and col >= 0 and col < COLS


func get_unit(row: int, col: int) -> Resource:
	if not in_bounds(row, col):
		return null
	return _cells[row][col]


func place_unit(row: int, col: int, unit: Resource) -> bool:
	if not in_bounds(row, col):
		return false
	_cells[row][col] = unit
	return true


func remove_unit(row: int, col: int) -> Resource:
	if not in_bounds(row, col):
		return null
	var u: Resource = _cells[row][col]
	_cells[row][col] = null
	return u


func swap(a_row: int, a_col: int, b_row: int, b_col: int) -> void:
	if not in_bounds(a_row, a_col) or not in_bounds(b_row, b_col):
		return
	var tmp: Resource = _cells[a_row][a_col]
	_cells[a_row][a_col] = _cells[b_row][b_col]
	_cells[b_row][b_col] = tmp


func get_adjacent(row: int, col: int) -> Array:
	var out: Array = []
	for dr: int in [-1, 0, 1]:
		for dc: int in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr := row + dr
			var nc := col + dc
			if in_bounds(nr, nc) and _cells[nr][nc] != null:
				out.append(_cells[nr][nc])
	return out


func iter_placed() -> Array:  ## Returns Array of Dictionaries: {row, col, unit}
	var out: Array = []
	for r in ROWS:
		for c in COLS:
			var u: Resource = _cells[r][c]
			if u != null:
				out.append({"row": r, "col": c, "unit": u})
	return out


func count_placed() -> int:
	var n: int = 0
	for r in ROWS:
		for c in COLS:
			if _cells[r][c] != null:
				n += 1
	return n
