shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
// #68 kick power meter: a billboard quad that draws `steps` stacked bars on a dark panel.
// The bars widen toward the top (a stepped wedge) and run green -> amber -> red; the
// lowest `lit` bars are bright, the rest are dim slots. `lit` is pushed only when it changes.
uniform int lit = 0;
uniform int steps = 10;

void vertex() {
	// Face the camera, stay upright on screen.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 uv = UV;
	float y = 1.0 - uv.y;   // 0 at the bottom
	// Panel: dark, rounded, with a thin light rim.
	float d = rounded_box(uv - 0.5, vec2(0.5, 0.5) - 0.02, 0.12);
	float aa = fwidth(d) + 0.001;
	float panel = 1.0 - smoothstep(-aa, aa, d);
	float rim = panel * smoothstep(-0.045 - aa, -0.045 + aa, d);
	vec3 col = mix(vec3(0.04, 0.05, 0.08), vec3(0.85, 0.9, 1.0), rim);
	float alpha = panel * mix(0.55, 0.9, rim);
	// Steps.
	float pad = 0.05;
	float fy = (y - pad) / (1.0 - 2.0 * pad) * float(steps);
	int i = int(floor(fy));
	if (fy >= 0.0 && i < steps) {
		float t = (float(i) + 0.5) / float(steps);
		float half_w = mix(0.16, 0.36, t);
		float local = fract(fy);
		float sx = abs(uv.x - 0.5);
		float fx = fwidth(uv.x) + 0.001;
		float fl = fwidth(fy) + 0.001;
		float in_step = (1.0 - smoothstep(half_w - fx, half_w + fx, sx))
			* smoothstep(0.18 - fl, 0.18 + fl, local);
		vec3 heat = t < 0.6 ? mix(vec3(0.3, 0.95, 0.45), vec3(1.0, 0.82, 0.22), t / 0.6)
			: mix(vec3(1.0, 0.82, 0.22), vec3(1.0, 0.28, 0.2), (t - 0.6) / 0.4);
		bool on = i < lit;
		vec3 step_col = on ? heat : mix(vec3(0.16, 0.18, 0.24), heat, 0.18);
		col = mix(col, step_col, in_step);
		alpha = max(alpha, in_step * (on ? 1.0 : 0.75));
	}
	ALBEDO = col;
	ALPHA = alpha;
}
