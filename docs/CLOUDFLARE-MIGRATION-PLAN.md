# Plano: Migrar Private Cloud para Cloudflare

## Contexto

A ACDG opera uma private cloud (K3s no Xeon) com gateway via VPS Umbler (Caddy + HAProxy) e DNS na Umbler. Nao usa nenhum servico Cloudflare. A infraestrutura funciona, mas tem gaps em: DDoS protection, WAF, CDN, backup offsite, e protecao de paineis admin. Alem disso, a VPS e um ponto de falha unico e um custo mensal desnecessario.

**Objetivo:** Integrar servicos gratuitos/baratos da Cloudflare para melhorar seguranca, performance e resiliencia — potencialmente eliminando a VPS.

---

## Estado Atual vs Proposto

| Aspecto | Atual | Proposto (Cloudflare) |
|---------|-------|-----------------------|
| **DNS** | Umbler (basico, sem anycast) | Cloudflare DNS (anycast, PoPs em SP/RJ/CWB/POA) — **gratis** |
| **Gateway HTTP** | VPS → Caddy → Tailscale → K3s | Cloudflare Tunnel (cloudflared no K3s) → direto ao Traefik — **gratis** |
| **TLS** | Let's Encrypt via Caddy | Cloudflare Edge TLS + Origin CA (15 anos) — **gratis** |
| **DDoS** | Nenhum | Cloudflare L3/L4/L7 DDoS mitigation — **gratis** |
| **WAF** | Nenhum | Cloudflare WAF (managed rules free tier) — **gratis** |
| **CDN** | Nenhum | Cloudflare CDN (cache de respostas estaticas) — **gratis** |
| **Admin panels** | Expostos publicamente | Cloudflare Zero Trust Access (SSO via Zitadel) — **gratis <50 users** |
| **Backup offsite** | Nenhum | Cloudflare R2 (PostgreSQL dumps) — **~R$ 0,85/mes p/ 10 GiB** |
| **Site estatico** | nginx no K3s (tcc-site) | Cloudflare Pages (deploy do GitHub) — **gratis** |
| **E-mail routing** | VPS HAProxy → Stalwart | Manter VPS so para mail OU IP publico no ISP — **ver Fase 5** |

---

## Fases de Implementacao

### Fase 1 — DNS (Cloudflare como autoritativo)
**Risco: baixo | Impacto: alto | Custo: R$ 0**

1. Criar conta Cloudflare e adicionar dominio `acdgbrasil.com.br`
2. Cloudflare importa registros DNS automaticamente
3. Revisar/ajustar registros importados:
   - `*.acdgbrasil.com.br` → A record `201.23.14.199` (proxy OFF inicialmente)
   - `mail.acdgbrasil.com.br` → A record `201.23.14.199` (proxy OFF — mail precisa DNS-only)
   - MX, SPF, DKIM, DMARC — manter como estao
4. Alterar nameservers na Umbler (registrar) para os da Cloudflare
5. Aguardar propagacao (ate 24h)
6. **Validar:** todos os subdominios resolvem corretamente

**Beneficios imediatos:** Anycast DNS (latencia menor), DNSSEC gratuito, dashboard de analytics DNS.

---

### Fase 2 — Cloudflare Tunnel (eliminar Caddy da VPS)
**Risco: medio | Impacto: muito alto | Custo: R$ 0**

1. Instalar `cloudflared` como Deployment no K3s (namespace `cloudflare-system`)
2. Criar tunnel via dashboard ou CLI:
   ```bash
   cloudflared tunnel create acdg-edge
   ```
3. Configurar ingress rules no ConfigMap do cloudflared:
   ```yaml
   tunnel: <TUNNEL_ID>
   ingress:
     - hostname: social-care.acdgbrasil.com.br
       service: http://traefik.kube-system.svc.cluster.local:80
     - hostname: social-care-hml.acdgbrasil.com.br
       service: http://traefik.kube-system.svc.cluster.local:80
     - hostname: auth.acdgbrasil.com.br
       service: http://traefik.kube-system.svc.cluster.local:80
     - hostname: tcc.acdgbrasil.com.br
       service: http://traefik.kube-system.svc.cluster.local:80
     - hostname: cloud.acdgbrasil.com.br
       service: http://traefik.kube-system.svc.cluster.local:80
     - service: http_status:404
   ```
4. No Cloudflare DNS, trocar A records por CNAME apontando para `<TUNNEL_ID>.cfargotunnel.com` (proxy ON — nuvem laranja)
5. **Manter** `mail.acdgbrasil.com.br` como A record → VPS (proxy OFF — nuvem cinza)
6. Testar cada subdominio HTTPS
7. Apos validacao: desativar Caddy na VPS

**Resultado:** Trafego HTTP nao passa mais pela VPS. O K3s faz conexao outbound para Cloudflare (sem portas expostas). DDoS e WAF ativados automaticamente.

**Manifest K8s para cloudflared:**

```yaml
# edge-cloud-infra/apps/cloudflared.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cloudflare-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared-config
  namespace: cloudflare-system
data:
  config.yaml: |
    tunnel: <TUNNEL_ID>
    credentials-file: /etc/cloudflared/credentials.json
    metrics: 0.0.0.0:2000
    no-autoupdate: true
    ingress:
      - hostname: social-care.acdgbrasil.com.br
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: social-care-hml.acdgbrasil.com.br
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: auth.acdgbrasil.com.br
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: mail.acdgbrasil.com.br
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: tcc.acdgbrasil.com.br
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: cloud.acdgbrasil.com.br
        service: http://traefik.kube-system.svc.cluster.local:80
      - service: http_status:404
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflare-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:latest
          args:
            - tunnel
            - --config
            - /etc/cloudflared/config.yaml
            - run
          volumeMounts:
            - name: config
              mountPath: /etc/cloudflared/config.yaml
              subPath: config.yaml
              readOnly: true
            - name: credentials
              mountPath: /etc/cloudflared/credentials.json
              subPath: credentials.json
              readOnly: true
          livenessProbe:
            httpGet:
              path: /ready
              port: 2000
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              memory: 64Mi
              cpu: 50m
            limits:
              memory: 128Mi
              cpu: 100m
      volumes:
        - name: config
          configMap:
            name: cloudflared-config
        - name: credentials
          secret:
            secretName: cloudflared-credentials
      nodeSelector:
        hardware-type: high-performance
```

> **Nota:** O Secret `cloudflared-credentials` contem o JSON gerado por `cloudflared tunnel create`. Armazenar no Bitwarden e sincronizar via BitwardenSecret.

---

### Fase 3 — Zero Trust Access (proteger admin panels)
**Risco: baixo | Impacto: alto | Custo: R$ 0 (<50 users)**

1. No dashboard Cloudflare Zero Trust, criar Identity Provider → OIDC (Zitadel):
   - Issuer: `https://auth.acdgbrasil.com.br`
   - Client ID/Secret: criar app "Cloudflare Access" no Zitadel (tipo Web)
   - Scopes: `openid profile email`
2. Criar Access Policies:

   | Subdominio/Path | Regra | Roles |
   |-----------------|-------|-------|
   | `auth.acdgbrasil.com.br/ui/console` | Exigir login | `admin` |
   | `mail.acdgbrasil.com.br` (admin web) | Exigir login | `admin` |
   | `cloud.acdgbrasil.com.br` | Exigir login | qualquer |
   | `social-care.acdgbrasil.com.br` | **Bypass** | — (JWT no backend) |
   | `social-care-hml.acdgbrasil.com.br` | **Bypass** | — (JWT no backend) |

3. APIs de social-care continuam com autenticacao propria (JWT + JWKS)

**Resultado:** Paineis admin protegidos por SSO corporativo antes mesmo de chegar ao backend. Ataque de forca bruta no Zitadel console bloqueado na edge da Cloudflare.

**Nota importante sobre auth.acdgbrasil.com.br:**
- O path `/ui/console` deve exigir login
- Os paths `/oauth/*` e `/.well-known/*` devem ser **bypass** (senao o OIDC flow quebra)
- Configurar Access Policy com path matching granular

---

### Fase 4 — R2 para backups de banco
**Risco: baixo | Impacto: medio | Custo: ~R$ 0,85/mes**

1. Criar bucket R2: `acdg-db-backups`
2. Criar API token com permissao de escrita no R2
3. Criar CronJob no K3s:

```yaml
# edge-cloud-infra/apps/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup-r2
  namespace: default
spec:
  schedule: "0 4 * * *"  # Diario, 04:00 UTC
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: postgres:15
              command:
                - /bin/bash
                - -c
                - |
                  set -euo pipefail
                  DATE=$(date +%Y-%m-%d)

                  # Instalar AWS CLI (para R2 S3-compatible)
                  apt-get update -qq && apt-get install -y -qq awscli > /dev/null

                  # Configurar R2
                  export AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY
                  export AWS_SECRET_ACCESS_KEY=$R2_SECRET_KEY
                  export AWS_DEFAULT_REGION=auto

                  # Backup de cada banco
                  for DB_PAIR in "postgres:5432:postgres:social_care" "postgres-zitadel:5432:zitadel:zitadel" "postgres-hml:5432:social_care_hml:social_care_hml" "postgres-stalwart.mail:5432:stalwart:stalwart"; do
                    IFS=':' read -r HOST PORT USER DBNAME <<< "$DB_PAIR"
                    echo "Backing up $DBNAME from $HOST..."
                    PGPASSWORD=$DB_PASSWORD pg_dump -h $HOST -p $PORT -U $USER -d $DBNAME | gzip > /tmp/${DBNAME}_${DATE}.sql.gz
                    aws s3 cp /tmp/${DBNAME}_${DATE}.sql.gz s3://acdg-db-backups/${DBNAME}/${DATE}.sql.gz --endpoint-url $R2_ENDPOINT
                    rm /tmp/${DBNAME}_${DATE}.sql.gz
                  done

                  echo "All backups completed successfully"
              env:
                - name: R2_ACCESS_KEY
                  valueFrom:
                    secretKeyRef:
                      name: r2-credentials
                      key: access-key
                - name: R2_SECRET_KEY
                  valueFrom:
                    secretKeyRef:
                      name: r2-credentials
                      key: secret-key
                - name: R2_ENDPOINT
                  value: "https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
                - name: DB_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: postgres-credentials
                      key: password
          nodeSelector:
            hardware-type: high-performance
```

4. Armazenar credenciais R2 no Bitwarden → BitwardenSecret `r2-credentials`
5. Configurar lifecycle rule no R2: expirar objetos com mais de 30 dias

**Resultado:** Backup offsite diario. Se o SSD do Xeon morrer, dados recuperaveis do R2. Egress do R2 e gratis (diferente do S3).

> **Nota:** O CronJob acima e um ponto de partida. Na pratica, cada banco tem credenciais diferentes (secrets separados). Ajustar as env vars conforme a arquitetura de secrets atual (BitwardenSecret por banco).

---

### Fase 5 — Decisao sobre mail (VPS vs IP publico)
**Risco: medio | Impacto: medio**

Cloudflare Tunnel **nao suporta** proxying de SMTP/IMAP para clientes genericos (Outlook, Thunderbird, etc.). Opcoes:

#### Opcao A: Manter VPS so para mail (~R$ 15-30/mes)
- Desligar Caddy (nao e mais necessario)
- Manter apenas HAProxy para portas 25, 465, 587, 993
- VPS vira "mail relay" puro
- **Menor mudanca, menor risco**

#### Opcao B: IP publico no ISP do Xeon
- Contratar IP fixo (~R$ 20-40/mes dependendo do ISP)
- HAProxy roda direto no Xeon (ou Stalwart expoe portas diretamente)
- Elimina VPS completamente
- DNS: `mail.acdgbrasil.com.br` → IP do Xeon
- **Cuidado:** expor o Xeon diretamente na internet traz riscos (firewall obrigatorio)

#### Opcao C: Cloudflare Email Routing + Resend (simplificar)
- Cloudflare Email Routing para recebimento (gratis, ate 25 destinatarios)
- Resend para envio (ja configurado como relay)
- Elimina Stalwart recebendo SMTP da internet
- Stalwart vira apenas servidor IMAP interno (acesso via Cloudflare WARP ou Tailscale)
- **Ideal se o volume de e-mail e baixo e nao precisa de IMAP externo**

**Recomendacao:** Opcao A no curto prazo (menor mudanca). Avaliar Opcao C no medio prazo se o volume de e-mail for baixo (<100 emails/dia).

---

### Fase 6 (Opcional) — Cloudflare Pages para sites estaticos
**Risco: nenhum | Impacto: baixo | Custo: R$ 0**

1. Conectar repo `tcc-content` ao Cloudflare Pages via dashboard
2. Configurar build: `output directory: /` (HTML estatico)
3. Custom domain: `tcc.acdgbrasil.com.br`
4. Cloudflare cria CNAME automaticamente no DNS
5. Remover `apps/tcc-site.yaml` do edge-cloud-infra (libera recursos do K3s)

**Resultado:** Site estatico servido pela CDN global da Cloudflare. Build automatico a cada push. Zero recursos consumidos no K3s.

---

## Estimativa de Custo Mensal Pos-Migracao

| Item | Antes | Depois |
|------|-------|--------|
| VPS (Umbler) | ~R$ 50/mes | R$ 15-30/mes (so mail) ou R$ 0 |
| Cloudflare DNS | — | R$ 0 |
| Cloudflare Tunnel | — | R$ 0 |
| Cloudflare WAF/DDoS | — | R$ 0 |
| Cloudflare Zero Trust | — | R$ 0 |
| Cloudflare R2 (10 GiB) | — | ~R$ 0,85/mes |
| Cloudflare Pages | — | R$ 0 |
| **Total delta** | ~R$ 50/mes | **~R$ 1 a R$ 31/mes** |

**Economia anual: R$ 230 a R$ 590**, mais os beneficios de seguranca (DDoS, WAF, Zero Trust) que nao tinham custo equivalente antes.

---

## Arquitetura Proposta

```
Internet (Usuarios / Flutter App / GitHub Actions CI)
    |
[Cloudflare Edge — PoPs em SP/RJ/CWB/POA]
    |-- DNS Anycast + DNSSEC
    |-- DDoS L3/L4/L7 mitigation
    |-- WAF (managed rules, free tier)
    |-- CDN (cache de respostas estaticas)
    |-- Zero Trust Access (admin panels: auth console, mail admin)
    |-- TLS termination (Edge Certificate)
    |
    | (Cloudflare Tunnel — conexao outbound-only, sem portas expostas)
    v
[K3s Cluster — Xeon Master — rede privada]
    |-- cloudflared (2 replicas, HA)
    |-- Traefik Ingress Controller
    |-- social-care v0.8.0 (prod) -----> PostgreSQL (social_care, 10Gi)
    |-- social-care-hml v0.8.0 --------> PostgreSQL (social_care_hml, 2Gi)
    |-- Zitadel IdP --------------------> PostgreSQL (zitadel, 10Gi)
    |-- NATS JetStream 2.10 (event streaming, 5Gi)
    |-- CronJob db-backup-r2 -----------> Cloudflare R2 (acdg-db-backups)
    |-- Bitwarden Operator (secrets sync)
    +-- SSD 1TB

[VPS — apenas mail relay]
    |-- HAProxy (TCP proxy)
    |   |-- SMTP  (25)  --> Stalwart NodePort 30208
    |   |-- SMTPS (465) --> Stalwart NodePort 32286
    |   |-- Sub   (587) --> Stalwart NodePort 31420
    |   +-- IMAPS (993) --> Stalwart NodePort 32078
    |
    v (Tailscale WireGuard — rede overlay privada)
[K3s — namespace mail]
    |-- Stalwart Mail v0.15.5
    +-- PostgreSQL (stalwart, 5Gi)

[Cloudflare R2]
    +-- acdg-db-backups/ (retencao 30 dias, egress gratis)

[Cloudflare Pages]
    +-- tcc.acdgbrasil.com.br (site estatico, CDN global)
```

---

## Ordem de Execucao e Rollback

| Fase | Pre-requisito | Rollback |
|------|---------------|----------|
| 1. DNS | Conta Cloudflare | Trocar NS de volta para Umbler (5min) |
| 2. Tunnel | DNS propagado | Trocar CNAME de volta para A record da VPS (5min) |
| 3. Zero Trust | Tunnel funcionando | Desativar policies no dashboard (1min) |
| 4. R2 Backup | Bucket criado | Desativar CronJob (1min) |
| 5. Mail | Decisao tomada | Manter VPS como esta |
| 6. Pages | Repo conectado | Manter tcc-site no K3s |

**Cada fase e independente** e pode ser revertida sem afetar as demais. A ordem sugerida minimiza risco: DNS primeiro (base), Tunnel depois (maior impacto), Zero Trust em seguida (depende do Tunnel), R2 a qualquer momento.

---

## Arquivos a Criar/Modificar (edge-cloud-infra)

| Acao | Arquivo | Fase |
|------|---------|------|
| **Criar** | `apps/cloudflared.yaml` (Deployment + ConfigMap + Secret) | 2 |
| **Criar** | `apps/backup-cronjob.yaml` (CronJob pg_dump → R2) | 4 |
| **Criar** | `clusters/master-xeon/cloudflare.yaml` (Kustomization para namespace) | 2 |
| **Modificar** | DNS records (no dashboard Cloudflare, nao em YAML) | 1 |
| **Remover** (opcional) | `apps/tcc-site.yaml` | 6 |
| **Criar** | `docs/CLOUDFLARE.md` (runbook de operacao) | 1-6 |

---

## Riscos e Mitigacoes

| Risco | Probabilidade | Mitigacao |
|-------|---------------|-----------|
| Propagacao DNS lenta | Baixa | Reduzir TTL para 300s antes de trocar NS. Aguardar 24h |
| Tunnel cai | Baixa | 2 replicas cloudflared + auto-reconnect nativo. Cloudflare SLA 99.99% |
| Cloudflare free tier muda | Muito baixa | Tunnel/DNS sao core business da CF. Plano gratis existe desde 2014 |
| Zero Trust bloqueia devs | Media | Criar bypass policies por email antes de ativar. Testar com 1 subdominio primeiro |
| E-mail quebra na migracao DNS | Media | `mail.*` sempre DNS-only (nuvem cinza). MX, SPF, DKIM nao mudam |
| Latencia do Tunnel vs Caddy | Baixa | Tunnel usa QUIC/HTTP2, PoP local em SP. Na pratica, latencia similar ou menor |
| Lock-in na Cloudflare | Media | DNS e padrao (portatil). Tunnel e substituivel por Caddy/nginx. R2 e S3-compatible |

---

## Checklist Pre-Migracao

- [ ] Criar conta Cloudflare (email: admin@acdgbrasil.com.br ou equivalente)
- [ ] Documentar TTL atual de todos os registros DNS na Umbler
- [ ] Garantir acesso ao painel da Umbler para trocar nameservers
- [ ] Ter SSH na VPS para desativar Caddy apos Fase 2
- [ ] Criar app "Cloudflare Access" no Zitadel (para Fase 3)
- [ ] Definir politica de retencao de backups (sugestao: 30 dias)
- [ ] Decidir sobre mail (Opcao A, B ou C na Fase 5)
