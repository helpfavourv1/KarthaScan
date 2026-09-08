#!/bin/bash
# Render Play Store required assets from logo.svg
cd "$(dirname "$0")/../app"

python3 << 'INNER_PYEOF'
import cairosvg
import os

svg_path = 'assets/logo.svg'
if not os.path.exists(svg_path):
    print("❌ assets/logo.svg not found!")
    exit(1)

print("=== RENDERING PLAY STORE ASSETS ===")

# Play Store icon: 512x512
cairosvg.svg2png(url=svg_path, write_to='assets/icon_play_store.png', output_width=512, output_height=512)
print("✅ Generated 512x512 icon_play_store.png")

# Play Store feature graphic: 1024x500
cairosvg.svg2png(url=svg_path, write_to='assets/feature_graphic.png', output_width=1024, output_height=500)
print("✅ Generated 1024x500 feature_graphic.png")

# Native assets (1024x1024)
cairosvg.svg2png(url=svg_path, write_to='assets/icon_source.png', output_width=1024, output_height=1024)
cairosvg.svg2png(url=svg_path, write_to='assets/splash_logo.png', output_width=1024, output_height=1024)
print("✅ Generated 1024x1024 native assets")
INNER_PYEOF

echo "=== REGENERATING NATIVE ICONS & SPLASH ==="
dart run flutter_launcher_icons
dart run flutter_native_splash:create
