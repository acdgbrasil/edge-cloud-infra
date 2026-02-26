# Gerenciamento de Segredos (Bitwarden 🔐)

Nossa nuvem utiliza o **External Secrets Operator (ESO)** para integrar o Kubernetes diretamente com o **Bitwarden Secrets Manager**. Isso garante que NENHUMA senha seja escrita no GitHub.

## O Fluxo do Segredo
1. Você cria o segredo no painel do **Bitwarden**.
2. O Kubernetes (via ESO) "puxa" esse valor e cria um `Secret` interno.
3. O seu Aplicativo lê esse `Secret` como uma variável de ambiente.

## Como usar em um novo App

### Passo 1: No Bitwarden
Crie um segredo no seu projeto do Bitwarden (ex: chave `MINHA_API_KEY`).

### Passo 2: No GitHub (Infra)
Crie um arquivo `ExternalSecret` na pasta `/apps`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: meu-app-secrets
spec:
  refreshInterval: 1h # Sincroniza a cada 1 hora
  secretStoreRef:
    name: bitwarden-sm
    kind: ClusterSecretStore
  data:
  - secretKey: api_key        # Como o segredo se chamará no K8s
    remoteRef:
      key: MINHA_API_KEY      # Nome exato da chave no Bitwarden
```

### Passo 3: No seu Deployment
Referencie o segredo no seu container:

```yaml
env:
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: meu-app-secrets # Nome do ExternalSecret acima
        key: api_key
```

## Comandos de Debug
Para ver se os segredos estão sincronizando:
```bash
# Ver status da sincronização
kubectl get externalsecret

# Ver se o segredo interno do K8s foi criado
kubectl get secret meu-app-secrets -o yaml
```
