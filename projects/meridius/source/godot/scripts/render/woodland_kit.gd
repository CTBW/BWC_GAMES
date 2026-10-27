## Painted terrain-lab kit. Originals stay unchanged; the material keys magenta.
## Root anchors and world heights are authored against the accepted source art.
extends RefCounted

const ROOT := "res://assets/terrain/woodland/"
const SOURCES := {
	"pine": ["tree_pine__take-01.png", Vector2(0.52, 0.94), 350.0],
	"beech": ["tree_beech__take-01.png", Vector2(0.50, 0.94), 310.0],
	"oak": ["tree_oak__take-02.png", Vector2(0.51, 0.92), 285.0],
	"shrub": ["bush_green__take-01.png", Vector2(0.46, 0.89), 66.0],
	"fern": ["undergrowth_ferns__take-01.png", Vector2(0.52, 0.88), 44.0],
}
static var _cache: Dictionary = {}


static func sprite(kind: String, size := 1.0) -> Dictionary:
	if not _cache.has(kind):
		var entry: Array = SOURCES[kind]
		var file: String = ROOT + entry[0]
		var tex: Texture2D = load(file)
		var w := tex.get_width()
		var h := tex.get_height()
		var anchor: Vector2 = entry[1]
		# The production canopy occlusion code reads this CPU alpha mask. It must
		# agree with the keyed material, including holes between branches.
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		var stride := 4
		var mw := ceili(float(w) / stride)
		var mh := ceili(float(h) / stride)
		var mask := PackedByteArray()
		mask.resize(mw * mh)
		for y in mh:
			for x in mw:
				var c := img.get_pixel(mini(x * stride + 2, w - 1), mini(y * stride + 2, h - 1))
				mask[y * mw + x] = roundi(255.0 * c.a * (1.0 - smoothstep(0.1, 0.58, minf(c.r, c.b) - c.g)))
		_cache[kind] = {"key": "woodland_" + kind, "file": file, "tex": tex,
			"region": Rect2(0, 0, w, h), "w": w, "h": h,
			"ax": w * anchor.x, "ay": h * anchor.y, "scale": float(entry[2]) / h,
			"noShadow": false, "art": true, "woodland": true,
			"_mask": {"w": mw, "h": mh, "k": stride, "a": mask}}
	var s: Dictionary = _cache[kind].duplicate()
	s.scale *= size
	return s


## Blue 8..9 is reserved for keyed foliage in the shared sorted material.
static func color(tint: Color) -> Color:
	return Color(tint.r, tint.g, tint.b + 8.0, tint.a)
