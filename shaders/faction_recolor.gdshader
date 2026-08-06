shader_type canvas_item;

// Faction recolour — hue-range swap.
//
// Repaints one band of hues on a sprite while leaving its shading intact, so a
// single piece of art can serve several factions. Only *hue* and *saturation*
// are touched; brightness (value) is passed through untouched, which is what
// preserves the artist's light-to-dark ramp.
//
// TUNING: flip `debug_mask` on. Every pixel the filter catches turns magenta,
// so you can see exactly what the window is grabbing before you trust it.

// Band of hues to repaint, as (start, end) on the 0..1 hue circle.
// Wraps when start > end — which is how you express red, since red straddles 0.
uniform vec2 hue_window = vec2(0.95, 0.05);

// Ignore pixels less saturated than this. Greys (steel, stone, bone, outlines)
// report a meaningless, unstable hue, so without this floor they speckle.
uniform float sat_floor : hint_range(0.0, 1.0) = 0.25;

// Ignore pixels darker than this, which protects the black outline pixels the
// silhouette depends on at 16px.
uniform float value_floor : hint_range(0.0, 1.0) = 0.10;

// The faction's hue, and a multiplier on the original saturation. Saturation is
// scaled rather than overwritten so shadowed pixels stay relatively duller.
uniform float target_hue : hint_range(0.0, 1.0) = 0.60;
uniform float sat_scale : hint_range(0.0, 2.0) = 1.0;

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

void fragment() {
	// COLOR arrives already sampled from the sprite's texture at the right
	// texel, so there is no need to call texture() — which also means the
	// sprite's region_rect is handled for us rather than being our problem.
	vec3 hsv = rgb2hsv(COLOR.rgb);
	if (COLOR.a > 0.5
		&& in_window(hsv.x, hue_window)
		&& hsv.y >= sat_floor
		&& hsv.z >= value_floor) {
		hsv.x = target_hue;
		hsv.y = clamp(hsv.y * sat_scale, 0.0, 1.0);
		COLOR.rgb = debug_mask ? vec3(1.0, 0.0, 1.0) : hsv2rgb(hsv);
	}
}
