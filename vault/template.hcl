{
  "sub": "{{identity.entity.name}}",
  "aud": "{{identity.entity.metadata.download_path}}",
  "iat": {{time.now}},
  "exp": {{time.now + 1800}}
}
