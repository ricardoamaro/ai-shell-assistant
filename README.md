# Shell Assistant

An intelligent command-line interface that combines natural language processing with shell command execution and web search capabilities.

## Features

- **Natural Language to Shell Commands**: Converts plain English instructions into bash commands using LLM APIs
- **Intelligent Intent Classification**: Automatically categorizes user input into four modes:
  - `COMMAND` - Execute shell operations
  - `RETRIEVE` - Fetch information from web or local files
  - `ANALYZE` - Analyze existing data/context
  - `QUESTION` - Answer general inquiries
- **Multi-LLM Support**: Works with OpenAI GPT, Google Gemini, and local Ollama models
- **Web Search Integration**: Two search backends available (Perplexica API and Brave Search)
- **Context Management**: Maintains conversation history and context across interactions
- **Safety Confirmation**: Asks for user approval before executing potentially dangerous commands
- **Token Usage Tracking**: Monitors API usage and costs
- **Session Logging**: Saves interaction history to timestamped log files

## Setup

### 1. Clone and Configure

```bash
git clone <repository-url>
cd shell-assistant
```

### 2. Environment Configuration

Copy the example environment file and configure your settings:

```bash
cp .env.example .env
```

Edit `.env` with your preferred text editor and configure the following:

#### Required API Keys
- **OpenAI**: Get your API key from [OpenAI Platform](https://platform.openai.com/api-keys)
- **Gemini**: Get your API key from [Google AI Studio](https://aistudio.google.com/app/apikey)
- **Ollama**: No API key required, just ensure Ollama is running locally

#### Model Configuration
- Choose your preferred models for each provider
- Adjust temperature (0.0-1.0) for response creativity
- Set your default LLM provider

#### Search Configuration
- Choose between `brave_search_function` or `perplexica_search`
- Configure Perplexica settings if using that search engine

### 3. Dependencies

Ensure you have the required dependencies installed:

```bash
# For JSON processing
sudo apt-get install jq  # Ubuntu/Debian
# or
brew install jq  # macOS

# For web scraping (Brave Search)
sudo apt-get install lynx  # Ubuntu/Debian
# or
brew install lynx  # macOS

# For secure password management (if using pass)
sudo apt-get install pass  # Ubuntu/Debian
# or
brew install pass  # macOS
```

### 4. Ollama Setup (Optional)

If you want to use local models with Ollama:

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Pull a model (e.g., llama3.1)
ollama pull llama3.1

# Start Ollama service
ollama serve
```

## Usage

### Basic Usage

```bash
# Use default LLM (configured in .env)
./nl_shell.sh

# Use specific LLM
./nl_shell.sh openai   # Use OpenAI
./nl_shell.sh gemini   # Use Gemini
./nl_shell.sh ollama   # Use Ollama
```

### Example Interactions

```bash
Ask me: list all files in the current directory
Mode: COMMAND
Running: ls -la
Proceed? (y/n): y

Ask me: what is the weather in New York?
Mode: RETRIEVE
Retrieving data...

Ask me: analyze the log files from yesterday
Mode: ANALYZE
Analyzing data...

Ask me: what is the capital of France?
Mode: QUESTION
Answering your question...
```

### Special Commands

- `/run <command>` - Directly execute a shell command
- `/ask <question>` - Directly ask a question  
- `/bye` or `/quit` or `/q` - Exit the shell assistant
- `/clear` - Clear conversation context and start fresh

### Security and Safety Features

The shell assistant includes comprehensive security measures to protect against command injection and information disclosure while maintaining usability for safe operations.

#### Multi-Layer Security Architecture

1. **Command Classification**: Commands are automatically classified as safe or potentially dangerous
2. **Pattern Detection**: Warns about access to sensitive files and system locations
3. **Injection Detection**: Detects special characters and command injection patterns
4. **Resource Protection**: Implements timeouts to prevent resource exhaustion

#### Safe Commands System

The system automatically executes certain "safe" read-only commands without requiring user confirmation:

**Safe Commands**:
- `date`, `pwd`, `whoami`, `id`, `uptime`, `which`, `uname`
- `ls`: Directory listings
- `cat`, `head`, `tail`, `less`, `more`: File viewing
- `wc`: Word count
- `grep`: Text search (including recursive with -r)
- `df`, `free`: System information  
- `ps`: Process listing
- `echo`: Text output

#### Security Protections

**Dangerous Pattern Detection**:
Commands containing sensitive paths or credential-related terms will prompt for user confirmation:
- System directories: `/etc/shadow`, `/etc/passwd`, `/root`, `/.ssh/`, `/var/log/`
- Device files: `/dev/zero`, `/dev/random`, `/dev/urandom`
- User sensitive paths: `~/.ssh`, `~/.aws`, `~/.config`
- System paths: `/proc/sys`, `/sys/`
- Credential-related terms: "credentials", "password", "secret", "key", "token", "private"
- Certificate files: `.pem`, `.key`, `.crt`, `.p12`

**Special Character Detection**:
Commands with special characters that might indicate command injection will prompt for confirmation:
- Special characters: `$`, `` ` ``, `;`, `|`, `&`, `(`, `)`, `<`, `>`, `{`, `}`

#### Custom Safe Commands

You can add your own safe commands by setting the `SAFE_COMMANDS` environment variable in your `.env` file:

```bash
# Add custom safe commands (comma-separated)
SAFE_COMMANDS=hostname,history,tree,file
```

**Security Note**: Custom safe commands still undergo all security checks. Only add commands you're confident are safe and won't expose sensitive information.

#### Advanced Security Configuration

Configure additional security settings in your `.env` file:

```bash
# Enable strict mode for enhanced security warnings
SAFE_MODE_STRICT=true

# Maximum command length (prevents injection attacks)
MAX_COMMAND_LENGTH=500

# Output limits (prevents resource exhaustion) - REMOVED for better UX
# MAX_OUTPUT_LINES=100
# MAX_OUTPUT_CHARS=10000

# Command execution timeout in seconds
COMMAND_TIMEOUT=60
```

#### Security Best Practices

1. **Review Commands**: Always review suggested commands before execution
2. **Limited Permissions**: Run the assistant with limited user permissions
3. **Network Isolation**: Consider network restrictions for enhanced security
4. **Log Monitoring**: Regularly review log files for suspicious activity
5. **API Key Security**: Keep API keys secure and rotate them regularly
6. **Environment Isolation**: Use in isolated environments for testing dangerous operations

## Configuration Options

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENAI_API_KEY` | OpenAI API key | Required for OpenAI |
| `GEMINI_API_KEY` | Google Gemini API key | Required for Gemini |
| `OLLAMA_HOST` | Ollama server URL | `http://localhost:11434` |
| `DEFAULT_LLM_MODEL` | Default LLM provider | `gemini` |
| `OPENAI_MODEL` | OpenAI model to use | `gpt-4o-mini` |
| `GEMINI_MODEL` | Gemini model to use | `gemini-2.5-flash` |
| `OLLAMA_MODEL` | Ollama model to use | `llama3.1` |
| `LLM_TEMPERATURE` | Response creativity (0.0-1.0) | `0.7` |
| `WEB_SEARCH_ENGINE_FUNCTION` | Search engine | `brave_search_function` |
| `DEBUG_RAW_MESSAGES` | Show raw LLM responses | `false` |
| `LOGS_DIR` | Log files directory | `logs` |
| `MAX_LAST_CONTEXT_WORDS` | Context window size | `512` |
| `SAFE_COMMANDS` | Additional safe commands (comma-separated) | `""` |
| `SAFE_MODE_STRICT` | Enable enhanced security warnings | `true` |
| `MAX_COMMAND_LENGTH` | Maximum allowed command length | `500` |
| `COMMAND_TIMEOUT` | Command execution timeout (seconds) | `60` |

### Recommended Models

#### Ollama (Local/Free)
- **llama3.1**: Strong open-source; excels in reasoning, general chat, and RAG
- **mistral**: High-quality, efficient, robust for chat and summarization
- **qwen3**: Excellent multilingual and general chat, strong context handling
- **deepseek-r1**: Especially strong for code, also good for chat

#### Cloud APIs
- **OpenAI**: `gpt-4o-mini`, `gpt-4o`, `gpt-3.5-turbo`
- **Gemini**: `gemini-2.5-flash`, `gemini-1.5-pro`

## File Structure

```
shell-assistant/
├── nl_shell.sh              # Main shell assistant script
├── perplexica_client.sh     # Perplexica search client
├── brave_search.sh          # Brave search scraper
├── .env                     # Environment configuration (not in git)
├── .env.example             # Environment template
├── .gitignore               # Git ignore rules
├── README.md                # This file
└── logs/                    # Session logs directory
    ├── YYYYMMDDHHMM_nl_shell_context.log
    └── YYYYMMDDHHMM_nl_shell_full_context.log
```

## Security

- The `.env` file is automatically excluded from version control
- API keys are never committed to the repository
- Commands require user confirmation before execution
- All interactions are logged locally for debugging

## Testing

The project includes comprehensive test suites to verify functionality across all supported models.

### Test Scripts

1. **Basic Functionality Tests** (`test_basic_functionality.sh`)
   - Tests core features that don't require API calls
   - Validates script structure and non-interactive mode
   - Quick verification of basic functionality

2. **Full Test Suite** (`test_nl_shell.sh`)
   - Tests all intent classifications (COMMAND, RETRIEVE, ANALYZE, QUESTION)
   - Validates direct commands and system controls
   - Comprehensive functionality testing

3. **All Models Test Runner** (`test_all_models.sh`)
   - Runs both test suites against all supported models
   - Provides summary results across all models

### Running Tests

#### Test a specific model:
```bash
# Basic functionality test
./tests/test_basic_functionality.sh gemini
./tests/test_basic_functionality.sh openai
./tests/test_basic_functionality.sh ollama

# Full test suite
./tests/test_nl_shell.sh gemini
./tests/test_nl_shell.sh openai
./tests/test_nl_shell.sh ollama
```

#### Test all models at once:
```bash
# Run comprehensive tests across all models
./tests/test_all_models.sh
```

#### Default model testing:
```bash
# If no model specified, defaults to gemini
./tests/test_basic_functionality.sh
./tests/test_nl_shell.sh
```

### Test Requirements

- Properly configured `.env` file with API keys
- For Ollama tests: Ollama server running locally
- Internet connection for web search tests
- Sufficient API quota for cloud models

## Troubleshooting

### Common Issues

1. **Missing .env file**
   ```
   Warning: .env file not found. Please copy .env.example to .env and configure your settings.
   ```
   Solution: `cp .env.example .env` and configure your API keys

2. **API Key errors**
   ```
   Error: GEMINI_API_KEY is required when using Gemini models.
   ```
   Solution: Add your API key to the `.env` file

3. **Ollama connection issues**
   ```
   Warning: Cannot connect to Ollama at http://localhost:11434
   ```
   Solution: Start Ollama with `ollama serve`

4. **Missing dependencies**
   ```
   Error: Required dependency 'jq' is not installed.
   ```
   Solution: Install missing dependencies as shown in the setup section

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License
Gnu General Public License v2.0
