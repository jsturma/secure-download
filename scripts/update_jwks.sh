# /usr/local/bin/update_jwks.sh
#!/bin/bash
set -e
# Use Docker service name or localhost depending on where script runs
if [ -f /.dockerenv ]; then
    JWKS_URL="http://vault:8200/v1/identity/oidc/.well-known/jwks"
else
    JWKS_URL="http://localhost:8200/v1/identity/oidc/.well-known/jwks"
fi
TMP=/tmp/jwks.json
curl -sfS $JWKS_URL -o $TMP || { echo "Failed to fetch JWKS from $JWKS_URL"; exit 1; }
python3 /usr/local/bin/jwk2pem.py $TMP /etc/nginx/jwks || { echo "Failed to convert JWKS"; exit 1; }
# Reload OpenResty in container if running in Docker
if [ -f /.dockerenv ]; then
    openresty -s reload || echo "Warning: Could not reload OpenResty"
elif command -v docker &> /dev/null; then
    docker exec nginx openresty -s reload 2>/dev/null || echo "Warning: Could not reload OpenResty in container"
fi
