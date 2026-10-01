"""Generate the app's platform icons from a shared supersampled design."""

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def icon(size):
    scale = 4
    canvas_size = size * scale
    image = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(
        (0, 0, canvas_size - 1, canvas_size - 1),
        radius=int(canvas_size * 0.24),
        fill='#5848d9',
    )
    width = max(2, int(canvas_size * 0.065))
    draw.line(
        [
            (canvas_size * 0.30, canvas_size * 0.24),
            (canvas_size * 0.30, canvas_size * 0.76),
            (canvas_size * 0.73, canvas_size * 0.76),
        ],
        fill='white', width=width, joint='curve',
    )
    for y, end in [(0.26, 0.73), (0.43, 0.73), (0.60, 0.60)]:
        draw.line(
            [(canvas_size * 0.46, canvas_size * y), (canvas_size * end, canvas_size * y)],
            fill='white', width=width,
        )
    return image.resize((size, size), Image.Resampling.LANCZOS)


def main():
    # Generate only when invoked as a script; importing this module is read-only.
    icon(256).save(
        ROOT / 'windows/runner/resources/app_icon.ico',
        sizes=[(size, size) for size in [16, 24, 32, 48, 64, 128, 256]],
    )
    for density, size in [
        ('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192),
    ]:
        icon(size).save(ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
    for platform in ['ios', 'macos']:
        assets = ROOT / platform / 'Runner/Assets.xcassets/AppIcon.appiconset'
        config = json.loads((assets / 'Contents.json').read_text(encoding='utf-8'))
        for entry in config['images']:
            if 'filename' not in entry:
                continue
            size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
            image = icon(size)
            if platform == 'ios':
                background = Image.new('RGB', image.size, '#5848d9')
                background.paste(image, mask=image.getchannel('A'))
                image = background
            image.save(assets / entry['filename'])
    icon(256).save(ROOT / 'assets/icon.png')


if __name__ == '__main__':
    main()
