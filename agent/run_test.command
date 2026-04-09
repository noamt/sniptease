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
echo "=== SnipTease Agent Capture Test ==="
echo ""
python3 test_agent_capture.py "the left sidebar file navigator panel" --preset linkedin-feed
echo ""
echo "Press any key to close..."
read -n 1
