#!/bin/bash
set -e

# Certificate generation script for llm-as-judge-proxy
# This script generates self-signed certificates for development/testing

# Disable MSYS path conversion (fixes OpenSSL -subj on Windows Git Bash)
export MSYS_NO_PATHCONV=1

CERT_DIR="./certs"
DAYS_VALID=365

echo "Generating self-signed certificates for llm-as-judge-proxy..."

# Create certificate directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Generate CA private key
echo "1. Generating CA private key..."
openssl genrsa -out "$CERT_DIR/ca.key" 4096

# Generate CA certificate
echo "2. Generating CA certificate..."
openssl req -new -x509 -days $DAYS_VALID -key "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Development/OU=Testing/CN=Proxy Chain CA"

# Generate server private key
echo "3. Generating server private key..."
openssl genrsa -out "$CERT_DIR/server.key" 4096

# Generate server certificate signing request
echo "4. Generating server CSR..."
openssl req -new -key "$CERT_DIR/server.key" -out "$CERT_DIR/server.csr" \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Development/OU=Testing/CN=llm-as-judge-proxy"

# Create extensions file for SAN
cat > "$CERT_DIR/server.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = llm-as-judge-proxy
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

# Sign the server certificate with CA
echo "5. Signing server certificate with CA..."
openssl x509 -req -in "$CERT_DIR/server.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial -out "$CERT_DIR/server.crt" -days $DAYS_VALID -sha256 \
    -extfile "$CERT_DIR/server.ext"

# Clean up temporary files
rm -f "$CERT_DIR/server.csr" "$CERT_DIR/server.ext" "$CERT_DIR/ca.srl"

# Set appropriate permissions
chmod 600 "$CERT_DIR"/*.key
chmod 644 "$CERT_DIR"/*.crt

echo ""
echo "Certificates generated successfully!"
echo "Location: $CERT_DIR"
echo ""
echo "Files created:"
echo "  - ca.crt: CA certificate (trusted by Envoy)"
echo "  - ca.key: CA private key"
echo "  - server.crt: Server certificate (used by llm-as-judge-proxy)"
echo "  - server.key: Server private key (used by llm-as-judge-proxy)"
echo ""
echo "Certificate information:"
openssl x509 -in "$CERT_DIR/server.crt" -text -noout | grep -A2 "Subject:"
openssl x509 -in "$CERT_DIR/server.crt" -text -noout | grep -A3 "Subject Alternative Name"
