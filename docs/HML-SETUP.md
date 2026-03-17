# Setup do Ambiente de Homologacao (HML)

Roteiro para provisionar o ambiente de homologacao do social-care para testes de integracao.

## Pre-requisitos

- Acesso admin ao Zitadel (`auth.acdgbrasil.com.br`)
- Acesso ao Bitwarden Secret Manager (organizacao ACDG)
- Acesso SSH ao VPS Gateway
- Acesso ao cluster K3s (`kubectl`)

---

## 1. Zitadel — Service Account

### 1.1 Criar Machine User

1. Acessar `https://auth.acdgbrasil.com.br/ui/console`
2. **Users** > **Service Users** > **New**
3. Configurar:
   - **Username:** `svc-social-care-integration-tests`
   - **Name:** Social Care Integration Tests
   - **Access Token Type:** JWT

### 1.2 Criar Application (API)

1. **Projects** > selecionar projeto > **New Application**
2. Configurar:
   - **Name:** `social-care-integration-tests`
   - **Type:** API
   - **Auth Method:** `CLIENT_SECRET_BASIC`
3. Anotar `client_id` e `client_secret`

### 1.3 Atribuir Role

1. No projeto, **Authorizations** > **New**
2. Selecionar `svc-social-care-integration-tests`
3. Atribuir role: `social_worker`

### 1.4 Testar Token

```bash
curl -X POST https://auth.acdgbrasil.com.br/oauth/v2/token \
  -u "<client_id>:<client_secret>" \
  -d "grant_type=client_credentials" \
  -d "scope=openid profile"
```

---

## 2. Bitwarden — Secret do PostgreSQL

### 2.1 Criar Secret

1. No Bitwarden SM, criar secret:
   - **Name:** `SC_HML_DB_PASSWORD`
   - **Value:** senha segura (minimo 32 chars)
2. Copiar o UUID

### 2.2 Atualizar Manifest

Em `apps/social-care-hml.yaml`, substituir o `bwSecretId` pelo UUID real.

---

## 3. Gateway (VPS)

Adicionar no Caddyfile:

```caddy
social-care-hml.acdgbrasil.com.br {
    reverse_proxy 100.77.46.69:80 {
        header_up Host {host}
    }
}
```

```bash
sudo systemctl reload caddy
```

---

## 4. DNS

Criar registro A (se nao coberto pelo wildcard):

```
social-care-hml.acdgbrasil.com.br → 201.23.14.199
```

---

## 5. Deploy via FluxCD

O manifest `apps/social-care-hml.yaml` ja esta no repositorio. Flux sincroniza automaticamente.

```bash
flux get kustomizations                        # Status do sync
kubectl get pods -l app=social-care-hml        # Pods do servico
kubectl get pods -l app=postgres-hml           # Pod do banco
kubectl get ingress social-care-hml-ingress    # Ingress
kubectl logs -l app=social-care-hml -f         # Logs
```

---

## 6. Validacao

```bash
# Health check
curl https://social-care-hml.acdgbrasil.com.br/health

# Obter token
TOKEN=$(curl -s -X POST https://auth.acdgbrasil.com.br/oauth/v2/token \
  -u "<client_id>:<client_secret>" \
  -d "grant_type=client_credentials" \
  -d "scope=openid profile" | jq -r '.access_token')

# Testar endpoint autenticado
curl -H "Authorization: Bearer $TOKEN" \
     -H "X-Actor-Id: svc-integration-tests" \
     https://social-care-hml.acdgbrasil.com.br/api/v1/dominios/dominio_parentesco
```

---

## 7. GitHub Actions — Secrets

Adicionar no repositorio (Settings > Secrets > Actions):

| Secret | Valor |
|--------|-------|
| `SOCIAL_CARE_HML_URL` | `https://social-care-hml.acdgbrasil.com.br` |
| `ZITADEL_HML_CLIENT_ID` | `<client_id>` |
| `ZITADEL_HML_CLIENT_SECRET` | `<client_secret>` |
| `ZITADEL_TOKEN_URL` | `https://auth.acdgbrasil.com.br/oauth/v2/token` |

---

## 8. Reset Automatico

O banco HML e resetado todo **domingo as 03:00 UTC** via CronJob. As migrations rodam automaticamente no restart do servico.

Reset manual:
```bash
kubectl create job --from=cronjob/social-care-hml-db-reset manual-reset
```

---

## Checklist

- [ ] Machine User no Zitadel (`svc-social-care-integration-tests`)
- [ ] Application API com client_credentials
- [ ] Role `social_worker` atribuida
- [ ] Token endpoint retorna JWT valido
- [ ] Secret `SC_HML_DB_PASSWORD` no Bitwarden
- [ ] `bwSecretId` atualizado em `social-care-hml.yaml`
- [ ] DNS `social-care-hml.acdgbrasil.com.br`
- [ ] Caddyfile atualizado no VPS
- [ ] Flux sync + pods running
- [ ] `GET /health` retorna 200
- [ ] Secrets configurados no GitHub Actions
