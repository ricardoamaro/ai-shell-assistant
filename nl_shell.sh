#!/bin/bash

OPENAI_API_KEY="$(pass secure/OpenAIAcquiaAPI)"   # <-- Put your OpenAI API key here
GEMINI_API_KEY="$(pass secure/GeminiRicardoAPIKEY)" # <-- Put your Gemini API key here

OPENAI_MODEL="gpt-4.1-mini"
GEMINI_MODEL="gemini-2.5-flash-preview-05-20"

# Default LLM model
LLM_MODEL="${1:-"gemini"}" # Default to gemini if no argument provided

# Function to call OpenAI LLM
call_openai_llm() {
  local SYSTEM_MESSAGE="$1"
  local USER_CONTENT="$2"
  local RAW_RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "$OPENAI_MODEL",
      "messages": [
        {"role": "system", "content": "'"$SYSTEM_MESSAGE"'"},
        {"role": "user", "content": "'"$USER_CONTENT"'"}
      ]
    }')
  local PARSED_CONTENT=$(echo "$RAW_RESPONSE" | jq -r '.choices[0].message.content')
  if [ -z "$PARSED_CONTENT" ]; then
    echo "Error: LLM (OpenAI) response was empty or unparseable. Raw response:" >&2
    echo "$RAW_RESPONSE" >&2
    return 1 # Indicate failure
  fi
  echo "$PARSED_CONTENT"
}

# Function to call Gemini LLM
call_gemini_llm() {
  local SYSTEM_MESSAGE="$1"
  local USER_CONTENT="$2"
  local FULL_PROMPT="${SYSTEM_MESSAGE}\n${USER_CONTENT}"

  local RAW_RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/$GEMINI_MODEL:generateContent?key=$GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "contents": [
        {
          "parts": [
            {"text": "'"${FULL_PROMPT}"'"}
          ]
        }
      ]
    }')
  local PARSED_CONTENT=$(echo "$RAW_RESPONSE" | jq -r '.candidates[0].content.parts[0].text')
  if [ -z "$PARSED_CONTENT" ]; then
    echo "Error: LLM (Gemini) response was empty or unparseable. Raw response:" >&2
    echo "$RAW_RESPONSE" >&2
    return 1 # Indicate failure
  fi
  echo "$PARSED_CONTENT"
}

# Generic function to call the selected LLM
get_llm_response() {
  local LLM="$1"
  local SYSTEM_MESSAGE="$2"
  local USER_CONTENT="$3"

  case "$LLM" in
    "openai")
      call_openai_llm "$SYSTEM_MESSAGE" "$USER_CONTENT"
      ;;
    "gemini")
      call_gemini_llm "$SYSTEM_MESSAGE" "$USER_CONTENT"
      ;;
    *)
      echo "Error: Invalid LLM model specified. Use 'openai' or 'gemini'." >&2
      exit 1
      ;;
  esac
}

# 1. Get instruction
echo -n "Ask me: "
read NL_INSTRUCTION

# 2. Use LLM to convert instruction to command
COMMAND=$(get_llm_response "$LLM_MODEL" "You are a helpful assistant that converts natural language to safe, single-line bash commands. Only reply with the command." "$NL_INSTRUCTION")
if [ -z "$COMMAND" ]; then
  echo "Failed to generate command from LLM. Exiting."
  exit 1
fi

echo "Running: $COMMAND"
echo -n "Proceed? (y/n): "
read CONFIRMATION

if [ "$CONFIRMATION" != "y" ]; then
  echo "Aborted."
  exit 0
fi

# 3. Run the command
Output:
OUTPUT=$(eval "$COMMAND" 2>&1 | tee /dev/tty)

# 4. Use LLM to interpret the output
EXPLANATION=$(get_llm_response "$LLM_MODEL" "You are a helpful assistant that explains the output of bash commands in plain English." "$OUTPUT")
if [ -z "$EXPLANATION" ]; then
  echo "Failed to get explanation from LLM. Exiting."
  exit 1
fi

echo "Explanation:"
echo "$EXPLANATION"
