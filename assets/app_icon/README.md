# Bible PAL App Icon

This directory contains the source icon for the Bible PAL app (PAL's Stories).

## Source Icon Requirements

- **Filename**: `app_icon_1024.png`
- **Dimensions**: Exactly 1024 × 1024 pixels
- **Format**: PNG
- **Design**: The approved PAL Stories icon design

## Setup Instructions

### 1. Add the Icon File

Copy your approved `PAL_Stories_AppIcon_1024.png` file into this directory and rename it to `app_icon_1024.png`:

```bash
# From the project root
cp /path/to/PAL_Stories_AppIcon_1024.png assets/app_icon/app_icon_1024.png
```

### 2. Verify the Icon Dimensions

```bash
sips -g pixelWidth -g pixelHeight assets/app_icon/app_icon_1024.png
```

Expected output:
```
pixelWidth: 1024
pixelHeight: 1024
```

### 3. Install Dependencies

```bash
flutter pub get
```

### 4. Generate Platform Icons

This will automatically generate all required icon sizes for iOS and Android:

```bash
dart run flutter_launcher_icons
```

This command will:
- Generate iOS icons in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- Generate Android icons in `android/app/src/main/res/mipmap-*/`
- Remove alpha channel from iOS icons (required by Apple)
- Create adaptive icons for Android

### 5. Verify and Test

```bash
# Clean and rebuild
flutter clean
flutter pub get

# Test on a device or simulator
flutter run
```

## What Gets Generated

### iOS
- Multiple sizes from 20x20 to 1024x1024
- All variants (@1x, @2x, @3x) for different device types
- Alpha channel removed (Apple requirement)
- Located in: `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

### Android
- Mipmap icons for all densities (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)
- Adaptive icon foreground and background
- Located in: `android/app/src/main/res/mipmap-*/`

## Configuration

Icon generation is configured in `pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/app_icon/app_icon_1024.png"
  remove_alpha_ios: true
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "assets/app_icon/app_icon_1024.png"
```

## Troubleshooting

### Icon not updating on device?
1. Run `flutter clean`
2. Regenerate icons: `dart run flutter_launcher_icons`
3. Rebuild: `flutter run`

### Wrong icon showing?
- On iOS: May need to restart Xcode and clean derived data
- On Android: Uninstall the app completely and reinstall

### Build errors?
- Verify icon is exactly 1024x1024: `sips -g all assets/app_icon/app_icon_1024.png`
- Ensure no alpha channel issues
- Check that `flutter pub get` ran successfully

## Notes

- **Do not manually edit** Xcode asset catalogs or Android mipmap folders
- Always regenerate icons using `dart run flutter_launcher_icons`
- Keep the source 1024x1024 PNG for future regeneration
- The icon file is **not** tracked in git (see `.gitignore`)
