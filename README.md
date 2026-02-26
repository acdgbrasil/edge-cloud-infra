# ACDG Brasil - Private Edge Cloud 🚀

Bem-vindo à infraestrutura de nuvem privada da **ACDG Brasil**. Este projeto utiliza uma arquitetura de **Edge Computing** e **GitOps** para gerenciar múltiplos servidores (Xeon e Raspberry Pis) como se fossem uma única nuvem, controlada totalmente via GitHub.

## 🏗️ Arquitetura do Sistema

```text
INTERNET
   |
   ▼
[ VPS GATEWAY ] (IP Público + Caddy)
   |
   | (Túnel Criptografado Tailscale)
   ▼
[ XEON MASTER ] (K3s Control Plane + FluxCD) <--- VOCÊ ESTÁ AQUI
   |
   | (Rede Interna Mesh)
   ▼
[ WORKERS ] (Raspberry Pis / Outros Hardwares)
```

## 🔐 Segurança & Segredos
Todos os segredos da infraestrutura são gerenciados via **Bitwarden Secrets Manager**. Nenhuma senha é armazenada neste repositório. Veja o [Guia de Segredos](docs/SECRETS.md) para mais detalhes.

## 🛠️ Tecnologias Utilizadas

*   **Rede Privada:** [Tailscale](https://tailscale.com/) (Overlay Network segura baseada em WireGuard).
*   **Orquestração:** [K3s](https://k3s.io/) (Kubernetes leve para Edge).
*   **GitOps:** [FluxCD](https://fluxcd.io/) (Sincronização automática entre GitHub e Cluster).
*   **Proxy/SSL:** [Caddy](https://caddyserver.com/) (Automação de HTTPS na borda).
*   **Segredos:** [Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/).

## 📁 Estrutura do Repositório

*   `/apps`: Manifestos Kubernetes de todos os serviços rodando na nuvem.
*   `/clusters/master-xeon`: Configurações específicas do nó mestre e componentes do sistema (Flux).
*   `/docs`: Guias detalhados de operação e expansão.

## 🚀 Como Operar

Para entender como subir novos serviços ou expandir o hardware, veja nossos guias:
1.  [**Operação Diária**](docs/OPERATIONS.md): Gerenciar apps, logs e deploy.
2.  [**Adicionando Hardware**](docs/EXPANSION.md): Como conectar novos Raspberry Pis.
3.  [**Gerenciando Domínios**](docs/GATEWAY.md): Configurar a VPS e SSL.

---
© 2026 ACDG Brasil. Gerenciado com 🧠 e GitOps.
