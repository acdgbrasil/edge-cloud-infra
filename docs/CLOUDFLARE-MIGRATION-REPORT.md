# Relatório de Migração: Cloudflare + Purelymail

**Data de execução:** 7-8 de abril de 2026
**Executor:** Gabriel Aderaldo + Claude Code
**Duração:** ~2 horas (sessão única)
**Status:** 5 de 6 fases completas

---

## 1. Contexto e Motivação

A ACDG Brasil (Associação Brasileira de Profissionais Atuantes em Doenças Genéticas) opera uma private cloud baseada em K3s rodando num servidor Xeon doméstico. Antes desta migração, toda a infraestrutura dependia de uma cadeia frágil:

```
Internet → VPS Magalu (201.23.14.199) → Caddy (reverse proxy) → Tailscale → K3s (Xeon)
```

### Problemas identificados

| Problema | Impacto | Severidade |
|----------|---------|------------|
| **VPS como ponto único de falha** | Se a VPS cair, todos os serviços ficam offline | Alta |
| **Sem proteção DDoS** | Qualquer ataque derruba a infraestrutura | Alta |
| **Sem WAF** | Vulnerável a ataques de aplicação (SQLi, XSS, etc.) | Alta |
| **Admin panels expostos** | Zitadel console e Nextcloud acessíveis sem camada extra de autenticação | Média |
| **Stalwart Mail Server instável** | ACME nunca funcionou, HAProxy complexo, relay problemático | Alta |
| **Sem backup offsite** | Se o SSD do Xeon morrer, dados de pacientes são perdidos | Crítica |
| **DNS básico (Umbler)** | Sem anycast, sem DNSSEC, sem analytics | Baixa |
| **Site estático no K3s** | tcc-site consome recursos do cluster sem necessidade | Baixa |
| **Custo da VPS: ~R$50/mês** | R$600/ano para um proxy que poderia ser eliminado | Média |

### Decisão

Migrar para Cloudflare (plano Free) para DNS, Tunnel, WAF, Zero Trust e Pages. Substituir Stalwart self-hosted por Purelymail (~R$45/ano). Objetivo final: eliminar a dependência da VPS e ganhar proteção enterprise-grade a custo zero.

### Por que Cloudflare?

- **Plano Free robusto:** DNS anycast, Tunnel, WAF, DDoS, Zero Trust (até 50 users), Pages — tudo gratuito
- **Tunnel elimina portas expostas:** conexão outbound-only do K3s para Cloudflare, sem portas abertas na internet
- **PoPs no Brasil:** São Paulo, Rio de Janeiro, Curitiba, Porto Alegre — latência mínima
- **Não é lock-in:** DNS é padrão (portátil), Tunnel é substituível por Caddy/nginx, R2 é S3-compatible

### Por que Purelymail ao invés de manter Stalwart?

- Stalwart nunca funcionou de verdade: ACME falhava, HAProxy era complexo, relay dava problemas
- Purelymail custa ~R$45/ano e elimina toda a complexidade de email self-hosted
- Email não é core business da ACDG — não faz sentido gastar tempo operando um mail server
- Suporta domínio próprio com DKIM, SPF, DMARC completos

---

## 2. Arquitetura: Antes vs Depois

### ANTES

```
Internet
    │
    ▼
[VPS Magalu — 201.23.14.199]
    ├── Caddy (reverse proxy HTTPS)
    │   └── Tailscale WireGuard → K3s Traefik
    ├── HAProxy (TCP proxy)
    │   ├── SMTP  (25)  → Stalwart NodePort 30208
    │   ├── SMTPS (465) → Stalwart NodePort 32286
    │   ├── Sub   (587) → Stalwart NodePort 31420
    │   └── IMAPS (993) → Stalwart NodePort 32078
    │
[DNS Umbler — sem anycast, sem DNSSEC]
    ├── *.acdgbrasil.com.br → 201.23.14.199
    ├── mail                → 201.23.14.199
    └── MX                  → mail.acdgbrasil.com.br
    │
[K3s Cluster — Xeon]
    ├── social-care (prod + hml)
    ├── Zitadel
    ├── Nextcloud
    ├── NATS JetStream
    ├── tcc-site (nginx + ConfigMap)
    ├── Stalwart Mail (namespace mail)
    ├── PostgreSQL (social_care, zitadel, stalwart)
    └── Sem proteção DDoS/WAF
```

### DEPOIS

```
Internet
    │
    ▼
[Cloudflare Edge — PoPs BR: SP/RJ/CWB/POA]
    ├── DNS Anycast + DNSSEC
    ├── DDoS L3/L4/L7 mitigation
    ├── WAF (managed rules, free tier)
    ├── CDN (cache respostas estáticas)
    ├── Zero Trust Access (SSO via Zitadel)
    │   ├── cloud.acdgbrasil.com.br → exige login
    │   └── auth.acdgbrasil.com.br/ui/console → exige login
    ├── TLS termination (Edge Certificate)
    │
    │ Cloudflare Tunnel (outbound-only, zero portas expostas)
    ▼
[K3s Cluster — Xeon]
    ├── cloudflared (2 replicas, namespace cloudflare-system)
    ├── Traefik Ingress Controller
    ├── social-care (prod + hml)
    ├── Zitadel
    ├── Nextcloud
    ├── NATS JetStream
    ├── PostgreSQL (social_care, zitadel)
    └── ❌ Stalwart REMOVIDO
    └── ❌ tcc-site REMOVIDO

[Cloudflare Pages — CDN global]
    └── tcc.acdgbrasil.com.br (site estático)

[Purelymail — externo]
    ├── admin@acdgbrasil.com.br
    ├── contato@acdgbrasil.com.br
    └── MX → mailserver.purelymail.com

[VPS Magalu — DESLIGADA]
    └── Sem tráfego, sem uso, pode ser cancelada
```

---

## 3. Fases Executadas

### Fase 1 — DNS Cloudflare

**O que foi feito:**
1. Criada conta Cloudflare (Free plan) para `acdgbrasil.com.br`
2. Registros DNS da Umbler exportados e analisados (21 registros)
3. Limpeza: removidos registros obsoletos (financeiro, hub-core, acme-challenge — serviços inativos)
4. Corrigido apex (`@`): removido IP da VPS que competia com Framer via round-robin
5. Registros recriados no Cloudflare via importação de zone file
6. Nameservers trocados na Umbler: `ns*.umbler.*` → `konnor.ns.cloudflare.com` + `luciana.ns.cloudflare.com`
7. Propagação validada via `dig` em múltiplos resolvers

**Por que:**
- DNS da Umbler era básico: sem anycast (resolução lenta fora do BR), sem DNSSEC, sem analytics
- Cloudflare DNS é o foundation de todos os outros serviços (Tunnel, Pages, Zero Trust dependem dele)
- Anycast garante resolução rápida de qualquer PoP global

**Registros DNS finais (20):**

| Tipo | Nome | Destino | Proxy |
|------|------|---------|-------|
| A | `@` | `31.43.160.6` (Framer) | Proxied |
| A | `@` | `31.43.161.6` (Framer) | Proxied |
| CNAME | `www` | `sites.framer.app` | Proxied |
| CNAME | `educa` | `sites.framer.app` | Proxied |
| CNAME | `social-care` | `baea09ba-...cfargotunnel.com` | Proxied |
| CNAME | `social-care-hml` | `baea09ba-...cfargotunnel.com` | Proxied |
| CNAME | `auth` | `baea09ba-...cfargotunnel.com` | Proxied |
| CNAME | `cloud` | `baea09ba-...cfargotunnel.com` | Proxied |
| CNAME | `tcc` | `tcc-site-e4d.pages.dev` | Proxied |
| CNAME | `purelymail1._domainkey` | `key1.dkimroot.purelymail.com` | DNS-only |
| CNAME | `purelymail2._domainkey` | `key2.dkimroot.purelymail.com` | DNS-only |
| CNAME | `purelymail3._domainkey` | `key3.dkimroot.purelymail.com` | DNS-only |
| CNAME | `_dmarc` | `dmarcroot.purelymail.com` | DNS-only |
| MX | `@` | `mailserver.purelymail.com` (pri 50) | DNS-only |
| MX | `send` | `feedback-smtp.sa-east-1.amazonses.com` (pri 10) | DNS-only |
| TXT | `@` | `v=spf1 include:_spf.purelymail.com ~all` | DNS-only |
| TXT | `@` | `purelymail_ownership_proof=...` | DNS-only |
| TXT | `resend._domainkey` | DKIM key Resend | DNS-only |
| TXT | `send` | `v=spf1 include:amazonses.com ~all` | DNS-only |

**Rollback:** trocar NS de volta para Umbler (~5 minutos).

---

### Fase 2 — Cloudflare Tunnel

**O que foi feito:**
1. Zero Trust ativado na conta Cloudflare (team: `acdgbrasil`, Free plan, 50 licenças)
2. Tunnel `acdg-edge` criado via dashboard
3. Namespace `cloudflare-system` criado no K3s
4. Secret `cloudflared-token` criado com o token do tunnel
5. Manifest `apps/cloudflared.yaml` criado e aplicado: Deployment com 2 replicas, liveness probe, resource limits
6. Ingress routes configuradas via API (5 hostnames → Traefik)
7. DNS atualizado: wildcard A record removido, CNAMEs individuais para o tunnel criados
8. Todos os subdomínios validados via `curl`

**Por que:**
- Elimina a VPS como intermediário: tráfego vai direto do Cloudflare Edge para o K3s
- Zero portas expostas na internet: cloudflared faz conexão outbound-only
- DDoS e WAF ativados automaticamente no tráfego proxied
- 2 replicas garantem HA: se um pod cair, o outro mantém o tunnel ativo
- Latência igual ou menor que o caminho anterior (VPS → Tailscale → K3s)

**Manifest criado:** `edge-cloud-infra/apps/cloudflared.yaml`

```yaml
# Deployment: 2 replicas, imagem cloudflare/cloudflared:2025.4.0
# Token via Secret (cloudflared-token)
# Métricas em :2000, liveness probe em /ready
# Resources: 50m-100m CPU, 64Mi-128Mi RAM
# nodeSelector: hardware-type: high-performance
```

**Rotas do tunnel:**

| Hostname | Serviço |
|----------|---------|
| `social-care.acdgbrasil.com.br` | `http://traefik.kube-system.svc.cluster.local:80` |
| `social-care-hml.acdgbrasil.com.br` | `http://traefik.kube-system.svc.cluster.local:80` |
| `auth.acdgbrasil.com.br` | `http://traefik.kube-system.svc.cluster.local:80` |
| `cloud.acdgbrasil.com.br` | `http://traefik.kube-system.svc.cluster.local:80` |
| catch-all | `http_status:404` |

**Validação:**

| Subdomínio | HTTP Status | Significado |
|------------|-------------|-------------|
| social-care | 401 | Correto — exige JWT |
| social-care-hml | 401 | Correto — exige JWT |
| auth | 302 | Correto — redirect Zitadel |
| tcc | 200 | Correto — site estático |
| cloud | 200 | Correto — Nextcloud |

**Rollback:** trocar CNAMEs de volta para A records apontando para VPS (~5 minutos).

---

### Fase 3 — Purelymail (substituição do Stalwart)

**O que foi feito:**
1. Código de ownership obtido via API Purelymail (`getOwnershipCode`)
2. TXT de ownership adicionado no Cloudflare DNS via API
3. Registros de email antigos (Stalwart) removidos via API: MX apex, SPF, 2x DKIM TXT, DMARC TXT
4. Novos registros Purelymail criados via API: MX, SPF, 3x DKIM CNAMEs, DMARC CNAME
5. Domínio `acdgbrasil.com.br` adicionado ao Purelymail via API (`addDomain`)
6. Contas de email criadas via API (`createUser`): `admin@` e `contato@`
7. Namespace `mail` deletada inteiramente do K3s (Stalwart, postgres-stalwart, snappymail, secrets, PVCs)
8. Registro DNS `mail` A record removido (não há mais mail server self-hosted)

**Por que:**
- **Stalwart nunca funcionou direito:** ACME para TLS falhava constantemente, HAProxy na VPS era complexo (4 portas TCP), relay de email era instável
- **Complexidade operacional desproporcional:** manter um mail server exige monitoramento de deliverability, blacklists, DKIM rotation, storage — para 2 caixas de email
- **Email não é core da ACDG:** a organização cuida de pacientes com doenças genéticas, não deveria gastar tempo operando infraestrutura de email
- **Purelymail é simples e barato:** ~R$45/ano, DKIM/SPF/DMARC gerenciados, webmail incluso, suporte a domínio próprio
- **Liberou recursos do K3s:** Stalwart + PostgreSQL dedicado + SnappyMail consumiam CPU, RAM e 5Gi de storage

**Recursos removidos do K3s:**
- `deployment/stalwart`
- `statefulset/postgres-stalwart`
- `deployment/snappymail`
- `service/stalwart`, `service/stalwart-mail`, `service/postgres-stalwart`, `service/snappymail`
- `pvc/postgres-stalwart-storage` (5Gi liberados)
- `cronjob/acme-cert-renew`
- Secrets: `stalwart-admin-credentials`, `stalwart-db-credentials`, `stalwart-dkim-key`, `stalwart-tls-cert`, `stalwart-cf-credentials`, `mailu-tls-cert`, `resend-credentials`, `bw-auth-token`

**Rollback:** recriar namespace mail, redeploy Stalwart, restaurar DNS antigos. Complexo mas possível.

---

### Fase 4 — Zero Trust Access

**O que foi feito:**
1. Zitadel configurado como Identity Provider OIDC no Cloudflare Zero Trust
2. App "Cloudflare Access" criada no Zitadel (tipo Web, confidencial)
   - Redirect URI: `https://acdgbrasil.cloudflareaccess.com/cdn-cgi/access/callback`
   - Configurado: "Include user's profile info in ID Token" + "User roles inside ID Token"
3. Access Application criada para `cloud.acdgbrasil.com.br` (Nextcloud) — exige login
4. Access Application criada para `auth.acdgbrasil.com.br/ui/console` (Zitadel Console) — exige login
5. Endpoints OIDC do Zitadel (`/oauth/*`, `/.well-known/*`) permanecem acessíveis (path-based, só `/ui/console` é protegido)
6. APIs do social-care continuam com autenticação própria (JWT + JWKS) — bypass no Zero Trust

**Por que:**
- **Admin panels estavam expostos:** qualquer pessoa podia acessar o Zitadel console e o Nextcloud diretamente, dependendo apenas da autenticação do próprio serviço
- **Defesa em profundidade:** agora há duas camadas de autenticação — primeiro Cloudflare Access (SSO), depois a autenticação nativa do serviço
- **Ataques de força bruta bloqueados na edge:** tentativas de brute force no login do Zitadel/Nextcloud são interceptadas pela Cloudflare antes de chegar ao K3s
- **Zero custo:** Free plan suporta até 50 usuários, mais que suficiente para a ACDG

**Observação sobre chicken-and-egg:** a proteção do Zitadel console foi temporariamente removida para criar a app OIDC no próprio Zitadel, e reativada logo em seguida.

**Rollback:** deletar Access Applications no dashboard (~1 minuto).

---

### Fase 5 — R2 Backups (ADIADA)

**O que foi planejado:**
- Bucket R2 `acdg-db-backups` para dumps diários do PostgreSQL
- CronJob no K3s rodando `pg_dump` → upload para R2 (S3-compatible)
- Lifecycle rule: expirar objetos com mais de 30 dias
- Custo estimado: ~R$0,85/mês para 10 GiB

**Por que foi adiado:**
- R2 precisa ser ativado manualmente no dashboard da Cloudflare antes de usar via API
- Será implementado na próxima sessão

---

### Fase 6 — Cloudflare Pages (tcc-site)

**O que foi feito:**
1. Projeto `tcc-site` criado no Cloudflare Pages via API
2. HTML do site (placeholder) extraído do ConfigMap `tcc-html` no K3s
3. Deploy via `wrangler pages deploy` (direct upload)
4. Custom domain `tcc.acdgbrasil.com.br` adicionado via API
5. DNS atualizado: CNAME `tcc` trocado de tunnel para `tcc-site-e4d.pages.dev`
6. Rota `tcc` removida do tunnel (não precisa mais passar pelo K3s)
7. Deployment, Service e ConfigMap do tcc-site removidos do K3s

**Por que:**
- **Site estático não precisa de cluster Kubernetes:** um placeholder HTML de 363 bytes rodando num pod nginx com ConfigMap é desperdício de recursos
- **CDN global gratuita:** Cloudflare Pages serve o conteúdo de 300+ PoPs mundiais, com cache automático
- **Deploy automático:** quando o conteúdo crescer, pode conectar ao repo `tcc-content` para deploy a cada push
- **Liberou recursos do K3s:** 1 pod, 1 service, 1 configmap a menos

**Rollback:** recriar deployment `tcc-site` no K3s, trocar DNS de volta para tunnel.

---

## 4. Impacto na Infraestrutura

### Recursos removidos do K3s

| Recurso | Namespace | Motivo |
|---------|-----------|--------|
| Stalwart (deployment + service) | mail | Substituído por Purelymail |
| postgres-stalwart (statefulset + PVC 5Gi) | mail | Banco do Stalwart, não é mais necessário |
| SnappyMail (deployment + service) | mail | Webmail do Stalwart, Purelymail tem webmail próprio |
| ACME cert CronJob | mail | Certificado TLS do Stalwart, não é mais necessário |
| 8 secrets (admin, db, dkim, tls, cf, resend, bw, mailu) | mail | Credenciais do Stalwart |
| tcc-site (deployment + service + configmap) | default | Migrado para Cloudflare Pages |
| **Namespace `mail` inteira** | — | Deletada completamente |

### Recursos adicionados ao K3s

| Recurso | Namespace | Finalidade |
|---------|-----------|------------|
| cloudflared (deployment, 2 replicas) | cloudflare-system | Cloudflare Tunnel connector |
| cloudflared-token (secret) | cloudflare-system | Token de autenticação do tunnel |

**Saldo líquido:** -9 recursos, -5Gi storage, -1 namespace. O cluster ficou mais limpo e leve.

### Custos

| Item | Antes | Depois | Delta |
|------|-------|--------|-------|
| VPS Magalu | ~R$50/mês | R$0 (desligada) | **-R$50/mês** |
| Cloudflare (DNS, Tunnel, WAF, Zero Trust, Pages) | — | R$0 (Free plan) | R$0 |
| Purelymail | — | ~R$3,75/mês (~R$45/ano) | +R$3,75/mês |
| **Total** | **~R$50/mês** | **~R$3,75/mês** | **-R$46,25/mês** |

**Economia anual: ~R$555**, com ganhos significativos de segurança e resiliência.

### Segurança

| Aspecto | Antes | Depois |
|---------|-------|--------|
| DDoS | Nenhuma proteção | L3/L4/L7 mitigation (Cloudflare) |
| WAF | Nenhum | Managed rules (OWASP, free tier) |
| Portas expostas | VPS: 80, 443, 25, 465, 587, 993 | Zero (tunnel é outbound-only) |
| Admin panels | Expostos publicamente | Protegidos por SSO (Zero Trust + Zitadel) |
| TLS | Let's Encrypt via Caddy | Cloudflare Edge TLS (auto-renew) |
| DNS | Sem DNSSEC | DNSSEC disponível |
| Email auth | SPF + DKIM (Stalwart, instável) | SPF + DKIM + DMARC (Purelymail, managed) |

---

## 5. Arquitetura DNS Final

```
acdgbrasil.com.br
├── @ (apex)
│   ├── A → 31.43.160.6 (Framer — site institucional)
│   ├── A → 31.43.161.6 (Framer — site institucional)
│   ├── MX → mailserver.purelymail.com (pri 50)
│   ├── TXT → SPF (Purelymail)
│   └── TXT → Purelymail ownership proof
│
├── www → CNAME → sites.framer.app
├── educa → CNAME → sites.framer.app
│
├── social-care → CNAME → tunnel.cfargotunnel.com (proxied)
├── social-care-hml → CNAME → tunnel.cfargotunnel.com (proxied)
├── auth → CNAME → tunnel.cfargotunnel.com (proxied)
├── cloud → CNAME → tunnel.cfargotunnel.com (proxied)
│
├── tcc → CNAME → tcc-site-e4d.pages.dev (proxied)
│
├── purelymail1._domainkey → CNAME → key1.dkimroot.purelymail.com (dns-only)
├── purelymail2._domainkey → CNAME → key2.dkimroot.purelymail.com (dns-only)
├── purelymail3._domainkey → CNAME → key3.dkimroot.purelymail.com (dns-only)
├── _dmarc → CNAME → dmarcroot.purelymail.com (dns-only)
│
├── send → MX → feedback-smtp.sa-east-1.amazonses.com (Resend)
├── send → TXT → SPF (Amazon SES)
└── resend._domainkey → TXT → DKIM key (Resend)
```

---

## 6. Identificadores e Referências

| Recurso | Identificador |
|---------|---------------|
| Cloudflare Account ID | `cd10252cefc27a9426b1ef8ae4698a44` |
| Cloudflare Zone ID | `f953a72a0e775b9a8823000c1b9bde04` |
| Tunnel ID | `baea09ba-b143-4ee9-b124-9b41248c9345` |
| Tunnel name | `acdg-edge` |
| Zero Trust team | `acdgbrasil.cloudflareaccess.com` |
| Zero Trust IdP (Zitadel) | `ff60a8d3-e1c7-4546-9f24-e4e69b64c0b9` |
| Access App: Nextcloud | `3d4b7fee-220e-4e92-9f17-c597ddfa9b4d` |
| Access App: Zitadel Console | `efe14103-c67a-4d09-a3bc-0d28cbd9687e` |
| Pages project | `tcc-site` → `tcc-site-e4d.pages.dev` |
| Zitadel App (Cloudflare Access) | Client ID `367617280390987926` |

**Credenciais sensíveis:** armazenadas em `docs/cloudflare-credentials.yaml` (gitignored) → mover para Bitwarden Secret Manager.

---

## 7. Pendências

| Item | Prioridade | Descrição |
|------|------------|-----------|
| **Trocar senhas Purelymail** | Alta | `admin@` e `contato@` têm senha temporária |
| **Ativar R2** | Média | Ativar no dashboard para criar bucket de backups |
| **CronJob de backup** | Média | pg_dump diário → R2 (Fase 5 do plano original) |
| **Cancelar VPS** | Baixa | Desligada, sem tráfego, pode ser cancelada |
| **DNSSEC** | Baixa | Ativar no dashboard do Cloudflare |
| **Conectar tcc-content ao Pages** | Baixa | Quando o conteúdo crescer, conectar GitHub para deploy automático |
| **Credenciais no Bitwarden** | Alta | Mover `cloudflare-credentials.yaml` para Bitwarden Secret Manager |

---

## 8. Rollback

Cada fase é independente e reversível:

| Fase | Tempo de rollback | Como |
|------|-------------------|------|
| DNS | ~5 min | Trocar NS de volta para Umbler |
| Tunnel | ~5 min | Trocar CNAMEs para A records apontando para VPS |
| Purelymail | ~30 min | Recriar namespace mail, redeploy Stalwart, restaurar DNS |
| Zero Trust | ~1 min | Deletar Access Applications |
| Pages | ~5 min | Recriar tcc-site no K3s, trocar DNS |

---

## 9. Lições Aprendidas

1. **Cloudflare importa DNS com falhas:** 5 registros A/CNAME foram importados vazios. Sempre validar a importação manualmente ou via zone file.

2. **Wildcard + mail = problema:** um wildcard `*` com proxy ON captura `mail.*` e quebra SMTP/IMAP. Registros de mail devem ser explícitos e DNS-only.

3. **Tunnel não cria todos os CNAMEs:** ao configurar rotas via API, nem todos os CNAMEs são criados automaticamente. Validar e criar manualmente os faltantes.

4. **Zero Trust + Zitadel = chicken-and-egg:** proteger o Zitadel console com Zero Trust que usa o próprio Zitadel como IdP requer cuidado — é preciso criar a app OIDC antes de ativar a proteção.

5. **API > Dashboard:** configurar tudo via API foi significativamente mais rápido e auditável. Os tokens criados permitem automação futura.

6. **Purelymail API é simples:** `addDomain` + `createUser` resolvem 90% dos casos. DNS é o único setup manual (feito via Cloudflare API).
