---
title: "Never use :latest image tag — use semver or sha256 digest"
scope: "file"
path: ["**/*.yaml", "**/*.yml"]
severity_min: "critical"
buckets: ["security"]
enabled: true
---

## Instructions

All container image references must use immutable tags: semver (e.g., `v0.6.0`) or sha256 digest (`@sha256:abc123...`). Never `:latest`.

Flag:
- `image:` fields ending with `:latest`
- `image:` fields with no tag at all (defaults to latest)
- `tag: latest` in HelmRelease values

Allowed:
- `image: ghcr.io/acdgbrasil/svc-social-care:v0.6.0`
- `image: ghcr.io/acdgbrasil/svc-social-care@sha256:abc123...`

## Examples

### Bad example
```yaml
spec:
  containers:
    - name: social-care
      image: ghcr.io/acdgbrasil/svc-social-care:latest
```

### Good example
```yaml
spec:
  containers:
    - name: social-care
      image: ghcr.io/acdgbrasil/svc-social-care:v0.6.0
```
