#!/bin/bash

# Test script for Envoy Proxy Chain

echo "========================================"
echo "Envoy Proxy Chain Test Script"
echo "========================================"
echo ""

# Set proxy environment variables
export HTTPS_PROXY=http://localhost:8080
export HTTP_PROXY=http://localhost:8080

echo "Proxy settings:"
echo "  HTTP_PROXY=$HTTP_PROXY"
echo "  HTTPS_PROXY=$HTTPS_PROXY"
echo ""

# Test 1: Check if Envoy is running
echo "Test 1: Checking Envoy Proxy status..."
if curl -s -f http://localhost:9901/ready > /dev/null 2>&1; then
    echo "✓ Envoy Proxy is ready"
else
    echo "✗ Envoy Proxy is not ready"
    echo "  Please run: docker compose up -d"
    exit 1
fi

echo ""

# Test 2: Test HTTP CONNECT through proxy chain
echo "Test 2: Testing HTTPS connection through proxy chain..."
echo "  Target: https://api.openai.com/v1/models"
echo ""

HTTP_RESPONSE=$(curl -v -x http://localhost:8080 \
    -H "Authorization: Bearer ${OPENAI_API_KEY:-sk-test}" \
    https://api.openai.com/v1/models \
    2>&1)

if echo "$HTTP_RESPONSE" | grep -q "CONNECT api.openai.com:443"; then
    echo "✓ CONNECT method detected in proxy chain"
else
    echo "⚠ Could not detect CONNECT method in output"
fi

if echo "$HTTP_RESPONSE" | grep -q "HTTP.*200\|HTTP.*401\|HTTP.*403"; then
    echo "✓ Successfully connected through proxy chain"
    echo ""
    echo "Response status:"
    echo "$HTTP_RESPONSE" | grep "< HTTP"
else
    echo "✗ Failed to connect through proxy chain"
    echo ""
    echo "Error details:"
    echo "$HTTP_RESPONSE"
    exit 1
fi

echo ""

# Test 3: Check Envoy access logs
echo "Test 3: Checking Envoy access logs..."
echo "Recent Envoy access logs:"
docker compose logs --tail=10 envoy-proxy | grep "upstream_proxy_chaining" || echo "No proxy chain logs found yet"

echo ""

# Test 4: Check llm-as-judge-proxy logs
echo "Test 4: Checking llm-as-judge-proxy logs..."
echo "Recent llm-as-judge-proxy logs:"
docker compose logs --tail=10 llm-as-judge-proxy | grep -i "connect\|proxy\|request" || echo "No relevant logs found"

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo ""
echo "The proxy chain is working if you see:"
echo "1. Envoy receiving CONNECT requests"
echo "2. Envoy forwarding to llm-as-judge-proxy"
echo "3. llm-as-judge-proxy forwarding to api.openai.com"
echo ""
echo "Expected flow:"
echo "  Client → Envoy (localhost:8080) → llm-as-judge-proxy (internal:8888) → api.openai.com"
echo ""
echo "To view live logs:"
echo "  docker compose logs -f"
echo ""
