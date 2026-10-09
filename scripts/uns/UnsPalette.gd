class_name UnsPalette
extends RefCounted
## 256-colour VGA palette (stored as 6-bit components in the original files).

var colors: PackedColorArray


func _init() -> void:
	colors = PackedColorArray()
	colors.resize(256)
	for i in 256:
		colors[i] = Color.BLACK


static func from_file(file_path: String) -> UnsPalette:
	var p := UnsPalette.new()
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f:
		p.overlay(f.get_buffer(768), 0)
		f.close()
	return p


func duplicate_palette() -> UnsPalette:
	var p := UnsPalette.new()
	p.colors = colors.duplicate()
	return p


## Writes a chunk of 6-bit RGB triplets into the palette starting at `start`.
func overlay(chunk: PackedByteArray, start: int) -> void:
	var n := chunk.size() / 3
	for i in n:
		var idx := start + i
		if idx > 255:
			break
		colors[idx] = Color8(_c(chunk[i * 3]), _c(chunk[i * 3 + 1]), _c(chunk[i * 3 + 2]))


## Palette-chunk start index for a given entry flag (see docs/FORMATS.md).
static func start_for_flag(flag: int) -> int:
	return 0 if flag == 1 else 64


static func _c(v: int) -> int:
	return mini(255, (v * 255) / 63)


## Converts indexed pixels to an RGBA Image. Pixels equal to any value in
## `transparent` become fully transparent.
func to_image(w: int, h: int, px: PackedByteArray, transparent: Array = []) -> Image:
	var rgba := PackedByteArray()
	rgba.resize(w * h * 4)
	var lut := PackedByteArray()
	lut.resize(256 * 4)
	for i in 256:
		var c := colors[i]
		lut[i * 4] = c.r8
		lut[i * 4 + 1] = c.g8
		lut[i * 4 + 2] = c.b8
		lut[i * 4 + 3] = 0 if transparent.has(i) else 255
	for i in w * h:
		var v := px[i] * 4
		var o := i * 4
		rgba[o] = lut[v]
		rgba[o + 1] = lut[v + 1]
		rgba[o + 2] = lut[v + 2]
		rgba[o + 3] = lut[v + 3]
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
