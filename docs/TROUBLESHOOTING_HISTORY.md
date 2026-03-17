# Historico de Troubleshooting

Registro dos problemas encontrados durante a construcao da ACDG Edge Cloud e como foram resolvidos.

---

## 1. Armazenamento (SSD de 1TB)

**Problema:** SSD em formato NTFS nao era montado automaticamente. Apos reboot, o disco sumia e o banco de dados quebrava.

**Solucao:** Formatar para ext4, identificar UUID e configurar montagem persistente no `/etc/fstab`.

---

## 2. Rede (Tailscale)

**Problema:** VPS e Xeon nao se comunicavam, mesmo com Tailscale instalado em ambos.

**Causa:** As maquinas foram autorizadas em Tailnets (redes) diferentes.

**Solucao:** `sudo tailscale logout` em ambas e novo login na mesma organizacao.

---

## 3. GitOps (FluxCD)

**Problema:** Bootstrap do FluxCD falhou: `422 Validation Failed: Deploy keys are disabled for this repository`.

**Causa:** Organizacao GitHub bloqueava deploy keys automaticas.

**Solucao:** Autenticacao via HTTPS + Token Auth (`--token-auth=true`) com PAT.

---

## 4. Gerenciamento de Secrets

### Tentativa A: External Secrets Operator

Multiplos erros em cascata:
- Conflito de versao de API (`v1beta1` vs `v1`)
- CRDs grandes demais para `kubectl apply` (`metadata.annotations: Too long`)
- FluxCD em `CrashLoopBackOff` por aplicar secrets antes do operador estar pronto

**Solucao:** Limpar Flux, instalar CRDs via `kubectl replace` e operador via Helm manual.

### Tentativa B: Operador Oficial da Bitwarden

Campos do YAML diferentes da documentacao generica (`name` vs `secretName`/`secretKey`).

**Solucao:** `kubectl explain bitwardensecret.spec` para descobrir nomes reais dos campos.

---

## 5. Persistencia (PostgreSQL)

**Problema:** Pod do PostgreSQL ficava em `Pending`.

**Causa:** Kubernetes nao sabia onde colocar os dados.

**Solucao:** Etiquetar o Xeon com `hardware-type=high-performance` e usar `nodeSelector` no manifest.

---

## 6. Deploy de Imagem Privada (social-care)

Tres problemas em cascata ao subir a primeira imagem privada do GHCR:

### 6.1 ImagePullBackOff (401 Unauthorized)

**Causa:** Cluster sem credenciais para acessar imagem privada.

**Solucao:**
```bash
kubectl create secret docker-registry ghcr-credentials \
  --docker-server=ghcr.io \
  --docker-username="$(gh api user --jq '.login')" \
  --docker-password="$(gh auth token)" \
  --docker-email="$(gh api user --jq '.email')"
```

Adicionar no Deployment:
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
      - name: ghcr-credentials
```

**Armadilha:** `gh auth login` padrao nao inclui `read:packages`. Sempre usar `--scopes read:packages`.

### 6.2 CrashLoopBackOff (banco nao existe)

**Causa:** PostgreSQL no cluster foi criado sem banco inicial para o servico.

**Solucao:**
```bash
kubectl exec -it postgres-0 -- psql -U postgres -c "CREATE DATABASE social_care"
```

### 6.3 CrashLoopBackOff (senha incorreta via rede)

**Causa:** `pg_hba.conf` usa `trust` para conexoes locais mas `scram-sha-256` para rede. A env `POSTGRES_PASSWORD` so e usada na primeira inicializacao do volume.

**Solucao:**
```bash
kubectl exec -it postgres-0 -- psql -U postgres -c "ALTER USER postgres PASSWORD 'SENHA_DO_SECRET'"
```

Obter a senha:
```bash
kubectl get secret postgres-credentials -o jsonpath='{.data.password}' | base64 -d
```

---

## 7. Stalwart Mail Server

### 7.1 Migracao de Mailu para Stalwart

Mailu exigia multiplos containers (Front, Admin, Postfix, Dovecot, Rspamd, Roundcube) e consumia muitos recursos. Stalwart substituiu com um unico container all-in-one.

### 7.2 IP de Probe Bloqueado

**Problema:** Stalwart bloqueava o IP do K8s probe (10.42.0.1), causando reinicializacao de pods.

**Causa:** Rate limiting ou fail2ban interno do Stalwart ao receber muitas conexoes do probe.

---

## Checklist: Deploy de Servico Privado

1. **Imagem existe no GHCR?** `github.com/orgs/acdgbrasil/packages`
2. **`imagePullSecret` existe?** `kubectl get secret ghcr-credentials`
3. **Token do gh tem `read:packages`?** `gh api orgs/acdgbrasil/packages/container/NOME/versions --jq '.[0]'`
4. **Banco de dados existe?** `kubectl exec -it postgres-0 -- psql -U postgres -c "\l" | grep NOME`
5. **Senha do PostgreSQL sincronizada?** Testar via Service: `psql "postgresql://user:pass@service:5432/db" -c "SELECT 1"`
6. **Caddy configurado na VPS?** Bloco com `reverse_proxy 100.77.46.69:80`
7. **DNS resolve?** Wildcard `*.acdgbrasil.com.br` ja aponta para a VPS

## Comandos de Diagnostico

```bash
kubectl get pods -l app=NOME              # Status
kubectl describe pod -l app=NOME          # Eventos detalhados
kubectl logs -l app=NOME --previous       # Logs de pod crashado
kubectl set env deployment/NOME --list    # Variaveis de ambiente
kubectl logs -l app=NOME -f              # Logs em tempo real
```

---

## Licoes Aprendidas

1. **APIs mudam rapido:** Verificar versao com `kubectl api-resources` antes de escrever YAML.
2. **Ordem importa:** Instalar operadores antes dos apps que dependem deles.
3. **CRDs grandes:** Usar Helm ou `kubectl create/replace` em vez de `apply`.
4. **Logs sao seus amigos:** Quando Flux travar, `kubectl logs` no `kustomize-controller`.
5. **Imagens privadas:** GHCR privado exige `imagePullSecret` com token que tenha `read:packages`.
6. **`POSTGRES_PASSWORD` so vale na primeira inicializacao:** Se o volume ja existir, usar `ALTER USER`.
7. **Testar conexao via Service:** `pg_hba.conf` pode ter regras diferentes para local vs rede.
