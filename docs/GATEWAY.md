# Gerenciando o Portão de Entrada (VPS) 🌐

A VPS funciona como o Gateway (Ingress Público).

## 1. Configurar Novo Domínio

### Estratégia Wildcard (Atalho)
Para facilitar sua vida, configure um registro **A** com o nome `*` (asterisco) apontando para o IP da VPS no seu painel DNS. Isso fará com que qualquer subdomínio (`qualquercoisa.acdgbrasil.com.br`) chegue até o nosso Gateway.
1. Aponte o DNS (Registro A) do seu domínio para o IP Público da VPS (`201.23.14.199`).
2. Acesse a VPS via SSH e edite o Caddyfile:
```bash
sudo nano /etc/caddy/Caddyfile
```
3. Adicione o novo bloco:
```caddy
seu-app.acdgbrasil.com.br {
    reverse_proxy 100.77.46.69:80
}
```
4. Reinicie o Caddy: `sudo systemctl reload caddy`.

## 2. SSL/HTTPS
O Caddy cuidará de tudo automaticamente. Certifique-se apenas de que as portas 80 e 443 estão abertas no firewall da VPS.
