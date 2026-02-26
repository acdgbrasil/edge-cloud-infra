# Gerenciamento de Segredos (Bitwarden Oficial 🔐)

Nossa nuvem utiliza o **Operador Oficial da Bitwarden** para sincronizar segredos.

## Como usar

### Passo 1: Pegar o UUID do Segredo no Bitwarden
No painel do Bitwarden, encontre o segredo desejado e copie o seu **ID (UUID)**.

### Passo 2: Criar o BitwardenSecret no GitHub
Crie um arquivo na pasta `/apps`:

```yaml
apiVersion: k8s.bitwarden.com/v1
kind: BitwardenSecret
metadata:
  name: meu-app-secret
spec:
  organizationId: "d00e0ecf-235b-4168-8367-b35e00dbf84d"
  secretName: nome-do-secret-final
  authToken:
    secretName: bw-auth-token
    secretKey: token
  map:
    - bwSecretId: "COLE-O-UUID-AQUI"
      secretKeyName: nome_da_chave_no_env
```

### Passo 3: Usar no App
No seu Deployment, use:
```yaml
env:
  - name: MINHA_SENHA
    valueFrom:
      secretKeyRef:
        name: nome-do-secret-final
        key: nome_da_chave_no_env
```
