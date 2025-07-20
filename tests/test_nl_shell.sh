#!/bin/bash

# Test battery for nl_shell.sh to ensure functionality after optimization
# This script tests all core features with 1-2 representative tests each
# Usage: ./test_nl_shell.sh [model]
#   model: ollama, gemini, or openai (default: gemini)

set -e  # Exit on any error

# Get model from command line argument or use default
MODEL="${1:-gemini}"

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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Function to print test results
print_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    elif [ "$result" = "SKIP" ]; then
        echo -e "${YELLOW}⏭️  SKIP${NC}: $test_name"
        if [ -n "$details" ]; then
            echo -e "   ${YELLOW}Details:${NC} $details"
        fi
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        if [ -n "$details" ]; then
            echo -e "   ${YELLOW}Details:${NC} $details"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Function to run a test and capture output
run_test() {
    local input="$1"
    local expected_mode="$2"
    local test_name="$3"
    
    echo -e "${BLUE}Testing:${NC} $test_name"
    echo -e "${YELLOW}Input:${NC} '$input'"
    
    # Run the command and capture output
    local output
    output=$(echo "$input" | timeout 30 ./nl_shell.sh "$MODEL" 2>&1)
    local exit_code=$?
    
    # Check if command completed successfully
    if [ $exit_code -eq 124 ]; then
        print_result "$test_name" "FAIL" "Command timed out after 20 seconds"
        return
    elif [ $exit_code -ne 0 ]; then
        print_result "$test_name" "FAIL" "Command failed with exit code $exit_code"
        return
    fi
    
    # Check for API quota/authentication errors
    if echo "$output" | grep -q "exceeded your current quota\|authentication\|API.*error\|invalid.*key"; then
        print_result "$test_name" "SKIP" "API quota exceeded or authentication error - skipping test"
        echo -e "${YELLOW}Output:${NC}"
        echo "$output" | head -5
        echo "---"
        echo
        return
    fi
    
    # Check if expected mode is present in output
    if echo "$output" | grep -q "Mode: $expected_mode"; then
        print_result "$test_name" "PASS"
    else
        print_result "$test_name" "FAIL" "Expected mode '$expected_mode' not found in output"
    fi
    
    echo -e "${YELLOW}Output:${NC}"
    echo "$output" | head -20  # Show first 20 lines of output
    echo "---"
    echo
}

# Function to test direct commands
test_direct_command() {
    local input="$1"
    local test_name="$2"
    
    echo -e "${BLUE}Testing:${NC} $test_name"
    echo -e "${YELLOW}Input:${NC} '$input'"
    
    local output
    output=$(echo "$input" | timeout 30 ./nl_shell.sh "$MODEL" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        print_result "$test_name" "FAIL" "Command timed out"
        return
    elif [ $exit_code -ne 0 ]; then
        print_result "$test_name" "FAIL" "Command failed with exit code $exit_code"
        return
    fi
    
    # Check for API quota/authentication errors
    if echo "$output" | grep -q "exceeded your current quota\|authentication\|API.*error\|invalid.*key"; then
        print_result "$test_name" "SKIP" "API quota exceeded or authentication error - skipping test"
        echo -e "${YELLOW}Output:${NC}"
        echo "$output" | head -5
        echo "---"
        echo
        return
    fi
    
    # For direct commands, check execution indicators
    # For /ask commands, check question answering indicators
    if [[ "$input" == /ask* ]]; then
        if echo "$output" | grep -q "Mode: QUESTION" && echo "$output" | grep -q "Answer:"; then
            print_result "$test_name" "PASS"
        else
            print_result "$test_name" "FAIL" "Direct ask command not working properly"
        fi
    else
        # For /run commands, check command execution indicators
        if echo "$output" | grep -q "Auto-proceeding\|Output:"; then
            print_result "$test_name" "PASS"
        else
            print_result "$test_name" "FAIL" "Direct command execution not detected"
        fi
    fi
    
    echo -e "${YELLOW}Output:${NC}"
    echo "$output" | head -20
    echo "---"
    echo
}

# Function to test system commands
test_system_command() {
    local input="$1"
    local test_name="$2"
    
    echo -e "${BLUE}Testing:${NC} $test_name"
    echo -e "${YELLOW}Input:${NC} '$input'"
    
    local output
    output=$(echo "$input" | timeout 30 ./nl_shell.sh "$MODEL" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        print_result "$test_name" "FAIL" "Command timed out"
        return
    elif [ $exit_code -ne 0 ]; then
        print_result "$test_name" "FAIL" "Command failed"
        return
    fi
    
    # Check for successful execution indicators
    if echo "$output" | grep -q "/clear\|Context cleared\|Exiting"; then
        print_result "$test_name" "PASS"
    else
        print_result "$test_name" "FAIL" "System command not executed properly"
    fi
    
    echo -e "${YELLOW}Output:${NC}"
    echo "$output" | head -20
    echo "---"
    echo
}

echo -e "${BLUE}=== nl_shell.sh Test Battery ===${NC}"
echo -e "${YELLOW}Testing optimized script functionality...${NC}"
echo

# Check if script exists and is executable
if [ ! -f "./nl_shell.sh" ]; then
    echo -e "${RED}Error: nl_shell.sh not found in current directory${NC}"
    exit 1
fi

if [ ! -x "./nl_shell.sh" ]; then
    echo -e "${YELLOW}Making nl_shell.sh executable...${NC}"
    chmod +x ./nl_shell.sh
fi

echo -e "${BLUE}=== 1. Error Handling Tests ===${NC}"
echo -e "${BLUE}Testing:${NC} Empty input handling"

# Test empty input (should be handled gracefully)
# Use a simpler approach to avoid hanging
if echo "" | timeout 10 ./nl_shell.sh "$MODEL" >/dev/null 2>&1; then
    exit_code=0
else
    exit_code=$?
fi

if [ $exit_code -eq 1 ]; then
    print_result "Empty input handling" "PASS"
else
    print_result "Empty input handling" "FAIL" "Empty input exit code was $exit_code, expected 1"
fi

echo "---"
echo

echo -e "${BLUE}=== 2. COMMAND Intent Tests ===${NC}"
run_test "what is the current date?" "COMMAND" "Date command classification"
run_test "show disk usage in current directory" "COMMAND" "Filesystem command classification"
run_test "check system memory usage" "COMMAND" "Memory status classification"
run_test "find all log files in this subtree modified today" "COMMAND" "File search classification"

echo -e "${BLUE}=== 3. QUESTION Intent Tests ===${NC}"
run_test "what is Python?" "QUESTION" "General knowledge question"
run_test "explain file permissions in Linux" "QUESTION" "Technical concept question"
run_test "what are the benefits of containerization?" "QUESTION" "Technology concept question"
run_test "how does HTTP work?" "QUESTION" "Protocol explanation question"
run_test "what is the difference between TCP and UDP?" "QUESTION" "Comparison question"

echo -e "${BLUE}=== 4. RETRIEVE Intent Tests ===${NC}"
run_test "search for latest news about AI" "RETRIEVE" "Web search classification"
run_test "find information about bash scripting best practices" "RETRIEVE" "Information retrieval classification"
run_test "look up documentation for Docker installation" "RETRIEVE" "Documentation lookup classification"
run_test "search for recent updates on Linux kernel" "RETRIEVE" "Technical news search classification"
run_test "search for Python package management tutorials online" "RETRIEVE" "Technical information retrieval"

echo -e "${BLUE}=== 5. ANALYZE Intent Tests ===${NC}"
# Note: ANALYZE tests require context, so we'll test with a simple case
run_test "analyze the current directory structure" "ANALYZE" "Analysis classification"
run_test "analyze disk usage in current directory" "ANALYZE" "Filesystem analysis classification"
run_test "analyze the performance of my server" "ANALYZE" "Performance analysis classification"
run_test "explain the output of this command" "ANALYZE" "Command output analysis"
run_test "analyze system logs for errors" "ANALYZE" "Log analysis classification"
run_test "review this code for potential issues" "ANALYZE" "Code review analysis"
run_test "examine network traffic patterns" "ANALYZE" "Network analysis classification"

echo -e "${BLUE}=== 6. Direct Command Tests ===${NC}"
test_direct_command "/run echo 'test message'" "Direct run command"
test_direct_command "/ask what is the capital of France?" "Direct ask command"

echo -e "${BLUE}=== 7. System Control Tests ===${NC}"
test_system_command "/clear" "Context clear command"

echo -e "${BLUE}=== 8. Non-Interactive Mode Test ===${NC}"
echo -e "${BLUE}Testing:${NC} Non-interactive mode"
echo -e "${YELLOW}Input:${NC} 'list files in current directory'"

output=$(echo "list files in current directory" | timeout 30 ./nl_shell.sh "$MODEL" 2>&1)
exit_code=$?

if [ $exit_code -eq 0 ] && echo "$output" | grep -q "Non-interactive mode detected"; then
    print_result "Non-interactive mode" "PASS"
else
    print_result "Non-interactive mode" "FAIL" "Non-interactive mode not working properly"
fi

echo -e "${YELLOW}Output:${NC}"
echo "$output" | head -20
echo "---"
echo

# Final results
echo
echo -e "${BLUE}=== Test Results Summary ===${NC}"
echo -e "Total Tests: ${YELLOW}$TOTAL_TESTS${NC}"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
echo -e "Skipped: ${YELLOW}$SKIPPED_TESTS${NC}"

# Calculate success rate for completed tests
COMPLETED_TESTS=$((TOTAL_TESTS - SKIPPED_TESTS))
if [ $COMPLETED_TESTS -gt 0 ]; then
    SUCCESS_RATE=$(( (PASSED_TESTS * 100) / COMPLETED_TESTS ))
    echo -e "Success Rate: ${YELLOW}${SUCCESS_RATE}%${NC} (of completed tests)"
fi

echo
if [ $FAILED_TESTS -eq 0 ]; then
    if [ $SKIPPED_TESTS -gt 0 ]; then
        echo -e "${YELLOW}⚠️  All available tests passed, but $SKIPPED_TESTS were skipped due to API issues.${NC}"
        echo -e "${YELLOW} Consider testing with a different model or checking API configuration.${NC}"
    else
        echo -e "${GREEN} All $TOTAL_TESTS tests passed! The script maintains full functionality.${NC}"
    fi
    exit 0
else
    echo -e "${RED}⚠️  $FAILED_TESTS test(s) failed out of $COMPLETED_TESTS completed tests.${NC}"
    echo -e "${YELLOW} Check the failed test outputs above for debugging information.${NC}"
    exit 1
fi
