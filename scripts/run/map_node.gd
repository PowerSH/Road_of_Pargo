class_name MapNode
extends Resource

## A single node on the Slay-the-Spire-style run map.
## Edges are stored as forward indices into the run's node array, so the
## graph is a simple DAG (left → right) without cycles.

enum Kind {
	BATTLE,
	ELITE,
	SHOP,
	REST,
	EVENT,
	TREASURE,
	BOSS,
}

@export var kind: Kind = Kind.BATTLE
## Column index in the map (0 = first stage). Used for layout + progression.
@export var depth: int = 0
## Row index within the column.
@export var lane: int = 0
## Forward indices in the RunState.nodes array this node connects to.
@export var next_indices: Array[int] = []

## Optional payload — e.g. encounter id for battles, item pool id for shops.
@export var payload_id: StringName = &""
