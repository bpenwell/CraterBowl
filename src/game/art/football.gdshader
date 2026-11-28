shader_type spatial;
// Football (#159): leather with four panel seams, white laces over the top seam and a white
// stripe near each end. Drawn from the object-space position, long axis Z, laces on +Y,
// so the mesh needs no UV layout (see football.gd).

uniform float half_length = 0.22;
uniform vec3 leather : source_color = vec3(0.47, 0.22, 0.09);
uniform vec3 seam_color : source_color = vec3(0.2, 0.09, 0.04);
uniform vec3 white : source_color = vec3(0.96, 0.95, 0.92);

varying vec3 p;

void vertex() {
	p = VERTEX;
}

// 1 inside a band of half-width w around 0 (d in metres), anti-aliased over a pixel.
float band(float d, float w) {
	float aa = fwidth(d) + 1e-5;
	return 1.0 - smoothstep(w - aa, w + aa, abs(d));
}

void fragment() {
	float r = length(p.xy);
	float phi = atan(p.y, p.x);                      // laces at +Y: phi = PI/2
	float t = p.z / half_length;                     // -1..1 tip to tip
	// Arc length (m) to the nearest of the four seams at 0, 90, 180, 270 deg.
	float q = PI * 0.5;
	float seam_arc = (phi - q * round(phi / q)) * r;
	// Arc length from the top (lace) seam.
	float top_arc = (phi - PI * 0.5) * r;
	float on_top = step(abs(phi - PI * 0.5), q * 0.5);

	vec3 col = leather;
	// Leather grain: faint per-panel shading so the panels read in a close-up.
	col *= 0.94 + 0.06 * cos(phi * 4.0);
	col = mix(col, seam_color, band(seam_arc, 0.0035));
	// White stripe around each end (college style), interrupted by nothing: it is a painted band.
	float stripe = band(abs(t) - 0.62, 0.055);
	col = mix(col, white, stripe);
	// Laces: a centre lace along the top seam plus eight cross stitches, middle 40% of the ball.
	float lace_len = step(abs(p.z), half_length * 0.4);
	float centre = band(top_arc, 0.006) * lace_len;
	float pitch = half_length * 0.8 / 8.0;
	float stitch = band(p.z - pitch * (floor(p.z / pitch) + 0.5), pitch * 0.22)
		* band(top_arc, 0.024) * lace_len;
	float lace = max(centre, stitch) * on_top;
	col = mix(col, white, lace);

	ALBEDO = col;
	ROUGHNESS = mix(0.6, 0.45, lace + stripe);
	SPECULAR = 0.35;
	RIM = 0.25;
	RIM_TINT = 0.6;
}
