# Diário de Bordo: Desafios e Soluções (Troubleshooting) 📑

Este documento registra a jornada de construção da **ACDG Edge Cloud**, listando as falhas encontradas e como foram resolvidas. Serve como guia para evitar os mesmos erros no futuro.

---

## 1. Armazenamento (SSD de 1TB)
- **Desafio:** O SSD secundário estava em formato NTFS e não era montado automaticamente.
- **Tentativa:** Montagem manual simples.
- **Erro:** Se o sistema reiniciasse, o disco sumia, quebrando o banco de dados.
- **Solução:** Formatamos para **ext4**, identificamos o **UUID** e configuramos o `/etc/fstab` para montagem automática persistente.

## 2. Rede (Tailscale & VPS)
- **Desafio:** A VPS e o Xeon não se comunicavam, mesmo ambos estando com Tailscale.
- **Erro:** "Isolamento de Redes". As máquinas foram autorizadas em contas/redes (Tailnets) diferentes, mesmo usando o mesmo e-mail.
- **Solução:** `sudo tailscale logout` em ambas as máquinas e novo login garantindo que ambas estavam na mesma organização/e-mail no painel do Tailscale.

## 3. GitOps (FluxCD & GitHub)
- **Desafio:** O bootstrap do FluxCD falhou ao tentar criar chaves SSH.
- **Erro:** `422 Validation Failed: Deploy keys are disabled for this repository`. A organização GitHub bloqueava chaves de deploy automáticas.
- **Solução:** Mudamos a estratégia de autenticação para **HTTPS + Token Auth** (`--token-auth=true`). Isso removeu a necessidade de chaves SSH e usou o Personal Access Token (PAT) para a comunicação.

## 4. O Grande Desafio: Gerenciamento de Segredos
Essa foi a parte mais complexa da montagem.

### Tentativa A: External Secrets Operator (Genérico)
- **Erro 1:** Conflito de versão de API (`v1beta1` vs `v1`). O Kubernetes rejeitava os manifestos por nomes de campos obsoletos.
- **Erro 2:** `metadata.annotations: Too long`. As definições de recurso (CRDs) eram grandes demais para o `kubectl apply` padrão.
- **Erro 3:** Sincronização travada. O FluxCD entrou em `CrashLoopBackOff` pois tentou aplicar segredos antes de o operador estar pronto.
- **Solução:** Limpamos o Flux, instalamos as CRDs via `kubectl replace` (que ignora o limite de tamanho) e instalamos o operador manualmente via Helm para destravar o cluster.

### Tentativa B: Operador Oficial da Bitwarden (`sm-operator`)
- **Erro:** Estrutura do arquivo YAML diferente da documentação genérica. Erros de `unknown field spec.authToken.name`.
- **Solução:** Usamos o comando `kubectl explain` para descobrir os nomes reais dos campos (`secretName` e `secretKey`) e o nome correto do provedor (`bitwardensecretsmanager`).

## 5. Persistência de Dados (PostgreSQL)
- **Desafio:** O banco de dados ficava em `Pending`.
- **Erro:** O Kubernetes não sabia onde colocar os dados ou não tinha a senha para iniciar o container.
- **Solução:** Etiquetamos o nó Xeon (`hardware-type=high-performance`) e usamos um `nodeSelector` no YAML para garantir que o banco nunca tente rodar em um Raspberry Pi, usando sempre o SSD de 1TB do Master.

## 6. Deploy do Primeiro Microserviço Privado (svc-social-care)

O deploy do `svc-social-care` foi a primeira vez que subimos uma imagem **privada do GHCR** no cluster. Enfrentamos 3 problemas em cascata:

### Problema A: `ImagePullBackOff` — 401 Unauthorized
- **Sintoma:** Pod ficava em `ImagePullBackOff`. Nos eventos: `failed to authorize: 401 Unauthorized`.
- **Causa:** A imagem `ghcr.io/acdgbrasil/svc-social-care` é privada e o cluster não tinha credenciais para acessá-la. Todos os outros apps usavam imagens públicas (`nginx`, `postgres`, `nats`).
- **Solução:** Criar um `imagePullSecret` no cluster e referenciá-lo no Deployment.

#### Passo 1: Instalar o `gh` CLI no Xeon (para obter token com escopos corretos)
```bash
sudo snap install gh --classic
gh auth login --scopes read:packages,write:packages
```

#### Passo 2: Criar o secret no cluster
```bash
kubectl create secret docker-registry ghcr-credentials --docker-server=ghcr.io --docker-username="$(gh api user --jq '.login')" --docker-password="$(gh auth token)" --docker-email="$(gh api user --jq '.email')"
```

#### Passo 3: Adicionar no Deployment
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
      - name: ghcr-credentials
```

**Armadilha:** O `gh auth login` padrão **não** inclui o escopo `read:packages`. Sem ele, o token retorna `403 Forbidden`. Sempre usar `--scopes read:packages`.

---

### Problema B: `CrashLoopBackOff` — Banco de dados não existe
- **Sintoma:** Pod subia mas crashava imediatamente. Nos logs: `password authentication failed for user "postgres"`.
- **Investigação:** Rodamos `kubectl exec -it postgres-0 -- psql -U postgres -c "\l" | grep social` e o banco `social_care` **não existia**.
- **Solução:**
```bash
kubectl exec -it postgres-0 -- psql -U postgres -c "CREATE DATABASE social_care"
```

**Lição:** O PostgreSQL no cluster foi criado sem banco inicial para o serviço. Sempre verificar se o database existe antes de subir um app novo.

---

### Problema C: `CrashLoopBackOff` — Senha incorreta via rede (scram-sha-256 vs trust)
- **Sintoma:** Mesmo após criar o banco, o pod continuava com `password authentication failed`.
- **Investigação detalhada:**
  1. `kubectl exec -it postgres-0 -- psql -U postgres -c "SELECT 1"` → **funcionava** (conexão local)
  2. `kubectl exec -it postgres-0 -- psql "postgresql://postgres:SENHA@localhost:5432/social_care" -c "SELECT 1"` → **funcionava** (localhost com senha)
  3. `kubectl exec -it postgres-0 -- psql "postgresql://postgres:SENHA@postgres:5432/social_care" -c "SELECT 1"` → **falhava** (via Service/rede)
- **Causa raiz:** O `pg_hba.conf` tinha configuração diferente para conexões locais vs rede:
  ```
  # Conexões locais: sem senha
  local   all   all                  trust
  host    all   all   127.0.0.1/32   trust

  # Conexões de rede: exige scram-sha-256
  host    all   all   all            scram-sha-256
  ```
  O PostgreSQL foi inicializado com `trust` local. A senha definida pelo Bitwarden foi injetada via env `POSTGRES_PASSWORD`, mas essa variável **só é usada na primeira inicialização do volume**. Como o volume já existia com dados, a senha real do banco nunca foi atualizada.
- **Solução:** Resetar a senha do usuário postgres para a que está no secret:
```bash
kubectl exec -it postgres-0 -- psql -U postgres -c "ALTER USER postgres PASSWORD 'SENHA_DO_SECRET'"
```
Para obter a senha do secret:
```bash
kubectl get secret postgres-credentials -o jsonpath='{.data.password}' | base64 -d
```

**Lição:** A env `POSTGRES_PASSWORD` da imagem oficial do PostgreSQL só funciona na **primeira criação** do volume. Se o volume já foi inicializado com outra senha (ou com `trust`), alterar a env não tem efeito. Use `ALTER USER` para sincronizar.

---

### Checklist: Deploy de Microserviço Privado no Cluster

Use este checklist ao subir um novo serviço com imagem privada do GHCR:

1. **Imagem existe no GHCR?** Verificar em `github.com/orgs/acdgbrasil/packages`
2. **`imagePullSecret` existe?** `kubectl get secret ghcr-credentials` (criar se necessário)
3. **Token do `gh` tem `read:packages`?** `gh api orgs/acdgbrasil/packages/container/NOME/versions --jq '.[0]'`
4. **Banco de dados existe?** `kubectl exec -it postgres-0 -- psql -U postgres -c "\l" | grep NOME_DO_BANCO`
5. **Senha do PostgreSQL está sincronizada?** Testar via Service: `kubectl exec -it postgres-0 -- psql "postgresql://postgres:SENHA@postgres:5432/BANCO" -c "SELECT 1"`
6. **Caddy configurado na VPS?** Bloco com `reverse_proxy 100.77.46.69:80`
7. **DNS resolve?** O wildcard `*.acdgbrasil.com.br` já aponta para a VPS

### Comandos de diagnóstico rápido
```bash
# Ver status dos pods
kubectl get pods -l app=NOME

# Ver eventos detalhados
kubectl describe pod -l app=NOME

# Ver logs (inclusive de pods crashados)
kubectl logs -l app=NOME --previous

# Ver variáveis de ambiente do deployment
kubectl set env deployment/NOME --list

# Acompanhar logs em tempo real
kubectl logs -l app=NOME -f
```

---

## Lições Aprendidas 🧠
1. **APIs mudam rápido:** Sempre verifique a versão da API com `kubectl api-resources` antes de escrever o YAML.
2. **Ordem importa:** Primeiro instale a infraestrutura (Operadores), depois os apps que dependem dela.
3. **Cuidado com CRDs grandes:** Para pacotes complexos, use Helm ou `kubectl create/replace` em vez de `apply`.
4. **Logs são seus amigos:** Quando o Flux travar, use `kubectl logs` no `kustomize-controller` para ver a mensagem real de erro.
5. **Imagens privadas precisam de `imagePullSecret`:** O GHCR privado exige credenciais no cluster. O `gh auth token` precisa do escopo `read:packages`.
6. **`POSTGRES_PASSWORD` só vale na primeira inicialização:** Se o volume já existir, use `ALTER USER` para mudar a senha.
7. **Teste a conexão via Service, não via localhost:** O `pg_hba.conf` pode ter regras diferentes para conexões locais e de rede.

