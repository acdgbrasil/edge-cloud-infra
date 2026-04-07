# OIDC Keyless Authentication — GitHub Actions → K3s

## Overview

Permite que GitHub Actions autentique no cluster K3s sem armazenar kubeconfig/tokens como secrets. O runner recebe um token OIDC temporário que o API server do K3s valida diretamente com o GitHub.

## Por que

- Elimina secrets estáticos de longa duração (kubeconfig, service account tokens)
- Token OIDC expira em minutos (não horas/dias)
- Audit trail nativo — cada token identifica o repo, branch, workflow e actor
- Princípio de menor privilégio — RBAC por repo/branch

## Pré-requisitos

1. K3s com acesso ao API server via Tailscale (já configurado)
2. K3s API server configurado para aceitar OIDC tokens do GitHub

## Configuração no K3s

### 1. Editar configuração do K3s API server

No servidor master, editar `/etc/rancher/k3s/config.yaml`:

```yaml
kube-apiserver-arg:
  - "--oidc-issuer-url=https://token.actions.githubusercontent.com"
  - "--oidc-client-id=sts.amazonaws.com"
  - "--oidc-username-claim=sub"
  - "--oidc-groups-claim=repository"
```

> Nota: `oidc-client-id` usa `sts.amazonaws.com` por convenção (é o audience padrão do GitHub OIDC). Pode ser qualquer string, desde que o workflow use o mesmo `audience`.

### 2. Reiniciar K3s

```bash
sudo systemctl restart k3s
```

### 3. Criar ClusterRole e ClusterRoleBinding

```yaml
# rbac-github-actions.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-actions-readonly
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "endpoints"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-actions-readonly
subjects:
  - kind: User
    name: "repo:acdgbrasil/edge-cloud-infra:ref:refs/heads/main"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: github-actions-readonly
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f rbac-github-actions.yaml
```

### 4. Usar no GitHub Actions workflow

```yaml
permissions:
  id-token: write  # Required for OIDC
  contents: read

steps:
  - name: Get OIDC token
    id: oidc
    uses: actions/github-script@v7
    with:
      script: |
        const token = await core.getIDToken('sts.amazonaws.com');
        core.setOutput('token', token);

  - name: Configure kubectl
    run: |
      kubectl config set-cluster k3s \
        --server=https://<tailscale-ip>:6443 \
        --certificate-authority=/dev/null \
        --insecure-skip-tls-verify=true

      kubectl config set-credentials github-oidc \
        --token="${{ steps.oidc.outputs.token }}"

      kubectl config set-context github \
        --cluster=k3s \
        --user=github-oidc

      kubectl config use-context github

  - name: Health check
    run: |
      kubectl get pods -l app=social-care -o wide
      kubectl get pods -l app=conecta-web -o wide
```

## Status

**Pendente** — requer configuração manual no K3s API server (step 1-3). Após configuração, o smoke-test.yml pode ser atualizado para usar kubectl ao invés de curl externo, verificando pods diretamente no cluster.

## Alternativa atual

O smoke-test.yml usa curl contra os endpoints públicos (/health), que funciona sem OIDC mas não dá visibilidade sobre o estado interno do cluster (pods restartando, OOMKilled, etc).
