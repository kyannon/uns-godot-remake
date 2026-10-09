"""Unnatural Selection (Maxis, 1993) asset extractor.

Container format (.bin / .iln):
  header: N x 8-byte entries (N = first entry's offset / 8)
    u16 size, u16 group, u16 offset_lo, u8 type, u8 palette_flag
  entries are stored back to back; an entry with a palette flag is
  preceded by a raw 6-bit VGA palette chunk that is NOT counted in size.
Types:
  'R' RLE image : u16 w, u16 h, u8 key, RLE stream, u8 checksum
                  RLE: 0x89 n v -> (n+1) copies of v, else literal
  'N' raw image : u16 w, u16 h, u8 key, w*h bytes
  'T' text      : bytes XOR 0x8A; values < 0x20 are punctuation (+0x20)
  'F'/'A'       : animation frames / tables (not decoded yet)
"""
import struct, sys, os, json

PAL_BYTES = {0: 0, 1: 768, 3: 576, 5: 192, 7: 285, 8: 18}


def read_container(path):
    d = open(path, 'rb').read()
    hdr = struct.unpack_from('<H', d, 4)[0]
    entries, pos = [], hdr
    for i in range(hdr // 8):
        size, grp, lo, t, fl = struct.unpack_from('<HHHBB', d, i * 8)
        if size == 0 and lo == 0:
            continue
        pal = None
        # resync: entry start is congruent to offset_lo mod 64K
        cand = (pos & ~0xFFFF) | lo
        best = min((cand - 0x10000, cand, cand + 0x10000), key=lambda a: abs(a - pos))
        pos = best
        extra = PAL_BYTES.get(fl, 0)
        if extra:
            pal = d[pos:pos + extra]
            pos += extra
        entries.append(dict(index=i, group=grp, type=chr(t), flag=fl, offset=pos,
                            size=size, palette=pal, data=d[pos:pos + size]))
        pos += size
    return entries


def rle_decode(buf, pos, n):
    out = bytearray()
    L = len(buf)
    while len(out) < n and pos < L:
        b = buf[pos]
        if b == 0x89 and pos + 2 < L:
            out += bytes([buf[pos + 2]]) * (buf[pos + 1] + 1)
            pos += 3
        else:
            out.append(b)
            pos += 1
    return bytes(out[:n]) + bytes(max(0, n - len(out)))


def decode_image(e):
    d = e['data']
    if e['type'] not in 'RN' or len(d) < 5:
        return None
    w, h = struct.unpack_from('<HH', d, 0)
    if not (0 < w <= 640 and 0 < h <= 480):
        return None
    key = d[4]
    if e['type'] == 'R':
        px = rle_decode(d, 5, w * h)
    else:
        px = d[4:4 + w * h]
        key = 0
        px = px + bytes(max(0, w * h - len(px)))
    return w, h, key, px


def decode_text(e):
    s = bytes(b ^ 0x8A for b in e['data'])
    s = s.rstrip(b'\x00')
    out = []
    for b in s:
        if b == 0:
            out.append(' ')
        elif b < 0x20:
            out.append(chr(b + 0x20))
        else:
            out.append(chr(b))
    return ''.join(out)


def load_pal(path):
    p = open(path, 'rb').read()
    return [min(255, (c * 255) // 63) for c in p[:768]]


def pal_overlay(base, chunk, start=0):
    pal = list(base)
    for i, c in enumerate(chunk):
        if start * 3 + i < 768:
            pal[start * 3 + i] = min(255, (c * 255) // 63)
    return pal


def save_png(path, w, h, px, pal, key=None):
    from PIL import Image
    im = Image.frombytes('P', (w, h), px)
    im.putpalette(pal)
    rgba = im.convert('RGBA')
    if key is not None:
        data = rgba.load()
        for y in range(h):
            for x in range(w):
                if px[y * w + x] == key:
                    data[x, y] = (0, 0, 0, 0)
    rgba.save(path)


def extract_all(game_dir, out_dir):
    base = load_pal(os.path.join(game_dir, 'data', '5x.pal'))
    manifest = {}
    os.makedirs(out_dir, exist_ok=True)
    files = []
    for sub in ('data', 'islands'):
        for f in sorted(os.listdir(os.path.join(game_dir, sub))):
            if f.endswith(('.bin', '.iln')) and f != 'isltiles.bin':
                files.append(os.path.join(sub, f))
    for rel in files:
        name = os.path.splitext(os.path.basename(rel))[0]
        try:
            ents = read_container(os.path.join(game_dir, rel))
        except Exception as ex:
            print('skip', rel, ex)
            continue
        pal = base
        fdir = os.path.join(out_dir, name)
        os.makedirs(fdir, exist_ok=True)
        info = []
        for e in ents:
            if e['palette'] is not None:
                start = 0 if e['flag'] == 1 else 64
                pal = pal_overlay(base, e['palette'], start)
            rec = dict(index=e['index'], group=e['group'], type=e['type'], flag=e['flag'], size=e['size'])
            if e['type'] == 'T':
                rec['text'] = decode_text(e)
            else:
                img = decode_image(e)
                if img:
                    w, h, key, px = img
                    fn = f"{name}_{e['index']:03d}.png"
                    save_png(os.path.join(fdir, fn), w, h, px, pal,
                             key if e['type'] == 'N' or key not in (0xff,) else None)
                    rec.update(w=w, h=h, key=key, png=fn)
            info.append(rec)
        manifest[name] = info
    json.dump(manifest, open(os.path.join(out_dir, 'manifest.json'), 'w'), indent=1)
    return manifest


if __name__ == '__main__':
    m = extract_all(sys.argv[1], sys.argv[2])
    for k, v in m.items():
        n = sum(1 for r in v if 'png' in r)
        print(f'{k:10s} entries={len(v):4d} images={n}')
