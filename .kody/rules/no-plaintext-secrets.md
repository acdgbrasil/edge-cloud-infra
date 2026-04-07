---
title: "No plaintext secrets in manifests"
scope: "pull_request"
severity_min: "critical"
buckets: ["security"]
enabled: true
---

## Instructions

Scan the PR diff for plaintext secrets in Kubernetes manifests. All secrets must be managed via Bitwarden Secrets Manager or sealed/encrypted.

Flag:
- `kind: Secret` with `data:` containing base64-encoded values (these are trivially decodable)
- `stringData:` with actual secret values
- Hardcoded passwords, tokens, or API keys in any YAML value
- Database connection strings with embedded credentials
- Zitadel master keys or DB credentials in plaintext

Allowed:
- `ExternalSecret` references to Bitwarden
- `secretKeyRef` pointing to externally-managed secrets
- Secret names/references (not values)
- Placeholder examples in comments
