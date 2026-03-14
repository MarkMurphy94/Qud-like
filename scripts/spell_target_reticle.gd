extends Node2D
class_name SpellTargetReticle

## Visual targeting overlay drawn while the player is aiming a spell.
## Renders a dashed range line from the caster origin to the cursor
## and a circle (or crosshair) at the target point sized to the spell's AOE.
## Add as a child of the caster so the origin automatically tracks them.

var spell: Spell = null
var _max_range_px:  float = 0.0
var _aoe_radius_px: float = 0.0
var _target_local:  Vector2 = Vector2.ZERO  ## cursor in local space, clamped to range

# ── Appearance ──────────────────────────────────────────────────────────────
const DASH_LEN:     float = 7.0
const GAP_LEN:      float = 5.0
const LINE_WIDTH:   float = 1.5
const RETICLE_SEGS: int   = 48
const CROSSHAIR_SZ: float = 6.0

var line_color:    Color = Color(1.0, 0.9, 0.3, 0.85)
var reticle_color: Color = Color(1.0, 0.4, 0.1, 0.80)


func setup(p_spell: Spell) -> void:
	spell          = p_spell
	_max_range_px  = spell.spell_range * 16.0
	_aoe_radius_px = spell.aoe_radius  * 16.0

	# Match line & reticle colour to the spell's own colour if set
	if spell.spell_color != Color.WHITE:
		line_color    = Color(spell.spell_color.r, spell.spell_color.g,
						  spell.spell_color.b, 0.85)
		reticle_color = Color(spell.spell_color.r, spell.spell_color.g,
						  spell.spell_color.b, 0.80)

	# Render above everything else in the scene
	z_as_relative = false
	z_index       = 10


func _process(_delta: float) -> void:
	var to_mouse: Vector2 = to_local(get_global_mouse_position())
	if to_mouse.length() > _max_range_px:
		to_mouse = to_mouse.normalized() * _max_range_px
	_target_local = to_mouse
	queue_redraw()


func _draw() -> void:
	# ── dashed line from caster origin to target ────────────────────────────
	_draw_dashed(Vector2.ZERO, _target_local, line_color, LINE_WIDTH)

	# ── range cap: small tick at the maximum-range endpoint ─────────────────
	var at_max := _target_local.length() >= _max_range_px - 1.0
	if at_max and _max_range_px > 0.0:
		var perp := Vector2(-_target_local.normalized().y,
							 _target_local.normalized().x) * 5.0
		draw_line(_target_local - perp, _target_local + perp,
				  line_color, LINE_WIDTH)

	# ── end-point indicator ──────────────────────────────────────────────────
	if _aoe_radius_px > 0.0:
		# AOE circle
		draw_arc(_target_local, _aoe_radius_px,
				 0.0, TAU, RETICLE_SEGS, reticle_color, LINE_WIDTH)
		# Centre dot
		draw_circle(_target_local, 2.5, reticle_color)
	else:
		# Crosshair for single-target spells
		var h := CROSSHAIR_SZ
		draw_line(_target_local + Vector2(-h,  0), _target_local + Vector2(h, 0),
				  reticle_color, LINE_WIDTH)
		draw_line(_target_local + Vector2( 0, -h), _target_local + Vector2(0, h),
				  reticle_color, LINE_WIDTH)
		# Outer ring
		draw_arc(_target_local, h * 1.4, 0.0, TAU, 24, reticle_color, LINE_WIDTH)


func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var dir      := (to - from) / dist
	var traveled := 0.0
	var drawing  := true
	while traveled < dist:
		var seg  := DASH_LEN if drawing else GAP_LEN
		var next := minf(traveled + seg, dist)
		if drawing:
			draw_line(from + dir * traveled, from + dir * next, color, width)
		traveled = next
		drawing  = not drawing
