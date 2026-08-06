extends RefCounted
class_name FactionPalette

## Faction colours, and the ShaderMaterials that apply them.
##
## Several NPC variants share one cell of the roguelike master sheet, so faction
## identity is painted on at runtime by faction_recolor.gdshader rather than by
## authoring a separate sprite per faction. See NPC._apply_faction_recolor().
##
## TWO SEPARATE PIECES OF DATA, deliberately kept apart:
##   • the hue *window* describes the source art — "which hue did the artist
##     draw this sprite's cloth in". It lives with the sprite, so an NPC profile
##     can override it with a `recolor_hue_window` key.
##   • the target *colour* describes the faction, and lives here.

const SHADER: Shader = preload("res://shaders/faction_recolor.gdshader")

## The hue band assumed to be recolourable cloth on the roguelike sheet.
## Defaults to red (which wraps past 0 on the hue circle, hence start > end).
## VERIFY THIS with the shader's `debug_mask` uniform before trusting it — if the
## sheet's garments are drawn in some other hue, change it here once.
const DEFAULT_HUE_WINDOW := Vector2(0.95, 0.05)

## Faction → colour. A faction absent from this table is simply not recoloured,
## which is the right default for ordinary townsfolk: they keep their original
## art and pay no material cost at all.
const COLORS: Dictionary = {
	"GUARD": Color(0.15, 0.35, 0.85),   # royal blue
	"OUTLAW": Color(0.35, 0.10, 0.12),  # dried-blood maroon
	"CLERGY": Color(0.90, 0.80, 0.25),  # gold
	"MAGE": Color(0.45, 0.20, 0.75),    # violet
	"NOBLE": Color(0.55, 0.10, 0.45),   # imperial purple
}

## One material per faction+window combination, shared by every NPC that needs
## it. Duplicating a material per NPC would break draw-call batching for no
## benefit, since faction colour almost never changes at runtime.
static var _cache: Dictionary = {}

## The material that paints `faction` onto art whose recolourable cloth sits in
## `hue_window`, or null when the faction has no colour assigned.
static func material_for(faction: String, hue_window: Vector2 = DEFAULT_HUE_WINDOW) -> ShaderMaterial:
	if not COLORS.has(faction):
		return null
	var key := "%s|%.3f,%.3f" % [faction, hue_window.x, hue_window.y]
	if _cache.has(key):
		return _cache[key]

	var color: Color = COLORS[faction]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("hue_window", hue_window)
	mat.set_shader_parameter("target_hue", color.h)
	# Colour picked above supplies the hue; its saturation becomes a multiplier
	# on whatever the source pixel already had, so the shading ramp survives.
	mat.set_shader_parameter("sat_scale", color.s)
	_cache[key] = mat
	return mat
