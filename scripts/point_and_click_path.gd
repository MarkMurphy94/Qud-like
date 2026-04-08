extends Node2D
## Point-and-click navigation overlay.
## Placed as a direct child of the game scene at (0,0) so that its local
## coordinate space equals world space. The Player calls the public API to
## rebuild the A* grid and refresh the mouse-hover preview.

# ── Configuration ────────────────────────────────────────────────────────────
var tile_size: int = 16

# ── Pathfinding ───────────────────────────────────────────────────────────────
var _astar: AStarGrid2D = null
var _is_grid_ready: bool = false

# ── Preview state ─────────────────────────────────────────────────────────────
## Tile-space path from player → mouse (includes both endpoints)
var _preview_tiles: Array[Vector2i] = []
var _dest_tile: Vector2i = Vector2i(-9999, -9999)   # last queried destination
var _prev_player_tile: Vector2i = Vector2i(-9999, -9999)
var _dest_blocked: bool = false

# ── Active navigation destination ─────────────────────────────────────────────
## The tile the player has committed to walk toward (set on click, cleared on arrival/cancel)
var _nav_dest_tile: Vector2i = Vector2i(-9999, -9999)
var _nav_pulse: float = 0.0   # 0..1 oscillating value for the destination highlight

# ── Visual constants ──────────────────────────────────────────────────────────
const CRUMB_COLOR    := Color(0.0,  1.0,  0.8,  0.75)   # cyan breadcrumbs
const DEST_COLOR     := Color(1.0,  0.85, 0.0,  0.95)   # gold reticle (walkable)
const BLOCKED_COLOR  := Color(1.0,  0.25, 0.25, 0.85)   # red reticle (blocked)
const NAV_DEST_COLOR := Color(0.2,  0.9,  1.0,  1.0)    # bright cyan destination marker
const CRUMB_RADIUS   := 2.0
const RETICLE_HALF   := 5.0


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

func setup_grid(rect: Rect2i, walkable_callable: Callable) -> void:
	"""Build (or rebuild) the A* grid covering `rect` (in tile coordinates)."""
	_is_grid_ready = false
	_preview_tiles = []
	_dest_tile = Vector2i(-9999, -9999)
	_prev_player_tile = Vector2i(-9999, -9999)

	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(rect.position, rect.size)
	_astar.cell_size = Vector2(tile_size, tile_size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER  # 4-directional only
	_astar.update()

	for y in rect.size.y:
		for x in rect.size.x:
			var tile := Vector2i(rect.position.x + x, rect.position.y + y)
			if not walkable_callable.call(tile):
				_astar.set_point_solid(tile)

	_is_grid_ready = true
	queue_redraw()


func update_preview(player_world: Vector2, mouse_world: Vector2) -> void:
	"""Recompute the hover preview path from player to mouse (world space)."""
	if not _is_grid_ready:
		return

	var pt := _w2t(player_world)
	var mt := _w2t(mouse_world)

	# Skip recompute if nothing changed
	if mt == _dest_tile and pt == _prev_player_tile:
		return

	_dest_tile = mt
	_prev_player_tile = pt
	_dest_blocked = false

	# Validate destination
	if not _astar.is_in_boundsv(mt) or _astar.is_point_solid(mt):
		_preview_tiles = []
		_dest_blocked = true
		queue_redraw()
		return

	# Validate origin
	if not _astar.is_in_boundsv(pt):
		_preview_tiles = []
		queue_redraw()
		return

	# Same tile — no path needed
	if pt == mt:
		_preview_tiles = [pt]
		queue_redraw()
		return

	var raw: Array[Vector2i] = _astar.get_id_path(pt, mt)
	_preview_tiles.clear()
	for v in raw:
		_preview_tiles.append(v)
	queue_redraw()


func clear_preview() -> void:
	"""Hide all visuals."""
	_preview_tiles = []
	_dest_tile = Vector2i(-9999, -9999)
	_prev_player_tile = Vector2i(-9999, -9999)
	_dest_blocked = false
	queue_redraw()


func set_nav_destination(world_pos: Vector2) -> void:
	"""Mark the tile at world_pos as the active navigation destination."""
	_nav_dest_tile = _w2t(world_pos)
	_nav_pulse = 0.0
	queue_redraw()


func clear_nav_destination() -> void:
	"""Remove the active navigation destination highlight."""
	_nav_dest_tile = Vector2i(-9999, -9999)
	queue_redraw()


func get_tile_path(from_world: Vector2, to_world: Vector2) -> Array[Vector2i]:
	"""Return the A* tile path (including start tile). Empty if unreachable."""
	if not _is_grid_ready:
		return []
	var pt := _w2t(from_world)
	var mt := _w2t(to_world)
	if not _astar.is_in_boundsv(pt) or not _astar.is_in_boundsv(mt):
		return []
	if _astar.is_point_solid(mt):
		return []
	var raw: Array[Vector2i] = _astar.get_id_path(pt, mt)
	var result: Array[Vector2i] = []
	for v in raw:
		result.append(v)
	return result


# ─────────────────────────────────────────────────────────────────────────────
# Drawing
# ─────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _nav_dest_tile != Vector2i(-9999, -9999):
		_nav_pulse = fmod(_nav_pulse + delta * 2.5, TAU)
		queue_redraw()

func _draw() -> void:
	# ── Active navigation destination ────────────────────────────────────────
	if _nav_dest_tile != Vector2i(-9999, -9999):
		var nd_center := _t2w_center(_nav_dest_tile)
		var pulse_alpha := 0.55 + 0.45 * sin(_nav_pulse)
		var nd_color := Color(NAV_DEST_COLOR.r, NAV_DEST_COLOR.g, NAV_DEST_COLOR.b, pulse_alpha)
		# Filled inner square
		var inner := float(tile_size) * 0.35
		draw_rect(
			Rect2(nd_center - Vector2(inner, inner), Vector2(inner * 2.0, inner * 2.0)),
			Color(nd_color.r, nd_color.g, nd_color.b, nd_color.a * 0.3), true
		)
		# Animated outer ring
		var expand := 1.0 + 0.25 * sin(_nav_pulse)
		var outer := float(tile_size) * 0.48 * expand
		draw_rect(
			Rect2(nd_center - Vector2(outer, outer), Vector2(outer * 2.0, outer * 2.0)),
			nd_color, false, 1.5
		)
		# Corner ticks
		var tick := float(tile_size) * 0.18
		var corners := [nd_center + Vector2(-outer, -outer), nd_center + Vector2(outer, -outer),
						nd_center + Vector2(outer, outer),  nd_center + Vector2(-outer, outer)]
		var dirs_x := [1, -1, -1, 1]
		var dirs_y := [1,  1, -1, -1]
		for i in 4:
			draw_line(corners[i], corners[i] + Vector2(dirs_x[i] * tick, 0.0), nd_color, 2.0)
			draw_line(corners[i], corners[i] + Vector2(0.0, dirs_y[i] * tick), nd_color, 2.0)

	if _dest_tile == Vector2i(-9999, -9999):
		return

	var dest_world := _t2w_center(_dest_tile)

	if _dest_blocked or _preview_tiles.is_empty():
		# Just show the blocked reticle at the cursor tile
		_draw_reticle(dest_world, BLOCKED_COLOR)
		return

	# Breadcrumb dots — skip index 0 (player tile) and last (destination)
	for i in range(1, _preview_tiles.size() - 1):
		draw_circle(_t2w_center(_preview_tiles[i]), CRUMB_RADIUS, CRUMB_COLOR)

	# Destination reticle
	_draw_reticle(dest_world, DEST_COLOR)


func _draw_reticle(center: Vector2, color: Color) -> void:
	var h := RETICLE_HALF
	# Cross hair
	draw_line(center + Vector2(-h, 0.0), center + Vector2(h, 0.0), color, 1.5)
	draw_line(center + Vector2(0.0, -h), center + Vector2(0.0, h), color, 1.5)
	# Bounding box
	var box_half := h * 0.6
	draw_rect(
		Rect2(center - Vector2(box_half, box_half), Vector2(box_half * 2.0, box_half * 2.0)),
		color, false, 1.0
	)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _w2t(world_pos: Vector2) -> Vector2i:
	"""World position → tile coordinate (floor division)."""
	return Vector2i(
		int(floorf(world_pos.x / tile_size)),
		int(floorf(world_pos.y / tile_size))
	)


func _t2w_center(tile: Vector2i) -> Vector2:
	"""Tile coordinate → world position at the tile's visual center."""
	return Vector2(tile.x * tile_size + tile_size * 0.5, tile.y * tile_size + tile_size * 0.5)
