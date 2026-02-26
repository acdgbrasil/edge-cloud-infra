# Guia de Operações Diárias 🛠️

Este guia explica como interagir com a nuvem no dia a dia.

## 1. Fazendo o Deploy de um Novo App
O fluxo é 100% via Git:
1. Crie um arquivo `.yaml` na pasta `/apps`.
2. Defina o `Deployment`, `Service` e `Ingress`.
3. Faça o `git push`.
4. O FluxCD aplicará as mudanças em até 1 minuto.

## 2. Comandos Úteis no Master (Xeon)
Para monitorar o cluster manualmente:
```bash
# Ver todos os apps rodando
kubectl get pods -A

# Ver logs de um app específico
kubectl logs -f <nome-do-pod>

# Ver status da sincronização do Git
flux get kustomizations
```

## 3. Gerenciando Segredos
**Nunca coloque senhas no GitHub.**
Use o Bitwarden Secrets Manager e integre com o Kubernetes (External Secrets Operator - recomendado para a próxima fase).
