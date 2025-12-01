# Security: Read-Only Operations

This document details the read-only protections implemented in the secure-download service to ensure that no file modifications are possible.

## Read-Only Protections

### 1. Docker Volume Mount (Primary Protection)

The shared data directory is mounted as **read-only** in `docker-compose.yml`:

```yaml
volumes:
  - ./shared:/data:ro
```

The `:ro` flag ensures that even if a process inside the container attempts to write files, the filesystem mount prevents it at the kernel level.

### 2. HTTP Method Restrictions

#### Location-Level Protection

All file-serving locations explicitly deny write methods:

```nginx
location ~ ^/files/(?<user>[^/]+)/(?<filepath>.+)$ {
    # Explicitly deny all write methods (POST, PUT, DELETE, PATCH, etc.)
    limit_except GET HEAD { deny all; }
}
```

This ensures only `GET` and `HEAD` HTTP methods are allowed. All other methods (POST, PUT, DELETE, PATCH, etc.) are denied.

#### Internal Location Protection

Even internal locations (only accessible via nginx internal redirects) have the same protection:

```nginx
location ~ ^/serve_file_internal/(?<user>[^/]+)/(?<filepath>.+)$ {
    internal;
    limit_except GET HEAD { deny all; }
}
```

### 3. Default Deny

Any requests to paths other than `/files/` are denied:

```nginx
location / {
    deny all;
    return 404;
}
```

### 4. File Operations

All file operations in Lua scripts use read-only mode:

```lua
local fh = io.open(target, "rb")  -- "rb" = read-only binary mode
```

No write operations (`"w"`, `"a"`, etc.) are used anywhere in the code.

### 5. Internal Location Isolation

Internal file-serving locations are marked as `internal`, meaning they cannot be accessed directly by external clients - only via nginx internal redirects from authenticated requests.

## Verification

### Check Read-Only Mount

```bash
docker exec nginx ls -ld /data
# Should show read-only if mounted correctly

docker exec nginx touch /data/test.txt
# Should fail with "Read-only file system" error
```

### Test HTTP Methods

```bash
# GET - should work
curl -X GET https://localhost:443/files/user/file.txt -k

# POST - should fail with 405 Method Not Allowed
curl -X POST https://localhost:443/files/user/file.txt -k

# PUT - should fail with 405 Method Not Allowed
curl -X PUT https://localhost:443/files/user/file.txt -k

# DELETE - should fail with 405 Method Not Allowed
curl -X DELETE https://localhost:443/files/user/file.txt -k
```

## Security Layers

The read-only protection uses multiple layers (defense in depth):

1. **Filesystem Level**: Docker read-only mount (kernel-level protection)
2. **HTTP Level**: Method restrictions in nginx configuration
3. **Application Level**: Lua scripts only use read operations
4. **Network Level**: Only specific paths are accessible

## Important Notes

- **File Management**: Files must be added/removed/modified outside the container by mounting files into `./shared/` directory on the host
- **No Upload Endpoint**: There is no endpoint for uploading files - this service is download-only
- **Read-Only by Design**: This is intentional - the service is designed solely for secure file downloads, not file management

## Production Considerations

For production environments, consider:

1. **File Permissions**: Ensure files in `./shared/` have appropriate permissions on the host
2. **SELinux/AppArmor**: Use security contexts to further restrict container capabilities
3. **Audit Logging**: Monitor all file access attempts
4. **Network Isolation**: Ensure the service is only accessible to authorized clients
5. **Regular Audits**: Periodically verify that no write capabilities have been accidentally added

