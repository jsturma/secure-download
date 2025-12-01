#!/bin/bash
# Generate self-signed SSL certificates for secure-download service
# Usage: ./scripts/generate-ssl.sh [domain]
# Example: ./scripts/generate-ssl.sh localhost

set -e

# Configuration
DOMAIN="${1:-localhost}"
VALIDITY_DAYS="${SSL_VALIDITY_DAYS:-365}"
SSL_DIR="$(cd "$(dirname "$0")/.." && pwd)/nginx/ssl"
KEY_SIZE=2048

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Generating SSL certificates for ${DOMAIN}...${NC}"

# Create SSL directory if it doesn't exist
mkdir -p "$SSL_DIR"

# Check if certificates already exist
if [ -f "$SSL_DIR/privkey.pem" ] || [ -f "$SSL_DIR/fullchain.pem" ]; then
    echo -e "${YELLOW}Warning: SSL certificates already exist in $SSL_DIR${NC}"
    read -p "Do you want to overwrite them? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Generate private key
echo "Generating private key..."
openssl genrsa -out "$SSL_DIR/privkey.pem" $KEY_SIZE
chmod 600 "$SSL_DIR/privkey.pem"

# Create certificate signing request config
CONFIG_FILE=$(mktemp)
cat > "$CONFIG_FILE" <<EOF
[req]
default_bits = $KEY_SIZE
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=Organization
OU=IT Department
CN=$DOMAIN

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
DNS.3 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Generate self-signed certificate
echo "Generating self-signed certificate (valid for $VALIDITY_DAYS days)..."
openssl req -new -x509 -key "$SSL_DIR/privkey.pem" -out "$SSL_DIR/cert.pem" \
    -days $VALIDITY_DAYS -config "$CONFIG_FILE" -extensions v3_req

# Create fullchain.pem (for self-signed, this is just the cert)
# In production, you'd concatenate cert + chain, but for self-signed it's just the cert
cp "$SSL_DIR/cert.pem" "$SSL_DIR/fullchain.pem"

# Cleanup
rm -f "$CONFIG_FILE"

# Set proper permissions
chmod 644 "$SSL_DIR/fullchain.pem"
chmod 644 "$SSL_DIR/cert.pem"

echo -e "${GREEN}✓ SSL certificates generated successfully!${NC}"
echo ""
echo "Certificate files:"
echo "  Private Key: $SSL_DIR/privkey.pem"
echo "  Certificate: $SSL_DIR/cert.pem"
echo "  Full Chain:  $SSL_DIR/fullchain.pem"
echo ""
echo -e "${YELLOW}Note: These are self-signed certificates for development/testing.${NC}"
echo "For production, use certificates from a trusted CA."
echo ""
echo "To verify the certificate:"
echo "  openssl x509 -in $SSL_DIR/fullchain.pem -text -noout"

