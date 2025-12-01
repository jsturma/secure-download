# Secure Download Service

A secure file download service that uses JWT authentication with Redis session management to allow downloads to continue even after JWT expiration.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Usage](#usage)
- [How Session Management Works](#how-session-management-works)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Development](#development)

## Features

- **JWT Authentication**: Uses HashiCorp Vault OIDC for JWT token generation and validation
- **Redis Session Management**: Creates long-lived sessions (8 hours) that persist even after JWT expires
- **Resumable Downloads**: Supports HTTP Range requests for resumable downloads
- **User-Based Access Control**: Each user can only access files in their own directory
- **OpenResty/NGINX**: Powered by OpenResty with Lua scripting for flexible authentication logic
- **Dockerized**: All services run in Docker containers for easy deployment

## Architecture

```
┌─────────┐      ┌──────────┐      ┌──────────┐      ┌─────────┐
│ Client  │─────>│  NGINX   │─────>│   Vault  │      │  Redis  │
│         │<─────│ OpenResty│      │  (JWKS)  │<─────│Session  │
└─────────┘      └──────────┘      └──────────┘      └─────────┘
                       │
                       │
                  ┌─────────┐
                  │ /shared │
                  │  files  │
                  └─────────┘
```

### How It Works

1. **Initial Request**: Client sends JWT token in Authorization header
2. **JWT Validation**: NGINX validates JWT using Vault's JWKS endpoint
3. **Session Creation**: On successful validation, a session is created in Redis (8h TTL)
4. **Cookie Setting**: Session ID is returned as HttpOnly cookie
5. **Subsequent Requests**: Client uses session cookie (JWT can expire)
6. **Long Downloads**: Each Range request refreshes session TTL, allowing downloads to continue

## Prerequisites

- Docker and Docker Compose
- OpenSSL (for certificate generation)
- Python 3 (for JWKS conversion script)
- Access to HashiCorp Vault (for JWT token generation)

## Quick Start

### 1. Generate SSL Certificates

```bash
./scripts/generate-ssl.sh
```

This creates self-signed certificates in `nginx/ssl/`. For production, use certificates from a trusted CA.

### 2. Configure Vault

Start Vault and configure OIDC:

```bash
# Start services
docker-compose up -d vault redis

# Wait for Vault to be ready
sleep 5

# Configure Vault (run from vault/ directory or provide path)
docker exec -it vault vault login root
docker exec -it vault vault auth enable oidc
docker exec -it vault vault write identity/oidc/key/mykey \
    algorithm=RS256 \
    verification_ttl=1h \
    rotation_period=24h
docker exec -it vault vault write identity/oidc/role/myrole \
    key=mykey \
    ttl=30m \
    template='{"sub":"{{identity.entity.name}}","aud":"nginx"}'
```

### 3. Fetch JWKS and Generate PEM Files

```bash
./scripts/update_jwks.sh
```

This fetches JWKS from Vault and converts them to PEM format for JWT verification.

### 4. Create User Directories

```bash
mkdir -p shared/username/
# Add files to share
cp your-file.txt shared/username/
```

### 5. Start All Services

```bash
docker-compose up -d
```

### 6. Test Download

Get a JWT token from Vault (see [Usage](#usage) section), then:

```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://localhost:443/files/username/your-file.txt \
     -k --cookie-jar cookies.txt --cookie cookies.txt
```

## Detailed Setup

### Directory Structure

```
secure-download/
├── docker-compose.yml          # Docker services configuration
├── nginx/
│   ├── conf.d/
│   │   └── nginx.conf          # OpenResty/NGINX configuration
│   ├── ssl/                    # SSL certificates (generate with script)
│   └── jwks/                   # PEM files from Vault JWKS
├── scripts/
│   ├── generate-ssl.sh         # Generate self-signed certificates
│   ├── update_jwks.sh          # Fetch and convert JWKS to PEM
│   └── jwk2pem.py              # Convert JWK to PEM format
├── shared/                     # User directories for file sharing
│   └── <username>/             # User-specific directories
├── vault/
│   ├── configure-vault.sh      # Vault OIDC configuration
│   ├── get-token-from-vault.sh # Token generation example
│   └── template.hcl            # JWT token template
└── openresty/
    └── install.sh              # OpenResty installation (for non-Docker setup)
```

### Configuration

#### NGINX Configuration

Key configuration variables in `nginx/conf.d/nginx.conf`:

- `$vault_jwks_url`: Vault JWKS endpoint URL (default: `http://vault:8200/v1/identity/oidc/.well-known/jwks`)
- `$redis_host`: Redis hostname (default: `redis`)
- `$redis_port`: Redis port (default: `6379`)
- `$base_data_path`: Base path for user files (default: `/data`)
- `$session_ttl_seconds`: Session TTL in seconds (default: `28800` = 8 hours)
- `$max_token_age`: Maximum JWT token age in seconds (default: `1800` = 30 minutes)

#### SSL Certificates

Certificates should be placed in `nginx/ssl/`:
- `privkey.pem`: Private key
- `fullchain.pem`: Certificate (or certificate chain)

Generate with:
```bash
./scripts/generate-ssl.sh [domain]
```

#### Vault Configuration

See `vault/configure-vault.sh` for OIDC setup. The service expects:
- JWT tokens with `sub` claim matching the username
- Optional `aud` claim matching the username (for additional validation)
- RS256 algorithm

## Usage

### Getting a JWT Token

1. **Create an Entity in Vault** (one-time setup):
```bash
docker exec -it vault vault write identity/entity name=username
# Note the entity ID from output
```

2. **Generate Token**:
```bash
docker exec -it vault vault write identity/oidc/token role=myrole entity_id=<entity-id>
# Copy the token from the response
```

Or use the helper script:
```bash
./vault/get-token-from-vault.sh <entity-id>
```

### Downloading Files

#### With JWT Token (First Request)

```bash
# Initial request - creates session
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://localhost:443/files/username/filename.txt \
     -k --cookie-jar cookies.txt \
     -o output.txt
```

#### With Session Cookie (Subsequent Requests)

```bash
# Subsequent requests - uses session cookie
curl https://localhost:443/files/username/filename.txt \
     -k --cookie cookies.txt \
     -o output.txt
```

#### Resumable Downloads

```bash
# Download with resume support
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://localhost:443/files/username/large-file.zip \
     -k --cookie-jar cookies.txt \
     -C - \
     -o large-file.zip
```

### API Endpoints

- `GET /files/<username>/<filepath>`: Download a file
  - Requires: JWT token (first request) or valid session cookie
  - Supports: HTTP Range requests for resumable downloads
  - Returns: File content with appropriate headers

## How Session Management Works

### Initial Authentication Flow

1. Client sends request with JWT token in `Authorization: Bearer <token>` header
2. NGINX validates JWT:
   - Fetches JWKS from Vault (cached for 5 minutes)
   - Verifies signature using PEM files from `/etc/nginx/jwks/`
   - Validates claims (`sub`, `aud`, `exp`, `iat`)
3. On success:
   - Creates random session ID
   - Stores file path in Redis: `sess:<session-id>` → `/data/username/filepath`
   - Sets TTL to 8 hours
   - Sets HttpOnly cookie: `sessionid=<session-id>`
   - Redirects to internal file serving location

### Subsequent Request Flow

1. Client sends request with session cookie
2. NGINX validates session:
   - Retrieves session from Redis
   - Verifies file path matches request
   - **Refreshes TTL** (important for long downloads)
3. On success: Serves file directly

### Why This Works for Long Downloads

- **JWT Expires**: Client's JWT token may expire during download
- **Session Persists**: Redis session (8h TTL) continues to work
- **TTL Refresh**: Each Range request refreshes session TTL
- **No Re-authentication**: Download continues seamlessly

## Maintenance

### Updating JWKS

JWKS keys rotate periodically. Update PEM files:

```bash
./scripts/update_jwks.sh
```

For automated updates, add to crontab:
```bash
*/5 * * * * /path/to/scripts/update_jwks.sh
```

### Monitoring Sessions

Check active sessions in Redis:

```bash
docker exec -it redis redis-cli KEYS "sess:*"
```

View session details:
```bash
docker exec -it redis redis-cli GET "sess:<session-id>"
docker exec -it redis redis-cli TTL "sess:<session-id>"
```

## Troubleshooting

### Certificate Errors

**Problem**: `SSL certificate problem: self signed certificate`

**Solution**: Use `-k` flag with curl or add certificate to trusted store:
```bash
curl -k https://localhost:443/files/...
```

### JWT Validation Fails

**Problem**: `401 Unauthorized` on initial request

**Solutions**:
1. Verify JWT token is valid: `jwt.io` or `openssl` tools
2. Check JWKS is up to date: `./scripts/update_jwks.sh`
3. Verify `sub` claim matches username in URL
4. Check Vault is accessible from nginx container

### Session Not Working

**Problem**: Session cookie not being set or recognized

**Solutions**:
1. Check Redis is running: `docker-compose ps redis`
2. Verify cookie is being sent: Check `Set-Cookie` header in response
3. Check session exists in Redis: `docker exec -it redis redis-cli KEYS "sess:*"`
4. Verify cookie path matches request path

### File Not Found

**Problem**: `404 Not Found`

**Solutions**:
1. Verify file exists: `ls -la shared/username/filename`
2. Check file permissions: Files should be readable
3. Verify path matches: `/files/username/path/to/file`
4. Check nginx logs: `docker logs nginx`

### Connection Issues

**Problem**: Cannot connect to services

**Solutions**:
1. Check all services are running: `docker-compose ps`
2. Verify network: `docker network inspect secure-download_secure-download`
3. Check service health: `docker-compose ps` (should show "healthy")
4. View logs: `docker-compose logs nginx vault redis`

## Security Considerations

### Production Recommendations

1. **Use Real SSL Certificates**: Replace self-signed certs with certificates from a trusted CA
2. **Secure Redis**: Enable authentication and use TLS for Redis connections
3. **Secure Vault**: Use proper Vault configuration (not dev mode) with TLS
4. **Network Isolation**: Limit network exposure, use firewall rules
5. **Session Security**: Consider shorter session TTLs for sensitive data
6. **File Permissions**: Ensure proper file system permissions
7. **Monitoring**: Set up logging and monitoring for security events
8. **Rate Limiting**: Consider adding rate limiting to prevent abuse

### Current Limitations

- Uses self-signed certificates (development only)
- Redis runs without authentication (use in isolated network)
- Vault runs in dev mode (use proper configuration for production)
- No rate limiting implemented
- No audit logging

## Development

### Adding New Users

1. Create directory:
   ```bash
   mkdir -p shared/username/
   ```

2. Create Vault entity:
   ```bash
   docker exec -it vault vault write identity/entity name=username
   ```

3. Add files:
   ```bash
   cp files/* shared/username/
   ```

### Testing Locally

1. Generate test certificate:
   ```bash
   ./scripts/generate-ssl.sh localhost
   ```

2. Start services:
   ```bash
   docker-compose up -d
   ```

3. Get token and test:
   ```bash
   TOKEN=$(docker exec -it vault vault write -field=token identity/oidc/token role=myrole entity_id=<id>)
   curl -H "Authorization: Bearer $TOKEN" https://localhost:443/files/username/file.txt -k
   ```

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]

