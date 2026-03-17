# Gateway (VPS)

A VPS e o unico ponto de entrada publico. Recebe trafego da internet e encaminha para o cluster K3s via Tailscale.

**IP Publico:** `201.23.14.199`
**IP Tailscale do Xeon:** `100.77.46.69`

## Como funciona

| Componente | Funcao | Portas |
|------------|--------|--------|
| **Caddy** | Reverse proxy HTTPS (HTTP/S) | 80, 443 |
| **HAProxy** | TCP proxy (protocolos de e-mail) | 25, 465, 587, 993 |

O Caddy cuida de HTTPS com certificados Let's Encrypt automaticos. O HAProxy lida com portas TCP que o Caddy nao suporta (mail).

## Adicionar novo subdominio

### Passo 1: DNS
O wildcard `*.acdgbrasil.com.br` ja aponta para `201.23.14.199`. Para subdominos especificos (necessarios para MX, por exemplo), criar registro A no painel DNS (Umbler).

### Passo 2: Caddyfile
SSH na VPS e editar o Caddyfile:
```bash
sudo nano /etc/caddy/Caddyfile
```

Adicionar o bloco:
```caddy
meu-app.acdgbrasil.com.br {
    reverse_proxy 100.77.46.69:80
}
```

Recarregar:
```bash
sudo systemctl reload caddy
```

O Caddy gera o certificado TLS automaticamente na primeira requisicao.

### Passo 3: Ingress no K3s
Criar o Ingress no manifest da aplicacao (em `/apps/`) para que o Traefik roteie pelo header `Host`.

## Subdominios ativos

| Subdominio | Destino | Servico |
|------------|---------|---------|
| `social-care.acdgbrasil.com.br` | Caddy → Traefik | social-care (prod) |
| `social-care-hml.acdgbrasil.com.br` | Caddy → Traefik | social-care (HML) |
| `auth.acdgbrasil.com.br` | Caddy → Traefik | Zitadel |
| `mail.acdgbrasil.com.br` | Caddy → Traefik | Stalwart (admin web) |
| `tcc.acdgbrasil.com.br` | Caddy → Traefik | tcc-site |
| `cloud.acdgbrasil.com.br` | Caddy → Traefik | hello-world (teste) |

## Verificar status

```bash
# Na VPS:
sudo systemctl status caddy
sudo systemctl status haproxy
ss -tlnp | grep -E ':(80|443|25|465|587|993)\b'
```
