extends Node
## Loads art from the player's own copy of Unnatural Selection at runtime.
## Nothing copyrighted ships with the remake: the player points the game at
## their original install folder once (see Settings.game_dir).
##
## High-resolution override hook: if Settings.hires_pack points to a folder
## containing "<file>_<index>.png" (e.g. "al1_002.png"), that image is used
## instead of the original, drawn into the same logical rectangle. A 4x or 8x
## redraw therefore shows up sharp at high window sizes with no code changes.

const REQUIRED := ["data/al1.bin", "data/al3.bin", "data/5x.pal", "data/4x6.fnt"]

var lab_palette: UnsPalette
var _archives := {}   # rel path -> UnsArchive
var _textures := {}   # cache key -> Texture2D
var _sizes := {}      # cache key -> Vector2i (logical size in original pixels)
var _fonts := {}      # name -> {tex, w, h}
var ready_ok := false


func init_from_settings() -> bool:
	ready_ok = false
	_archives.clear()
	_textures.clear()
	_sizes.clear()
	_fonts.clear()
	if not is_valid_game_dir(Settings.game_dir):
		return false
	lab_palette = UnsPalette.from_file(resolve("data/5x.pal"))
	ready_ok = true
	return true


## True if `dir` looks like an Unnatural Selection install.
static func is_valid_game_dir(dir: String) -> bool:
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return false
	for rel in REQUIRED:
		if find_case_insensitive(dir, rel).is_empty():
			return false
	return true


## DOS installs are often upper-case; look files up without caring about case.
static func find_case_insensitive(base: String, rel: String) -> String:
	return UnsArchive.find_file(base, rel)


func resolve(rel: String) -> String:
	return find_case_insensitive(Settings.game_dir, rel)


func archive(rel: String) -> UnsArchive:
	if not _archives.has(rel):
		var p := resolve(rel)
		_archives[rel] = UnsArchive.open(p) if not p.is_empty() else null
	return _archives[rel]


## Texture for image `index` of container `rel` (e.g. "data/al1.bin", 2).
## `transparent` lists palette indices to make transparent; by default the
## RLE key colour of the image is used.
func texture(rel: String, index: int, transparent = null, palette: UnsPalette = null) -> Texture2D:
	var key := "%s#%d#%s" % [rel, index, str(transparent)]
	if _textures.has(key):
		return _textures[key]
	var tex: Texture2D = null
	var size := Vector2i.ZERO
	var arc := archive(rel)
	if arc:
		var e := arc.get_entry(index)
		var img := UnsArchive.decode_image(e)
		if not img.is_empty():
			var pal := palette if palette else lab_palette
			if e.palette.size() > 0:
				pal = pal.duplicate_palette()
				pal.overlay(e.palette, UnsPalette.start_for_flag(e.flag))
			var tr: Array = []
			if transparent == null:
				if img.key >= 0 and img.key != 0xFF:
					tr = [img.key]
			else:
				tr = transparent
			size = Vector2i(img.w, img.h)
			tex = ImageTexture.create_from_image(pal.to_image(img.w, img.h, img.px, tr))
	# optional high-resolution replacement
	var hi := _hires_texture(rel, index)
	if hi:
		tex = hi
	_textures[key] = tex
	_sizes[key] = size
	return tex


## Logical (original-pixel) size of an image, regardless of hi-res overrides.
func size_of(rel: String, index: int, transparent = null) -> Vector2i:
	var key := "%s#%d#%s" % [rel, index, str(transparent)]
	if not _sizes.has(key):
		texture(rel, index, transparent)
	return _sizes.get(key, Vector2i.ZERO)


func _hires_texture(rel: String, index: int) -> Texture2D:
	if Settings.hires_pack.is_empty():
		return null
	var stem := rel.get_file().get_basename().to_lower()
	var p := Settings.hires_pack.path_join("%s_%03d.png" % [stem, index])
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	return ImageTexture.create_from_image(img) if img else null


## Bitmap font from the original .fnt files: u8 w, u8 h, then 90 glyphs
## (ASCII 32..121), one byte per row, MSB = leftmost pixel.
func font(name: String = "4x6") -> Dictionary:
	if _fonts.has(name):
		return _fonts[name]
	var p := resolve("data/%s.fnt" % name)
	var f := FileAccess.open(p, FileAccess.READ) if not p.is_empty() else null
	if f == null:
		return {}
	var d := f.get_buffer(f.get_length())
	f.close()
	var gw := d[0]
	var gh := d[1]
	var count := (d.size() - 2) / gh
	var img := Image.create(gw * count, gh, false, Image.FORMAT_RGBA8)
	for g in count:
		for row in gh:
			var bits := d[2 + g * gh + row]
			for col in gw:
				if bits & (0x80 >> col):
					img.set_pixel(g * gw + col, row, Color.WHITE)
	var info := {"tex": ImageTexture.create_from_image(img), "w": gw, "h": gh, "count": count}
	_fonts[name] = info
	return info


## Draws text with an original bitmap font onto `ci` (a CanvasItem in _draw).
func draw_text(ci: CanvasItem, pos: Vector2, text: String, color: Color, name: String = "4x6") -> void:
	var f := font(name)
	if f.is_empty():
		ci.draw_string(ThemeDB.fallback_font, pos + Vector2(0, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, color)
		return
	var x := pos.x
	for ch in text.to_upper() if name == "4x6" else text:
		var code := ch.unicode_at(0) - 32
		if code >= 0 and code < f.count:
			ci.draw_texture_rect_region(f.tex, Rect2(x, pos.y, f.w, f.h),
				Rect2(code * f.w, 0, f.w, f.h), color)
		x += f.w
