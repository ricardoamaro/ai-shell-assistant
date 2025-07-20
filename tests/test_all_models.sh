#!/bin/bash

# Test runner for all supported models
# This script runs the test suite against ollama, gemini, and openai models

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Models to test
MODELS=("ollama" "gemini" "openai")

# Test scripts to run
BASIC_TEST="./tests/test_basic_functionality.sh"
FULL_TEST="./tests/test_nl_shell.sh"

# Results tracking
declare -A RESULTS

echo -e "${BLUE}=== AI Shell Assistant - Model Test Suite ===${NC}"
echo -e "${YELLOW}Testing all supported models: ${MODELS[*]}${NC}"
echo

# Function to run tests for a specific model
run_model_tests() {
    local model="$1"
    local test_script="$2"
    local test_name="$3"
    
    echo -e "${BLUE}Running $test_name for model: ${YELLOW}$model${NC}"
    echo "----------------------------------------"
    
    if timeout 300 "$test_script" "$model"; then
        RESULTS["${model}_${test_name}"]="PASS"
        echo -e "${GREEN}✅ $test_name passed for $model${NC}"
    else
        RESULTS["${model}_${test_name}"]="FAIL"
        echo -e "${RED}❌ $test_name failed for $model${NC}"
    fi
    
    echo
}

# Run tests for each model
for model in "${MODELS[@]}"; do
    echo -e "${BLUE}=== Testing Model: ${YELLOW}$model${NC} ${BLUE}===${NC}"
    
    # Check if test scripts exist
    if [ ! -f "$BASIC_TEST" ] || [ ! -f "$FULL_TEST" ]; then
        echo -e "${RED}Error: Test scripts not found${NC}"
        exit 1
    fi
    
    # Make sure scripts are executable
    chmod +x "$BASIC_TEST" "$FULL_TEST"
    
    # Run basic functionality tests
    run_model_tests "$model" "$BASIC_TEST" "basic"
    
    # Run full test suite
    run_model_tests "$model" "$FULL_TEST" "full"
    
    echo -e "${BLUE}=== Completed testing for $model ===${NC}"
    echo
done

# Print summary
echo -e "${BLUE}=== Test Results Summary ===${NC}"
echo

for model in "${MODELS[@]}"; do
    echo -e "${YELLOW}Model: $model${NC}"
    
    basic_result="${RESULTS[${model}_basic]}"
    full_result="${RESULTS[${model}_full]}"
    
    if [ "$basic_result" = "PASS" ]; then
        echo -e "  Basic Tests: ${GREEN}✅ PASS${NC}"
    else
        echo -e "  Basic Tests: ${RED}❌ FAIL${NC}"
    fi
    
    if [ "$full_result" = "PASS" ]; then
        echo -e "  Full Tests:  ${GREEN}✅ PASS${NC}"
    else
        echo -e "  Full Tests:  ${RED}❌ FAIL${NC}"
    fi
    
    echo
done

# Calculate overall results
total_tests=0
passed_tests=0

for key in "${!RESULTS[@]}"; do
    total_tests=$((total_tests + 1))
    if [ "${RESULTS[$key]}" = "PASS" ]; then
        passed_tests=$((passed_tests + 1))
    fi
done

echo -e "${BLUE}Overall Results:${NC}"
echo -e "Total Test Suites: ${YELLOW}$total_tests${NC}"
echo -e "Passed: ${GREEN}$passed_tests${NC}"
echo -e "Failed: ${RED}$((total_tests - passed_tests))${NC}"

if [ $passed_tests -eq $total_tests ]; then
    echo -e "${GREEN}🎉 All model tests passed!${NC}"
    exit 0
else
    echo -e "${RED}⚠️  Some model tests failed. Check the output above for details.${NC}"
    exit 1
fi
