---
title: "Pods must have resource requests and limits"
scope: "file"
path: ["apps/**/*.yaml", "apps/**/*.yml"]
severity_min: "high"
buckets: ["security", "performance-and-optimization"]
enabled: true
---

## Instructions

Every container in a Pod/Deployment/StatefulSet must define `resources.requests` and `resources.limits` for both CPU and memory. This prevents resource starvation on the single-node edge hardware.

Flag:
- Containers missing `resources:` block entirely
- `resources:` with only `requests` but no `limits` (or vice versa)
- Missing `cpu` or `memory` in either requests or limits

Exceptions:
- Init containers with trivial workloads
- HelmRelease values where the chart handles defaults

## Examples

### Bad example
```yaml
containers:
  - name: social-care
    image: ghcr.io/acdgbrasil/svc-social-care:v0.6.0
    # No resource limits — can consume all node resources
```

### Good example
```yaml
containers:
  - name: social-care
    image: ghcr.io/acdgbrasil/svc-social-care:v0.6.0
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
```
