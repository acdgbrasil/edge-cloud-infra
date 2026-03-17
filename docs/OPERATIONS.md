# Guia de Operacoes

Referencia rapida para operar a ACDG Edge Cloud no dia a dia.

## Deploy de Aplicacoes

O fluxo e 100% via Git (GitOps):

1. Crie ou edite um `.yaml` na pasta `/apps` (ou `/mail`)
2. Commit e push para `main`
3. FluxCD sincroniza automaticamente (1 min para apps, 5 min para mail)

Verificar sincronizacao:
```bash
flux get kustomizations
flux reconcile kustomization apps    # forcar sync imediato
```

## Comandos Essenciais

### Cluster
```bash
kubectl get nodes                    # Status dos nos
kubectl get pods -A                  # Todos os pods
kubectl top pods -A                  # Consumo de recursos
```

### Aplicacoes
```bash
# Status
kubectl get pods -l app=social-care
kubectl get pods -l app=social-care-hml

# Logs
kubectl logs -l app=social-care -f
kubectl logs -l app=social-care --previous    # pod crashado

# Restart
kubectl rollout restart deployment/social-care
kubectl rollout status deployment/social-care

# Eventos detalhados
kubectl describe pod -l app=social-care

# Variaveis de ambiente
kubectl set env deployment/social-care --list
```

### PostgreSQL
```bash
# Listar databases
kubectl exec -it postgres-0 -- psql -U postgres -c "\l"

# Conectar no banco
kubectl exec -it postgres-0 -- psql -U postgres -d social_care

# Verificar senha (via Service/rede)
kubectl exec -it postgres-0 -- psql "postgresql://postgres:SENHA@postgres:5432/social_care" -c "SELECT 1"

# Obter senha do secret
kubectl get secret postgres-credentials -o jsonpath='{.data.password}' | base64 -d
```

### NATS JetStream
```bash
# Status do pod
kubectl get pods -l app=nats

# Verificar stream
kubectl exec -it nats-0 -- nats stream info SOCIAL_CARE_EVENTS -s nats://localhost:4222

# Listar mensagens
kubectl exec -it nats-0 -- nats stream view SOCIAL_CARE_EVENTS -s nats://localhost:4222

# Recriar stream (via job)
kubectl create job --from=job/nats-stream-setup nats-stream-setup-run
```

### Stalwart (Mail)
```bash
# Status
kubectl get pods -n mail
kubectl get svc -n mail

# Logs
kubectl logs -n mail -l app=stalwart -f

# Admin web
# https://mail.acdgbrasil.com.br
```

### Zitadel
```bash
# Status
kubectl get pods -l app.kubernetes.io/name=zitadel

# Logs
kubectl logs -l app.kubernetes.io/name=zitadel -f

# Console admin
# https://auth.acdgbrasil.com.br/ui/console
```

### FluxCD
```bash
# Status geral
flux get all

# Forcar reconciliacao
flux reconcile kustomization apps
flux reconcile kustomization mail

# Suspender/retomar sync (manutencao)
flux suspend kustomization apps
flux resume kustomization apps

# Logs do controller
kubectl logs -n flux-system deployment/kustomize-controller -f
```

## Gestao de Secrets

Secrets sao gerenciados pelo Bitwarden Secret Manager. Ver [SECRETS.md](SECRETS.md) para o guia completo.

```bash
# Listar secrets sincronizados
kubectl get bitwardensecrets
kubectl get secrets

# Verificar sync de um secret
kubectl describe bitwardensecret <nome>
```

## HML (Homologacao)

### Reset manual do banco
```bash
kubectl create job --from=cronjob/social-care-hml-db-reset manual-reset
```

O reset automatico roda todo domingo as 03:00 UTC.

### Health check
```bash
curl https://social-care-hml.acdgbrasil.com.br/health
curl https://social-care-hml.acdgbrasil.com.br/ready
```

## VPS Gateway

### Adicionar novo subdominio
```bash
# SSH na VPS
sudo nano /etc/caddy/Caddyfile

# Adicionar bloco:
# meu-app.acdgbrasil.com.br {
#     reverse_proxy 100.77.46.69:80
# }

sudo systemctl reload caddy
```

### Verificar status
```bash
# Na VPS:
sudo systemctl status caddy
sudo systemctl status haproxy
```

## Troubleshooting Rapido

| Sintoma | Comando | Causa comum |
|---------|---------|-------------|
| Pod em CrashLoopBackOff | `kubectl logs -l app=NOME --previous` | Erro na app, banco indisponivel |
| Pod em ImagePullBackOff | `kubectl describe pod -l app=NOME` | Secret `ghcr-credentials` ausente |
| Pod em Pending | `kubectl describe pod -l app=NOME` | Sem recursos ou nodeSelector errado |
| Flux nao sincroniza | `kubectl logs -n flux-system deploy/kustomize-controller` | YAML invalido, conflito |
| Banco nao conecta via rede | Testar com `psql "postgresql://user:pass@service:5432/db"` | pg_hba.conf, senha dessincronizada |

Para historico detalhado de problemas e solucoes, ver [TROUBLESHOOTING_HISTORY.md](TROUBLESHOOTING_HISTORY.md).
