shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	// Only map primitives use this material; interface text remains unfiltered.
	float scanline = 0.5 + 0.5 * cos(FRAGCOORD.y * 3.14159265);
	COLOR.rgb *= 1.0 - scanline * 0.045 * strength;
}
