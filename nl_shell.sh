#!/bin/bash

# Load environment variables from .env file
if [ -f "$(dirname "$0")/.env" ]; then
    set -a  # automatically export all variables
    source "$(dirname "$0")/.env"
    set +a  # stop automatically exporting
else
    echo "Warning: .env file not found. Please copy .env.example to .env and configure your settings."
    echo "Using default values where possible..."
fi

source "$(dirname "$0")/perplexica_client.sh"
source "$(dirname "$0")/brave_search.sh"

# AI minimal bash example that:
# Accepts a natural language instruction from the user.
# Uses an LLM (e.g., OpenAI API, Gemini, or a placeholder) to convert the instruction into a shell command.
# Runs the shell command.
# Feeds the CLI output back to the LLM for an explanation in case of failure.
# TODO: Add a file change mode
# TODO: Add a summarize previous context function that will reduce past tokens
# TODO: Add color/emojis to modes 
# TODO: Add linx MCP to search the web

# Set defaults for variables that might not be in .env
WEB_SEARCH_ENGINE_FUNCTION="${WEB_SEARCH_ENGINE_FUNCTION:-brave_search_function}"
DEBUG_RAW_MESSAGES="${DEBUG_RAW_MESSAGES:-false}"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4.1-mini}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash-preview-05-20}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1}"
LLM_TEMPERATURE="${LLM_TEMPERATURE:-0.7}"
LOGS_DIR="${LOGS_DIR:-logs}"
MAX_LAST_CONTEXT_WORDS="${MAX_LAST_CONTEXT_WORDS:-512}"
TOTAL_TOKENS_USED="${TOTAL_TOKENS_USED:-0}"

# Default LLM model from command line argument or environment variable
LLM_MODEL="${1:-${DEFAULT_LLM_MODEL:-gemini}}"

# Circuit breaker variables
FAILED_CLASSIFICATION_COUNT=0
MAX_FAILED_CLASSIFICATIONS=3

# Validate required API keys based on selected LLM
case "$LLM_MODEL" in
    "openai")
        if [ -z "$OPENAI_API_KEY" ]; then
            echo "Error: OPENAI_API_KEY is required when using OpenAI models."
            echo "Please set it in your .env file."
            exit 1
        fi
        ;;
    "gemini")
        if [ -z "$GEMINI_API_KEY" ]; then
            echo "Error: GEMINI_API_KEY is required when using Gemini models."
            echo "Please set it in your .env file."
            exit 1
        fi
        ;;
    "ollama")
        # Ollama doesn't require API keys, but we can check if the host is reachable
        if ! curl -s "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
            echo "Warning: Cannot connect to Ollama at $OLLAMA_HOST"
            echo "Make sure Ollama is running or update OLLAMA_HOST in your .env file."
        fi
        ;;
esac
# Generate a timestamp for log files
TIMESTAMP=$(date +"%Y%m%d%H%M")
mkdir -p "$LOGS_DIR"
CONTEXT_SAVE_LOCATION="./${LOGS_DIR}/${TIMESTAMP}_nl_shell_context.log"
FULL_CONTEXT_SAVE_LOCATION="./${LOGS_DIR}/${TIMESTAMP}_nl_shell_full_context.log"
LAST_CONTEXT="" # Initialize context for RAG
FULL_CONTEXT="" # Initialize full context for long-term memory (per session)
LAST_INTERACTION="" # Initialize last interaction

# Function to call OpenAI LLM
call_openai_llm() {
  local SYSTEM_MESSAGE="$1"
  local USER_CONTENT="$2"
  local ESCAPED_SYSTEM_MESSAGE=$(echo "$SYSTEM_MESSAGE" | jq -Rs .)
  local ESCAPED_USER_CONTENT=$(echo "$USER_CONTENT" | jq -Rs .)

  local RAW_RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "'"$OPENAI_MODEL"'",
      "temperature": '$LLM_TEMPERATURE',
      "messages": [
        {"role": "system", "content": '"$ESCAPED_SYSTEM_MESSAGE"'},
        {"role": "user", "content": '"$ESCAPED_USER_CONTENT"'}
      ]
    }')
  if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
    echo "OpenAI Raw Response:" >&2
    echo "$RAW_RESPONSE" >&2
  fi
  local PARSED_CONTENT=$(echo "$RAW_RESPONSE" | jq -r '.choices[0].message.content')
  local TOTAL_TOKENS=$(echo "$RAW_RESPONSE" | jq -r '.usage.total_tokens')
  if [ -z "$PARSED_CONTENT" ]; then
    echo "Error: LLM (OpenAI) response was empty or unparseable." >&2
    echo "0" # Return 0 tokens on failure
    return 1 # Indicate failure
  fi
  echo "$PARSED_CONTENT"
  echo "$TOTAL_TOKENS"
}

# Function to call Gemini LLM
call_gemini_llm() {
  local SYSTEM_MESSAGE="$1"
  local USER_CONTENT="$2"
  local ESCAPED_FULL_PROMPT=$(echo -e "${SYSTEM_MESSAGE}\n${USER_CONTENT}" | jq -Rs .)

  local RAW_RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/$GEMINI_MODEL:generateContent?key=$GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "contents": [
        {
          "parts": [
            {"text": '"$ESCAPED_FULL_PROMPT"'}
          ]
        }
      ],
      "generationConfig": {
        "temperature": '$LLM_TEMPERATURE'
      }
    }')
  if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
    echo "Gemini Raw Response:" >&2
    echo "$RAW_RESPONSE" >&2
  fi
  local PARSED_CONTENT=$(echo "$RAW_RESPONSE" | jq -r '.candidates[0].content.parts[0].text')
  local TOTAL_TOKENS=$(echo "$RAW_RESPONSE" | jq -r '.usageMetadata.totalTokenCount // 0') # Use // 0 for robustness
  if [ -z "$PARSED_CONTENT" ]; then
    echo "Error: LLM (Gemini) response was empty or unparseable." >&2
    echo "0" # Return 0 tokens on failure
    return 1 # Indicate failure
  fi
  echo "$PARSED_CONTENT"
  echo "$TOTAL_TOKENS"
}

# Function to call Ollama LLM
call_ollama_llm() {
  local SYSTEM_MESSAGE="$1"
  local USER_CONTENT="$2"
  local ESCAPED_SYSTEM_MESSAGE=$(echo "$SYSTEM_MESSAGE" | jq -Rs .)
  local ESCAPED_USER_CONTENT=$(echo "$USER_CONTENT" | jq -Rs .)

  local RAW_RESPONSE=$(curl -s "$OLLAMA_HOST/api/chat" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "'"$OLLAMA_MODEL"'",
      "messages": [
        {"role": "system", "content": '"$ESCAPED_SYSTEM_MESSAGE"'},
        {"role": "user", "content": '"$ESCAPED_USER_CONTENT"'}
      ],
      "stream": false,
      "options": {
        "temperature": '$LLM_TEMPERATURE'
      }
    }')

  if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
    echo "Ollama Raw Response:" >&2
    echo "$RAW_RESPONSE" >&2
  fi
  local PARSED_CONTENT=$(echo "$RAW_RESPONSE" | jq -r '.message.content' | awk 'NF {last = $0} END {print last}')
  # Ollama API does not directly return token counts in the same way as OpenAI/Gemini
  # For simplicity, we'll return 0 tokens for now or implement a more complex token estimation if needed.
  local TOTAL_TOKENS=0
  if [ -z "$PARSED_CONTENT" ]; then
    echo "Error: LLM (Ollama) response was empty or unparseable." >&2
    echo "0" # Return 0 tokens on failure
    return 1 # Indicate failure
  fi
  echo "$PARSED_CONTENT"
  echo "$TOTAL_TOKENS"
}

# Generic function to call the selected LLM
get_llm_response() {
  local LLM="$1"
  local SYSTEM_MESSAGE="$2"
  local USER_CONTENT="$3"
  local LLM_RAW_OUTPUT="" # Renamed to avoid confusion with PARSED_CONTENT

  case "$LLM" in
    "openai")
      LLM_RAW_OUTPUT=$(call_openai_llm "$SYSTEM_MESSAGE" "$USER_CONTENT")
      ;;
    "gemini")
      LLM_RAW_OUTPUT=$(call_gemini_llm "$SYSTEM_MESSAGE" "$USER_CONTENT")
      ;;
    "ollama")
      LLM_RAW_OUTPUT=$(call_ollama_llm "$SYSTEM_MESSAGE" "$USER_CONTENT")
      ;;
    *)
      echo "Error: Invalid LLM model specified. Use 'openai', 'gemini', or 'ollama'." >&2
      exit 1
      ;;
  esac

  # Extract content (all lines except the last) and tokens (the last line)
  PARSED_CONTENT=$(echo "$LLM_RAW_OUTPUT" | head -n -1) # All lines except the last
  LLM_TOKENS=$(echo "$LLM_RAW_OUTPUT" | tail -n 1)

  echo "$PARSED_CONTENT"
  echo "$LLM_TOKENS"
}

# Function to handle data retrieval (local or web)
handle_retrieve() {
  local NL_INSTRUCTION="$1"
  local LAST_CONTEXT="$2"
  local RETRIEVED_CONTENT=""
  local TOKENS_USED_IN_RETRIEVAL=0

  # Decide between WEB_SEARCH and LOCAL_SEARCH
  local USER_CONTENT_DECISION="$NL_INSTRUCTION"
  if [ -n "$LAST_CONTEXT" ]; then
    USER_CONTENT_DECISION="Previous interaction:\n$LAST_CONTEXT\n\nNew instruction: $NL_INSTRUCTION"
  fi

  LLM_RESPONSE=$(get_llm_response "$LLM_MODEL" "You are a helpful assistant that determines the best way to retrieve data for analysis. Given the user's request, decide if the information needs to be retrieved from from the local shell functions, binaries, filesystem or data ('LOCAL_SEARCH'), or from the internet ('WEB_SEARCH') if not available locally. Reply with only 'WEB_SEARCH' or 'LOCAL_SEARCH'. Consider the previous interaction if provided." "$USER_CONTENT_DECISION")
  RETRIEVAL_TYPE=$(echo "$LLM_RESPONSE" | head -n 1)
  TOKENS_USED_IN_RETRIEVAL=$((TOKENS_USED_IN_RETRIEVAL + $(echo "$LLM_RESPONSE" | tail -n 1)))

  case "$RETRIEVAL_TYPE" in
    "WEB_SEARCH")
      # Use the selected web search engine function
      if [ "$WEB_SEARCH_ENGINE_FUNCTION" == "perplexica_search" ]; then
        RETRIEVED_CONTENT=$("$WEB_SEARCH_ENGINE_FUNCTION" "$NL_INSTRUCTION" "webSearch" | jq -r '.message')
      elif [ "$WEB_SEARCH_ENGINE_FUNCTION" == "brave_search_function" ]; then
        RETRIEVED_CONTENT=$("$WEB_SEARCH_ENGINE_FUNCTION" "$NL_INSTRUCTION" | jq -r '.message')
      else
        echo "Error: Invalid WEB_SEARCH_ENGINE_FUNCTION specified: $WEB_SEARCH_ENGINE_FUNCTION" >&2
        echo "" # Return empty content
        echo "$TOKENS_USED_IN_RETRIEVAL"
        return 1
      fi
      ;;

    "LOCAL_SEARCH")
      local USER_CONTENT_LOCAL_RETRIEVAL="$NL_INSTRUCTION"
      if [ -n "$LAST_CONTEXT" ]; then
        USER_CONTENT_LOCAL_RETRIEVAL="Previous interaction:\n$LAST_CONTEXT\n\nNew instruction (for local data retrieval): $NL_INSTRUCTION"
      fi
      LLM_RESPONSE=$(get_llm_response "$LLM_MODEL" "You are a helpful assistant that converts natural language requests for data retrieval into safe, single-line bash commands to retrieve that data from local files or system. Only reply with the command with no markdown. For example, if asked to 'read test.txt', you might reply 'cat test.txt'. Consider the previous interaction if provided." "$USER_CONTENT_LOCAL_RETRIEVAL")
      COMMAND_LOCAL_RETRIEVAL=$(echo "$LLM_RESPONSE" | head -n 1)
      TOKENS_USED_IN_RETRIEVAL=$((TOKENS_USED_IN_RETRIEVAL + $(echo "$LLM_RESPONSE" | tail -n 1)))

      COMMAND_LOCAL_RETRIEVAL=${COMMAND_LOCAL_RETRIEVAL#\`} # Remove leading backtick
      COMMAND_LOCAL_RETRIEVAL=${COMMAND_LOCAL_RETRIEVAL%\`} # Remove trailing backtick

      if [ -z "$COMMAND_LOCAL_RETRIEVAL" ]; then
        echo "Failed to generate local data retrieval command." >&2
        echo "" # Return empty content
        echo "$TOKENS_USED_IN_RETRIEVAL"
        return 1
      fi

      RETRIEVED_CONTENT=$(eval "$COMMAND_LOCAL_RETRIEVAL" 2>&1 | tee /dev/tty)
      ;;
    *)
      echo "Error: LLM failed to classify retrieval type." >&2
      echo "" # Return empty content
      echo "$TOKENS_USED_IN_RETRIEVAL"
      return 1
      ;;
  esac

  echo "$RETRIEVED_CONTENT"
  echo "---END_CONTENT---"
  echo "$TOKENS_USED_IN_RETRIEVAL"
}

# Function to update LAST_CONTEXT and FULL_CONTEXT
update_context() {
  local current_interaction_content="$1" # This is the content for the new LAST_INTERACTION

  # Trim existing newlines from current_interaction_content
  local trimmed_current_interaction=$(echo "$current_interaction_content" | tr -s '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Assign to the global LAST_INTERACTION variable
  LAST_INTERACTION="$trimmed_current_interaction"

  # Append the LAST_INTERACTION to FULL_CONTEXT
  FULL_CONTEXT="${FULL_CONTEXT}${LAST_INTERACTION}\n"

  # Derive LAST_CONTEXT by taking the last MAX_LAST_CONTEXT_WORDS from the updated FULL_CONTEXT
  # This ensures LAST_CONTEXT is a true rolling window that includes the latest interaction.
  LAST_CONTEXT=$(echo "$FULL_CONTEXT" | tr -s '[:space:]' '\n' | tail -n "$MAX_LAST_CONTEXT_WORDS" | paste -s -d ' ')

  # Save LAST_CONTEXT to the context file (new file per session)
  echo "$LAST_CONTEXT" > "$CONTEXT_SAVE_LOCATION"
  # Save FULL_CONTEXT to the full context file (new file per session)
  echo "$FULL_CONTEXT" > "$FULL_CONTEXT_SAVE_LOCATION"
}


# Function to process a single instruction
process_instruction() {
  local NL_INSTRUCTION="$1"
  
  # Check for exit commands
  if [[ "$NL_INSTRUCTION" == "/bye" || "$NL_INSTRUCTION" == "/quit" || "$NL_INSTRUCTION" == "/q" ]]; then
    echo "Exiting $0..."
    exit 0
  fi

  # Check for clear context command
  if [[ "$NL_INSTRUCTION" == "/clear" ]]; then
    echo "Clearing context..."
    LAST_CONTEXT=""
    FULL_CONTEXT=""
    LAST_INTERACTION=""
    # Clear the context files
    echo "" > "$CONTEXT_SAVE_LOCATION"
    echo "" > "$FULL_CONTEXT_SAVE_LOCATION"
    echo "Context cleared successfully!"
    # Reset circuit breaker
    FAILED_CLASSIFICATION_COUNT=0
    return 0
  fi

  # Check for direct commands and set variables to skip LLM classification
  INTENT=""
  COMMAND=""
  TOKENS_FOR_INTENT=0
  
  if [[ "$NL_INSTRUCTION" =~ ^/run[[:space:]](.+) ]]; then
    INTENT="COMMAND"
    COMMAND="${BASH_REMATCH[1]}"
  elif [[ "$NL_INSTRUCTION" =~ ^/ask[[:space:]](.+) ]]; then
    INTENT="QUESTION"
    NL_INSTRUCTION="${BASH_REMATCH[1]}" # Replace with just the question part
  else
    # 2. Use LLM to classify intent
    LLM_RESPONSE=$(get_llm_response "$LLM_MODEL" "You are an intent classifier for a shell assistant. Classify the user's input as 'COMMAND' (for shell operations), 'RETRIEVE' (for requests to fetch information from local files or the internet), 'ANALYZE' (for requests to analyze/examine/synthesize/evaluate already available data), or 'QUESTION' (for general inquiries). Reply with only 'COMMAND', 'RETRIEVE', 'ANALYZE', or 'QUESTION'." "$NL_INSTRUCTION")
    INTENT=$(echo "$LLM_RESPONSE" | head -n 1)
    TOKENS_FOR_INTENT=$(echo "$LLM_RESPONSE" | tail -n 1)
  fi
  
  TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + TOKENS_FOR_INTENT))

  echo "Mode: $INTENT" # Display the classified mode

  # Circuit breaker: Check if intent classification failed
  if [[ "$INTENT" != "COMMAND" && "$INTENT" != "RETRIEVE" && "$INTENT" != "ANALYZE" && "$INTENT" != "QUESTION" ]]; then
    FAILED_CLASSIFICATION_COUNT=$((FAILED_CLASSIFICATION_COUNT + 1))
    echo "Error: LLM failed to classify intent (attempt $FAILED_CLASSIFICATION_COUNT/$MAX_FAILED_CLASSIFICATIONS). Please try again." >&2
    
    if [[ $FAILED_CLASSIFICATION_COUNT -ge $MAX_FAILED_CLASSIFICATIONS ]]; then
      echo "Too many failed classification attempts. Ending session to prevent infinite loop."
      return 1
    fi
    return 0
  fi

  # Reset circuit breaker on successful classification
  FAILED_CLASSIFICATION_COUNT=0

  case "$INTENT" in
    "COMMAND")
      # Check if COMMAND is already set (from /run command)
      if [ -z "$COMMAND" ]; then
        # Prepare user content with context for command generation
        USER_CONTENT_COMMAND="$NL_INSTRUCTION"
        if [ -n "$LAST_CONTEXT" ]; then
          USER_CONTENT_COMMAND="Previous interaction:\n$LAST_CONTEXT\n\nNew instruction: $NL_INSTRUCTION"
        fi

        # 3. Use LLM to convert instruction to command
        LLM_RESPONSE=$(get_llm_response "$LLM_MODEL" "You are a helpful assistant that converts natural language to safe, single-line bash commands or several commands in the same line. Only reply with the commands with no markdown. Consider the previous interaction if provided." "$USER_CONTENT_COMMAND")
        COMMAND=$(echo "$LLM_RESPONSE" | head -n -1)
        TOKENS_FOR_COMMAND=$(echo "$LLM_RESPONSE" | tail -n 1)
        TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + TOKENS_FOR_COMMAND))

        COMMAND=${COMMAND#\`} # Remove leading backtick
        COMMAND=${COMMAND%\`} # Remove trailing backtick
        if [ -z "$COMMAND" ]; then
          echo "Failed to generate command from LLM. Exiting."
          return 1
        fi
      fi

      echo "Running: $COMMAND"
      
      # Skip confirmation for /run commands or non-interactive mode
      if [ -z "$TOKENS_FOR_COMMAND" ] || [ ! -t 0 ]; then
        # Direct /run command or non-interactive mode - no confirmation needed
        echo "Auto-proceeding"
      else
        # Regular command mode - ask for confirmation
        echo -n "Proceed? (y/n): "
        read CONFIRMATION
        if [ "$CONFIRMATION" != "y" ]; then
          echo "Aborted."
          return 0
        fi
      fi

      # 4. Run the command
      echo "Output:"
      COMMAND_OUTPUT=$(eval "$COMMAND" 2>&1 | tee /dev/tty)
      COMMAND_EXIT_STATUS=$?
      OUTPUT="$COMMAND_OUTPUT"

      # Update context with current interaction details
      update_context "Instruction: '$NL_INSTRUCTION'\nCommand: '$COMMAND'\nOutput: '$OUTPUT'"

      # 5. Use LLM to interpret the output ONLY IF command failed
      if [ "$COMMAND_EXIT_STATUS" -ne 0 ]; then
        echo "Command failed (exit status: $COMMAND_EXIT_STATUS). Getting analysis..."
        # Prepare user content with context for analysis
        USER_CONTENT_ANALYSIS="Previous interaction:\n$LAST_CONTEXT\n\nThe command was: '$COMMAND'\nThe output was: '$OUTPUT'\n\nAnalyze this output and explain the failure concisely."
        LLM_RESPONSE=$(get_llm_response "$LLM_MODEL" "You are a helpful assistant that analyzes the output of bash commands. Given the command and its output, provide a concise summary or explanation, especially if it failed. Consider the previous interaction if provided." "$USER_CONTENT_ANALYSIS")
        ANALYSIS=$(echo "$LLM_RESPONSE" | head -n 1)
        TOKENS_FOR_ANALYSIS=$(echo "$LLM_RESPONSE" | tail -n 1)
        TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + TOKENS_FOR_ANALYSIS))

        if [ -z "$ANALYSIS" ]; then
          echo "Failed to get analysis from LLM."
        else
          echo "Analysis:"
          echo "$ANALYSIS"
        fi
      fi
      ;;
    "RETRIEVE")
      echo "Retrieving data..."
      # Capture stdout, discarding stderr to ensure clean output
      LLM_RESPONSE_RAW=$(handle_retrieve "$NL_INSTRUCTION" "$LAST_CONTEXT" 2>/dev/null)
      
      # Parse the response by splitting on the separator
      if [[ "$LLM_RESPONSE_RAW" == *"---END_CONTENT---"* ]]; then
          # Extract content before the separator
          RETRIEVED_CONTENT=$(echo "$LLM_RESPONSE_RAW" | sed '/---END_CONTENT---/,$d')
          # Extract tokens after the separator
          TOKENS_FOR_RETRIEVAL=$(echo "$LLM_RESPONSE_RAW" | sed -n '/---END_CONTENT---/,$p' | tail -n 1 | tr -d '[:space:]')
      else
          # Fallback if separator not found
          RETRIEVED_CONTENT="$LLM_RESPONSE_RAW"
          TOKENS_FOR_RETRIEVAL=0
      fi


      if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
        echo "DEBUG: Raw LLM_RESPONSE_RAW from handle_retrieve:" >&2
        echo "LLM_RESPONSE_RAW $LLM_RESPONSE_RAW" >&2
        echo "DEBUG: Parsed RETRIEVED_CONTENT (in main loop):" >&2
        echo "RETRIEVED_CONTENT $RETRIEVED_CONTENT" >&2
        echo "DEBUG: Parsed TOKENS_FOR_RETRIEVAL (in main loop):" >&2
        echo "TOKENS_FOR_RETRIEVAL $TOKENS_FOR_RETRIEVAL" >&2
      fi
      TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + TOKENS_FOR_RETRIEVAL))

      if [ -z "$RETRIEVED_CONTENT" ]; then
        echo "Data retrieval failed or returned empty content."
      else
        echo "$RETRIEVED_CONTENT"
        update_context "Instruction: '$NL_INSTRUCTION'\nRetrieved Content: '$RETRIEVED_CONTENT'"

        # Check if the original instruction was a question, and if so, analyze the retrieved content
        # Re-classify the original instruction to see if it was a QUESTION
        LLM_RESPONSE_QUESTION_CHECK=$(get_llm_response "$LLM_MODEL" "You are an intent classifier. Classify the user's input as 'QUESTION' or 'NOT_QUESTION'. Reply with only 'QUESTION' or 'NOT_QUESTION'." "$NL_INSTRUCTION")
        QUESTION_CHECK_INTENT=$(echo "$LLM_RESPONSE_QUESTION_CHECK" | head -n 1)
        TOKENS_FOR_QUESTION_CHECK=$(echo "$LLM_RESPONSE_QUESTION_CHECK" | tail -n 1)
        TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + TOKENS_FOR_QUESTION_CHECK))

        if [ "$QUESTION_CHECK_INTENT" = "QUESTION" ]; then
          echo "Original instruction was a question. Analyzing retrieved data to answer..."
          USER_CONTENT_ANALYSIS="Original question: '$NL_INSTRUCTION'\nRetrieved Content: '$RETRIEVED_CONTENT'\n\nAnalyze the retrieved content to answer the original question concisely."
          if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
            echo "DEBUG: Retrieved content before LLM analysis:" >&2
            echo "$RETRIEVED_CONTENT" >&2
            echo "DEBUG: USER_CONTENT_ANALYSIS sent to LLM:" >&2
            echo "$USER_CONTENT_ANALYSIS" >&2
          fi 
          LLM_RESPONSE_ANALYSIS=$(get_llm_response "$LLM_MODEL" "You are a helpful assistant that analyzes provided data or context to answer a specific question. Given the original question and the retrieved content, provide a concise answer." "$USER_CONTENT_ANALYSIS")
          ANALYSIS_ANSWER=$(echo "$LLM_RESPONSE_ANALYSIS" | head -n 1)
          TOKENS_FOR_ANALYSIS_ANSWER=$(echo "$LLM_RESPONSE_ANALYSIS" | tail -n 1)
          TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + TOKENS_FOR_ANALYSIS_ANSWER))

          if [ -z "$ANALYSIS_ANSWER" ]; then
            echo "Failed to get an analysis/answer from LLM."
          else
            echo "Answer:"
            echo "$ANALYSIS_ANSWER"
          fi
          update_context "Question: '$NL_INSTRUCTION'\nRetrieved Content: '$RETRIEVED_CONTENT'\nAnswer: '$ANALYSIS_ANSWER'"
        fi
      fi
      ;;
    "ANALYZE")
      echo "Analyzing data..."
      # Prepare user content for analysis
      USER_CONTENT_ANALYSIS="$NL_INSTRUCTION"
      if [ -n "$LAST_CONTEXT" ]; then
        USER_CONTENT_ANALYSIS="Previous interaction:\n$LAST_CONTEXT\n\nNew instruction (for analysis): $NL_INSTRUCTION"
      fi

      LLM_RESPONSE=$(get_llm_response "$LLM_MODEL" "You are a helpful assistant that analyzes provided data or context. Given the user's instruction and any previous context, provide a concise summary or insights. Assume the necessary data is already available in the context. Consider the previous interaction if provided." "$USER_CONTENT_ANALYSIS")
      ANALYSIS=$(echo "$LLM_RESPONSE" | head -n -1)
      TOKENS_FOR_ANALYSIS=$(echo "$LLM_RESPONSE" | tail -n 1)
      TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + TOKENS_FOR_ANALYSIS))

      if [ -z "$ANALYSIS" ]; then
        echo "Failed to get analysis from LLM."
      else
        echo "Analysis:"
        echo "$ANALYSIS"
      fi
      # Update context with current interaction details for analysis
      update_context "Instruction: '$NL_INSTRUCTION'\nAnalysis: '$ANALYSIS'"
      ;;
    "QUESTION")
      echo "Answering your question..."
      # Prepare user content with context for question answering
      USER_CONTENT_QUESTION="$NL_INSTRUCTION"
      if [ -n "$LAST_CONTEXT" ]; then
        USER_CONTENT_QUESTION="Previous interaction:\n$LAST_CONTEXT\n\nNew question: $NL_INSTRUCTION"
      fi

      LLM_RESPONSE=$(get_llm_response "$LLM_MODEL" "You are a helpful shell assistant that can both run bash commands and answer general questions. Answer the user's question directly and concisely, keeping in mind your capabilities of running commands in the shell or just responding questions. Consider the previous interaction if provided." "$USER_CONTENT_QUESTION")
      ANSWER=$(echo "$LLM_RESPONSE" | head -n -1)
      TOKENS_FOR_ANSWER=$(echo "$LLM_RESPONSE" | tail -n 1)
      TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + TOKENS_FOR_ANSWER))

      if [ -z "$ANSWER" ]; then
        echo "Failed to get an answer from LLM."
      else
        echo "Answer:"
        echo "$ANSWER"
      fi
      # For questions, the LAST_CONTEXT should reflect the question and answer
      update_context "Question: '$NL_INSTRUCTION'\nAnswer: '$ANSWER'"
      ;;
    *)
      echo "Error: LLM failed to classify intent. Please try again." >&2
      ;;
  esac
  echo # Add a newline for better readability between runs
  return 0
}

# Check if input is being piped or if we're running interactively
if [ -t 0 ]; then
  # Interactive mode - main loop for continuous interaction
  while true; do
    # Calculate words in context
    WORDS_IN_CONTEXT=0
    WORDS_IN_FILE=0 # This will now refer to LAST_CONTEXT file
    WORDS_IN_FULL_FILE=0 # This will now refer to FULL_CONTEXT file
    WORDS_IN_LAST_INTERACTION=0

    if [ -n "$LAST_CONTEXT" ]; then
      WORDS_IN_CONTEXT=$(echo "$LAST_CONTEXT" | wc -w)
    fi
    if [ -f "$CONTEXT_SAVE_LOCATION" ]; then
      WORDS_IN_FILE=$(wc -w < "$CONTEXT_SAVE_LOCATION")
    fi
    if [ -f "$FULL_CONTEXT_SAVE_LOCATION" ]; then
      WORDS_IN_FULL_FILE=$(wc -w < "$FULL_CONTEXT_SAVE_LOCATION")
    fi
    if [ -n "$LAST_INTERACTION" ]; then
      WORDS_IN_LAST_INTERACTION=$(echo "$LAST_INTERACTION" | wc -w)
    fi

    # 1. Get instruction
    echo "Tokens last used: $TOTAL_TOKENS_USED | Context: $WORDS_IN_CONTEXT | File: $WORDS_IN_FILE | Full file: $WORDS_IN_FULL_FILE | Last Interaction: $WORDS_IN_LAST_INTERACTION"
    echo -n "Ask me: "
    
    if read NL_INSTRUCTION; then
      # Skip processing empty input
      if [[ -z "${NL_INSTRUCTION// }" ]]; then
        continue
      fi
      process_instruction "$NL_INSTRUCTION"
    else
      # EOF reached, exit gracefully
      echo
      echo "Exiting $0..."
      exit 0
    fi
  done
else
  # Non-interactive mode - read from stdin and process once
  echo "Non-interactive mode detected. Reading from stdin..."
  
  # Read all input from stdin
  NL_INSTRUCTION=$(cat)
  
  # Skip processing if input is empty
  if [[ -z "${NL_INSTRUCTION// }" ]]; then
    echo "No input provided."
    exit 1
  fi
  
  echo "Processing: $NL_INSTRUCTION"
  process_instruction "$NL_INSTRUCTION"
fi
