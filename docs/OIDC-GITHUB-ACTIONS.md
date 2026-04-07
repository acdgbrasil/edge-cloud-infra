# OIDC Keyless Authentication — GitHub Actions → K3s

## Overview

Permite que GitHub Actions autentique no cluster K3s sem armazenar kubeconfig/tokens como secrets. O runner recebe um token OIDC temporário que o API server do K3s valida diretamente com o GitHub.

## Por que

- Elimina secrets estáticos de longa duração (kubeconfig, service account tokens)
- Token OIDC expira em minutos (não horas/dias)
- Audit trail nativo — cada token identifica o repo, branch, workflow e actor
- Princípio de menor privilégio — RBAC por repo/branch

## Setup

### Opção 1: Script automatizado (recomendado)

No master-xeon, na raiz do repo:

```bash
sudo bash scripts/setup-oidc.sh
```

O script:
1. Adiciona OIDC flags ao K3s config (`/etc/rancher/k3s/config.yaml`)
2. Reinicia K3s
3. Aplica RBAC (`clusters/master-xeon/rbac-github-actions.yaml`)

### Opção 2: Manual

#### 1. Editar `/etc/rancher/k3s/config.yaml`

```yaml
kube-apiserver-arg:
  - "--oidc-issuer-url=https://token.actions.githubusercontent.com"
  - "--oidc-client-id=sts.amazonaws.com"
  - "--oidc-username-claim=sub"
  - "--oidc-groups-claim=repository"
```

#### 2. Reiniciar K3s

```bash
sudo systemctl restart k3s
```

#### 3. Aplicar RBAC

```bash
kubectl apply -f clusters/master-xeon/rbac-github-actions.yaml
```

## Arquivos

| Arquivo | O que faz |
|---|---|
| `clusters/master-xeon/rbac-github-actions.yaml` | ClusterRole (readonly) + bindings para org acdgbrasil |
| `scripts/setup-oidc.sh` | Script de setup automatizado |
| `.github/workflows/smoke-test.yml` | Smoke test com modo `http` e `kubectl` |

## RBAC — Permissões concedidas

O ClusterRole `github-actions-readonly` permite:
- **Pods**: get, list, logs
- **Deployments/StatefulSets/ReplicaSets**: get, list
- **Services/Endpoints/Events**: get, list
- **Flux Kustomizations/HelmReleases**: get, list
- **Git/Helm Repositories (Flux)**: get, list

Nenhuma permissão de escrita. Apenas leitura.

## Uso no Smoke Test

O workflow `smoke-test.yml` tem dois modos:

### HTTP (padrão, sem OIDC)
```
Actions → Run workflow → mode: http
```
Curl nos endpoints públicos `/health`. Funciona sem setup OIDC.

### Kubectl (requer OIDC)
```
Actions → Run workflow → mode: kubectl
```
Conecta via OIDC ao K3s API server e verifica:
- Status de todos os deployments
- Pods não-Running ou com restarts
- Flux reconciliation status
- Resource usage (se metrics-server estiver ativo)

## Verificação

Após rodar `setup-oidc.sh`, teste com:

```bash
# No GitHub: Actions → smoke-test → Run workflow → mode: kubectl
# Ou via CLI:
gh workflow run smoke-test.yml -f mode=kubectl -f environment=prod --repo acdgbrasil/edge-cloud-infra
```
