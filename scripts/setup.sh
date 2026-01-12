#!/bin/bash
set -e

echo "========================================"
echo "Envoy Proxy Chain Setup Script"
echo "========================================"
echo ""

# Check if llm-as-judge-proxy directory exists
if [ ! -d "llm-as-judge-proxy" ]; then
    echo "Cloning llm-as-judge-proxy repository..."
    git clone https://github.com/nyasukun/llm-as-judge-proxy.git
    echo "✓ Repository cloned successfully"
else
    echo "✓ llm-as-judge-proxy directory already exists"
    echo "  Pulling latest changes..."
    cd llm-as-judge-proxy
    git pull origin main || git pull origin master || true
    cd ..
fi

echo ""

# Generate certificates
if [ ! -f "certs/ca.crt" ] || [ ! -f "certs/server.crt" ]; then
    echo "Generating SSL certificates..."
    bash scripts/generate-certs.sh
    echo "✓ Certificates generated successfully"
else
    echo "✓ Certificates already exist"
    echo "  To regenerate, delete the 'certs' directory and run this script again"
fi

echo ""

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    echo "Creating .env file..."
    cat > .env <<EOF
# OpenAI API Key (optional - can be set per request)
OPENAI_API_KEY=

# Proxy Configuration
ENVOY_PORT=8080
ENVOY_ADMIN_PORT=9901
LLM_PROXY_PORT=8888

# Logging
LOG_LEVEL=debug
EOF
    echo "✓ .env file created"
    echo "  Please edit .env and add your OPENAI_API_KEY if needed"
else
    echo "✓ .env file already exists"
fi

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. (Optional) Edit .env file to add your OPENAI_API_KEY"
echo "2. Start the proxy chain:"
echo "   docker compose up -d"
echo ""
echo "3. Test the proxy chain:"
echo "   export HTTPS_PROXY=http://localhost:8080"
echo "   export HTTP_PROXY=http://localhost:8080"
echo "   curl -v https://api.openai.com/v1/models"
echo ""
echo "4. View logs:"
echo "   docker compose logs -f"
echo ""
