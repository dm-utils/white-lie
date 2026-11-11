// Island ground and water in one pass (styleguide budget: one water shader).
// The sim's tile heights arrive as a small texture (one texel per tile, linear filtered), so the coast is a smooth
// line exactly where the tiles meet: a tile is water when level - height >= 1, i.e. the coast is at d = 0.5.
// Colours come from data/palette.json ("world"); the detail atlas from tools/art/tiles.py.
shader_type canvas_item;

uniform sampler2D heights : filter_linear, repeat_disable;
uniform sampler2D atlas : filter_linear, repeat_disable;
uniform vec2 grid = vec2(40.0, 30.0); // island size in tiles
uniform float margin = 12.0; // tiles of sea drawn around the island
uniform float height_scale = 25.0; // texel value = height * height_scale / 255
uniform float level = 2.0; // shown tide level (eases towards the sim's level)
uniform float warn = 0.0; // 1 while the tide warning runs: the tiles about to flood glitter
uniform float atlas_slots = 4.0;

uniform vec4 sand_high : source_color;
uniform vec4 sand : source_color;
uniform vec4 sand_shade : source_color;
uniform vec4 wet_sand : source_color;
uniform vec4 shallow : source_color;
uniform vec4 deep : source_color;
uniform vec4 abyss : source_color;
uniform vec4 foam : source_color;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 slot(float i, vec2 p) {
	vec2 f = clamp(fract(p), vec2(0.004), vec2(0.996));
	return texture(atlas, vec2((i + f.x) / atlas_slots, f.y));
}

float height_at(vec2 t) {
	float h = texture(heights, t / grid).r * 255.0 / height_scale;
	vec2 outside = max(max(-t, t - grid), vec2(0.0));
	return h - length(outside) * 0.6; // the sea floor falls away past the edge
}

void fragment() {
	vec2 t = UV * (grid + 2.0 * margin) - margin; // position in tiles
	float d = level - height_at(t); // continuous depth; whole numbers at tile centres
	float aa = max(fwidth(d), 0.001);
	float dry = -d; // 0 = wet sand, 1, 2, 3+ = higher and drier

	// --- ground: terraces of sand, darker and wetter towards the water ---
	vec3 land = wet_sand.rgb;
	land = mix(land, sand_shade.rgb, smoothstep(0.5 - aa, 0.5 + aa, dry));
	land = mix(land, sand.rgb, smoothstep(1.5 - aa, 1.5 + aa, dry));
	land = mix(land, sand_high.rgb, smoothstep(2.5 - aa, 2.5 + aa, dry));
	vec4 grain = slot(0.0, t * 0.5);
	land = mix(land, grain.rgb, grain.a * smoothstep(0.3, 0.7, dry));
	vec4 ripple = slot(1.0, t * 0.6);
	land = mix(land, ripple.rgb, ripple.a * (1.0 - smoothstep(0.3, 0.7, dry)));
	land *= mix(0.86, 1.0, smoothstep(0.0, 0.18, 0.5 - d)); // dark wet line along the coast

	// dune grass on the highest tiles, one tuft in some of them (placed per tile, so it never moves)
	vec2 cell = floor(t);
	float hc = level - height_at(cell + 0.5);
	float r = hash(cell);
	if (hc <= -2.0 && r < 0.16) {
		vec2 jitter = vec2(hash(cell + 7.0), hash(cell + 13.0)) - 0.5;
		vec2 local = (fract(t) - vec2(0.5, 0.45) - jitter * 0.4) / 0.62 + 0.5;
		if (local.x > 0.0 && local.x < 1.0 && local.y > 0.0 && local.y < 1.0) {
			vec4 g = slot(3.0, vec2(r > 0.08 ? local.x : 1.0 - local.x, local.y));
			land = mix(land, g.rgb, g.a);
		}
	}

	// the tide warning: the tiles that flood next glitter white (styleguide: 50 % blinking)
	if (warn > 0.0 && d > -0.5) {
		float blink = 0.18 + 0.18 * sin(TIME * 14.0);
		// twinkles: a small four-point star at a random spot in some cells, switching every 1/6 s
		vec2 sc = t * 2.5;
		vec2 id = floor(sc);
		float on = step(0.72, hash(id + floor(TIME * 6.0)));
		vec2 f = (fract(sc) - 0.5 - (vec2(hash(id + 3.0), hash(id + 5.0)) - 0.5) * 0.5) * 6.0;
		float star = max(0.0, 1.0 - abs(f.x) * abs(f.y) * 6.0 - length(f) * 0.9);
		land = mix(land, vec3(1.0), warn * clamp(blink + star * on, 0.0, 1.0));
	}

	// --- water: shallow turquoise, deep blue with a wave pattern (also readable without colour), abyss ---
	vec3 water = shallow.rgb;
	water = mix(water, deep.rgb, smoothstep(1.3, 1.7, d));
	water = mix(water, abyss.rgb, smoothstep(2.3, 2.9, d));
	float caustic = sin(t.x * 3.0 + TIME * 1.5 + sin(t.y * 2.0)) * sin(t.y * 3.0 - TIME * 1.2 + sin(t.x * 1.7));
	water += vec3(pow(max(caustic, 0.0), 10.0) * 0.12) * (1.0 - smoothstep(1.2, 1.7, d));
	vec4 marks = slot(2.0, t * 0.5 + vec2(TIME * 0.04, TIME * 0.015));
	water = mix(water, marks.rgb, marks.a * 0.45 * smoothstep(1.3, 1.8, d));

	// foam: a steady rim plus a line that laps outwards and fades
	float coast = d - 0.5 + sin(t.x * 4.0 + TIME * 2.0) * 0.025 + sin(t.y * 3.3 - TIME * 1.7) * 0.025;
	float rim = 1.0 - smoothstep(0.06, 0.06 + aa * 2.0, coast);
	float lap = fract(TIME * 0.35);
	float line_at = 0.12 + lap * 0.38;
	float lapping = (1.0 - smoothstep(0.0, 0.035 + aa, abs(coast - line_at))) * (1.0 - lap) * 0.7;
	water = mix(water, foam.rgb, clamp(rim * 0.9 + lapping, 0.0, 1.0));

	COLOR = vec4(mix(land, water, smoothstep(-aa, aa, coast)), 1.0);
}
