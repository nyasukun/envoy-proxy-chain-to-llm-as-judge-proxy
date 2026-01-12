# Architecture Document

## System Overview

This project implements a two-stage Forward Proxy chain using Envoy Proxy and llm-as-judge-proxy.

## Component Architecture

```
┌─────────┐         ┌──────────────┐         ┌────────────────────┐         ┌─────────────┐
│ Client  │────────>│ Envoy Proxy  │────────>│ llm-as-judge-proxy │────────>│ OpenAI API  │
│         │ :8080   │ (1st Proxy)  │ :8888   │   (2nd Proxy)      │ :443    │             │
└─────────┘         └──────────────┘         └────────────────────┘         └─────────────┘
                            │
                            │ :9901
                            ▼
                    ┌──────────────┐
                    │ Admin UI     │
                    └──────────────┘
```

## Data Flow

### 1. HTTPS Communication (HTTP CONNECT)

```
1. Client → Envoy
   CONNECT api.openai.com:443 HTTP/1.1
   Host: api.openai.com:443

2. Envoy → llm-as-judge-proxy
   CONNECT api.openai.com:443 HTTP/1.1
   Host: api.openai.com:443

3. llm-as-judge-proxy → OpenAI API
   TCP connection to api.openai.com:443

4. HTTP 200 Connection Established ← llm-as-judge-proxy
   ← Envoy

5. Client ⟷ OpenAI API
   TLS tunnel established
   Encrypted communication
```

### 2. HTTP Communication

```
1. Client → Envoy
   GET http://example.com/ HTTP/1.1
   Host: example.com

2. Envoy → llm-as-judge-proxy
   GET http://example.com/ HTTP/1.1
   Host: example.com

3. llm-as-judge-proxy → example.com
   GET / HTTP/1.1
   Host: example.com

4. Response ← example.com
   ← llm-as-judge-proxy
   ← Envoy
   ← Client
```

## Envoy Proxy Configuration Details

### Listener Configuration

```yaml
listeners:
- name: forward_proxy_listener
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 8080
```

- **Port 8080**: Operates as HTTP/HTTPS proxy
- **0.0.0.0**: Listens on all network interfaces

### HTTP Connection Manager

```yaml
http_connection_manager:
  stat_prefix: ingress_http
  upgrade_configs:
  - upgrade_type: CONNECT
```

- **upgrade_type: CONNECT**: Supports HTTP CONNECT method
- **stat_prefix**: Metrics prefix

### Routing Configuration

```yaml
routes:
- match:
    connect_matcher: {}
  route:
    cluster: upstream_proxy_cluster
    upgrade_configs:
    - upgrade_type: CONNECT
      connect_config: {}
```

- **connect_matcher**: Matches CONNECT requests
- **upstream_proxy_cluster**: Routes to llm-as-judge-proxy

### Cluster Configuration

```yaml
clusters:
- name: upstream_proxy_cluster
  type: STRICT_DNS
  load_assignment:
    endpoints:
    - lb_endpoints:
      - endpoint:
          address:
            socket_address:
              address: llm-as-judge-proxy
              port_value: 8888
```

- **STRICT_DNS**: Uses DNS name resolution
- **llm-as-judge-proxy:8888**: Next-hop proxy

### TLS Configuration

```yaml
transport_socket:
  name: envoy.transport_sockets.tls
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
    common_tls_context:
      validation_context:
        trust_chain_filename: /etc/envoy/certs/ca.crt
```

- **trust_chain_filename**: Trusted CA certificate
- Validates llm-as-judge-proxy's self-signed certificate

## llm-as-judge-proxy

llm-as-judge-proxy has two roles:

1. **Forward Proxy**: Forwards requests to OpenAI API
2. **LLM Judge**: Validates requests/responses (optional)

### Communication Protocol

- **Listening**: HTTPS (port 8888)
- **Certificate**: Self-signed certificate (development environment)
- **Protocol**: HTTP/1.1 with CONNECT support

## Certificate Management

### Certificate Structure

```
certs/
├── ca.crt        # CA certificate (trusted by Envoy)
├── ca.key        # CA private key
├── server.crt    # Server certificate (used by llm-as-judge-proxy)
└── server.key    # Server private key (used by llm-as-judge-proxy)
```

### Certificate Usage

1. **ca.crt**: Used by Envoy to validate llm-as-judge-proxy's certificate
2. **server.crt/server.key**: Used by llm-as-judge-proxy to accept TLS connections

### SAN (Subject Alternative Name)

The server certificate includes the following SANs:

- DNS: llm-as-judge-proxy
- DNS: localhost
- IP: 127.0.0.1

## Docker Networking

### Network Configuration

```yaml
networks:
  proxy-chain-network:
    driver: bridge
```

- **bridge**: Docker bridge network
- Name resolution between containers is possible
- Resolved as DNS name `llm-as-judge-proxy`

### Port Mapping

- **8080:8080**: Envoy Proxy (accessible from host)
- **9901:9901**: Envoy Admin UI (accessible from host)
- **8888**: llm-as-judge-proxy (inter-container only)

## Logging and Monitoring

### Access Log Format

```
[START_TIME] "METHOD PATH PROTOCOL" RESPONSE_CODE FLAGS RX_BYTES TX_BYTES DURATION
UPSTREAM_TIME "X-FORWARDED-FOR" "USER-AGENT" "REQUEST-ID" "AUTHORITY" "UPSTREAM_HOST" TAG
```

### Important Log Fields

- **METHOD**: CONNECT, GET, POST, etc.
- **RESPONSE_CODE**: HTTP status code
- **UPSTREAM_HOST**: Next-hop proxy (llm-as-judge-proxy:8888)
- **TAG**: `upstream_proxy_chaining` identifies the proxy chain

### Admin Interface

The Envoy admin interface (:9901) provides access to:

- `/stats`: Metrics
- `/clusters`: Cluster status
- `/config_dump`: Current configuration
- `/ready`: Health check

## Security Considerations

### Development Environment

- Uses self-signed certificates
- Simplified TLS verification
- Detailed log output

### Migration to Production

The following changes are required:

1. **Certificates**
   - Use proper CA-issued certificates
   - Regular certificate renewal

2. **Authentication and Authorization**
   - Access control for the proxy
   - Implement API authentication

3. **Logs**
   - Mask sensitive information
   - Adjust log level (info/warn)

4. **Network**
   - Firewall configuration
   - Expose only necessary ports

## Performance

### Configuration Parameters

```yaml
connect_timeout: 30s
```

- **connect_timeout**: Upstream connection timeout
- Can be adjusted as needed

### Scaling

- Envoy uses multiple worker threads
- Can scale out using Docker Compose `replicas`
- Can place a load balancer in front

## Troubleshooting Flow

```
[Connection Failure]
    │
    ├─ Check Envoy startup → curl http://localhost:9901/ready
    │
    ├─ Check llm-as-judge-proxy startup → docker compose ps
    │
    ├─ Check certificates → ls -la certs/
    │
    ├─ Check network → docker compose exec envoy-proxy ping llm-as-judge-proxy
    │
    └─ Check logs → docker compose logs
```

## Extensibility

### Customization Points

1. **Add Filters**
   - Rate limiting
   - Authentication
   - Logging

2. **Add Metrics**
   - Prometheus integration
   - Custom metrics

3. **Multiple Backends**
   - Support multiple LLM providers
   - Load balancing

## References

- [Envoy Proxy - HTTP Connection Manager](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_conn_man/http_conn_man)
- [Envoy Proxy - CONNECT Support](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/http/upgrades)
- [HTTP CONNECT Method - RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#name-connect)
