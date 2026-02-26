# Guia de Expansão de Hardware (Workers) 🍓

Siga estes passos para transformar um Raspberry Pi (ou qualquer PC antigo) em um servidor da sua nuvem.

## Requisitos
*   Sistema Operacional instalado (Ubuntu ou Raspberry Pi OS).
*   Acesso à internet.

## Passo 1: Conectar à Rede Privada
No novo hardware, instale o Tailscale:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```
*Autorize o dispositivo na mesma conta do Master.*

## Passo 2: Instalar o Agente K3s
Recupere o **IP do Master** (100.77.46.69) e o **Node Token**.
No novo hardware, rode:
```bash
curl -sfL https://get.k3s.io | K3S_URL=https://100.77.46.69:6443 K3S_TOKEN=<TOKEN_DO_MASTER> sh -
```

## Passo 3: Validar
No Master (Xeon), verifique se o novo nó apareceu:
```bash
kubectl get nodes
```
