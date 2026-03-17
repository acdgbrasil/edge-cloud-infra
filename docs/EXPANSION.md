# Expansao de Hardware (Workers)

Como adicionar um novo no (Raspberry Pi, PC antigo, etc.) ao cluster K3s.

## Requisitos

- Sistema operacional instalado (Ubuntu ou Raspberry Pi OS)
- Acesso a internet

## Passo 1: Conectar a Rede Privada

Instalar o Tailscale no novo hardware:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Autorizar o dispositivo na **mesma conta** do Master no painel do Tailscale.

## Passo 2: Instalar o Agente K3s

Recuperar o **Node Token** do Master:
```bash
# No Master (Xeon):
sudo cat /var/lib/rancher/k3s/server/node-token
```

Instalar no novo hardware:
```bash
curl -sfL https://get.k3s.io | K3S_URL=https://100.77.46.69:6443 K3S_TOKEN=<TOKEN_DO_MASTER> sh -
```

## Passo 3: Etiquetar o No (opcional)

Se o novo hardware tem SSD ou e potente o suficiente para rodar bancos de dados:
```bash
# No Master:
kubectl label node <nome-do-no> hardware-type=high-performance
```

Workloads com `nodeSelector: hardware-type: high-performance` (PostgreSQL, NATS) passarao a considerar este no.

## Passo 4: Validar

```bash
# No Master (Xeon):
kubectl get nodes
```

O novo no deve aparecer com status `Ready`.
