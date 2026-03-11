# Setup do Ambiente de Homologação (social-care-hml)

Roteiro passo a passo para provisionar o ambiente de homologação para testes de integração.

## Pré-requisitos

- Acesso admin ao Zitadel (auth.acdgbrasil.com.br)
- Acesso ao Bitwarden Secret Manager (organização ACDG)
- Acesso SSH ao VPS Gateway (Caddy)
- Acesso ao cluster K3s (kubectl)

---

## 1. Zitadel — Service Account para Testes

### 1.1 Criar Machine User

1. Acessar https://auth.acdgbrasil.com.br/ui/console
2. Ir em **Users → Service Users → New**
3. Configurar:
   - **Username:** `svc-social-care-integration-tests`
   - **Name:** Social Care Integration Tests
   - **Access Token Type:** JWT

### 1.2 Criar Application (API)

1. Ir em **Projects** → selecionar o projeto do social-care (ou criar um)
2. **New Application:**
   - **Name:** `social-care-integration-tests`
   - **Type:** API
   - **Auth Method:** `CLIENT_SECRET_BASIC` (client_credentials)
3. Anotar o `client_id` e `client_secret` gerados

### 1.3 Atribuir Role

1. No projeto, ir em **Authorizations → New**
2. Selecionar o user `svc-social-care-integration-tests`
3. Atribuir role: `social_worker`

### 1.4 Testar Token

```bash
curl -X POST https://auth.acdgbrasil.com.br/oauth/v2/token \
  -u "<client_id>:<client_secret>" \
  -d "grant_type=client_credentials" \
  -d "scope=openid profile"
```

Deve retornar um `access_token` JWT válido.

---

## 2. Bitwarden — Secret para PostgreSQL HML

### 2.1 Criar Secret

1. No Bitwarden Secret Manager, criar novo secret:
   - **Name:** `SC_HML_DB_PASSWORD`
   - **Value:** gerar senha segura (mínimo 32 chars)
   - **Project:** ACDG (ou criar sub-projeto HML)
2. Copiar o **UUID** do secret criado

### 2.2 Atualizar Manifest

No arquivo `apps/social-care-hml.yaml`, substituir:
```yaml
bwSecretId: "SUBSTITUIR_PELO_ID_DO_SECRET_HML"
```
pelo UUID real do secret criado no passo anterior.

---

## 3. Caddy — Reverse Proxy (VPS Gateway)

Adicionar o bloco abaixo no Caddyfile do VPS Gateway:

```caddyfile
social-care-hml.acdgbrasil.com.br {
    reverse_proxy <TAILSCALE_IP_XEON>:80 {
        header_up Host {host}
    }
}
```

> O Caddy gera automaticamente o certificado TLS via Let's Encrypt.

Recarregar: `sudo systemctl reload caddy`

---

## 4. DNS

Criar registro A no provedor DNS:

```
social-care-hml.acdgbrasil.com.br → <IP_PUBLICO_VPS>
```

(Mesmo IP público do VPS Gateway usado pelos outros subdomínios)

---

## 5. Deploy via FluxCD

O manifest `apps/social-care-hml.yaml` já está no repositório. O Flux sincroniza automaticamente a cada 1 minuto.

Após o commit/merge em `main` do `edge-cloud-infra`:

```bash
# Verificar se o Flux sincronizou
flux get kustomizations

# Verificar pods
kubectl get pods -l app=social-care-hml
kubectl get pods -l app=postgres-hml

# Verificar ingress
kubectl get ingress social-care-hml-ingress

# Logs do serviço
kubectl logs -l app=social-care-hml -f
```

---

## 6. Validação

```bash
# Health check
curl https://social-care-hml.acdgbrasil.com.br/health

# Token via client_credentials
TOKEN=$(curl -s -X POST https://auth.acdgbrasil.com.br/oauth/v2/token \
  -u "<client_id>:<client_secret>" \
  -d "grant_type=client_credentials" \
  -d "scope=openid profile" | jq -r '.access_token')

# Testar endpoint autenticado
curl -H "Authorization: Bearer $TOKEN" \
     -H "X-Actor-Id: svc-integration-tests" \
     https://social-care-hml.acdgbrasil.com.br/v1/patients
```

---

## 7. GitHub Actions — Secrets

Adicionar no repositório `acdg` (Settings → Secrets → Actions):

| Secret | Valor |
|--------|-------|
| `SOCIAL_CARE_HML_URL` | `https://social-care-hml.acdgbrasil.com.br` |
| `ZITADEL_HML_CLIENT_ID` | `<client_id do service account>` |
| `ZITADEL_HML_CLIENT_SECRET` | `<client_secret do service account>` |
| `ZITADEL_TOKEN_URL` | `https://auth.acdgbrasil.com.br/oauth/v2/token` |

---

## 8. CronJob de Reset (Automático)

O banco HML é resetado automaticamente todo **domingo às 03:00 UTC** via CronJob (`social-care-hml-db-reset`). As migrations rodam automaticamente quando o serviço reinicia.

Para reset manual:

```bash
kubectl create job --from=cronjob/social-care-hml-db-reset manual-reset
```

---

## Checklist

- [ ] Criar Machine User no Zitadel (`svc-social-care-integration-tests`)
- [ ] Criar Application API com client_credentials
- [ ] Atribuir role `social_worker` ao service account
- [ ] Testar client_credentials grant → JWT válido
- [ ] Criar secret `SC_HML_DB_PASSWORD` no Bitwarden
- [ ] Atualizar `bwSecretId` em `social-care-hml.yaml`
- [ ] Adicionar entrada DNS `social-care-hml.acdgbrasil.com.br`
- [ ] Adicionar bloco no Caddyfile do VPS Gateway
- [ ] Commit + push em `edge-cloud-infra` (main)
- [ ] Verificar Flux sync + pods running
- [ ] `GET /health` → 200 OK
- [ ] Token endpoint → JWT válido com role `social_worker`
- [ ] Adicionar secrets no GitHub Actions
- [ ] Entregar ao frontend: URL + client_id + client_secret + token_url
