#!/bin/bash
set -e

# ==============================================================================
# MASTER KARTHASCAN ASSET & MANIFEST UNIFICATION SCRIPT
# Clinically exhaustive, step-by-step automation.
# ==============================================================================

BASE="/data/data/com.termux/files/home/KarthaScan"
APP="$BASE/app"
WEB="$BASE/website"

cd "$BASE"

echo "========================================================================"
echo "PHASE 1: ENVIRONMENT GUARDS"
echo "========================================================================"
command -v cairosvg >/dev/null 2>&1 || { echo "❌ STOP: cairosvg missing. Run: pip install cairosvg"; exit 1; }
command -v flutter  >/dev/null 2>&1 || { echo "❌ STOP: flutter missing."; exit 1; }
command -v python3  >/dev/null 2>&1 || { echo "❌ STOP: python3 missing."; exit 1; }
command -v git      >/dev/null 2>&1 || { echo "❌ STOP: git missing."; exit 1; }
test -f app/assets/logo.svg || { echo "❌ STOP: app/assets/logo.svg missing."; exit 1; }
echo "✅ [1/9] Guards passed."

echo "========================================================================"
echo "PHASE 2: CORE PNG ASSET GENERATION & VALIDATION"
echo "========================================================================"
cd "$APP"
echo "Generating 1024x1024 and 512x512 PNGs..."
python3 -c "import cairosvg; cairosvg.svg2png(url='assets/logo.svg', write_to='assets/icon_source.png', output_width=1024, output_height=1024)"
python3 -c "import cairosvg; cairosvg.svg2png(url='assets/logo.svg', write_to='assets/splash_logo.png', output_width=1024, output_height=1024)"
python3 -c "import cairosvg; cairosvg.svg2png(url='assets/logo.svg', write_to='assets/icon_play_store.png', output_width=512, output_height=512)"

echo "Generating 1024x500 Feature Graphic..."
python3 -c "
src=open('assets/logo.svg').read()
inner=src[src.index('>',src.index('<svg'))+1: src.rindex('</svg>')]
wrap='<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"500\" viewBox=\"0 0 1024 500\"><rect width=\"1024\" height=\"500\" fill=\"#0b1220\"/><g transform=\"translate(312,50) scale(0.390625)\">'+inner+'</g></svg>'
open('assets/feature_graphic_src.svg','w').write(wrap)
"
python3 -c "import cairosvg; cairosvg.svg2png(url='assets/feature_graphic_src.svg', write_to='assets/feature_graphic.png', output_width=1024, output_height=500)"
rm assets/feature_graphic_src.svg

echo "Validating Dimensions..."
python3 -c "
import struct
def check_png(path, expected_w, expected_h):
    d=open(path,'rb').read(33)
    w,h = struct.unpack('>II',d[16:24])
    if w != expected_w or h != expected_h:
        print(f'❌ DIMENSION MISMATCH: {path} is {w}x{h}, expected {expected_w}x{expected_h}')
        exit(1)
    print(f'✅ {path}: {w}x{h}')

check_png('assets/icon_source.png', 1024, 1024)
check_png('assets/splash_logo.png', 1024, 1024)
check_png('assets/icon_play_store.png', 512, 512)
check_png('assets/feature_graphic.png', 1024, 500)
"
echo "✅ [2/9] Core assets generated and validated."

echo "========================================================================"
echo "PHASE 3: YAML CONFIGURATION UNIFICATION"
echo "========================================================================"
cd "$BASE"
# Launcher Icons
sed -i 's/#007AFF/#0B1220/g' app/flutter_launcher_icons.yaml
sed -i 's/^  ios: false/  ios: true/g' app/flutter_launcher_icons.yaml
sed -i 's/image_path_android:.*/image_path_android: "assets\/icon_source.png"/g' app/flutter_launcher_icons.yaml
sed -i 's/adaptive_icon_background:.*/adaptive_icon_background: "#0B1220"/g' app/flutter_launcher_icons.yaml
sed -i 's/adaptive_icon_foreground:.*/adaptive_icon_foreground: "assets\/icon_source.png"/g' app/flutter_launcher_icons.yaml

# Native Splash
sed -i 's/"#F2F2F7"/"#0B1220"/g; s/"#000000"/"#0B1220"/g; s/#F2F2F7/#0B1220/g; s/#000000/#0B1220/g' app/flutter_native_splash.yaml
sed -i 's/^  ios: false/  ios: true/g' app/flutter_native_splash.yaml
echo "✅ [3/9] YAMLs unified to #0B1220 and iOS enabled."

echo "========================================================================"
echo "PHASE 4: FLUTTER NATIVE GENERATORS"
echo "========================================================================"
cd "$APP"
flutter pub get >/dev/null 2>&1
echo "Running flutter_launcher_icons..."
dart run flutter_launcher_icons >/dev/null 2>&1
echo "Running flutter_native_splash..."
dart run flutter_native_splash:create >/dev/null 2>&1
echo "✅ [4/9] Flutter generators completed."

echo "========================================================================"
echo "PHASE 5: ANDROID MANIFEST ENFORCEMENT (OUTSTANDING ITEM)"
echo "========================================================================"
cd "$APP"
MANIFEST="android/app/src/main/AndroidManifest.xml"
python3 -c "
import re
path = '$MANIFEST'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Force android:icon
content = re.sub(r'android:icon=\"[^\"]+\"', 'android:icon=\"@mipmap/launcher_icon\"', content)
# Force android:roundIcon
content = re.sub(r'android:roundIcon=\"[^\"]+\"', 'android:roundIcon=\"@mipmap/launcher_icon\"', content)

# If roundIcon is completely missing from the application tag, inject it
if 'android:roundIcon=' not in content:
    content = content.replace('android:icon=\"@mipmap/launcher_icon\"', 'android:icon=\"@mipmap/launcher_icon\"\n        android:roundIcon=\"@mipmap/launcher_icon\"')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('✅ AndroidManifest.xml updated to @mipmap/launcher_icon')
"
echo "✅ [5/9] Android Manifest secured."

echo "========================================================================"
echo "PHASE 6: iOS PROJECT HARDENING"
echo "========================================================================"
cd "$APP"
if [ ! -d "ios" ]; then
    echo "Creating iOS project..."
    flutter create --platforms=ios . >/dev/null 2>&1
fi

echo "Enforcing iPhone-only..."
sed -i 's/TARGETED_DEVICE_FAMILY = "1,2"/TARGETED_DEVICE_FAMILY = "1"/g' ios/Runner.xcodeproj/project.pbxproj

echo "Injecting Info.plist keys..."
python3 -c "
import plistlib
p='ios/Runner/Info.plist'
d=plistlib.load(open(p,'rb'))
d['NSCameraUsageDescription']='KatharScan uses the camera to scan documents into PDF.'
d['NSPhotoLibraryUsageDescription']='KatharScan saves exported scans to your photo library only when you choose to.'
d['NSPhotoLibraryAddUsageDescription']='KatharScan saves exported scans to your photo library only when you choose to.'
d['NSUserTrackingUsageDescription']='KatharScan uses this identifier to serve and measure ads.'
plistlib.dump(d,open(p,'wb'))
"

echo "Writing PrivacyInfo.xcprivacy..."
python3 -c "
import plistlib
d={'NSPrivacyTracking':False, 'NSPrivacyTrackingDomains':[], 'NSPrivacyCollectedDataTypes':[], 'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryUserDefaults','NSPrivacyAccessedAPITypeReasons':['1C8F.1']}]}
plistlib.dump(d,open('ios/Runner/PrivacyInfo.xcprivacy','wb'))
"
echo "✅ [6/9] iOS project hardened."

echo "========================================================================"
echo "PHASE 7: WEB ASSETS & META TAGS"
echo "========================================================================"
cd "$BASE"
mkdir -p website/assets
cp app/assets/logo.svg website/assets/favicon.svg
python3 -c "import cairosvg; cairosvg.svg2png(url='app/assets/logo.svg', write_to='website/assets/apple-touch-icon.png', output_width=180, output_height=180)"
python3 -c "import cairosvg; cairosvg.svg2png(url='app/assets/logo.svg', write_to='website/assets/pwa-192.png', output_width=192, output_height=192)"
python3 -c "import cairosvg; cairosvg.svg2png(url='app/assets/logo.svg', write_to='website/assets/pwa-512.png', output_width=512, output_height=512)"
cp website/assets/pwa-512.png website/assets/og-image.png

for file in website/index.html website/privacy.html website/terms.html website/support.html; do
    if [ -f "$file" ]; then
        # Remove existing icon links to prevent duplicates
        sed -i '/<link rel="icon"/d' "$file"
        sed -i '/<link rel="apple-touch-icon"/d' "$file"
        sed -i '/<meta property="og:image"/d' "$file"
        
        # Inject fresh tags
        sed -i 's|<head[^>]*>|&\n    <link rel="icon" type="image/svg+xml" href="assets/favicon.svg">\n    <link rel="apple-touch-icon" href="assets/apple-touch-icon.png">\n    <meta property="og:image" content="assets/og-image.png">|' "$file"
    fi
done
echo "✅ [7/9] Web assets and meta tags injected."

echo "========================================================================"
echo "PHASE 8: GIT STAGING & COMMIT (OUTSTANDING ITEM)"
echo "========================================================================"
cd "$BASE"
git add app/assets/ app/flutter_launcher_icons.yaml app/flutter_native_splash.yaml app/android/app/src/main/AndroidManifest.xml app/ios/ website/
git commit -m "chore: unify brand assets (#0B1220), enforce Android/iOS manifests, and generate native splash/icons" >/dev/null 2>&1 || echo "No changes to commit or already committed."
echo "✅ [8/9] Git staged and committed locally."

echo "========================================================================"
echo "PHASE 9: LOCAL TESTING INSTRUCTIONS (OUTSTANDING ITEM)"
echo "========================================================================"
echo "🛑 AUTOMATION PAUSED FOR MANUAL VERIFICATION."
echo ""
echo "To test the app locally and verify the splash screen & launcher icon:"
echo "1. Start your Android Emulator or connect a physical device."
echo "2. Run the following command in your Termux terminal:"
echo ""
echo "   cd /data/data/com.termux/files/home/KarthaScan/app && flutter run"
echo ""
echo "3. Verify the following on the device/emulator:"
echo "   - The Splash Screen displays the navy background (#0B1220) and logo."
echo "   - The Home Screen app icon is the new KatharScan logo."
echo "   - The app opens without crashing (camera permissions prompt appears if needed)."
echo ""
echo "4. Once verified, push to Git:"
echo "   cd /data/data/com.termux/files/home/KarthaScan && git push"
echo ""
echo "========================================================================"
echo "✅ ALL AUTOMATED STEPS COMPLETED SUCCESSFULLY."
echo "========================================================================"
