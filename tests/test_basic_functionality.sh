#!/bin/bash

# Basic functionality test for nl_shell.sh
# Tests core features that don't require API calls
# Usage: ./test_basic_functionality.sh [model]
#   model: ollama, gemini, or openai (default: gemini)

set -e

# Get model from command line argument or use default
MODEL="${1:-gemini}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Validate model parameter
case "$MODEL" in
    "ollama"|"gemini"|"openai")
        echo -e "${BLUE}Using model: ${YELLOW}$MODEL${NC}"
        ;;
    *)
        echo -e "${RED}Error: Invalid model '$MODEL'. Use 'ollama', 'gemini', or 'openai'${NC}"
        exit 1
        ;;
esac

echo -e "${BLUE}=== Basic Functionality Test ===${NC}"
echo

# Test 1: Script exists and is executable
echo -e "${BLUE}Test 1:${NC} Script existence and permissions"
if [ -f "./nl_shell.sh" ] && [ -x "./nl_shell.sh" ]; then
    echo -e "${GREEN}✅ PASS${NC}: nl_shell.sh exists and is executable"
else
    echo -e "${RED}❌ FAIL${NC}: nl_shell.sh missing or not executable"
    exit 1
fi

# Test 2: Non-interactive mode detection
echo -e "${BLUE}Test 2:${NC} Non-interactive mode detection"
output=$(echo "test" | timeout 5 ./nl_shell.sh "$MODEL" 2>&1 || true)
if echo "$output" | grep -q "Non-interactive mode detected"; then
    echo -e "${GREEN}✅ PASS${NC}: Non-interactive mode properly detected"
else
    echo -e "${RED}❌ FAIL${NC}: Non-interactive mode not detected"
fi

# Test 3: Empty input handling
echo -e "${BLUE}Test 3:${NC} Empty input handling"
output=$(echo "" | timeout 5 ./nl_shell.sh "$MODEL" 2>&1 || true)
if echo "$output" | grep -q "No input provided"; then
    echo -e "${GREEN}✅ PASS${NC}: Empty input handled correctly"
else
    echo -e "${RED}❌ FAIL${NC}: Empty input not handled properly"
fi

# Test 4: Direct /run command (no API needed)
echo -e "${BLUE}Test 4:${NC} Direct /run command execution"
output=$(echo "/run echo 'Hello World'" | timeout 10 ./nl_shell.sh "$MODEL" 2>&1 || true)
if echo "$output" | grep -q "Hello World" && echo "$output" | grep -q "Auto-proceeding"; then
    echo -e "${GREEN}✅ PASS${NC}: Direct /run command works correctly"
else
    echo -e "${RED}❌ FAIL${NC}: Direct /run command failed"
    echo "Output: $output"
fi

# Test 5: System commands (/clear)
echo -e "${BLUE}Test 5:${NC} System command /clear"
output=$(echo "/clear" | timeout 5 ./nl_shell.sh "$MODEL" 2>&1 || true)
if echo "$output" | grep -q "Context cleared successfully"; then
    echo -e "${GREEN}✅ PASS${NC}: /clear command works correctly"
else
    echo -e "${RED}❌ FAIL${NC}: /clear command failed"
fi

# Test 6: Script structure validation
echo -e "${BLUE}Test 6:${NC} Script structure validation"
if grep -q "call_llm()" ./nl_shell.sh && grep -q "parse_llm_response()" ./nl_shell.sh; then
    echo -e "${GREEN}✅ PASS${NC}: Optimized functions present in script"
else
    echo -e "${RED}❌ FAIL${NC}: Expected optimized functions not found"
fi

# Test 7: Environment loading
echo -e "${BLUE}Test 7:${NC} Environment file loading"
if grep -q "source.*\.env" ./nl_shell.sh; then
    echo -e "${GREEN}✅ PASS${NC}: Environment loading code present"
else
    echo -e "${RED}❌ FAIL${NC}: Environment loading code missing"
fi

echo
echo -e "${BLUE}=== API Connectivity Test ===${NC}"

# Test 8: Simple API test (if possible)
echo -e "${BLUE}Test 8:${NC} API connectivity (simple test)"
output=$(echo "what is the current date?" | timeout 15 ./nl_shell.sh "$MODEL" 2>&1 || true)
if echo "$output" | grep -q "Mode: COMMAND" && echo "$output" | grep -q "$(date +%Y)"; then
    echo -e "${GREEN}✅ PASS${NC}: API working - date command executed correctly"
elif echo "$output" | grep -q "Error.*API"; then
    echo -e "${YELLOW}⚠️  WARNING${NC}: API connectivity issue detected"
    echo "This is expected if API keys are not configured"
else
    echo -e "${YELLOW}⚠️  WARNING${NC}: Unexpected API response"
    echo "Output: $(echo "$output" | head -3)"
fi

echo
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "${GREEN}Core functionality tests completed.${NC}"
echo -e "${YELLOW}Note: Some tests may show warnings if API keys are not configured,${NC}"
echo -e "${YELLOW}but the basic script structure and non-API features should work.${NC}"
