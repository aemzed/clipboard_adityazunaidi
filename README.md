# Project Clipboard

Aplikasi clipboard manager macOS berbasis SwiftUI.

## Prasyarat

- macOS + Xcode terpasang
- Command Line Tools aktif
- Bisa menjalankan `xcodebuild`, `codesign`, `hdiutil`

## Build `.app` (Release)

Jalankan dari root repo:

```bash
xcodebuild \
  -project project_clipboard.xcodeproj \
  -scheme project_clipboard \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/project_clipboard_derived_release \
  clean build
```

Ambil path `.app` hasil build:

```bash
APP_PATH="$(find /tmp/project_clipboard_derived_release/Build/Products/Release -maxdepth 1 -name '*.app' -print -quit)"
echo "$APP_PATH"
```

## Build `.dmg` (tanpa signing)

```bash
APP_PATH="$(find /tmp/project_clipboard_derived_release/Build/Products/Release -maxdepth 1 -name '*.app' -print -quit)"

rm -rf dist/dmg_staging
mkdir -p dist/dmg_staging
cp -R "$APP_PATH" dist/dmg_staging/
ln -s /Applications dist/dmg_staging/Applications

hdiutil create \
  -volname "Project Clipboard" \
  -srcfolder dist/dmg_staging \
  -ov \
  -format UDZO \
  dist/project_clipboard-macos.dmg
```

Output akhir:

- `dist/project_clipboard-macos.dmg`

## Build `.dmg` untuk distribusi (signed + notarized)

Set identity Developer ID Application milik kamu:

```bash
export APP_SIGN_IDENTITY="Developer ID Application: NAMA KAMU (TEAMID)"
```

Sign `.app`, buat `.dmg`, lalu sign `.dmg`:

```bash
APP_PATH="$(find /tmp/project_clipboard_derived_release/Build/Products/Release -maxdepth 1 -name '*.app' -print -quit)"

codesign --force --deep --sign "$APP_SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -rf dist/dmg_staging_signed
mkdir -p dist/dmg_staging_signed
cp -R "$APP_PATH" dist/dmg_staging_signed/
ln -s /Applications dist/dmg_staging_signed/Applications

hdiutil create \
  -volname "Project Clipboard" \
  -srcfolder dist/dmg_staging_signed \
  -ov \
  -format UDZO \
  dist/project_clipboard-macos.dmg

codesign --force --sign "$APP_SIGN_IDENTITY" dist/project_clipboard-macos.dmg
codesign --verify --verbose=2 dist/project_clipboard-macos.dmg
```

Notarization (butuh profile `notarytool` yang sudah dikonfigurasi):

```bash
xcrun notarytool submit dist/project_clipboard-macos.dmg \
  --keychain-profile default \
  --wait

xcrun stapler staple dist/project_clipboard-macos.dmg
xcrun stapler validate dist/project_clipboard-macos.dmg
```

## Push README ke GitHub

```bash
git add README.md
git commit -m "docs: add dmg build and deploy guide"
git push origin main
```

Jika branch aktif bukan `main`, sesuaikan target branch pada perintah `git push`.
