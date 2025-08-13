#!/bin/bash

echo "🧪 Claude Auth Swift Package Test"
echo "================================="
echo ""

# Run unit tests
echo "📝 Running unit tests..."
if swift test; then
    echo "✅ All tests passed!"
else
    echo "❌ Tests failed"
    exit 1
fi

echo ""
echo "🔐 Running authentication test tool..."
echo "To test the OAuth flow:"
echo ""
echo "1. Run: swift run claude-auth-test"
echo "2. A browser will open to Claude's OAuth page"
echo "3. Click 'Authorize' and copy the code#state string"
echo "4. Paste it back in the terminal"
echo ""
echo "Try it now? (y/n)"
read -r response

if [[ "$response" == "y" ]]; then
    swift run claude-auth-test
fi