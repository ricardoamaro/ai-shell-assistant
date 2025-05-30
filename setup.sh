#!/bin/bash

echo " Shell Assistant Setup"
echo "======================="

# Check if .env already exists
if [ -f ".env" ]; then
    echo "⚠️  .env file already exists. Backing up to .env.backup"
    cp .env .env.backup
fi

# Copy .env.example to .env
echo " Creating .env file from template..."
cp .env.example .env

echo " .env file created successfully!"
echo ""
echo " Next steps:"
echo "1. Edit .env file with your API keys:"
echo "   - Add your OpenAI API key (if using OpenAI)"
echo "   - Add your Gemini API key (if using Gemini)"
echo "   - Configure your preferred models and settings"
echo ""
echo "2. Install dependencies:"
echo "   Ubuntu/Debian: sudo apt-get install jq lynx"
echo "   macOS: brew install jq lynx"
echo ""
echo "3. (Optional) Set up Ollama for local models:"
echo "   curl -fsSL https://ollama.ai/install.sh | sh"
echo "   ollama pull llama3.1"
echo ""
echo "4. Make the script executable:"
echo "   chmod +x nl_shell.sh"
echo ""
echo "5. Run the shell assistant:"
echo "   ./nl_shell.sh"
echo ""
echo " For detailed instructions, see README.md"
echo ""
echo " Configuration completed! Happy shelling!"
