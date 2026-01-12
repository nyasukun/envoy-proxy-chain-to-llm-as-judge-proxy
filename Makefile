.PHONY: help setup start stop restart logs logs-envoy logs-proxy test test-api clean certs status

# Default target
help:
	@echo "Envoy Proxy Chain - Available commands:"
	@echo ""
	@echo "  make setup        - Initial setup (clone repos, generate certs)"
	@echo "  make start        - Start the proxy chain"
	@echo "  make stop         - Stop the proxy chain"
	@echo "  make restart      - Restart the proxy chain"
	@echo "  make logs         - Show all logs"
	@echo "  make logs-envoy   - Show Envoy logs only"
	@echo "  make logs-proxy   - Show llm-as-judge-proxy logs only"
	@echo "  make test         - Test proxy chain connection"
	@echo "  make test-api     - Test OpenAI API through proxy (requires OPENAI_API_KEY)"
	@echo "  make status       - Show container status"
	@echo "  make certs        - Regenerate SSL certificates"
	@echo "  make clean        - Stop and remove all containers"
	@echo "  make help         - Show this help message"
	@echo ""

# Initial setup
setup:
	@echo "Running initial setup..."
	@chmod +x scripts/*.sh
	@bash scripts/setup.sh

# Start the proxy chain
start:
	@echo "Starting proxy chain..."
	@docker compose up -d
	@echo ""
	@echo "Proxy chain started!"
	@echo "  Envoy Proxy:  http://localhost:8080"
	@echo "  Admin UI:     http://localhost:9901"
	@echo ""
	@echo "To use the proxy, run:"
	@echo "  export HTTPS_PROXY=http://localhost:8080"
	@echo "  export HTTP_PROXY=http://localhost:8080"

# Stop the proxy chain
stop:
	@echo "Stopping proxy chain..."
	@docker compose down

# Restart the proxy chain
restart:
	@echo "Restarting proxy chain..."
	@docker compose restart
	@echo "Proxy chain restarted!"

# Show all logs
logs:
	@docker compose logs -f

# Show Envoy logs
logs-envoy:
	@docker compose logs -f envoy-proxy

# Show llm-as-judge-proxy logs
logs-proxy:
	@docker compose logs -f llm-as-judge-proxy

# Test proxy chain
test:
	@echo "Testing proxy chain..."
	@bash scripts/test-proxy-chain.sh

# Test OpenAI API
test-api:
	@if [ -z "$$OPENAI_API_KEY" ]; then \
		echo "Error: OPENAI_API_KEY environment variable is not set"; \
		echo "Please set it: export OPENAI_API_KEY=sk-xxxxx"; \
		exit 1; \
	fi
	@bash scripts/test-openai-api.sh

# Show container status
status:
	@echo "Container status:"
	@docker compose ps
	@echo ""
	@echo "Checking Envoy readiness..."
	@curl -s http://localhost:9901/ready && echo "✓ Envoy is ready" || echo "✗ Envoy is not ready"

# Regenerate certificates
certs:
	@echo "Regenerating SSL certificates..."
	@rm -rf certs
	@bash scripts/generate-certs.sh
	@echo ""
	@echo "Certificates regenerated. Restarting services..."
	@docker compose restart

# Clean up
clean:
	@echo "Stopping and removing all containers..."
	@docker compose down -v
	@echo "Cleanup complete!"
