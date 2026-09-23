#!/usr/bin/env python3
"""Extract logical partitions from the split super_N.img pieces of a QFIL ROM.

The pieces are raw (non-sparse) chunks written by rawprogram*.xml at
start_sector (4096-byte sectors) of the physical LUN. The first piece holds the
LP geometry/metadata. Partitions are rebuilt from their LINEAR extents; any
range not covered by a piece is zero-filled.

usage: extract_super.py <rom_dir> <out_dir> [partition ...]
       (partition names without slot suffix; default: all non-empty *_a)
"""
import glob
import os
import re
import struct
import sys

SECTOR = 512
LP_TARGET_TYPE_LINEAR = 0


def load_pieces(rom):
    pieces = []
    for xml in sorted(glob.glob(os.path.join(rom, "rawprogram[0-9].xml"))):
        for m in re.finditer(r"<program [^>]*>", open(xml, encoding="utf-8").read()):
            tag = m.group(0)
            attr = dict(re.findall(r'(\w+)="([^"]*)"', tag))
            if attr.get("label") != "super" or not attr.get("filename"):
                continue
            ss = int(attr.get("SECTOR_SIZE_IN_BYTES", "4096"))
            pieces.append((int(attr["start_sector"]) * ss, os.path.join(rom, attr["filename"])))
    pieces = sorted(set(pieces))
    if not pieces:
        sys.exit("no super pieces found in rawprogram*.xml")
    base = pieces[0][0]
    return [(off - base, path, os.path.getsize(path)) for off, path in pieces]


def read_super(pieces, off, length):
    out = bytearray(length)
    for poff, path, psize in pieces:
        lo, hi = max(off, poff), min(off + length, poff + psize)
        if lo < hi:
            with open(path, "rb") as f:
                f.seek(lo - poff)
                out[lo - off:hi - off] = f.read(hi - lo)
    return bytes(out)


def parse_metadata(pieces):
    geo = read_super(pieces, 4096, 4096)
    if geo[:4] != b"gDla":
        sys.exit("LP geometry not found")
    max_meta = struct.unpack("<I", geo[40:44])[0]
    meta = read_super(pieces, 4096 * 3, max_meta)
    hsz = struct.unpack("<I", meta[8:12])[0]
    tabs = [struct.unpack("<III", meta[80 + i * 12:92 + i * 12]) for i in range(4)]
    body = meta[hsz:]
    (po, pn, pes), (eo, en, ees) = tabs[0], tabs[1]
    extents = []
    for i in range(en):
        e = body[eo + i * ees:eo + (i + 1) * ees]
        nsec, ttype, tdata, tsrc = struct.unpack("<QIQI", e[:24])
        extents.append((nsec, ttype, tdata))
    parts = {}
    for i in range(pn):
        e = body[po + i * pes:po + (i + 1) * pes]
        name = e[:36].rstrip(b"\0").decode()
        _, first, num, _ = struct.unpack("<IIII", e[36:52])
        parts[name] = extents[first:first + num]
    return parts


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    rom, out = sys.argv[1], sys.argv[2]
    want = sys.argv[3:]
    pieces = load_pieces(rom)
    parts = parse_metadata(pieces)
    os.makedirs(out, exist_ok=True)
    for name, exts in parts.items():
        if not exts or not name.endswith("_a"):
            continue
        base = name[:-2]
        if want and base not in want:
            continue
        dst = os.path.join(out, base + ".img")
        total = 0
        with open(dst, "wb") as f:
            for nsec, ttype, tdata in exts:
                size = nsec * SECTOR
                if ttype == LP_TARGET_TYPE_LINEAR:
                    pos, left = tdata * SECTOR, size
                    while left:
                        n = min(left, 64 << 20)
                        f.write(read_super(pieces, pos, n))
                        pos += n
                        left -= n
                else:
                    f.write(b"\0" * size)
                total += size
        with open(dst, "rb") as f:
            f.seek(1024)
            sb = f.read(1024)
        fs = "erofs" if sb[:4] == b"\xe2\xe1\xf5\xe0" else "ext4" if sb[0x38:0x3a] == b"\x53\xef" else "unknown"
        print(f"{base:12s} {total:>12d} bytes  fs={fs}  -> {dst}")


if __name__ == "__main__":
    main()
