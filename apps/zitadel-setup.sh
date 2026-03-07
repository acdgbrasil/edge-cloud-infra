#!/bin/bash
# -----------------------------------------------------------
# Zitadel — Setup script for K3s cluster
# Run this on the master node (Xeon) with kubectl access
# -----------------------------------------------------------
set -euo pipefail

echo "=== 1. Removendo recursos do Logto ==="
kubectl delete deployment logto --ignore-not-found
kubectl delete service logto --ignore-not-found
kubectl delete ingress logto-ingress logto-admin-ingress --ignore-not-found
kubectl delete job logto-db-init logto-db-seed --ignore-not-found
echo "Logto removido."

echo ""
echo "=== 2. Criando database 'zitadel' no PostgreSQL ==="
PGPASSWORD=$(kubectl get secret postgres-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -it postgres-0 -- bash -c "
  PGPASSWORD='$PGPASSWORD' psql -U postgres -tc \"SELECT 1 FROM pg_database WHERE datname = 'zitadel'\" | grep -q 1 && echo 'Database já existe.' || \
  (PGPASSWORD='$PGPASSWORD' psql -U postgres -c 'CREATE DATABASE zitadel' && echo 'Database criado.')
"

echo ""
echo "=== 3. Criando usuário 'zitadel' no PostgreSQL ==="
kubectl exec -it postgres-0 -- bash -c "
  PGPASSWORD='$PGPASSWORD' psql -U postgres -tc \"SELECT 1 FROM pg_roles WHERE rolname = 'zitadel'\" | grep -q 1 && echo 'User já existe.' || \
  (PGPASSWORD='$PGPASSWORD' psql -U postgres -c \"CREATE USER zitadel WITH PASSWORD 'zitadel-app-pw'; GRANT ALL PRIVILEGES ON DATABASE zitadel TO zitadel; ALTER DATABASE zitadel OWNER TO zitadel;\" && echo 'User criado.')
"

echo ""
echo "=== 4. Criando secrets ==="
kubectl get secret zitadel-masterkey &>/dev/null && echo "Secret zitadel-masterkey já existe." || \
  kubectl create secret generic zitadel-masterkey \
    --from-literal=masterkey="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)"

kubectl get secret zitadel-db-credentials &>/dev/null && echo "Secret zitadel-db-credentials já existe." || \
  kubectl create secret generic zitadel-db-credentials \
    --from-literal=config.yaml="
Database:
  Postgres:
    User:
      Password: zitadel-app-pw
    Admin:
      Password: $PGPASSWORD
"

echo ""
echo "=== 5. Adicionando Helm repo ==="
helm repo add zitadel https://charts.zitadel.com 2>/dev/null || true
helm repo update

echo ""
echo "=== 6. Instalando Zitadel ==="
helm install zitadel zitadel/zitadel --values apps/zitadel-values.yaml

echo ""
echo "=== 7. Aguardando pods ==="
echo "Acompanhe com: kubectl get pods --watch"
echo ""
echo "Quando estiver Ready, acesse:"
echo "  https://auth.acdgbrasil.com.br/ui/console"
echo ""
echo "Login inicial:"
echo "  User: admin"
echo "  Pass: AcdgAdmin2024! (será pedido para trocar)"
