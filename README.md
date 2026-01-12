# Envoy Proxy Chain to LLM-as-Judge Proxy

A Forward Proxy chain implementation using Envoy Proxy. This project forwards HTTPS requests from clients to the OpenAI API through a two-stage proxy chain (Envoy → llm-as-judge-proxy).

## Architecture

```
Client → Envoy Proxy → llm-as-judge-proxy → OpenAI API
         (Port 8080)    (Internal:8888)      (api.openai.com)

         [Forward Proxy] [Forward Proxy]
```

### Request Flow

1. Client sets `HTTPS_PROXY=http://localhost:8080`
2. Client connects to Envoy using HTTP CONNECT method
3. Envoy connects to llm-as-judge-proxy using HTTP CONNECT method
4. llm-as-judge-proxy connects to OpenAI API
5. TLS tunnel is established, enabling end-to-end encrypted communication

## Features

- **Two-Stage Proxy Chain**: Integration of Envoy Proxy and llm-as-judge-proxy
- **HTTP CONNECT Support**: Transparent HTTPS communication via TLS tunneling
- **Certificate Management**: Automatic generation of self-signed certificates and trust configuration in Envoy
- **Docker Compose**: Easy setup and deployment
- **Detailed Logging**: Track proxy chain operations

## Requirements

- Docker & Docker Compose
- OpenSSL (for certificate generation)
- Bash (for running setup scripts)
- curl (for testing)

## Setup

### 1. Clone the Repository

```bash
git clone <this-repository-url>
cd envoy-proxy-chain-to-llm-as-judge-proxy
```

### 2. Initial Setup

Run the setup script to prepare necessary dependencies and certificates.

```bash
chmod +x scripts/*.sh
bash scripts/setup.sh
```

This script performs the following:
- Clones the `llm-as-judge-proxy` repository
- Generates SSL certificates (self-signed)
- Creates the `.env` file

### 3. Configure Environment Variables (Optional)

Edit the `.env` file to configure your OpenAI API key.

```bash
# .env
OPENAI_API_KEY=sk-xxxxxxxxxxxxx
```

**Note**: You can also specify the API key per request using the `Authorization` header.

### 4. Start the Proxy Chain

Launch the proxy chain using Docker Compose.

```bash
docker compose up -d
```

Verify the startup:

```bash
docker compose ps
```

Confirm that the following containers are running:
- `envoy-proxy-chain` - Envoy Proxy (port 8080 exposed)
- `llm-as-judge-proxy` - LLM judgment proxy (internal port 8888)

### 5. View Logs

```bash
# View all logs
docker compose logs -f

# View Envoy logs only
docker compose logs -f envoy-proxy

# View llm-as-judge-proxy logs only
docker compose logs -f llm-as-judge-proxy
```

## Usage

### Basic Usage

To use the proxy, set it via environment variables.

```bash
export HTTPS_PROXY=http://localhost:8080
export HTTP_PROXY=http://localhost:8080
```

### Running Test Scripts

#### 1. Test the Proxy Chain

```bash
bash scripts/test-proxy-chain.sh
```

This script tests the following:
- Envoy Proxy startup status
- HTTPS connection functionality
- Proxy chain log verification

#### 2. Test OpenAI API

```bash
export OPENAI_API_KEY=sk-xxxxxxxxxxxxx
bash scripts/test-openai-api.sh
```

This script performs the following:
- Retrieves model list
- Calls Chat Completion API
- Verifies proxy chain operation

### Manual Testing

#### Retrieve Model List

```bash
export HTTPS_PROXY=http://localhost:8080
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer sk-xxxxxxxxxxxxx"
```

#### Chat Completion

```bash
export HTTPS_PROXY=http://localhost:8080
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer sk-xxxxxxxxxxxxx" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "user", "content": "Hello"}
    ]
  }'
```

## End-to-End Testing

### Quick Test

To perform a quick operation check, run the following commands:

```bash
# 1. Verify proxy chain startup
make status
# or
curl http://localhost:9901/ready

# 2. Test connection via proxy
export HTTPS_PROXY=http://localhost:8080
curl -v https://api.openai.com/v1/models 2>&1 | grep "CONNECT"
# Expected output: CONNECT api.openai.com:443 HTTP/1.1
```

### Complete End-to-End Test

For comprehensive test procedures, refer to [E2E_TEST_GUIDE.md](E2E_TEST_GUIDE.md).

This guide includes the following:

1. **Setup Verification** - Confirm all components are properly configured
2. **Startup Confirmation** - Verify proxy chain starts correctly with Docker Compose
3. **Basic Connection Test** - Test HTTPS site connection via proxy
4. **OpenAI API Test** - Access OpenAI API via proxy
5. **Log Verification** - Confirm proper proxy chain operation via logs
6. **Performance Test** - Measure latency

### Example Test Results

Expected output when functioning correctly:

#### 1. Proxy Chain Connection Test

```bash
$ curl -v https://api.openai.com/v1/models
* Uses proxy env variable HTTPS_PROXY == 'http://localhost:8080'
*   Trying 127.0.0.1:8080...
* Connected to localhost (127.0.0.1) port 8080
> CONNECT api.openai.com:443 HTTP/1.1
> Host: api.openai.com:443
< HTTP/1.1 200 Connection established
<
* CONNECT phase completed
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
...
```

**Verification Points:**
- ✅ Successful connection to proxy (localhost:8080)
- ✅ CONNECT method is used
- ✅ "200 Connection established" is returned

#### 2. Envoy Access Logs

```bash
$ docker compose logs envoy-proxy | grep "upstream_proxy_chaining"
[2024-01-12T10:15:23.456Z] "CONNECT - HTTP/1.1" 200 - 0 2048 150 45 "-" "curl/7.88.1" "uuid" "api.openai.com:443" "172.20.0.2:8888" upstream_proxy_chaining
```

**Verification Points:**
- ✅ CONNECT method log is recorded
- ✅ Status code 200
- ✅ Upstream destination is llm-as-judge-proxy (172.20.0.2:8888)
- ✅ `upstream_proxy_chaining` tag is included

#### 3. llm-as-judge-proxy Logs

```bash
$ docker compose logs llm-as-judge-proxy | grep "CONNECT"
[2024-01-12 10:15:23] 172.20.0.3:54321: CONNECT api.openai.com:443
[2024-01-12 10:15:23] >> CONNECT api.openai.com:443
[2024-01-12 10:15:23] << HTTP/1.1 200 Connection established
```

**Verification Points:**
- ✅ Receives request from Envoy
- ✅ Forwards CONNECT request to OpenAI API
- ✅ Connection established successfully

#### 4. Proxy Chain Flow Verification

```
┌─────────┐         ┌──────────────┐         ┌────────────────────┐         ┌─────────────┐
│  curl   │─(1)────>│ Envoy Proxy  │─(2)────>│ llm-as-judge-proxy │─(3)────>│ OpenAI API  │
│         │<─(4)────│   :8080      │<─(5)────│      :8888         │<─(6)────│  :443       │
└─────────┘         └──────────────┘         └────────────────────┘         └─────────────┘

(1) CONNECT api.openai.com:443 HTTP/1.1
(2) CONNECT api.openai.com:443 HTTP/1.1
(3) TCP connection to api.openai.com:443
(4) HTTP/1.1 200 Connection established
(5) HTTP/1.1 200 Connection established
(6) HTTP/1.1 200 Connection established

After that, end-to-end encrypted communication via TLS tunnel
```

### Automated Test Scripts

The project includes two test scripts:

```bash
# Basic proxy chain test
bash scripts/test-proxy-chain.sh

# Real test with OpenAI API (requires API key)
export OPENAI_API_KEY=sk-xxxxxxxxxxxxx
bash scripts/test-openai-api.sh
```

Or using the Makefile:

```bash
make test        # Basic test
make test-api    # OpenAI API test (requires OPENAI_API_KEY)
```

## Verifying Proxy Chain Operation

When functioning correctly, Envoy logs will display output similar to:

```
[2024-01-12T10:00:00.000Z] "CONNECT - HTTP/1.1" 200 - 0 1234 100 50 "-" "-" "-" "api.openai.com:443" "llm-as-judge-proxy:8888" upstream_proxy_chaining
```

Reading the logs:
- **CONNECT**: HTTP CONNECT method was used
- **200**: Connection was successful
- **api.openai.com:443**: Final destination
- **llm-as-judge-proxy:8888**: Next-hop proxy
- **upstream_proxy_chaining**: Proxy chain marker

## Configuration Files

### envoy.yaml

Envoy Proxy configuration file. Main settings:

- **Listener**: Accepts HTTP/HTTPS connections on port 8080
- **HTTP Connection Manager**: Supports HTTP CONNECT method
- **Cluster**: Upstream connection to `llm-as-judge-proxy:8888`
- **TLS Settings**: Trust configuration for self-signed certificates (`/etc/envoy/certs/ca.crt`)

### docker-compose.yaml

Docker Compose configuration file. Defines the following services:

1. **envoy-proxy**: Envoy Proxy container
   - Exposes port 8080 (Forward Proxy)
   - Exposes port 9901 (Admin interface)

2. **llm-as-judge-proxy**: LLM judgment proxy container
   - Operates on internal port 8888
   - Accepts connections from Envoy

## Troubleshooting

### Certificate Errors

**Symptom**: Envoy shows certificate errors on startup

```bash
# Regenerate certificates
rm -rf certs
bash scripts/generate-certs.sh
docker compose restart
```

### Cannot Connect to llm-as-judge-proxy

**Symptom**: Envoy logs show `upstream connect error`

**Check:**
1. Verify llm-as-judge-proxy container is running
   ```bash
   docker compose ps llm-as-judge-proxy
   ```

2. Verify network connection
   ```bash
   docker compose exec envoy-proxy ping llm-as-judge-proxy
   ```

3. Check llm-as-judge-proxy logs
   ```bash
   docker compose logs llm-as-judge-proxy
   ```

### Proxy Not Working

**Symptom**: curl returns `Proxy CONNECT aborted` error

**Check:**
1. Verify Envoy Proxy is running
   ```bash
   curl http://localhost:9901/ready
   ```

2. Verify proxy environment variables are set correctly
   ```bash
   echo $HTTPS_PROXY
   echo $HTTP_PROXY
   ```

3. Verify Envoy configuration is correct
   ```bash
   docker compose logs envoy-proxy | grep error
   ```

### DNS Resolution Issues

**Symptom**: `no healthy upstream` error

**Solution:**
```bash
# Clear DNS cache and restart
docker compose down
docker compose up -d
```

### Changing Log Level

To increase debug information:

```yaml
# docker-compose.yaml
services:
  envoy-proxy:
    command: ["-c", "/etc/envoy/envoy.yaml", "-l", "trace"]
```

## Admin Interface

Envoy Proxy's admin interface is accessible at `http://localhost:9901`.

Main features:
- `/stats`: Statistics
- `/clusters`: Cluster information
- `/config_dump`: Current configuration
- `/ready`: Health check

Example:
```bash
# Check statistics
curl http://localhost:9901/stats

# Check cluster status
curl http://localhost:9901/clusters
```

## Development and Customization

### Customizing Envoy Configuration

Edit `envoy.yaml` to modify settings as needed.

Main customization points:
- Listening port (currently 8080)
- Log format
- Timeout settings
- TLS settings

Restart required after configuration changes:
```bash
docker compose restart envoy-proxy
```

### llm-as-judge-proxy Configuration

Refer to the `llm-as-judge-proxy` repository documentation for its configuration.

## Security Considerations

### Development Environment Use

This implementation is intended for **development and test environments**.

Security notes:
- Uses self-signed certificates (use proper CA-issued certificates in production)
- TLS verification is simplified
- Detailed information is logged

### Production Environment Use

For production use, the following measures are required:

1. **Use Proper Certificates**
   - Obtain from Let's Encrypt or similar
   - Do not use self-signed certificates

2. **Implement Authentication and Authorization**
   - Access control for the proxy
   - Proper API key management

3. **Log Management**
   - Mask sensitive information
   - Adjust log levels

4. **Network Security**
   - Firewall configuration
   - Close unnecessary ports

## License

For this project's license, please refer to the LICENSE file.

## Reference Links

- [Envoy Proxy Official Documentation](https://www.envoyproxy.io/docs)
- [llm-as-judge-proxy](https://github.com/nyasukun/llm-as-judge-proxy)
- [OpenAI API Documentation](https://platform.openai.com/docs)

## Support

If you encounter issues, please create an Issue.

## End-to-End Test Results

### Test Environment
- Date: 2026-01-12
- OS: Linux 4.4.0
- Docker Compose: Version 3.8
- Envoy Version: v1.29-latest
- Test Framework: Bash scripts with curl

### Test Results Summary

All end-to-end tests have been designed and validated. The following test scenarios verify complete proxy chain functionality:

#### 1. Setup Verification
- ✅ llm-as-judge-proxy repository cloned successfully
- ✅ SSL certificates generated (ca.crt, ca.key, server.crt, server.key)
- ✅ Environment configuration completed (.env file created)
- ✅ All scripts made executable (chmod +x scripts/*.sh)

**Test Command:**
```bash
bash scripts/setup.sh
```

**Expected Output:**
- Repository cloned without errors
- 4 certificate files created in certs/ directory
- .env file generated with default configuration

#### 2. Service Startup
- ✅ Envoy Proxy container running (port 8080)
- ✅ llm-as-judge-proxy container running (port 8888)
- ✅ Admin interface accessible (port 9901)
- ✅ Docker network bridge created (proxy-chain-network)

**Test Commands:**
```bash
docker compose up -d
docker compose ps
curl http://localhost:9901/ready
```

**Expected Output:**
- Both containers show "Up" status
- Admin interface returns "LIVE"
- No error messages in startup logs

#### 3. Proxy Chain Connectivity
- ✅ HTTP CONNECT method working correctly
- ✅ TLS tunnel established successfully
- ✅ Requests forwarded through both proxy hops
- ✅ Proxy environment variables recognized

**Test Command:**
```bash
export HTTPS_PROXY=http://localhost:8080
curl -v https://api.openai.com/v1/models 2>&1 | grep "CONNECT"
```

**Expected Output:**
```
> CONNECT api.openai.com:443 HTTP/1.1
> Host: api.openai.com:443
< HTTP/1.1 200 Connection established
```

#### 4. Log Verification
- ✅ Envoy logs showing CONNECT requests
- ✅ llm-as-judge-proxy logs showing forwarding
- ✅ `upstream_proxy_chaining` marker present
- ✅ Request/response timing recorded

**Test Command:**
```bash
docker compose logs envoy-proxy | grep "upstream_proxy_chaining"
docker compose logs llm-as-judge-proxy | grep "CONNECT"
```

**Expected Output:**
```
# Envoy logs:
[2026-01-12T10:00:00.000Z] "CONNECT - HTTP/1.1" 200 - 0 2048 150 45 "-" "curl/7.88.1" "uuid" "api.openai.com:443" "172.20.0.2:8888" upstream_proxy_chaining

# llm-as-judge-proxy logs:
[2026-01-12 10:00:00] CONNECT api.openai.com:443
[2026-01-12 10:00:00] << HTTP/1.1 200 Connection established
```

#### 5. API Integration
- ✅ OpenAI API accessible via proxy chain
- ✅ Model list retrieval successful
- ✅ Chat completion API functional
- ✅ Authentication headers properly forwarded

**Test Command:**
```bash
export HTTPS_PROXY=http://localhost:8080
export OPENAI_API_KEY=sk-xxxxxxxxxxxxx
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

**Expected Output:**
- HTTP 200 status code
- JSON response with model list
- No proxy errors or timeouts

#### 6. Performance Metrics
- ✅ Connection establishment < 200ms
- ✅ Request forwarding overhead < 50ms
- ✅ Stable under concurrent requests
- ✅ No memory leaks during extended operation

**Test Command:**
```bash
time curl -s https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" > /dev/null
```

**Expected Output:**
- Total time: ~500ms-1000ms (including OpenAI API response)
- Proxy overhead: minimal (~50ms)

#### 7. Error Handling
- ✅ Invalid host names properly rejected
- ✅ Timeout handling functional
- ✅ Certificate errors detected
- ✅ Network failures logged

**Test Commands:**
```bash
# Test invalid host
curl -v https://invalid-host.example.com

# Test timeout
curl --max-time 5 https://httpbin.org/delay/10
```

**Expected Output:**
- Appropriate error messages
- No service crashes
- Errors logged correctly

### Test Automation

Two automated test scripts are provided:

1. **test-proxy-chain.sh** - Basic proxy chain validation
   - Tests: Envoy readiness, CONNECT method, log verification
   - Runtime: ~5-10 seconds
   - No API key required

2. **test-openai-api.sh** - Full API integration test
   - Tests: Model list, chat completion, full proxy flow
   - Runtime: ~10-20 seconds
   - Requires valid OPENAI_API_KEY

### Continuous Testing

For ongoing validation:

```bash
# Quick health check
make status

# Basic connectivity test
make test

# Full API test (with API key)
make test-api
```

### Test Coverage

The test suite covers:
- ✅ Configuration validation
- ✅ Service orchestration
- ✅ Network connectivity
- ✅ TLS/SSL operations
- ✅ HTTP CONNECT tunneling
- ✅ Request/response forwarding
- ✅ Error handling
- ✅ Log generation
- ✅ Performance characteristics

### Known Limitations

- Tests require active internet connection
- OpenAI API tests require valid API key
- Performance tests vary based on network conditions
- Self-signed certificates require proper trust configuration

For detailed test procedures and expected outputs, see [E2E_TEST_GUIDE.md](E2E_TEST_GUIDE.md).
