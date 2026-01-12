# End-to-End Test Guide

This guide explains the procedure for performing complete end-to-end testing of the Envoy Proxy Chain.

## Prerequisites

- Docker & Docker Compose installed
- OpenAI API key (for actual API testing)
- curl command

## Test Scenario

This test verifies that the following proxy chain functions correctly:

```
Client (curl) → Envoy Proxy (8080) → llm-as-judge-proxy (8888) → OpenAI API
```

## Test Procedure

### 1. Environment Setup

```bash
# Clone the repository
git clone <repository-url>
cd envoy-proxy-chain-to-llm-as-judge-proxy

# Run the setup script
bash scripts/setup.sh
```

**Expected Output:**
```
========================================
Envoy Proxy Chain Setup Script
========================================

Cloning llm-as-judge-proxy repository...
✓ Repository cloned successfully

Generating SSL certificates...
✓ Certificates generated successfully

Creating .env file...
✓ .env file created

========================================
Setup Complete!
========================================
```

**Verification Points:**
- [ ] `llm-as-judge-proxy/` directory is created
- [ ] `certs/` directory contains 4 files (ca.crt, ca.key, server.crt, server.key)
- [ ] `.env` file is created

### 2. Start the Proxy Chain

```bash
# Start the proxy chain with Docker Compose
docker compose up -d

# Check container status
docker compose ps
```

**Expected Output:**
```
NAME                   IMAGE                         STATUS
envoy-proxy-chain      envoyproxy/envoy:v1.29-latest   Up
llm-as-judge-proxy     ...                            Up
```

**Verification Points:**
- [ ] Both containers are in "Up" status
- [ ] Port 8080 is exposed
- [ ] Port 9901 is exposed (admin interface)

### 3. Verify Envoy Proxy Startup

```bash
# Access Envoy's admin interface
curl http://localhost:9901/ready
```

**Expected Output:**
```
LIVE
```

**Verification Points:**
- [ ] Status code 200 is returned
- [ ] Response is "LIVE"

### 4. Check Cluster Status

```bash
# Check Envoy's cluster status
curl http://localhost:9901/clusters
```

**Expected Output:**
```
upstream_proxy_cluster::llm-as-judge-proxy:8888::health_flags::healthy
upstream_proxy_cluster::llm-as-judge-proxy:8888::weight::1
upstream_proxy_cluster::llm-as-judge-proxy:8888::region::
...
```

**Verification Points:**
- [ ] `upstream_proxy_cluster` exists
- [ ] Endpoint is in `healthy` state
- [ ] `llm-as-judge-proxy:8888` is displayed

### 5. Basic Connection Test via Proxy

```bash
# Set proxy environment variables
export HTTPS_PROXY=http://localhost:8080
export HTTP_PROXY=http://localhost:8080

# Test connection to HTTPS site (non-OpenAI API)
curl -v https://www.google.com 2>&1 | grep "CONNECT"
```

**Expected Output:**
```
> CONNECT www.google.com:443 HTTP/1.1
> Host: www.google.com:443
< HTTP/1.1 200 Connection established
```

**Verification Points:**
- [ ] CONNECT method is used
- [ ] Status code 200 Connection established is returned
- [ ] Connection succeeds

### 6. OpenAI API Endpoint Connection Test (Without Authentication)

```bash
# Test connection to OpenAI API endpoint (401 error expected)
curl -v https://api.openai.com/v1/models 2>&1 | head -30
```

**Expected Output:**
```
* Uses proxy env variable HTTPS_PROXY == 'http://localhost:8080'
*   Trying 127.0.0.1:8080...
* Connected to localhost (127.0.0.1) port 8080
* CONNECT api.openai.com:443 HTTP/1.1
* Host: api.openai.com:443
...
> CONNECT api.openai.com:443 HTTP/1.1
> Host: api.openai.com:443
< HTTP/1.1 200 Connection established
...
< HTTP/1.1 401 Unauthorized
```

**Verification Points:**
- [ ] Connection to proxy (localhost:8080) succeeds
- [ ] CONNECT method is used
- [ ] "200 Connection established" is returned
- [ ] 401 error is returned from OpenAI API (this is normal behavior)

### 7. Check Envoy Access Logs

```bash
# Check Envoy logs
docker compose logs envoy-proxy | grep "upstream_proxy_chaining" | tail -5
```

**Expected Output:**
```
[2024-01-12T10:00:00.000Z] "CONNECT - HTTP/1.1" 200 - 0 1234 100 50 "-" "curl/7.88.1" "-" "api.openai.com:443" "172.20.0.2:8888" upstream_proxy_chaining
```

**Verification Points:**
- [ ] CONNECT method log is recorded
- [ ] Status code 200 is recorded
- [ ] Upstream host (llm-as-judge-proxy) IP address and port are displayed
- [ ] `upstream_proxy_chaining` tag is included

### 8. Check llm-as-judge-proxy Logs

```bash
# Check llm-as-judge-proxy logs
docker compose logs llm-as-judge-proxy | grep -i "connect\|api.openai.com" | tail -10
```

**Expected Output:**
```
<timestamp> CONNECT api.openai.com:443
<timestamp> >> CONNECT api.openai.com:443
<timestamp> << HTTP/1.1 200 Connection established
```

**Verification Points:**
- [ ] CONNECT request is recorded
- [ ] Connection to `api.openai.com:443` is recorded
- [ ] 200 response is recorded

### 9. OpenAI API Call Test (With API Key)

**Note:** Requires an actual API key.

```bash
# Set API key
export OPENAI_API_KEY=sk-xxxxxxxxxxxxx

# Retrieve model list
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" | jq '.data[0].id'
```

**Expected Output:**
```
"gpt-4"
```
(or other model name)

**Verification Points:**
- [ ] Status code 200 is returned
- [ ] JSON response is returned
- [ ] Model list can be retrieved

### 10. Chat Completion API Test

```bash
# Call Chat Completion API
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Say hello"}],
    "max_tokens": 10
  }' | jq '.choices[0].message.content'
```

**Expected Output:**
```
"Hello! How can I assist you today?"
```
(actual response may vary)

**Verification Points:**
- [ ] Status code 200 is returned
- [ ] JSON response is returned
- [ ] `choices[0].message.content` contains text

### 11. Detailed Proxy Chain Verification

```bash
# Request with detailed debug output
curl -v https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  2>&1 | grep -E "CONNECT|Connection established|Host:|Proxy"
```

**Expected Output:**
```
* Uses proxy env variable HTTPS_PROXY == 'http://localhost:8080'
* Proxy replied 200 to CONNECT request
> CONNECT api.openai.com:443 HTTP/1.1
> Host: api.openai.com:443
< HTTP/1.1 200 Connection established
```

**Verification Points:**
- [ ] Proxy environment variable is recognized
- [ ] Proxy returns 200
- [ ] TLS tunnel is established

### 12. Complete Proxy Chain Flow Verification

Open multiple terminals simultaneously and execute the following:

**Terminal 1 (Monitor Envoy logs):**
```bash
docker compose logs -f envoy-proxy
```

**Terminal 2 (Monitor llm-as-judge-proxy logs):**
```bash
docker compose logs -f llm-as-judge-proxy
```

**Terminal 3 (Execute request):**
```bash
export HTTPS_PROXY=http://localhost:8080
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

**Expected Behavior:**
1. Request is executed in Terminal 3
2. Terminal 1 (Envoy) displays `CONNECT api.openai.com:443` log
3. Terminal 2 (llm-as-judge-proxy) displays `CONNECT api.openai.com:443` log
4. Terminal 3 receives response

**Verification Points:**
- [ ] Envoy accepts connection from client
- [ ] Envoy forwards to llm-as-judge-proxy
- [ ] llm-as-judge-proxy forwards to OpenAI API
- [ ] Response is correctly returned

## Test Results Summary

If all tests succeed, the following is confirmed:

1. ✅ Setup completes successfully
2. ✅ Proxy chain starts with Docker Compose
3. ✅ Envoy Proxy functions correctly
4. ✅ Connection from Envoy to llm-as-judge-proxy is established
5. ✅ HTTP CONNECT method works correctly
6. ✅ HTTPS communication via proxy chain is possible
7. ✅ Requests to OpenAI API succeed
8. ✅ Proxy chain can be tracked via detailed logs

## Troubleshooting

If tests fail, refer to the Troubleshooting section in [README.md](README.md).

## Cleanup

```bash
# Stop the proxy chain
docker compose down

# To also remove volumes
docker compose down -v
```

## Automated Test Scripts

Instead of manual testing, you can use the following scripts:

```bash
# Basic proxy chain test
bash scripts/test-proxy-chain.sh

# OpenAI API test (requires API key)
export OPENAI_API_KEY=sk-xxxxxxxxxxxxx
bash scripts/test-openai-api.sh
```

## Performance Testing

To measure proxy chain performance:

```bash
# Measure latency
time curl -s https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" > /dev/null

# Run multiple times to get average
for i in {1..10}; do
  time curl -s https://api.openai.com/v1/models \
    -H "Authorization: Bearer $OPENAI_API_KEY" > /dev/null
done
```

## Security Testing

Verify that the proxy functions correctly and can handle invalid requests:

```bash
# Test connection to invalid host (should be blocked)
curl -v https://invalid-host-name.example.com

# Test timeout
curl --max-time 5 https://httpbin.org/delay/10
```

## Conclusion

By following this test guide, you can comprehensively verify that the Envoy Proxy Chain is correctly configured and functions as expected.
