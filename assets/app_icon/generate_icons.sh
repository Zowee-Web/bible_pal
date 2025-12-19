#!/bin/bash

################################################################################
# Bible PAL App Icon Generation Script
################################################################################
#
# This script automates the complete app icon generation process.
#
# PREREQUISITES:
#   - app_icon_1024.png must exist in this directory
#   - File must be exactly 1024 × 1024 pixels
#
# USAGE:
#   cd /Volumes/T9-AI/bible_pal
#   bash assets/app_icon/generate_icons.sh
#
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "================================================================================"
echo "  Bible PAL App Icon Generation"
echo "================================================================================"
echo ""

# Check we're in project root
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}❌ Error: Must run from project root${NC}"
    echo "Usage: bash assets/app_icon/generate_icons.sh"
    exit 1
fi

# Check icon file exists
ICON_PATH="assets/app_icon/app_icon_1024.png"
if [ ! -f "$ICON_PATH" ]; then
    echo -e "${RED}❌ Error: Icon file not found${NC}"
    echo ""
    echo "Expected: $ICON_PATH"
    echo ""
    echo "Please copy your icon file:"
    echo "  cp /path/to/PAL_Stories_AppIcon_1024.png $ICON_PATH"
    echo ""
    exit 1
fi

echo -e "${BLUE}📋 Step 1: Verifying icon dimensions...${NC}"
WIDTH=$(sips -g pixelWidth "$ICON_PATH" | awk '/pixelWidth:/ {print $2}')
HEIGHT=$(sips -g pixelHeight "$ICON_PATH" | awk '/pixelHeight:/ {print $2}')

if [ "$WIDTH" != "1024" ] || [ "$HEIGHT" != "1024" ]; then
    echo -e "${RED}❌ Error: Icon must be exactly 1024×1024 pixels${NC}"
    echo "Current size: ${WIDTH}×${HEIGHT}"
    exit 1
fi

echo -e "${GREEN}✅ Icon dimensions verified: 1024×1024${NC}"
echo ""

echo -e "${BLUE}📋 Step 2: Installing dependencies...${NC}"
flutter pub get
echo -e "${GREEN}✅ Dependencies installed${NC}"
echo ""

echo -e "${BLUE}📋 Step 3: Generating platform icons...${NC}"
dart run flutter_launcher_icons
echo -e "${GREEN}✅ Platform icons generated${NC}"
echo ""

echo -e "${BLUE}📋 Step 4: Verifying generated files...${NC}"

# Check iOS
if [ -f "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png" ]; then
    echo -e "${GREEN}✅ iOS icons generated${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: iOS icons may not have generated correctly${NC}"
fi

# Check Android
if [ -f "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" ]; then
    echo -e "${GREEN}✅ Android icons generated${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Android icons may not have generated correctly${NC}"
fi

echo ""
echo "================================================================================"
echo -e "${GREEN}✅ Icon generation complete!${NC}"
echo "================================================================================"
echo ""
echo "Next steps:"
echo "  1. Clean build: flutter clean"
echo "  2. Get dependencies: flutter pub get"
echo "  3. Run app: flutter run"
echo ""
echo "Platform-specific icons generated:"
echo "  • iOS: ios/Runner/Assets.xcassets/AppIcon.appiconset/"
echo "  • Android: android/app/src/main/res/mipmap-*/"
echo ""
echo "================================================================================"
echo ""
