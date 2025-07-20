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

# Constants
readonly MAX_FAILED_CLASSIFICATIONS=3
readonly CONTENT_SEPARATOR="---END_CONTENT---"

# Set defaults for variables that might not be in .env
WEB_SEARCH_ENGINE_FUNCTION="${WEB_SEARCH_ENGINE_FUNCTION:-brave_search_function}"
DEBUG_RAW_MESSAGES="${DEBUG_RAW_MESSAGES:-false}"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1}"
LLM_TEMPERATURE="${LLM_TEMPERATURE:-0.7}"
LOGS_DIR="${LOGS_DIR:-logs}"
MAX_LAST_CONTEXT_WORDS="${MAX_LAST_CONTEXT_WORDS:-512}"
TOTAL_TOKENS_USED="${TOTAL_TOKENS_USED:-0}"
SAFE_COMMANDS="${SAFE_COMMANDS:-}"
SAFE_MODE_STRICT="${SAFE_MODE_STRICT:-false}"
MAX_COMMAND_LENGTH="${MAX_COMMAND_LENGTH:-200}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-60}"

# Default LLM model from command line argument or environment variable
LLM_MODEL="${1:-${DEFAULT_LLM_MODEL:-gemini}}"

# Circuit breaker variables
FAILED_CLASSIFICATION_COUNT=0

# Initialize context variables
LAST_CONTEXT=""
FULL_CONTEXT=""
LAST_INTERACTION=""

# Generate timestamp and setup logging
TIMESTAMP=$(date +"%Y%m%d%H%M")
mkdir -p "$LOGS_DIR"
CONTEXT_SAVE_LOCATION="./${LOGS_DIR}/${TIMESTAMP}_nl_shell_context.log"
FULL_CONTEXT_SAVE_LOCATION="./${LOGS_DIR}/${TIMESTAMP}_nl_shell_full_context.log"

# Utility function to escape JSON strings
escape_json() {
    local input="$1"
    printf '%s' "$input" | jq -Rs .
}

# Utility function to extract content and tokens from LLM response
parse_llm_response() {
    local response="$1"
    local content tokens
    
    # Check if response has multiple lines
    if [[ "$response" == *$'\n'* ]]; then
        # Multi-line response: content is all lines except the last, tokens is the last line
        content=$(echo "$response" | head -n -1)
        tokens=$(echo "$response" | tail -n 1)
    else
        # Single line response: assume it's all content, tokens = 0
        content="$response"
        tokens="0"
    fi
    
    printf '%s\n%s\n' "$content" "$tokens"
}

# Unified LLM calling function
call_llm() {
    local provider="$1"
    local system_message="$2"
    local user_content="$3"
    local escaped_system escaped_user raw_response parsed_content total_tokens
    
    escaped_system=$(escape_json "$system_message")
    escaped_user=$(escape_json "$user_content")
    
    case "$provider" in
        "openai")
            raw_response=$(curl -s https://api.openai.com/v1/chat/completions \
                -H "Authorization: Bearer $OPENAI_API_KEY" \
                -H "Content-Type: application/json" \
                -d '{
                    "model": "'"$OPENAI_MODEL"'",
                    "temperature": '$LLM_TEMPERATURE',
                    "messages": [
                        {"role": "system", "content": '"$escaped_system"'},
                        {"role": "user", "content": '"$escaped_user"'}
                    ]
                }')
            
            if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
                echo "OpenAI Raw Response:" >&2
                echo "$raw_response" >&2
            fi
            
            parsed_content=$(echo "$raw_response" | jq -r '.choices[0].message.content // empty')
            total_tokens=$(echo "$raw_response" | jq -r '.usage.total_tokens // 0')
            
            # Check for specific OpenAI API errors
            if [ -z "$parsed_content" ] && echo "$raw_response" | grep -q "exceeded your current quota"; then
                echo "API quota exceeded for OpenAI. Please check your billing details." >&2
                printf 'API_QUOTA_EXCEEDED\n0\n'
                return 1
            fi
            ;;
            
        "gemini")
            local escaped_full_prompt
            escaped_full_prompt=$(escape_json "${system_message}${system_message:+$'\n'}${user_content}")
            
            raw_response=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/$GEMINI_MODEL:generateContent?key=$GEMINI_API_KEY" \
                -H "Content-Type: application/json" \
                -d '{
                    "contents": [{"parts": [{"text": '"$escaped_full_prompt"'}]}],
                    "generationConfig": {"temperature": '$LLM_TEMPERATURE'}
                }')
            
            if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
                echo "Gemini Raw Response:" >&2
                echo "$raw_response" >&2
            fi
            
            parsed_content=$(echo "$raw_response" | jq -r '.candidates[0].content.parts[0].text // empty')
            total_tokens=$(echo "$raw_response" | jq -r '.usageMetadata.totalTokenCount // 0')
            
            # Check for specific Gemini API errors
            if [ -z "$parsed_content" ] && echo "$raw_response" | grep -q "exceeded your current quota"; then
                echo "API quota exceeded for Gemini. Please check your billing details." >&2
                printf 'API_QUOTA_EXCEEDED\n0\n'
                return 1
            fi
            ;;
            
        "ollama")
            raw_response=$(curl -s "$OLLAMA_HOST/api/chat" \
                -H "Content-Type: application/json" \
                -d '{
                    "model": "'"$OLLAMA_MODEL"'",
                    "messages": [
                        {"role": "system", "content": '"$escaped_system"'},
                        {"role": "user", "content": '"$escaped_user"'}
                    ],
                    "stream": false,
                    "options": {"temperature": '$LLM_TEMPERATURE'}
                }')
            
            if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
                echo "Ollama Raw Response:" >&2
                echo "$raw_response" >&2
            fi
            
            parsed_content=$(echo "$raw_response" | jq -r '.message.content // empty' | awk 'NF {last = $0} END {print last}')
            total_tokens=0  # Ollama doesn't provide token counts
            ;;
            
        *)
            echo "Error: Invalid LLM model specified. Use 'openai', 'gemini', or 'ollama'." >&2
            return 1
            ;;
    esac
    
    if [ -z "$parsed_content" ]; then
        echo "Error: LLM ($provider) response was empty or unparseable." >&2
        if [ "$DEBUG_RAW_MESSAGES" = "true" ] || [ -z "$raw_response" ]; then
            echo "Raw response was: '$raw_response'" >&2
        fi
        
        # Check for common API errors
        if echo "$raw_response" | grep -q "error"; then
            local error_message
            error_message=$(echo "$raw_response" | jq -r '.error.message // "Unknown API error"' 2>/dev/null)
            [ -z "$error_message" ] && error_message="Unknown API error"
            echo "API Error: $error_message" >&2
        fi
        
        # Check for authentication issues
        if echo "$raw_response" | grep -qi "unauthorized\|invalid.*key\|authentication"; then
            echo "Authentication failed. Please check your API key configuration." >&2
            case "$provider" in
                "openai")
                    echo "Verify OPENAI_API_KEY in your .env file." >&2
                    ;;
                "gemini")
                    echo "Verify GEMINI_API_KEY in your .env file." >&2
                    ;;
            esac
        fi
        
        printf '0\n'
        return 1
    fi
    
    printf '%s\n%s\n' "$parsed_content" "$total_tokens"
}

# Generic function to get LLM response
get_llm_response() {
    local provider="$1"
    local system_message="$2"
    local user_content="$3"
    
    call_llm "$provider" "$system_message" "$user_content"
}

# Function to handle data retrieval (local or web)
handle_retrieve() {
    local nl_instruction="$1"
    local last_context="$2"
    local retrieved_content=""
    local tokens_used_in_retrieval=0
    local user_content_decision retrieval_response retrieval_type
    
    # Decide between WEB_SEARCH and LOCAL_SEARCH
    user_content_decision="$nl_instruction"
    if [ -n "$last_context" ]; then
        user_content_decision="Previous interaction:${last_context:+$'\n'}$last_context${last_context:+$'\n\n'}New instruction: $nl_instruction"
    fi
    
    retrieval_response=$(get_llm_response "$LLM_MODEL" \
        "You are a helpful assistant that determines the best way to retrieve data for analysis. Given the user's request, decide if the information needs to be retrieved from from the local shell functions, binaries, filesystem or data ('LOCAL_SEARCH'), or from the internet ('WEB_SEARCH') if not available locally. Reply with only 'WEB_SEARCH' or 'LOCAL_SEARCH'. Consider the previous interaction if provided." \
        "$user_content_decision")
    
    local parsed_response
    parsed_response=$(parse_llm_response "$retrieval_response")
    retrieval_type=$(echo "$parsed_response" | sed -n '1p')
    tokens_used_in_retrieval=$(echo "$parsed_response" | sed -n '2p')
    
    case "$retrieval_type" in
        "WEB_SEARCH")
            if [ "$WEB_SEARCH_ENGINE_FUNCTION" == "perplexica_search" ]; then
                retrieved_content=$("$WEB_SEARCH_ENGINE_FUNCTION" "$nl_instruction" "webSearch" | jq -r '.message // empty')
            elif [ "$WEB_SEARCH_ENGINE_FUNCTION" == "brave_search_function" ]; then
                retrieved_content=$("$WEB_SEARCH_ENGINE_FUNCTION" "$nl_instruction" | jq -r '.message // empty')
            else
                echo "Error: Invalid WEB_SEARCH_ENGINE_FUNCTION specified: $WEB_SEARCH_ENGINE_FUNCTION" >&2
                printf '\n%s\n%s\n' "$CONTENT_SEPARATOR" "$tokens_used_in_retrieval"
                return 1
            fi
            ;;
            
        "LOCAL_SEARCH")
            local user_content_local_retrieval command_response command_local_retrieval command_tokens
            
            user_content_local_retrieval="$nl_instruction"
            if [ -n "$last_context" ]; then
                user_content_local_retrieval="Previous interaction:${last_context:+$'\n'}$last_context${last_context:+$'\n\n'}New instruction (for local data retrieval): $nl_instruction"
            fi
            
            command_response=$(get_llm_response "$LLM_MODEL" \
                "You are a helpful assistant that converts natural language requests for data retrieval into safe, single-line bash commands to retrieve that data from local files or system. Only reply with the command with no markdown. For example, if asked to 'read test.txt', you might reply 'cat test.txt'. Consider the previous interaction if provided." \
                "$user_content_local_retrieval")
            
            local parsed_command_response
            parsed_command_response=$(parse_llm_response "$command_response")
            command_local_retrieval=$(echo "$parsed_command_response" | sed -n '1p')
            command_tokens=$(echo "$parsed_command_response" | sed -n '2p')
            tokens_used_in_retrieval=$((tokens_used_in_retrieval + command_tokens))
            
            # Clean command of backticks
            command_local_retrieval="${command_local_retrieval#\`}"
            command_local_retrieval="${command_local_retrieval%\`}"
            
            if [ -z "$command_local_retrieval" ]; then
                echo "Failed to generate local data retrieval command." >&2
                printf '\n%s\n%s\n' "$CONTENT_SEPARATOR" "$tokens_used_in_retrieval"
                return 1
            fi
            
            retrieved_content=$(eval "$command_local_retrieval" 2>&1)
            echo "$retrieved_content"
            ;;
            
        *)
            echo "Error: LLM failed to classify retrieval type." >&2
            printf '\n%s\n%s\n' "$CONTENT_SEPARATOR" "$tokens_used_in_retrieval"
            return 1
            ;;
    esac
    
    printf '%s\n%s\n%s\n' "$retrieved_content" "$CONTENT_SEPARATOR" "$tokens_used_in_retrieval"
}

# Function to update context efficiently
update_context() {
    local current_interaction_content="$1"
    
    # Trim and normalize whitespace in one operation
    LAST_INTERACTION=$(echo "$current_interaction_content" | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Append to full context
    FULL_CONTEXT="${FULL_CONTEXT}${LAST_INTERACTION}${LAST_INTERACTION:+$'\n'}"
    
    # Derive rolling window context more efficiently
    LAST_CONTEXT=$(printf '%s' "$FULL_CONTEXT" | tr -s '[:space:]' '\n' | tail -n "$MAX_LAST_CONTEXT_WORDS" | paste -s -d ' ')
    
    # Save contexts to files
    printf '%s' "$LAST_CONTEXT" > "$CONTEXT_SAVE_LOCATION"
    printf '%s' "$FULL_CONTEXT" > "$FULL_CONTEXT_SAVE_LOCATION"
}

# Function to validate API configuration
validate_api_config() {
    case "$LLM_MODEL" in
        "openai")
            if [ -z "$OPENAI_API_KEY" ]; then
                echo "Error: OPENAI_API_KEY is required when using OpenAI models."
                echo "Please set it in your .env file."
                exit 1
            fi
            # Test if API key looks valid (basic format check)
            if [[ ! "$OPENAI_API_KEY" =~ ^sk-[a-zA-Z0-9_-]{20,}$ ]]; then
                echo "Warning: OPENAI_API_KEY format appears invalid."
                echo "OpenAI API keys should start with 'sk-' followed by alphanumeric characters."
            fi
            ;;
        "gemini")
            if [ -z "$GEMINI_API_KEY" ]; then
                echo "Error: GEMINI_API_KEY is required when using Gemini models."
                echo "Please set it in your .env file."
                exit 1
            fi
            # Test if API key looks valid (basic format check)
            if [[ ! "$GEMINI_API_KEY" =~ ^[a-zA-Z0-9_-]{20,}$ ]]; then
                echo "Warning: GEMINI_API_KEY format appears invalid."
                echo "Gemini API keys should be alphanumeric strings of 20+ characters."
            fi
            ;;
        "ollama")
            if ! curl -s "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
                echo "Warning: Cannot connect to Ollama at $OLLAMA_HOST"
                echo "Make sure Ollama is running or update OLLAMA_HOST in your .env file."
            fi
            ;;
    esac
}

# Function to check if a command is safe (doesn't require confirmation)
is_safe_command() {
    local command="$1"
    local base_command full_args
    
    # Extract base command and full arguments
    base_command=$(echo "$command" | awk '{print $1}')
    full_args="$command"
    
    # Security check: Command length limit
    if [ ${#full_args} -gt ${MAX_COMMAND_LENGTH} ]; then
        return 1  # Command too long, potentially dangerous
    fi
    
    # Security check: Dangerous patterns and paths (these should prompt user, not auto-block)
    local dangerous_patterns=(
        "/etc/shadow"
        "/etc/passwd"
        "/root"
        "/.ssh/"
        "/var/log/"
        "/dev/zero"
        "/dev/random"
        "/dev/urandom"
        "~/.ssh"
        "~/.aws"
        "~/.config"
        "/proc/sys"
        "/sys/"
        "credentials"
        "password"
        "secret"
        "key"
        "token"
        "private"
        ".pem"
        ".key"
        ".crt"
        ".p12"
    )
    
    # Check for dangerous patterns in the full command (case-insensitive)
    # Instead of blocking, we'll let these go to user confirmation
    for pattern in "${dangerous_patterns[@]}"; do
        if [[ "${full_args,,}" == *"${pattern,,}"* ]]; then
            return 1  # Contains dangerous pattern - will prompt user
        fi
    done
    
    # Check for special characters that might indicate injection
    # Instead of auto-blocking, let user decide
    if [[ "$full_args" =~ [\$\`\;\|\&\(\)\<\>\{\}] ]]; then
        return 1  # Contains potential injection characters - will prompt user
    fi
    
    # Safe commands (no restrictions)
    local safe_commands=(
        "date"
        "pwd"
        "whoami"
        "id"
        "uptime"
        "which"
        "uname"
        "ls"
        "cat"
        "head"
        "tail"
        "less"
        "more"
        "grep"
        "wc"
        "echo"
        "df"
        "free"
        "ps"
    )
    
    # Check safe commands first
    for safe_cmd in "${safe_commands[@]}"; do
        if [[ "$base_command" == "$safe_cmd" ]]; then
            return 0  # Safe
        fi
    done
    
    # Check user-defined safe commands
    if [ -n "$SAFE_COMMANDS" ]; then
        # Convert comma-separated string to array
        IFS=',' read -ra user_safe_commands <<< "$SAFE_COMMANDS"
        for cmd in "${user_safe_commands[@]}"; do
            # Trim whitespace
            cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$cmd" ] && [[ "$base_command" == "$cmd" ]]; then
                return 0
            fi
        done
    fi
    
    return 1  # Not safe by default
}

# Function to handle command execution
execute_command() {
    local command="$1"
    local nl_instruction="$2"
    local skip_confirmation="$3"
    local command_output command_exit_status
    
    echo "Running: $command"
    
    # Enhanced security check for safe commands
    local is_safe_cmd=false
    if is_safe_command "$command"; then
        is_safe_cmd=true
    fi
    
    # Skip confirmation for /run commands, non-interactive mode, or safe commands
    if [ "$skip_confirmation" = "true" ] || [ ! -t 0 ] || [ "$is_safe_cmd" = "true" ]; then
        if [ "$is_safe_cmd" = "true" ]; then
            echo "Auto-proceeding (safe command)"
        else
            echo "Auto-proceeding"
        fi
    else
        # For potentially unsafe commands, show more context
        if [ "$SAFE_MODE_STRICT" = "true" ]; then
            echo "WARNING: This command may modify your system or access sensitive data."
            echo "Command: $command"
        fi
        echo -n "Proceed? (y/n): "
        read CONFIRMATION
        if [ "$CONFIRMATION" != "y" ]; then
            echo "Aborted."
            return 0
        fi
    fi
    
    echo "Output:"
    
    # Execute command with timeout if configured, preserving colors and formatting
    if [ -n "$COMMAND_TIMEOUT" ] && [ "$COMMAND_TIMEOUT" -gt 0 ]; then
        timeout "${COMMAND_TIMEOUT}s" bash -c "$command"
        command_exit_status=$?
        
        # Capture output for context (without colors for LLM processing)
        command_output=$(timeout "${COMMAND_TIMEOUT}s" bash -c "$command" 2>&1)
        
        # Check if command was killed by timeout
        if [ $command_exit_status -eq 124 ]; then
            echo "[COMMAND TIMEOUT: Execution exceeded ${COMMAND_TIMEOUT} seconds]"
            command_output="$command_output\n[COMMAND TIMEOUT: Execution exceeded ${COMMAND_TIMEOUT} seconds]"
        fi
    else
        eval "$command"
        command_exit_status=$?
        
        # Capture output for context
        command_output=$(eval "$command" 2>&1)
    fi
    
    # Update context with original output
    update_context "Instruction: '$nl_instruction'${nl_instruction:+$'\n'}Command: '$command'${command:+$'\n'}Output: '$command_output'"
    
    # Analyze output only if command failed
    if [ "$command_exit_status" -ne 0 ]; then
        echo "Command failed (exit status: $command_exit_status). Getting analysis..."
        analyze_command_failure "$command" "$command_output"
    fi
}

# Function to analyze command failures
analyze_command_failure() {
    local command="$1"
    local output="$2"
    local user_content_analysis analysis_response parsed_analysis analysis tokens_for_analysis
    
    user_content_analysis="Previous interaction:${LAST_CONTEXT:+$'\n'}$LAST_CONTEXT${LAST_CONTEXT:+$'\n\n'}The command was: '$command'${command:+$'\n'}The output was: '$output'${output:+$'\n\n'}Analyze this output and explain the failure concisely."
    
    analysis_response=$(get_llm_response "$LLM_MODEL" \
        "You are a helpful assistant that analyzes the output of bash commands. Given the command and its output, provide a concise summary or explanation, especially if it failed. Consider the previous interaction if provided." \
        "$user_content_analysis")
    
    parsed_analysis=$(parse_llm_response "$analysis_response")
    analysis=$(echo "$parsed_analysis" | sed -n '1p')
    tokens_for_analysis=$(echo "$parsed_analysis" | sed -n '2p')
    TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + tokens_for_analysis))
    
    if [ -n "$analysis" ]; then
        echo "Analysis:"
        printf "%s\n" "$analysis"
    else
        echo "Failed to get analysis from LLM."
    fi
}

# Function to handle questions and analysis
handle_question_or_analysis() {
    local intent="$1"
    local nl_instruction="$2"
    local system_prompt user_content response_label
    
    case "$intent" in
        "ANALYZE")
            echo "Analyzing data..."
            system_prompt="You are a helpful assistant that analyzes provided data or context. Given the user's instruction and any previous context, provide a concise summary or insights. Assume the necessary data is already available in the context. Consider the previous interaction if provided."
            response_label="Analysis"
            ;;
        "QUESTION")
            echo "Answering your question..."
            system_prompt="You are a helpful shell assistant that can both run bash commands and answer general questions. Answer the user's question directly and concisely, keeping in mind your capabilities of running commands in the shell or just responding questions. Consider the previous interaction if provided."
            response_label="Answer"
            ;;
    esac
    
    user_content="$nl_instruction"
    if [ -n "$LAST_CONTEXT" ]; then
        user_content="Previous interaction:${LAST_CONTEXT:+$'\n'}$LAST_CONTEXT${LAST_CONTEXT:+$'\n\n'}New ${intent,,}: $nl_instruction"
    fi
    
    local llm_response parsed_response answer tokens_for_answer
    llm_response=$(get_llm_response "$LLM_MODEL" "$system_prompt" "$user_content")
    parsed_response=$(parse_llm_response "$llm_response")
    answer=$(echo "$parsed_response" | sed -n '1p')
    tokens_for_answer=$(echo "$parsed_response" | sed -n '2p')
    TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + tokens_for_answer))
    
    if [ -n "$answer" ]; then
        echo "$response_label:"
        printf "%s\n" "$answer"
    else
        echo "Failed to get $response_label from LLM."
    fi
    
    # Update context
    update_context "${intent^}: '$nl_instruction'${nl_instruction:+$'\n'}$response_label: '$answer'"
}

# Function to process a single instruction
process_instruction() {
    local nl_instruction="$1"
    
    # Check for exit commands
    case "$nl_instruction" in
        "/bye"|"/quit"|"/q")
            echo "Exiting $0..."
            exit 0
            ;;
        "/clear")
            echo "Clearing context..."
            LAST_CONTEXT=""
            FULL_CONTEXT=""
            LAST_INTERACTION=""
            printf '' > "$CONTEXT_SAVE_LOCATION"
            printf '' > "$FULL_CONTEXT_SAVE_LOCATION"
            echo "Context cleared successfully!"
            FAILED_CLASSIFICATION_COUNT=0
            return 0
            ;;
    esac
    
    # Check for direct commands and set variables to skip LLM classification
    local intent="" command="" tokens_for_intent=0 skip_confirmation="false"
    
    if [[ "$nl_instruction" =~ ^/run[[:space:]](.+) ]]; then
        intent="COMMAND"
        command="${BASH_REMATCH[1]}"
        skip_confirmation="true"
    elif [[ "$nl_instruction" =~ ^/ask[[:space:]](.+) ]]; then
        intent="QUESTION"
        nl_instruction="${BASH_REMATCH[1]}"
    else
        # Use LLM to classify intent
        local intent_response parsed_intent_response
        intent_response=$(get_llm_response "$LLM_MODEL" \
            "You are an intent classifier for a shell assistant. Classify the user's input as:
- 'COMMAND': Shell operations, system information requests that require executing commands to get current/live data (date, time, disk space, processes, file operations)
- 'RETRIEVE': Requests to fetch information from local files or the internet (e.g., web search, file content retrieval)  
- 'ANALYZE': Requests to analyze/examine/synthesize/evaluate/summarize data that is already available or will be retrieved. Keywords: 'analyze', 'examine', 'review', 'summarize', 'evaluate'
- 'QUESTION': General knowledge questions that can be answered without system access or command execution

Examples:
- 'what is the current date or time?' → COMMAND (needs 'date' command for current info)
- 'list files' → COMMAND (needs 'ls' command)
- 'analyze the current directory structure' → ANALYZE (analyzing/examining data)
- 'what is Python?' → QUESTION (general knowledge)
- 'search for news about AI' → RETRIEVE (needs web search)

Reply with only 'COMMAND', 'RETRIEVE', 'ANALYZE', or 'QUESTION'." \
            "$nl_instruction")
        
        parsed_intent_response=$(parse_llm_response "$intent_response")
        intent=$(echo "$parsed_intent_response" | sed -n '1p')
        tokens_for_intent=$(echo "$parsed_intent_response" | sed -n '2p')
    fi
    
    TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + tokens_for_intent))
    echo "Mode: $intent"
    
    # Circuit breaker: Check if intent classification failed
    case "$intent" in
        "COMMAND"|"RETRIEVE"|"ANALYZE"|"QUESTION")
            FAILED_CLASSIFICATION_COUNT=0  # Reset on success
            ;;
        "API_QUOTA_EXCEEDED")
            echo "API quota exceeded. Cannot continue processing requests." >&2
            return 1
            ;;
        *)
            FAILED_CLASSIFICATION_COUNT=$((FAILED_CLASSIFICATION_COUNT + 1))
            echo "Error: LLM failed to classify intent (attempt $FAILED_CLASSIFICATION_COUNT/$MAX_FAILED_CLASSIFICATIONS). Please try again." >&2
            
            if [[ $FAILED_CLASSIFICATION_COUNT -ge $MAX_FAILED_CLASSIFICATIONS ]]; then
                echo "Too many failed classification attempts. Ending session to prevent infinite loop."
                return 1
            fi
            return 0
            ;;
    esac
    
    case "$intent" in
        "COMMAND")
            # Generate command if not already set
            if [ -z "$command" ]; then
                local user_content_command command_response parsed_command_response tokens_for_command
                
                user_content_command="$nl_instruction"
                if [ -n "$LAST_CONTEXT" ]; then
                    user_content_command="Previous interaction:${LAST_CONTEXT:+$'\n'}$LAST_CONTEXT${LAST_CONTEXT:+$'\n\n'}New instruction: $nl_instruction"
                fi
                
                command_response=$(get_llm_response "$LLM_MODEL" \
                    "You are a helpful assistant that converts natural language to safe, single-line bash commands or several commands in the same line. Only reply with the commands with no markdown. Consider the previous interaction if provided." \
                    "$user_content_command")
                
                parsed_command_response=$(parse_llm_response "$command_response")
                command=$(echo "$parsed_command_response" | sed -n '1p')
                tokens_for_command=$(echo "$parsed_command_response" | sed -n '2p')
                TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + tokens_for_command))
                
                # Clean command of backticks
                command="${command#\`}"
                command="${command%\`}"
                
                if [ -z "$command" ]; then
                    echo "Failed to generate command from LLM. Exiting."
                    return 1
                fi
            fi
            
            execute_command "$command" "$nl_instruction" "$skip_confirmation"
            ;;
            
        "RETRIEVE")
            echo "Retrieving data..."
            local llm_response_raw retrieved_content tokens_for_retrieval
            
            llm_response_raw=$(handle_retrieve "$nl_instruction" "$LAST_CONTEXT" 2>/dev/null)
            
            # Parse the response by splitting on the separator
            if [[ "$llm_response_raw" == *"$CONTENT_SEPARATOR"* ]]; then
                retrieved_content="${llm_response_raw%$CONTENT_SEPARATOR*}"
                tokens_for_retrieval="${llm_response_raw##*$CONTENT_SEPARATOR}"
                tokens_for_retrieval="${tokens_for_retrieval//[[:space:]]/}"
            else
                retrieved_content="$llm_response_raw"
                tokens_for_retrieval=0
            fi
            
            if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
                echo "DEBUG: Raw LLM_RESPONSE_RAW from handle_retrieve:" >&2
                echo "LLM_RESPONSE_RAW $llm_response_raw" >&2
                echo "DEBUG: Parsed RETRIEVED_CONTENT (in main loop):" >&2
                echo "RETRIEVED_CONTENT $retrieved_content" >&2
                echo "DEBUG: Parsed TOKENS_FOR_RETRIEVAL (in main loop):" >&2
                echo "TOKENS_FOR_RETRIEVAL $tokens_for_retrieval" >&2
            fi
            
            TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + tokens_for_retrieval))
            
            if [ -z "$retrieved_content" ]; then
                echo "Data retrieval failed or returned empty content."
            else
                # Always analyze retrieved content to provide useful summary
                echo "Analyzing retrieved data..."
                local user_content_analysis analysis_response parsed_analysis_response analysis_summary tokens_for_analysis_summary
                
                user_content_analysis="Original request: '$nl_instruction'${nl_instruction:+$'\n'}Retrieved Content: '$retrieved_content'${retrieved_content:+$'\n\n'}Analyze and summarize the retrieved content to provide a useful response to the original request. Focus on the key information that addresses what the user was looking for."
                
                if [ "$DEBUG_RAW_MESSAGES" = "true" ]; then
                    echo "DEBUG: Retrieved content before LLM analysis:" >&2
                    echo "$retrieved_content" >&2
                    echo "DEBUG: USER_CONTENT_ANALYSIS sent to LLM:" >&2
                    echo "$user_content_analysis" >&2
                fi
                
                analysis_response=$(get_llm_response "$LLM_MODEL" \
                    "You are a helpful assistant that analyzes retrieved data to provide useful summaries. Given the user's original request and the retrieved content, provide a clear, concise summary that addresses what the user was looking for. Extract the key information and present it in an organized, readable format." \
                    "$user_content_analysis")
                
                parsed_analysis_response=$(parse_llm_response "$analysis_response")
                analysis_summary=$(echo "$parsed_analysis_response" | head -n -1)
                tokens_for_analysis_summary=$(echo "$parsed_analysis_response" | tail -n 1)
                TOTAL_TOKENS_USED=$((TOTAL_TOKENS_USED + tokens_for_analysis_summary))
                
                if [ -n "$analysis_summary" ]; then
                    echo "Summary:"
                    printf "%s\n" "$analysis_summary"
                else
                    echo "Failed to analyze retrieved content. Showing raw data:"
                    printf "%s\n" "$retrieved_content"
                fi
                
                update_context "Request: '$nl_instruction'${nl_instruction:+$'\n'}Retrieved Content: '$retrieved_content'${retrieved_content:+$'\n'}Summary: '$analysis_summary'"
            fi
            ;;
            
        "ANALYZE"|"QUESTION")
            handle_question_or_analysis "$intent" "$nl_instruction"
            ;;
    esac
    
    echo  # Add newline for readability
    return 0
}

# Function to calculate and display context statistics
display_context_stats() {
    local words_in_context=0 words_in_file=0 words_in_full_file=0 words_in_last_interaction=0
    
    [ -n "$LAST_CONTEXT" ] && words_in_context=$(echo "$LAST_CONTEXT" | wc -w)
    [ -f "$CONTEXT_SAVE_LOCATION" ] && words_in_file=$(wc -w < "$CONTEXT_SAVE_LOCATION")
    [ -f "$FULL_CONTEXT_SAVE_LOCATION" ] && words_in_full_file=$(wc -w < "$FULL_CONTEXT_SAVE_LOCATION")
    [ -n "$LAST_INTERACTION" ] && words_in_last_interaction=$(echo "$LAST_INTERACTION" | wc -w)
    
    echo "Tokens last used: $TOTAL_TOKENS_USED | Context: $words_in_context | File: $words_in_file | Full file: $words_in_full_file | Last Interaction: $words_in_last_interaction"
}

# Main execution logic
main() {
    # Validate API configuration
    validate_api_config
    
    # Check if input is being piped or if we're running interactively
    if [ -t 0 ]; then
        # Interactive mode - main loop for continuous interaction
        while true; do
            display_context_stats
            echo -n "Ask me: "
            
            if read NL_INSTRUCTION; then
                # Skip processing empty input
                [[ -z "${NL_INSTRUCTION// }" ]] && continue
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
}

# Run main function
main "$@"
