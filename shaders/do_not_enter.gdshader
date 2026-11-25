shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// "Do Not Enter" panel on the barrier's playable face.
// The reveal is computed per fragment against the player's world position, so the panel does not
// switch on as a block: a soft blob grows across it as the player closes in, and it is fully gone
// past fade_far. The stripes are a hazard pattern in the panel's own metres.

uniform vec3 player_pos;
uniform vec2 sign_size = vec2(3.0, 1.6);
uniform float fade_near = 18.0;
uniform float fade_far = 55.0;
uniform vec4 stripe_a : source_color = vec4(0.95, 0.72, 0.05, 1.0);
uniform vec4 stripe_b : source_color = vec4(0.07, 0.07, 0.08, 1.0);
uniform vec4 rim_color : source_color = vec4(0.95, 0.15, 0.10, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = distance(world_pos, player_pos);
	float reveal = 1.0 - smoothstep(fade_near, fade_far, d);

	// Hazard stripes in panel metres, plus a red border so the panel reads as a sign, not a smear.
	vec2 m = UV * sign_size;
	float stripe = step(0.5, fract((m.x + m.y) * 0.5));
	vec3 col = mix(stripe_a.rgb, stripe_b.rgb, stripe);
	vec2 edge = min(m, sign_size - m);
	float border = 1.0 - step(0.09, min(edge.x, edge.y));
	col = mix(col, rim_color.rgb, border);

	ALBEDO = col;
	ALPHA = reveal * 0.92;
}
