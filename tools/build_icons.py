"""Convert the FreeScene SVG icons into a theme-tinted Flutter icon font.

Development-only dependency: fonttools (python -m pip install fonttools).
"""
from pathlib import Path
from xml.etree import ElementTree
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path

root = Path(__file__).resolve().parents[1]
font = FontBuilder(1024, isTTF=True)
# Navigation glyphs: google/material-design-icons, symbols/web,
# Material Symbols Outlined, optical size 48, weight 400 (Apache 2.0).
icons = {
    'download': 0xE900, 'heart_plus': 0xE901, 'settings': 0xE902,
    'history': 0xE903, 'keyboard_double_arrow_left': 0xE904,
    'keyboard_double_arrow_right': 0xE905, 'tracker_add': 0xE906,
}
font.setupGlyphOrder(['.notdef', *icons])
font.setupCharacterMap({code: name for name, code in icons.items()})
glyphs = {'.notdef': TTGlyphPen(None).glyph()}
for name in icons:
    pen = TTGlyphPen(None)
    svg = ElementTree.parse(root/f'assets/icons/{name}.svg').getroot()
    x, y, width, height = map(float, svg.attrib['viewBox'].split())
    if width != height:
        raise ValueError(f'Expected a square viewBox for {name}')
    scale = 1024 / width
    transform = TransformPen(pen, (scale, 0, 0, -scale, -x * scale, 1024 + y * scale))
    for path in svg.iter('{http://www.w3.org/2000/svg}path'):
        parse_path(path.attrib['d'], transform)
    glyphs[name] = pen.glyph()
font.setupGlyf(glyphs)
font.setupHorizontalMetrics({name: (1024, glyph.xMin if name in icons else 0)
                            for name, glyph in glyphs.items()})
font.setupHorizontalHeader(ascent=1024, descent=0)
font.setupNameTable({'familyName': 'FreeSceneIcons', 'styleName': 'Regular',
                    'uniqueFontIdentifier': 'FreeSceneIcons-Regular-1',
                    'fullName': 'FreeSceneIcons Regular', 'psName': 'FreeSceneIcons-Regular'})
font.setupOS2(sTypoAscender=1024, sTypoDescender=0, usWinAscent=1024, usWinDescent=0)
font.setupPost()
font.setupMaxp()
font.font['head'].created = font.font['head'].modified = 2082844800
font.save(root/'assets/icons/FreeSceneIcons.ttf')
