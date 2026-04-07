# Servidor de E-mail (Stalwart)

Servidor de e-mail all-in-one rodando na edge cloud (K3s).

**Software:** Stalwart v0.15.5 (SMTP/IMAP/JMAP/Web)
**Dominio:** `acdgbrasil.com.br`
**Hostname:** `mail.acdgbrasil.com.br`
**Namespace K8s:** `mail`
**Relay SMTP:** Resend (smtp.resend.com:587, STARTTLS)
**Storage:** PostgreSQL dedicado (`stalwart` database, 5 Gi)

## Topologia de Rede

```
INTERNET
    |
[VPS Gateway] (201.23.12.141)
    |- Caddy :443  → Tailscale → K3s Traefik :80 (HTTPS, webmail)
    |- HAProxy :25  → Tailscale → K3s NodePort :30208 (SMTP entrada)
    |- HAProxy :465 → Tailscale → K3s NodePort :32286 (SMTPS)
    |- HAProxy :587 → Tailscale → K3s NodePort :31420 (Submission)
    |- HAProxy :993 → Tailscale → K3s NodePort :32078 (IMAPS)
    |
    TLS: ACME DNS-01 via Cloudflare (CNAME delegation noticetable.com)
    |
[XEON K3s] (100.77.46.69)
    |- Namespace: mail
    |- Stalwart (all-in-one: SMTP + IMAP + JMAP + Web)
    |- PostgreSQL stalwart (storage backend)
    |- Services:
    |    stalwart (ClusterIP :8080) → Ingress (admin web)
    |    stalwart-mail (NodePort) → portas TCP de email
```

## Componentes K8s

| Recurso | Nome | Descricao |
|---------|------|-----------|
| Deployment | `stalwart` | Stalwart v0.15.5 (all-in-one) |
| StatefulSet | `postgres-stalwart` | PostgreSQL 15 dedicado |
| Service | `stalwart` | ClusterIP :8080 (HTTP/admin) |
| Service | `stalwart-mail` | NodePort (TCP: SMTP, SMTPS, Submission, IMAPS) |
| Ingress | `stalwart-ingress` | `mail.acdgbrasil.com.br` → :8080 |
| BitwardenSecret | `stalwart-db-bitwardensecret` | Senha do PostgreSQL |

## Configuracao do HAProxy (VPS)

O HAProxy na VPS faz TCP proxy das portas de e-mail para os NodePorts do K3s.

Arquivo: `/etc/haproxy/haproxy.cfg`

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

frontend ft_smtp
    bind *:25
    default_backend bk_smtp
backend bk_smtp
    server xeon-mail 100.77.46.69:30208 check

frontend ft_smtps
    bind *:465
    default_backend bk_smtps
backend bk_smtps
    server xeon-mail 100.77.46.69:32286 check

frontend ft_submission
    bind *:587
    default_backend bk_submission
backend bk_submission
    server xeon-mail 100.77.46.69:31420 check

frontend ft_imaps
    bind *:993
    default_backend bk_imaps
backend bk_imaps
    server xeon-mail 100.77.46.69:32078 check
```

```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
```

## DNS (Umbler)

| Tipo | Nome | Valor | TTL |
|------|------|-------|-----|
| A | `mail` | `201.23.12.141` | 3600 |
| MX | `@` (raiz) | `mail.acdgbrasil.com.br` (prioridade 10) | 3600 |
| TXT | `@` (raiz) | `v=spf1 ip4:201.23.12.141 include:_spf.resend.com ~all` | 3600 |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@acdgbrasil.com.br` | 3600 |
| TXT | `default._domainkey` | `v=DKIM1; k=rsa; p=<CHAVE-PUBLICA>` | 3600 |

Verificar:
```bash
dig A mail.acdgbrasil.com.br +short          # 201.23.12.141
dig MX acdgbrasil.com.br +short              # 10 mail.acdgbrasil.com.br.
dig TXT acdgbrasil.com.br +short             # SPF
dig TXT _dmarc.acdgbrasil.com.br +short      # DMARC
dig TXT dkim._domainkey.acdgbrasil.com.br     # DKIM
dig -x 201.23.12.141 +short                  # PTR (mail.acdgbrasil.com.br)
```

## Integracao com Zitadel

O Zitadel envia e-mails (reset de senha, verificacao) via Stalwart.

Configurar no console admin (`https://auth.acdgbrasil.com.br/ui/console`):

1. **Settings** > **Notification Settings** > **SMTP**
2. Preencher:
   - **Host:** `stalwart.mail.svc.cluster.local`
   - **Port:** `587`
   - **TLS:** STARTTLS
   - **From:** `noreply@acdgbrasil.com.br`
   - **User:** `noreply@acdgbrasil.com.br`
   - **Password:** senha da conta noreply

## Contas de E-mail

| Conta | Uso |
|-------|-----|
| `admin@acdgbrasil.com.br` | Administracao geral |
| `noreply@acdgbrasil.com.br` | Notificacoes do sistema (Zitadel) |
| `contato@acdgbrasil.com.br` | Contato institucional |
| `dmarc@acdgbrasil.com.br` | Relatorios DMARC |

## Troubleshooting

### Pods nao iniciam
```bash
kubectl describe pod -n mail <pod-name>
kubectl logs -n mail <pod-name>
```

### NodePort nao responde
```bash
# Verificar services
kubectl get svc -n mail

# Testar SMTP local (no Xeon)
echo QUIT | nc -w5 100.77.46.69 30208
```

### E-mails rejeitados
1. Verificar PTR: `dig -x 201.23.12.141 +short`
2. Verificar SPF: `dig TXT acdgbrasil.com.br`
3. Score geral: https://www.mail-tester.com/
4. Blacklists: https://mxtoolbox.com/blacklists.aspx

### HAProxy nao encaminha
```bash
sudo systemctl status haproxy
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
nc -zv 100.77.46.69 30208    # testar Gateway → Xeon via Tailscale
```

## Arquivos Relacionados

| Arquivo | Descricao |
|---------|-----------|
| `mail/namespace.yaml` | Namespace `mail` |
| `mail/stalwart.yaml` | Stalwart (Deployment, Services, Ingress, ConfigMap) |
| `mail/postgres-stalwart.yaml` | PostgreSQL dedicado + BitwardenSecret |
| `clusters/master-xeon/mail.yaml` | FluxCD Kustomization |
