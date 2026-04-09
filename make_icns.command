#!/bin/bash
# Generate AppIcon.icns from the .iconset directory
cd "$(dirname "$0")"

ICONSET="SnipTease/AppIcon.iconset"
OUTPUT="SnipTease/AppIcon.icns"

if [ ! -d "$ICONSET" ]; then
    echo "ERROR: $ICONSET not found"
    exit 1
fi

echo "Converting .iconset → .icns ..."
iconutil -c icns "$ICONSET" -o "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "✓ Created $OUTPUT ($(du -h "$OUTPUT" | cut -f1) bytes)"
    echo ""
    echo "Now in Xcode:"
    echo "  1. Drag AppIcon.icns into the SnipTease group in the project navigator"
    echo "  2. Make sure 'Copy items if needed' is UNCHECKED (it's already in place)"
    echo "  3. Make sure it's added to the SnipTease target"
    echo "  4. Product → Clean Build Folder (⇧⌘K)"
    echo "  5. Build & run"
else
    echo "ERROR: iconutil failed"
    exit 1
fi
