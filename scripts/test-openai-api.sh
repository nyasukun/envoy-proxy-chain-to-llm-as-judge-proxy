#!/bin/bash

# Test script for OpenAI API calls through proxy chain

if [ -z "$OPENAI_API_KEY" ]; then
    echo "Error: OPENAI_API_KEY environment variable is not set"
    echo "Please set it: export OPENAI_API_KEY=sk-xxxxx"
    exit 1
fi

echo "========================================"
echo "OpenAI API Test through Proxy Chain"
echo "========================================"
echo ""

# Set proxy environment variables
export HTTPS_PROXY=http://localhost:8080
export HTTP_PROXY=http://localhost:8080

echo "Proxy settings:"
echo "  HTTP_PROXY=$HTTP_PROXY"
echo "  HTTPS_PROXY=$HTTPS_PROXY"
echo ""

# Test 1: List models
echo "Test 1: Listing available models..."
echo ""

curl -v https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  2>&1 | tee /tmp/test-output.log

echo ""
echo "---"
echo ""

# Test 2: Chat completion
echo "Test 2: Testing chat completion API..."
echo ""

curl -v https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {
        "role": "user",
        "content": "Hello, this is a test message through proxy chain."
      }
    ],
    "max_tokens": 50
  }' \
  2>&1 | tee -a /tmp/test-output.log

echo ""
echo ""
echo "========================================"
echo "Proxy Chain Verification"
echo "========================================"
echo ""

# Check if CONNECT was used
if grep -q "CONNECT api.openai.com:443" /tmp/test-output.log; then
    echo "✓ HTTP CONNECT method was used (proxy chaining working)"
else
    echo "⚠ Could not verify CONNECT method in output"
fi

# Check for successful proxy connection
if grep -q "HTTP.*200" /tmp/test-output.log; then
    echo "✓ Request completed successfully (200 OK)"
elif grep -q "HTTP.*4[0-9][0-9]" /tmp/test-output.log; then
    echo "⚠ Request completed with client error (check API key)"
else
    echo "✗ Request failed"
fi

echo ""
echo "Full output saved to: /tmp/test-output.log"
echo ""
echo "To check Envoy logs:"
echo "  docker compose logs envoy-proxy | tail -20"
echo ""
echo "To check llm-as-judge-proxy logs:"
echo "  docker compose logs llm-as-judge-proxy | tail -20"
echo ""
