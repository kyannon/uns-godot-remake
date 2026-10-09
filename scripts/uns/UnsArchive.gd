class_name UnsArchive
extends RefCounted
## Reader for the original Unnatural Selection (Maxis, 1993) resource containers
## (data/*.bin and islands/*.iln). See docs/FORMATS.md for the full layout.
##
## Header: N entries of 8 bytes (N = first entry's offset / 8):
##   u16 size, u16 group, u16 offset_lo, u8 type, u8 palette_flag
## Entries are stored back to back. An entry with a palette flag is preceded by
## a raw 6-bit VGA palette chunk that is not counted in `size`.

const PAL_BYTES := {0: 0, 1: 768, 3: 576, 5: 192, 7: 285, 8: 18}

var path: String
var entries: Array = []  # Array of Dictionary


static func open(file_path: String) -> UnsArchive:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		push_error("UnsArchive: cannot open %s" % file_path)
		return null
	var data := f.get_buffer(f.get_length())
	f.close()
	var arc := UnsArchive.new()
	arc.path = file_path
	arc._parse(data)
	return arc


func _parse(d: PackedByteArray) -> void:
	if d.size() < 8:
		return
	var hdr := d.decode_u16(4)
	var count := hdr / 8
	var pos := hdr
	for i in count:
		var size := d.decode_u16(i * 8)
		var group := d.decode_u16(i * 8 + 2)
		var lo := d.decode_u16(i * 8 + 4)
		var type := d[i * 8 + 6]
		var flag := d[i * 8 + 7]
		if size == 0 and lo == 0:
			continue
		# Re-sync: the stored 16-bit offset is the entry start modulo 64K.
		var cand := (pos & ~0xFFFF) | lo
		var best := cand
		for c in [cand - 0x10000, cand + 0x10000]:
			if absi(c - pos) < absi(best - pos):
				best = c
		pos = best
		var pal := PackedByteArray()
		var extra: int = PAL_BYTES.get(flag, 0)
		if extra > 0:
			pal = d.slice(pos, pos + extra)
			pos += extra
		entries.append({
			"index": i,
			"group": group,
			"type": char(type),
			"flag": flag,
			"palette": pal,
			"data": d.slice(pos, pos + size),
		})
		pos += size


## Case-insensitive lookup of `rel` (e.g. "data/al1.bin") under `base`;
## DOS installs are often upper-case. Returns "" if not found.
static func find_file(base: String, rel: String) -> String:
	var cur := base
	for part in rel.split("/"):
		var da := DirAccess.open(cur)
		if da == null:
			return ""
		var found := ""
		for name in da.get_files() + da.get_directories():
			if name.to_lower() == part.to_lower():
				found = name
				break
		if found.is_empty():
			return ""
		cur = cur.path_join(found)
	return cur


func get_entry(index: int) -> Dictionary:
	for e in entries:
		if e.index == index:
			return e
	return {}


## Decodes an 'R' (RLE) or 'N' (raw) image entry.
## Returns {w, h, key, px: PackedByteArray of palette indices} or {} on failure.
static func decode_image(e: Dictionary) -> Dictionary:
	if e.is_empty():
		return {}
	var d: PackedByteArray = e.data
	if d.size() < 5 or not (e.type == "R" or e.type == "N"):
		return {}
	var w := d.decode_u16(0)
	var h := d.decode_u16(2)
	if w == 0 or h == 0 or w > 640 or h > 480:
		return {}
	var n := w * h
	var px := PackedByteArray()
	px.resize(n)
	var key := -1
	if e.type == "N":
		# raw: pixels start right after w,h; trailing byte is a checksum
		var avail := mini(n, d.size() - 4)
		for i in avail:
			px[i] = d[4 + i]
	else:
		key = d[4]
		var pos := 5
		var o := 0
		var L := d.size()
		while o < n and pos < L:
			var b := d[pos]
			if b == 0x89 and pos + 2 < L:
				var cnt := d[pos + 1] + 1
				var v := d[pos + 2]
				var end := mini(o + cnt, n)
				while o < end:
					px[o] = v
					o += 1
				pos += 3
			else:
				px[o] = b
				o += 1
				pos += 1
	return {"w": w, "h": h, "key": key, "px": px}


## Decodes a 'T' text entry (XOR 0x8A; values < 0x20 are punctuation + 0x20).
static func decode_text(e: Dictionary) -> String:
	var s := ""
	for b in e.data:
		var c: int = b ^ 0x8A
		if c == 0x8A:  # raw 0x00 terminator
			break
		if c == 0:
			s += " "
		elif c < 0x20:
			s += char(c + 0x20)
		else:
			s += char(c)
	return s.strip_edges()
