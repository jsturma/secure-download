vault login root

vault auth enable oidc

vault write identity/oidc/key/mykey \
    algorithm=RS256 \
    verification_ttl=1h \
    rotation_period=24h

vault write identity/oidc/role/myrole \
    key=mykey \
    ttl=30m \
    template='{"sub":"{{identity.entity.name}}","aud":"nginx"}'
