#!/bin/bash
cd "$(dirname "$0")"

if [ -z "$GEMINI_API_KEY" ]; then
    echo "❌ GEMINI_API_KEY is not set."
    echo "   Export it before running this script:"
    echo "       export GEMINI_API_KEY=\"your-key-here\""
    echo "   Get a free key at: https://aistudio.google.com/apikey"
    echo ""
    echo "Press any key to close..."
    read -n 1
    exit 1
fi

echo ""
echo "=== SnipTease Agent Capture Test 2 ==="
echo ""
python3 test_agent_capture.py \
  "the Recents section in the left sidebar, including the Recents heading and the four recent task items listed below it" \
  --preset x-square \
  --input ~/Desktop/"Screenshot 2026-04-07 at 19.49.55.png" \
  --output ~/Desktop/SnipTease_recents_x-square.png
echo ""
echo "Press any key to close..."
read -n 1
