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

---

## Lições Aprendidas 🧠
1. **APIs mudam rápido:** Sempre verifique a versão da API com `kubectl api-resources` antes de escrever o YAML.
2. **Ordem importa:** Primeiro instale a infraestrutura (Operadores), depois os apps que dependem dela.
3. **Cuidado com CRDs grandes:** Para pacotes complexos, use Helm ou `kubectl create/replace` em vez de `apply`.
4. **Logs são seus amigos:** Quando o Flux travar, use `kubectl logs` no `kustomize-controller` para ver a mensagem real de erro.

