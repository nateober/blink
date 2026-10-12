#!/usr/bin/env -S uv run --quiet --with fonttools --python 3.12 --
"""Build Resources/Fonts/BlinkSymbols.ttf, the terminal's one-cell symbols fallback.

Some symbols (for example U+23FA, the record dot Claude Code prints) are in no bundled
terminal font and no Apple text font, only in Apple Color Emoji, whose glyphs are a full em
wide. The terminal counts them as one cell, so the text after them shifts. This font holds
those symbols drawn inside one 600/1000 em cell, and sits in the font stack ahead of emoji.

The set is every BMP character that Unicode marks Emoji=Yes without Emoji_Presentation and
that is not East Asian Wide/Fullwidth (so the terminal treats it as one cell), limited to
what the source font has and the bundled DejaVu fallback lacks.

Usage: build_symbols_font.py <NotoSansSymbols2-Regular.ttf> <emoji-data.txt> <EastAsianWidth.txt>
Source font: Noto Sans Symbols 2, SIL Open Font License 1.1 (github.com/notofonts/symbols).
"""
import re
import sys
from fontTools import subset
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

CELL = 600      # advance, in 1000 units per em: the cell of most monospace fonts
INK = 540       # widest drawing allowed inside the cell
OUT = "Resources/Fonts/BlinkSymbols.ttf"
FALLBACK = "Resources/Fonts/DejaVu-Sans-Mono-for-Powerline.ttf"


def ranges(path, want):
    out = set()
    for line in open(path, encoding="utf-8"):
        line = line.split("#")[0].strip()
        m = re.match(r"([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*(\S+)", line)
        if m and m.group(3) in want:
            a = int(m.group(1), 16)
            out.update(range(a, int(m.group(2) or m.group(1), 16) + 1))
    return out


def main():
    src, emoji_data, eaw = sys.argv[1:4]
    emoji = ranges(emoji_data, {"Emoji"})
    presentation = ranges(emoji_data, {"Emoji_Presentation"})
    wide = ranges(eaw, {"W", "F"})
    fallback = set(TTFont(FALLBACK).getBestCmap())
    font = TTFont(src)
    have = set(font.getBestCmap())
    cps = sorted(c for c in emoji - presentation - wide
                 if 0x2000 <= c <= 0xFFFF and c in have and c not in fallback)

    options = subset.Options()
    options.layout_features = []
    options.name_IDs = [1, 2, 3, 4, 6, 13, 14]
    options.notdef_outline = True
    options.glyph_names = False
    options.hinting = False
    sub = subset.Subsetter(options)
    sub.populate(unicodes=cps)
    sub.subset(font)

    upm = font["head"].unitsPerEm
    scale_em = 1000 / upm
    glyphs = font.getGlyphSet()
    glyf, hmtx = font["glyf"], font["hmtx"]
    for name in font.getGlyphOrder():
        bounds = BoundsPen(glyphs)
        glyphs[name].draw(bounds)
        if bounds.bounds is None:
            hmtx[name] = (round(CELL / scale_em), 0)
            continue
        x0, y0, x1, y1 = bounds.bounds
        width = (x1 - x0) * scale_em
        k = min(1.0, INK / width) if width > 0 else 1.0
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        # scale about the drawing's centre, then centre it in the cell
        dx = (CELL / scale_em) / 2 - cx * k
        dy = cy - cy * k
        pen = TTGlyphPen(None)
        glyphs[name].draw(TransformPen(pen, (k, 0, 0, k, dx, dy)))
        glyf[name] = pen.glyph()
        hmtx[name] = (round(CELL / scale_em), round((CELL / scale_em) / 2 - (x1 - x0) * k / 2))

    font["hhea"].advanceWidthMax = round(CELL / scale_em)
    font["post"].isFixedPitch = 1
    if "OS/2" in font:
        font["OS/2"].xAvgCharWidth = round(CELL / scale_em)
        font["OS/2"].panose.bProportion = 9
    for record in font["name"].names:
        if record.nameID in (1, 4):
            record.string = "Blink Symbols"
        elif record.nameID == 6:
            record.string = "BlinkSymbols-Regular"
        elif record.nameID == 3:
            record.string = "BlinkSymbols-Regular;derived from Noto Sans Symbols 2"
    font.save(OUT)
    print(f"{OUT}: {len(cps)} symbols, e.g. " + " ".join(f"U+{c:04X}" for c in cps[:12]))
    print("has U+23FA:", 0x23FA in cps)


main()
