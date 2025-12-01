# Curl Command Explanation

## Command Breakdown

```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://localhost:443/files/username/filename.txt \
     -k --cookie-jar cookies.txt \
     -o output.txt
```

Let's break down each component:

### Command Structure

#### 1. `curl`
- **What it is**: Command-line tool for transferring data from/to servers
- **Purpose**: Acts as the HTTP client making requests to the secure download service

#### 2. `-H "Authorization: Bearer YOUR_JWT_TOKEN"`
- **Flag**: `-H` sets a custom HTTP header
- **Header**: `Authorization: Bearer YOUR_JWT_TOKEN`
- **Purpose**: 
  - Sends JWT token for authentication
  - Format follows OAuth 2.0 Bearer token standard
  - The service validates this token using Vault's JWKS endpoint
- **What happens**:
  1. NGINX extracts the token from this header
  2. Validates the JWT signature using PEM files from `/etc/nginx/jwks/`
  3. Verifies claims (`sub`, `aud`, `exp`, `iat`)
  4. On success: Creates a Redis session and sets a cookie
  5. On failure: Returns 401 Unauthorized

#### 3. `https://localhost:443/files/username/filename.txt`
- **Protocol**: `https://` - Encrypted HTTPS connection
- **Host**: `localhost` - Local machine (or use your server's IP/domain)
- **Port**: `443` - Standard HTTPS port
- **Path**: `/files/username/filename.txt`
  - `/files/` - Base path for file downloads
  - `username` - User identifier (must match JWT `sub` claim)
  - `filename.txt` - File to download within user's directory
- **File location**: Maps to `/data/username/filename.txt` in the container

#### 4. `-k`
- **Flag**: `-k` or `--insecure`
- **Purpose**: Disables SSL certificate verification
- **Why needed**: 
  - Self-signed certificates (development) aren't trusted by default
  - Allows curl to connect without certificate validation errors
- **Production note**: Remove `-k` when using trusted SSL certificates

#### 5. `--cookie-jar cookies.txt`
- **Flag**: `--cookie-jar` (or `-c`)
- **Purpose**: Save cookies received from server to a file
- **What it stores**:
  - Session cookie: `sessionid=<random-session-id>`
  - HttpOnly, Secure, SameSite=Strict flags
- **Why important**: 
  - Session cookie allows subsequent requests without re-authentication
  - JWT can expire, but session (8h TTL) continues to work
  - Enables long downloads to continue after JWT expiration

#### 6. `-o output.txt`
- **Flag**: `-o` (output file)
- **Purpose**: Save downloaded file content to `output.txt`
- **Alternative**: Omit `-o` to print to stdout

## Request Flow

### Step-by-Step Process

```
1. curl sends request with JWT token
   ↓
2. NGINX receives request at /files/username/filename.txt
   ↓
3. access_by_lua_block executes:
   - Checks for session cookie (first request: none exists)
   - Validates JWT token:
     * Fetches JWKS from Vault (cached)
     * Verifies signature with PEM file
     * Validates claims (sub=username, etc.)
   - Creates Redis session (8h TTL)
   - Sets HttpOnly cookie: sessionid=<id>
   - Redirects to internal file serving location
   ↓
4. File is served from /data/username/filename.txt
   ↓
5. Response sent to curl:
   - File content
   - Set-Cookie header with sessionid
   ↓
6. curl saves:
   - Cookie to cookies.txt
   - File content to output.txt
```

### What Happens Behind the Scenes

#### JWT Validation Process

1. **Token Extraction**: 
   ```lua
   local auth = ngx.req.get_headers()["Authorization"]
   local token = extract_bearer_token(auth)  -- Extracts "YOUR_JWT_TOKEN"
   ```

2. **JWKS Fetching**:
   - Checks Lua shared cache (5-minute cache)
   - If not cached: Fetches from `http://vault:8200/v1/identity/oidc/.well-known/jwks`
   - Caches JWKS for performance

3. **Signature Verification**:
   - Extracts `kid` (key ID) from token header
   - Loads corresponding PEM file: `/etc/nginx/jwks/<kid>.pem`
   - Verifies RS256 signature

4. **Claim Validation**:
   - `sub` (subject) must equal `username` from URL
   - `aud` (audience) must match `username` (optional but validated if present)
   - `exp` (expiration) must be in future
   - `iat` (issued at) not too old (default: 30 minutes max)

5. **Session Creation**:
   - Generates random 16-byte session ID
   - Stores in Redis: `sess:<session-id>` → `/data/username/filename.txt`
   - Sets TTL to 8 hours (28800 seconds)

6. **Cookie Setting**:
   ```
   Set-Cookie: sessionid=<session-id>; Path=/; HttpOnly; Secure; SameSite=Strict
   ```

## Complete Example Session

### First Request (with JWT)

```bash
# Request with JWT token
curl -H "Authorization: Bearer eyJhbGc..." \
     https://localhost:443/files/alice/document.pdf \
     -k --cookie-jar cookies.txt \
     -o document.pdf

# Response includes:
# - File content (saved to document.pdf)
# - Set-Cookie header (saved to cookies.txt)
```

**What happens**:
- JWT validated → Session created
- File downloaded
- Cookie saved for next request

### Subsequent Requests (with Session Cookie)

```bash
# Use saved cookie (JWT can be expired now)
curl https://localhost:443/files/alice/document.pdf \
     -k --cookie cookies.txt \
     -o document.pdf

# No Authorization header needed!
```

**What happens**:
- Session cookie validated in Redis
- Session TTL refreshed (extends 8h from now)
- File downloaded
- No JWT needed!

## Common Variations

### 1. View Response Headers

```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://localhost:443/files/username/filename.txt \
     -k -v \
     -o output.txt
```

The `-v` (verbose) flag shows:
- Request headers sent
- Response headers received (including `Set-Cookie`)
- SSL handshake details

### 2. Resume Download (Range Request)

```bash
# Start download
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://localhost:443/files/username/large-file.zip \
     -k --cookie-jar cookies.txt \
     -C - \
     -o large-file.zip
```

The `-C -` flag:
- Automatically resumes partial downloads
- Uses HTTP Range requests
- Session cookie allows resume even if JWT expired

### 3. Test Authentication Only

```bash
# Check if authentication works (HEAD request)
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://localhost:443/files/username/filename.txt \
     -k -I
```

The `-I` flag:
- Sends HEAD request (no file body)
- Shows response headers
- Useful for testing without downloading

### 4. Follow Redirects

```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://localhost:443/files/username/filename.txt \
     -k -L \
     -o output.txt
```

The `-L` flag:
- Follows HTTP redirects
- May be needed if service uses redirects (though internal redirects are handled by nginx)

### 5. Show Progress

```bash
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     https://localhost:443/files/username/large-file.zip \
     -k --cookie-jar cookies.txt \
     -# \
     -o large-file.zip
```

The `-#` flag:
- Shows download progress bar
- Useful for large files

## Error Responses

### 401 Unauthorized
- **Cause**: Invalid or missing JWT token
- **Solution**: Check token validity, ensure it's not expired
```bash
curl: (22) The requested URL returned error: 401
```

### 403 Forbidden
- **Cause**: 
  - JWT `sub` claim doesn't match username in URL
  - Accessing file outside user's directory
  - Symlink points outside allowed directory
- **Solution**: Verify username matches JWT subject

### 404 Not Found
- **Cause**: File doesn't exist at `/data/username/filename.txt`
- **Solution**: Check file path and permissions

### SSL Certificate Error (without `-k`)
```
curl: (60) SSL certificate problem: self signed certificate
```
- **Cause**: Self-signed certificate not trusted
- **Solution**: Use `-k` flag or add certificate to trusted store

## Security Considerations

### Development vs Production

**Development** (with `-k`):
```bash
curl ... -k ...  # Accepts self-signed certificates
```

**Production** (remove `-k`):
```bash
curl ...  # Validates trusted SSL certificates
```

### Cookie Security

The saved `cookies.txt` file contains:
- Session ID (sensitive)
- HttpOnly flag (prevents JavaScript access)
- Secure flag (HTTPS only)
- SameSite=Strict (CSRF protection)

**Protect the cookie file**:
- Set restrictive permissions: `chmod 600 cookies.txt`
- Don't commit to version control
- Delete after use if needed

## Advanced: Using Environment Variables

### Store Token in Variable

```bash
export JWT_TOKEN="eyJhbGc..."
curl -H "Authorization: Bearer $JWT_TOKEN" \
     https://localhost:443/files/username/filename.txt \
     -k --cookie-jar cookies.txt \
     -o output.txt
```

### Read Token from File

```bash
JWT_TOKEN=$(cat token.txt)
curl -H "Authorization: Bearer $JWT_TOKEN" \
     https://localhost:443/files/username/filename.txt \
     -k --cookie-jar cookies.txt \
     -o output.txt
```

## Troubleshooting

### Check if Service is Running

```bash
# Test connection
curl -k https://localhost:443/files/ -v

# Should return 404 (no path) or 403 (no auth)
# But confirms service is accessible
```

### Verify JWT Token

```bash
# Decode JWT (without verification)
echo "YOUR_JWT_TOKEN" | cut -d. -f2 | base64 -d | jq

# Check claims:
# - sub: should match username
# - exp: should be in future
# - iat: should be recent
```

### Test Session Cookie

```bash
# First request creates session
curl -H "Authorization: Bearer $JWT_TOKEN" \
     https://localhost:443/files/username/test.txt \
     -k --cookie-jar cookies.txt -v

# Second request uses cookie (check -v output for cookie usage)
curl https://localhost:443/files/username/test.txt \
     -k --cookie cookies.txt -v
```

## Summary

The curl command demonstrates the complete authentication and download flow:

1. **Sends JWT** for initial authentication
2. **Receives session cookie** for continued access
3. **Downloads file** to local filesystem
4. **Saves cookie** for subsequent requests

This enables:
- ✅ Secure authentication with JWT
- ✅ Long-lived sessions (8 hours)
- ✅ Downloads that continue after JWT expiration
- ✅ Resumable downloads with Range requests

