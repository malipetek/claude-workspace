#!/bin/bash

# Auth Check Script for AI CLIs
# Usage: ./check-auth.sh <ai_name>
# Returns: 0 if authenticated, 1 if auth required, 2 if CLI not found

AI_NAME=$1

check_gemini() {
    # Check if gemini CLI exists
    if ! command -v gemini &> /dev/null; then
        echo "ERROR: gemini CLI not found"
        echo "Install with: npm install -g @anthropic/gemini-cli or similar"
        return 2
    fi

    # Try a simple command to check auth status
    # Capture stderr to detect login prompts
    OUTPUT=$(echo "echo test" | timeout 10 gemini 2>&1)

    # Check for common auth-required patterns
    if echo "$OUTPUT" | grep -qi "login\|authenticate\|sign in\|authorization\|credentials\|token expired\|unauthorized"; then
        echo "AUTH_REQUIRED: Gemini CLI needs authentication"
        echo "Run 'gemini' manually in terminal to complete login"
        return 1
    fi

    echo "OK: Gemini CLI authenticated"
    return 0
}

check_zai() {
    # Check if opencode CLI exists
    if ! command -v opencode &> /dev/null; then
        echo "ERROR: opencode CLI not found"
        return 2
    fi

    # Try a simple command to check auth status
    OUTPUT=$(echo "echo test" | timeout 10 opencode 2>&1)

    # Check for common auth-required patterns
    if echo "$OUTPUT" | grep -qi "login\|authenticate\|sign in\|authorization\|credentials\|token expired\|unauthorized\|api key"; then
        echo "AUTH_REQUIRED: Z.ai (opencode) CLI needs authentication"
        echo "Run 'opencode' manually in terminal to complete login"
        return 1
    fi

    echo "OK: Z.ai (opencode) CLI authenticated"
    return 0
}

case $AI_NAME in
    gemini)
        check_gemini
        exit $?
        ;;
    zai)
        check_zai
        exit $?
        ;;
    all)
        echo "=== Checking all AI CLIs ==="
        echo ""
        echo "Gemini:"
        check_gemini
        GEMINI_STATUS=$?
        echo ""
        echo "Z.ai (opencode):"
        check_zai
        ZAI_STATUS=$?
        echo ""

        if [ $GEMINI_STATUS -ne 0 ] || [ $ZAI_STATUS -ne 0 ]; then
            echo "=== Some CLIs need attention ==="
            exit 1
        fi
        echo "=== All CLIs ready ==="
        exit 0
        ;;
    *)
        echo "Usage: ./check-auth.sh <gemini|zai|all>"
        exit 1
        ;;
esac
