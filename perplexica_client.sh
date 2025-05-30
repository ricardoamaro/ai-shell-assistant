#!/bin/bash

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it to use this function."
    echo "e.g., sudo apt-get install jq / sudo yum install jq / brew install jq"
    # exit 1 # Or return 1 if sourced
fi

# --- Perplexica Search Bash Function ---

# Usage:
# perplexica_search "Your query" "focusMode" [options]
#
# Options can be set via environment variables (defaults) or overridden by function arguments.
#
# Required Arguments:
#   1. query (string): Your search query.
#   2. focus_mode (string): One of webSearch, academicSearch, writingAssistant, wolframAlphaSearch, youtubeSearch, redditSearch.
#
# Optional Arguments (can also be set via environment variables):
#   3. chat_model_provider (string, default: $PERPLEXICA_CHAT_PROVIDER or "google")
#   4. chat_model_name (string, default: $PERPLEXICA_CHAT_NAME or "gemini-2.5-flash-preview-05-20")
#   5. embedding_model_provider (string, default: $PERPLEXICA_EMBEDDING_PROVIDER or "google")
#   6. embedding_model_name (string, default: $PERPLEXICA_EMBEDDING_NAME or "text-embedding-004")
#   7. optimization_mode (string, default: $PERPLEXICA_OPTIMIZATION_MODE or "speed")
#   8. system_instructions (string, default: $PERPLEXICA_SYSTEM_INSTRUCTIONS or "")
#   9. stream (boolean, default: $PERPLEXICA_STREAM or "false") - "true" or "false"
#  10. history_json (string, default: $PERPLEXICA_HISTORY or "[]") - JSON string for history
#
# Environment Variables for Defaults:
#   PERPLEXICA_API_URL: Endpoint URL (default: http://localhost:3000/api/search)
#   PERPLEXICA_CHAT_PROVIDER
#   PERPLEXICA_CHAT_NAME
#   PERPLEXICA_EMBEDDING_PROVIDER
#   PERPLEXICA_EMBEDDING_NAME
#   PERPLEXICA_OPTIMIZATION_MODE
#   PERPLEXICA_SYSTEM_INSTRUCTIONS
#   PERPLEXICA_STREAM (set to "true" or "false")
#   PERPLEXICA_HISTORY (JSON string, e.g., '[["human", "Hi"], ["assistant", "Hello"]]')
perplexica_search() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: perplexica_search <query> <focus_mode> [chat_provider] [chat_name] [embedding_provider] [embedding_name] [optimization_mode] [system_instructions] [stream] [history_json]"
        echo "Example: perplexica_search \"What is Perplexica?\" \"webSearch\""
        return 1
    fi

    # Required parameters
    local query="$1"
    local focus_mode="${2:-webSearch}"

    # API URL
    local api_url="${PERPLEXICA_API_URL:-http://localhost:3000/api/search}"

    # Optional parameters from arguments or environment variables
    local chat_model_provider="${3:-${PERPLEXICA_CHAT_PROVIDER:-gemini}}"
    local chat_model_name="${4:-${PERPLEXICA_CHAT_NAME:-gemini-2.0-flash}}"
    #local chat_model_name="${4:-${PERPLEXICA_CHAT_NAME:-qwen3:latest}}"
    local embedding_model_provider="${5:-${PERPLEXICA_EMBEDDING_PROVIDER:-gemini}}"
    local embedding_model_name="${6:-${PERPLEXICA_EMBEDDING_NAME:-models/text-embedding-004}}"
    local optimization_mode="${7:-${PERPLEXICA_OPTIMIZATION_MODE:-speed}}"
    local system_instructions="${8:-${PERPLEXICA_SYSTEM_INSTRUCTIONS:-}}"
    local stream_flag_str="${9:-${PERPLEXICA_STREAM:-false}}" # "true" or "false" as string
    local history_json="${10:-${PERPLEXICA_HISTORY:-[]}}"

    # Convert stream_flag_str to boolean for JSON
    local stream_flag_bool="false"
    if [[ "$stream_flag_str" == "true" ]]; then
        stream_flag_bool="true"
    fi

    # Construct JSON payload using jq
    # Start with mandatory fields
    local payload
    payload=$(jq -n \
        --arg query "$query" \
        --arg focusMode "$focus_mode" \
        --argjson stream "$stream_flag_bool" \
        '{query: $query, focusMode: $focusMode, stream: $stream}')

    # Add optional chatModel
    if [[ -n "$chat_model_provider" && -n "$chat_model_name" ]]; then
        local chat_model_obj
        chat_model_obj=$(jq -n \
            --arg provider "$chat_model_provider" \
            --arg name "$chat_model_name" \
            '{provider: $provider, name: $name}')
        # OpenAI-specific custom URL/Key fields removed
        payload=$(echo "$payload" | jq --argjson cm "$chat_model_obj" '.chatModel = $cm')
    fi

    # Add optional embeddingModel
    if [[ -n "$embedding_model_provider" && -n "$embedding_model_name" ]]; then
        payload=$(echo "$payload" | jq \
            --arg provider "$embedding_model_provider" \
            --arg name "$embedding_model_name" \
            '.embeddingModel = {provider: $provider, name: $name}')
    fi

    # Add optional optimizationMode
    if [[ -n "$optimization_mode" ]]; then
        payload=$(echo "$payload" | jq --arg optimizationMode "$optimization_mode" '.optimizationMode = $optimizationMode')
    fi

    # Add optional systemInstructions
    if [[ -n "$system_instructions" ]]; then
        payload=$(echo "$payload" | jq --arg systemInstructions "$system_instructions" '.systemInstructions = $systemInstructions')
    fi

    # Add optional history (jq needs it as actual JSON, not a string)
    # Validate if history_json is valid JSON before passing to --argjson
    if jq -e . >/dev/null 2>&1 <<<"$history_json"; then
        if [[ "$history_json" != "[]" ]]; then # Only add if not the default empty array string
            payload=$(echo "$payload" | jq --argjson history "$history_json" '.history = $history')
        fi
    else
        if [[ -n "$history_json" && "$history_json" != "[]" ]]; then # if not empty and not default "[]"
            echo "Warning: PERPLEXICA_HISTORY or history_json argument is not valid JSON. Skipping history." >&2
        fi
    fi

    # For debugging the payload:
    # echo "Payload:"
    # echo "$payload" | jq '.'
    # return

    # Make the curl request
    if [[ "$stream_flag_bool" == "true" ]]; then
        # -N disables buffering for streaming
        curl -s -N -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$api_url"
    else
        # Pretty print JSON output if not streaming and jq is available
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$api_url" | jq '.'
    fi
}

# --- End of Perplexica Search Bash Function ---

# To make this function available in your current terminal session:
# source perplexica_client.sh
#
# Example Usages (after sourcing):
#
# 1. Basic search (uses Google Gemini Flash for chat and Google text-embedding-004 for embeddings by default):
# perplexica_search "What is the largest moon of Saturn?" "webSearch"
#
# 2. Override chat model to a different Google model (e.g., gemini-1.5-pro-preview-0514):
# perplexica_search "Summarize the history of AI" "academicSearch" "google" "gemini-1.5-pro-preview-0514"
#
# 3. Explicitly set to OpenAI (though custom URL/Key fields are removed from this script):
# perplexica_search "Explain quantum entanglement for beginners" "academicSearch" "openai" "gpt-4o-mini"
#
# 4. Search with system instructions (default chat and embedding models are Google):
# perplexica_search "Write a short poem about the sea" "writingAssistant" "" "" "" "" "" "Keep it under 50 words and melancholic."
#
# 5. Streaming search (default chat and embedding models are Google):
# perplexica_search "Latest news on AI advancements" "webSearch" "" "" "" "" "" "" "true"
