# Servidor de E-mail Self-Hosted (Mailu)

Servidor de e-mail completo rodando na edge cloud (K3s), usando Mailu (Postfix + Dovecot + Rspamd + Roundcube).

**Domínio:** `acdgbrasil.com.br`
**Hostname:** `mail.acdgbrasil.com.br`
**Namespace K8s:** `mail`
**Relay SMTP:** Resend (smtp.resend.com:465) — MagaluCloud não suporta PTR/rDNS

## Topologia de Rede

```
INTERNET
    |
[VPS MagaluCloud] (201.23.14.199)
    |- Caddy :443  → Tailscale → K3s Traefik :80 (HTTPS, webmail/admin)
    |- HAProxy :25  → Tailscale → K3s :25  (SMTP entrada)
    |- HAProxy :587 → Tailscale → K3s :587 (Submission)
    |- HAProxy :465 → Tailscale → K3s :465 (SMTPS)
    |- HAProxy :993 → Tailscale → K3s :993 (IMAPS)
    |
[XEON K3s] (100.77.46.69)
    |- Namespace: mail
    |- Front (nginx) → Admin, Webmail, Postfix, Dovecot, Rspamd
    |- ServiceLB expõe portas de email no IP do nó
    |- hostPath /var/lib/mailu/ para dados persistentes
```

## Fase 1 — Preparação de Rede

### 1.1 PTR/rDNS na MagaluCloud

O registro PTR (reverse DNS) é **essencial** para deliverability. Sem ele, Gmail e Outlook rejeitam e-mails.

- **IP:** `201.23.14.199`
- **PTR deve apontar para:** `mail.acdgbrasil.com.br`
- **Onde configurar:** Painel da MagaluCloud (ou abrir ticket no suporte)

Verificar após configurar:
```bash
dig -x 201.23.14.199 +short
# Esperado: mail.acdgbrasil.com.br.
```

### 1.2 HAProxy na VPS (TCP proxy para portas de e-mail)

O Caddy lida com HTTPS. Para as portas TCP de e-mail, instalar HAProxy na VPS.

**Instalar:**
```bash
sudo apt update && sudo apt install -y haproxy
```

**Configurar** `/etc/haproxy/haproxy.cfg`:
```haproxy
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 10s
    timeout client  300s
    timeout server  300s

# --- SMTP (MTA-to-MTA) ---
frontend ft_smtp
    bind *:25
    default_backend bk_smtp

backend bk_smtp
    server xeon-mail 100.77.46.69:25 check

# --- SMTPS (Submission TLS implícito) ---
frontend ft_smtps
    bind *:465
    default_backend bk_smtps

backend bk_smtps
    server xeon-mail 100.77.46.69:465 check

# --- Submission (STARTTLS) ---
frontend ft_submission
    bind *:587
    default_backend bk_submission

backend bk_submission
    server xeon-mail 100.77.46.69:587 check

# --- IMAPS (IMAP sobre TLS) ---
frontend ft_imaps
    bind *:993
    default_backend bk_imaps

backend bk_imaps
    server xeon-mail 100.77.46.69:993 check
```

**Ativar e iniciar:**
```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
sudo systemctl status haproxy
```

**Verificar portas:**
```bash
ss -tlnp | grep -E ':(25|465|587|993)\b'
```

### 1.3 Caddyfile — Adicionar entrada para webmail/admin

SSH na VPS e editar `/etc/caddy/Caddyfile`:
```caddy
mail.acdgbrasil.com.br {
    reverse_proxy 100.77.46.69:80
}
```

```bash
sudo systemctl reload caddy
```

## Fase 2 — Deploy do Mailu no K3s

### 2.1 Pré-requisitos (executar no Xeon)

```bash
# Criar diretórios de dados
sudo mkdir -p /var/lib/mailu/{data,data/dkim,mail,filter,queue,webmail,overrides}
sudo chmod -R 755 /var/lib/mailu

# Criar namespace
kubectl create namespace mail

# Criar secret key do Mailu (chave de encriptação)
kubectl create secret generic mailu-secret-key -n mail \
  --from-literal=secret-key=$(openssl rand -hex 16)

# Criar senha do admin inicial
kubectl create secret generic mailu-admin-credentials -n mail \
  --from-literal=admin-password='<GERAR-SENHA-FORTE>'
```

### 2.2 Deploy via FluxCD

Os manifests estão em:
- `mail/namespace.yaml` — Namespace
- `mail/mailu.yaml` — Todos os recursos (ConfigMap, Deployments, Services, Ingress)
- `clusters/master-xeon/mail.yaml` — FluxCD Kustomization

Após push para `main`, o FluxCD sincroniza automaticamente (intervalo: 5min).

**Verificar deploy:**
```bash
kubectl get pods -n mail
kubectl get svc -n mail
kubectl logs -n mail deployment/admin --tail=50
kubectl logs -n mail deployment/front --tail=50
```

### 2.3 Verificar portas expostas

```bash
# ServiceLB deve expor portas no IP do nó
kubectl get svc mailu-mail-lb -n mail
# EXTERNAL-IP deve mostrar o IP do nó ou <pending> -> verificar ServiceLB

# Testar SMTP local
echo QUIT | nc -w5 100.77.46.69 25

# Testar da VPS (via Tailscale)
echo QUIT | nc -w5 100.77.46.69 25
```

## Fase 3 — DNS e Autenticação

### 3.1 Registros DNS na Umbler

Criar no painel da Umbler (https://app.umbler.com):

| Tipo | Nome | Valor | TTL |
|------|------|-------|-----|
| A | `mail` | `201.23.14.199` | 3600 |
| MX | `@` (raiz) | `mail.acdgbrasil.com.br` (prioridade 10) | 3600 |
| TXT | `@` (raiz) | `v=spf1 mx a:mail.acdgbrasil.com.br -all` | 3600 |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@acdgbrasil.com.br` | 3600 |

> **Nota:** O registro `A mail` é necessário mesmo com wildcard `*`, pois o MX precisa de um registro A explícito.

### 3.2 Verificar DNS

```bash
dig A mail.acdgbrasil.com.br +short
# Esperado: 201.23.14.199

dig MX acdgbrasil.com.br +short
# Esperado: 10 mail.acdgbrasil.com.br.

dig TXT acdgbrasil.com.br +short
# Esperado: "v=spf1 mx a:mail.acdgbrasil.com.br -all"

dig TXT _dmarc.acdgbrasil.com.br +short
# Esperado: "v=DMARC1; p=none; rua=mailto:dmarc@acdgbrasil.com.br"
```

### 3.3 DKIM

Após o deploy, o Mailu Admin gera as chaves DKIM automaticamente.

1. Acessar `https://mail.acdgbrasil.com.br/admin`
2. Ir em **Mail domains** → `acdgbrasil.com.br` → **Regenerate keys** (se necessário)
3. Copiar a chave pública DKIM exibida
4. Criar registro TXT na Umbler:

| Tipo | Nome | Valor | TTL |
|------|------|-------|-----|
| TXT | `dkim._domainkey` | `v=DKIM1; k=rsa; p=<CHAVE-PUBLICA>` | 3600 |

> O seletor padrão do Mailu é `dkim`. Verificar no admin se é diferente.

**Verificar DKIM:**
```bash
dig TXT dkim._domainkey.acdgbrasil.com.br +short
```

### 3.4 Criar contas de e-mail

Acessar `https://mail.acdgbrasil.com.br/admin`:

1. Fazer login com `admin@acdgbrasil.com.br` e a senha definida em `mailu-admin-credentials`
2. Adicionar domínio `acdgbrasil.com.br` (se não existir)
3. Criar contas:
   - `admin@acdgbrasil.com.br` — Administração geral
   - `noreply@acdgbrasil.com.br` — Notificações do sistema
   - `contato@acdgbrasil.com.br` — Contato institucional
   - `dmarc@acdgbrasil.com.br` — Relatórios DMARC

## Fase 4 — Integração com Zitadel

Configurar o Zitadel para enviar e-mails via Mailu (SMTP interno via Tailscale/K8s).

### 4.1 Configuração SMTP no Zitadel

No console admin do Zitadel (`https://auth.acdgbrasil.com.br/ui/console`):

1. **Settings** → **Notification Settings** → **SMTP**
2. Configurar:
   - **SMTP Host:** `smtp.mail.svc.cluster.local`
   - **SMTP Port:** `587`
   - **TLS:** `STARTTLS`
   - **From Address:** `noreply@acdgbrasil.com.br`
   - **From Name:** `ACDG Brasil`
   - **User:** `noreply@acdgbrasil.com.br`
   - **Password:** (senha da conta noreply criada no Mailu)

> **Nota:** `smtp.mail.svc.cluster.local` é o DNS interno do K8s para o Service `smtp` no namespace `mail`. Se o Zitadel está no namespace `default`, use o FQDN completo.

> **Alternativa:** Se o Zitadel não conseguir resolver o DNS entre namespaces, usar `front.mail.svc.cluster.local:587` (o front faz proxy para o Postfix).

### 4.2 Testar

1. Criar um usuário de teste no Zitadel
2. Usar **Reset Password** para disparar um e-mail
3. Verificar se o e-mail chega na caixa de entrada

## Fase 5 — Hardening e Produção

### 5.1 TLS com cert-manager (substituir certificados auto-assinados)

Instalar cert-manager no cluster:
```bash
# Adicionar repo Helm
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Instalar
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

Criar ClusterIssuer (Let's Encrypt):
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@acdgbrasil.com.br
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: traefik
```

Criar Certificate para o mail:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mail-tls
  namespace: mail
spec:
  secretName: mail-tls-cert
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - mail.acdgbrasil.com.br
```

Após emissão, atualizar o ConfigMap:
```yaml
TLS_FLAVOR: "cert"
```

E montar o Secret `mail-tls-cert` no front:
```yaml
volumeMounts:
- name: tls-certs
  mountPath: /certs
volumes:
- name: tls-certs
  secret:
    secretName: mail-tls-cert
    items:
    - key: tls.crt
      path: cert.pem
    - key: tls.key
      path: key.pem
```

### 5.2 MTA-STS

Publicar política MTA-STS em `https://mta-sts.acdgbrasil.com.br/.well-known/mta-sts.txt`:

```
version: STSv1
mode: testing
mx: mail.acdgbrasil.com.br
max_age: 604800
```

DNS:
| Tipo | Nome | Valor |
|------|------|-------|
| TXT | `_mta-sts` | `v=STSv1; id=20260315` |
| A | `mta-sts` | `201.23.14.199` |

Pode ser servido por um pod nginx simples (similar ao `tcc-site.yaml`) ou pelo Caddy na VPS.

### 5.3 Monitoramento

- **Google Postmaster Tools:** https://postmaster.google.com (registrar domínio)
- **Microsoft SNDS:** https://sendersupport.olc.protection.outlook.com/snds/
- **mail-tester.com:** Enviar e-mail de teste e verificar score (meta: > 8/10)

### 5.4 PROXY Protocol (IPs reais no Rspamd)

Para que o Rspamd tenha acesso aos IPs reais dos remetentes (melhor filtragem de spam):

1. Ativar PROXY protocol no HAProxy (porta 25):
   ```haproxy
   backend bk_smtp
       server xeon-mail 100.77.46.69:25 check send-proxy-v2
   ```

2. Configurar no Mailu (ConfigMap):
   ```yaml
   PROXY_PROTOCOL: "<IP-TAILSCALE-DA-VPS>"
   ```

## Fase 6 — Warm-up e Gradual

### 6.1 Primeiras 2 semanas

- Enviar **10-20 e-mails/dia** (começar com destinatários internos e contas próprias)
- Monitorar bounce rate e spam reports
- Verificar logs do Postfix: `kubectl logs -n mail deployment/smtp --tail=100`

### 6.2 Escalar DMARC

Progressão gradual:
1. `p=none` (monitoramento) — semanas 1-4
2. `p=quarantine; pct=50` — semanas 5-8
3. `p=reject` — após confirmar zero falsos positivos

Atualizar registro TXT `_dmarc` na Umbler a cada transição.

### 6.3 Contas finais

| Conta | Uso |
|-------|-----|
| `admin@acdgbrasil.com.br` | Administração geral |
| `noreply@acdgbrasil.com.br` | Notificações do sistema (Zitadel, social-care) |
| `contato@acdgbrasil.com.br` | Contato institucional |
| `dmarc@acdgbrasil.com.br` | Relatórios DMARC |

## Verificação Final (Checklist)

```bash
# 1. DNS
dig A mail.acdgbrasil.com.br +short          # 201.23.14.199
dig MX acdgbrasil.com.br +short              # 10 mail.acdgbrasil.com.br.
dig TXT acdgbrasil.com.br +short             # SPF
dig TXT _dmarc.acdgbrasil.com.br +short      # DMARC
dig TXT dkim._domainkey.acdgbrasil.com.br     # DKIM
dig -x 201.23.14.199 +short                  # PTR

# 2. Conectividade
echo QUIT | nc -w5 mail.acdgbrasil.com.br 25   # 220 banner
echo QUIT | nc -w5 mail.acdgbrasil.com.br 587  # 220 banner
openssl s_client -connect mail.acdgbrasil.com.br:993 </dev/null  # cert info

# 3. Pods
kubectl get pods -n mail                       # Todos Running

# 4. Envio
# Enviar e-mail para uma conta Gmail
# Verificar headers: SPF=pass, DKIM=pass, DMARC=pass

# 5. Recepção
# Enviar de Gmail para admin@acdgbrasil.com.br
# Verificar no Roundcube (mail.acdgbrasil.com.br/webmail)

# 6. Zitadel
# Testar reset de senha -> e-mail deve chegar
```

## Troubleshooting

### Pods não iniciam
```bash
kubectl describe pod -n mail <pod-name>
kubectl logs -n mail <pod-name>
```

### ServiceLB não atribui IP
```bash
kubectl get svc mailu-mail-lb -n mail
# Se EXTERNAL-IP fica <pending>, verificar se o ServiceLB do K3s está ativo:
kubectl get pods -n kube-system | grep svclb
```

### E-mails rejeitados (Gmail/Outlook)
1. Verificar PTR: `dig -x 201.23.14.199 +short`
2. Verificar SPF: `dig TXT acdgbrasil.com.br`
3. Verificar DKIM: Enviar e-mail e checar headers (`dkim=pass`)
4. Verificar blacklists: https://mxtoolbox.com/blacklists.aspx
5. Score geral: https://www.mail-tester.com/

### HAProxy não encaminha
```bash
# Na VPS:
sudo systemctl status haproxy
sudo haproxy -c -f /etc/haproxy/haproxy.cfg  # Validar config
journalctl -u haproxy --tail=50

# Testar conectividade VPS -> Xeon:
nc -zv 100.77.46.69 25
```

## Arquivos Relacionados

| Arquivo | Descrição |
|---------|-----------|
| `mail/namespace.yaml` | Namespace K8s `mail` |
| `mail/mailu.yaml` | Todos os recursos Mailu (ConfigMap, Deployments, Services, Ingress) |
| `clusters/master-xeon/mail.yaml` | FluxCD Kustomization |
| `docs/MAIL.md` | Este documento |
