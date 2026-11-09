"""Package the approved mascot into Android density/adaptive launcher resources."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
# Preserve the white source canvas and its intentional breathing room.
source = Image.open(root/'assets/branding/jungbion-vehicle-logo.png').convert('RGBA')
mascot = source
res = root/'android/app/src/main/res'
for density, scale in [('mdpi',1),('hdpi',1.5),('xhdpi',2),('xxhdpi',3),('xxxhdpi',4)]:
    folder=res/f'mipmap-{density}'
    folder.mkdir(exist_ok=True)
    for name, base, occupancy, background in [
        ('jungbion_launcher',48,1.0,(255,255,255,255)),
        ('jungbion_foreground',108,84/108,(255,255,255,255)),
    ]:
        size=round(base*scale)
        artwork=mascot.copy()
        artwork.thumbnail((round(size*occupancy),round(size*occupancy)),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',(size,size),background)
        canvas.alpha_composite(artwork,((size-artwork.width)//2,(size-artwork.height)//2))
        if name == 'jungbion_launcher':
            mask = Image.new('L', (size, size))
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, size-1, size-1), radius=round(size*.22), fill=255)
            canvas.putalpha(mask)
        canvas.save(folder/f'{name}.png')
(res/'mipmap-anydpi-v26').mkdir(exist_ok=True)
(res/'mipmap-anydpi-v26/jungbion_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/jungbion_icon_background" />
    <foreground android:drawable="@mipmap/jungbion_foreground" />
</adaptive-icon>
''')
(res/'values/jungbion_brand.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">정비온</string>
    <color name="jungbion_icon_background">#FFFFFF</color>
</resources>
''')
