#!/usr/bin/env bash

# brave_search.sh
# Search Brave and extract the top snippet and URLs, mimicking Perplexica's approach.
# Dependencies: lynx, jq

# Ensure jq and w3m are installed
for dep in jq w3m; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo >&2 "Error: Required dependency '$dep' is not installed."
        jq -n '{message: null}'
        return 1
    fi
done

# --- Brave Search Bash Function ---

# Usage:
# brave_search_function "Your query"
#
# Required Arguments:
#   1. query (string): Your search query.
brave_search_function() {
    # --- Input Handling ---
    local query="$1"
    if [[ $# -lt 1 ]]; then
        echo "Usage: brave_search_function <query>" >&2
        jq -n '{message: null}'
        return 1
    fi

    # --- URL Encoding ---
    local encoded_query
    encoded_query=$(printf "%s" "$query" | jq -sRr @uri)
    local brave_url="https://search.brave.com/search?q=${encoded_query}&source=web"

    # --- Fetch Plaintext Content with w3m ---
    local w3m_output
    w3m_output=$(w3m -dump "$brave_url")

    echo "DEBUG: First 500 chars from w3m output: ${w3m_output:0:500}" >&2

    if [[ -z "$w3m_output" ]]; then
        echo >&2 "Error: Failed to fetch content from Brave Search for query '$query'."
        jq -n '{message: null}'
        return 1
    fi

    # --- Improved Content Extraction ---
    # Clean up the w3m output and limit the content length
    local cleaned_content
    cleaned_content=$(echo "$w3m_output" | \
        # Remove empty lines and common navigation elements
        sed '/^[[:space:]]*$/d' | \
        sed '/^\[.*\]$/d' | \
        sed '/^Search$/d' | \
        sed '/^Images$/d' | \
        sed '/^Videos$/d' | \
        sed '/^News$/d' | \
        sed '/^Maps$/d' | \
        sed '/^More$/d' | \
        sed '/^Settings$/d' | \
        sed '/^Sign in$/d' | \
        sed '/^Brave Search$/d' | \
        sed '/^Advertisement$/d' | \
        sed '/^Ad$/d' | \
        # Remove leading/trailing whitespace from each line
        sed 's/^[[:space:]]*//' | \
        sed 's/[[:space:]]*$//' | \
        # Convert to single line with spaces
        tr '\n' ' ' | \
        # Normalize multiple spaces to single space
        sed 's/  */ /g' | \
        # Remove leading/trailing whitespace
        sed 's/^[[:space:]]*//' | \
        sed 's/[[:space:]]*$//' | \
        # Limit to first 2500 characters
        cut -c1-2500)
    
    # Try to cut at sentence boundary if we hit the limit
    if [[ ${#cleaned_content} -eq 2500 ]]; then
        # Find the last sentence ending within our limit
        local last_sentence_end=$(echo "$cleaned_content" | grep -o '.*[.!?]' | tail -1)
        if [[ -n "$last_sentence_end" && ${#last_sentence_end} -gt 500 ]]; then
            cleaned_content="$last_sentence_end"
        fi
    fi

    # --- Output JSON ---
    local message_json
    if [[ -z "$cleaned_content" ]]; then
        message_json=null
    else
        message_json=$(printf '%s' "$cleaned_content" | jq -R '.')
    fi

    # Return empty URLs array since we're not extracting them anymore
    jq -n --argjson message "$message_json" --argjson urls "[]" '{message: $message, urls: $urls}'
}

# --- End of Brave Search Bash Function ---

# To make this function available in your current terminal session:
# source brave_search.sh

# Example Usage (after sourcing):
# brave_search_function "What is the capital of France?"
