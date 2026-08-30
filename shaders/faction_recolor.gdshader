shader_type canvas_item;

// Faction recolour — hue-range swap.
//
// Repaints one band of hues on a sprite while leaving its shading intact, so a
// single piece of art can serve several factions. Hue is replaced outright;
// saturation and brightness are only *scaled*, which is what preserves the
// artist's light-to-dark ramp — a shadowed fold stays a shadowed fold.
//
// TUNING: flip `debug_mask` on. Magenta is a pixel about to be dyed, green is
// one the skin list is protecting, and everything else was never a candidate.
// A face showing magenta means SKIN_TONES is missing a tone.

// Band of hues to repaint, as (start, end) on the 0..1 hue circle.
// Wraps when start > end, which is also how you express "everything but one
// band" — the default excludes skin and bare wood. See FactionPalette.
uniform vec2 hue_window = vec2(0.11, 0.02);

// Ignore pixels less saturated than this. Greys (steel, stone, bone, outlines)
// report a meaningless, unstable hue, so without this floor they speckle. It is
// also what leaves undyed linen and grey homespun alone.
uniform float sat_floor : hint_range(0.0, 1.0) = 0.25;

// Ignore pixels darker than this. On this sheet the darkest shade doubles as the
// outline, and repainting it costs the silhouette at 16px.
uniform float value_floor : hint_range(0.0, 1.0) = 0.28;

// The faction's colour, taken apart: its hue replaces the source hue, while its
// saturation and brightness arrive as multipliers on what the source pixel
// already had. Scaling rather than overwriting is what keeps the ramp — a
// shadowed pixel stays relatively duller and darker than a lit one.
// FactionPalette derives all three from Faction.color.
uniform float target_hue : hint_range(0.0, 1.0) = 0.60;
uniform float sat_scale : hint_range(0.0, 2.0) = 1.0;
uniform float value_scale : hint_range(0.0, 2.0) = 1.0;


// Colours that are never dyed, whatever the window and the floors say. Skin is
// the reason this exists: a face has no business taking a house's colour, and
// hue alone cannot always tell flesh from tan cloth.
//
// Matched by distance in RGB, and the match can afford to be tight because the
// sheet uses a fixed palette and the project draws it with nearest filtering
// (default_texture_filter=0), so COLOR is the untouched texel. Two things widen
// that distance and would need a looser tolerance: filtering set to linear, and
// anything that modulates the sprite.
//
// Filled from FactionPalette.SKIN_TONES — add tones there, not here.
const int MAX_SKIN_TONES = 8;
uniform vec3 skin_tones[MAX_SKIN_TONES];
uniform int skin_tone_count = 0;
uniform float skin_tolerance : hint_range(0.0, 0.5) = 0.04;


uniform bool debug_mask = false;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.x) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

bool in_window(float h, vec2 w) {
	// Two cases because hue is a circle: a normal span, or one that wraps past 0.
	return (w.x <= w.y) ? (h >= w.x && h <= w.y) : (h >= w.x || h <= w.y);
}

bool is_skin(vec3 rgb) {
	int count = min(skin_tone_count, MAX_SKIN_TONES);
	for (int i = 0; i < count; i++) {
		if (distance(rgb, skin_tones[i]) <= skin_tolerance) {
			return true;
		}
	}
	return false;
}

void fragment() {
	// COLOR arrives already sampled from the sprite's texture at the right
	// texel, so there is no need to call texture() — which also means the
	// sprite's region_rect is handled for us rather than being our problem.
	vec3 hsv = rgb2hsv(COLOR.rgb);
	bool skin = is_skin(COLOR.rgb);
	if (COLOR.a > 0.5
		&& !skin
		&& in_window(hsv.x, hue_window)
		&& hsv.y >= sat_floor
		&& hsv.z >= value_floor) {
		hsv.x = target_hue;
		hsv.y = clamp(hsv.y * sat_scale, 0.0, 1.0);
		hsv.z = clamp(hsv.z * value_scale, 0.0, 1.0);
		COLOR.rgb = debug_mask ? vec3(1.0, 0.0, 1.0) : hsv2rgb(hsv);
	} else if (debug_mask && skin && COLOR.a > 0.5) {
		// Green separates "the skin list spared this" from "the window never
		// wanted it anyway", which is the distinction a tuning pass needs: an
		// unlit face means a tone is still missing from SKIN_TONES.
		COLOR.rgb = vec3(0.0, 1.0, 0.0);
	}
}
