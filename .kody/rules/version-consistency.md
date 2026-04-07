---
title: "Image versions must be consistent across environments"
scope: "pull_request"
severity_min: "high"
buckets: ["architecture"]
enabled: true
---

## Instructions

When bumping an image version, check that the version is consistent across production and HML (homologation) manifests for the same service.

Pattern: `apps/<service>.yaml` (prod) and `apps/<service>-hml.yaml` (HML). HML should have the same or newer version than production.

Flag:
- Production manifest updated but HML not updated (or vice versa) in the same PR
- HML running an older version than production

This is a warning, not a blocker — sometimes intentional. But it should be called out.
