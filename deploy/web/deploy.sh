#!/usr/bin/env bash
# Compila la app web, arma la imagen para el servidor y la publica.
#
#   deploy/web/deploy.sh [usuario@servidor] [plataforma]
#   deploy/web/deploy.sh orangepi@192.168.1.77 linux/arm64
#
# Requiere flutter y docker con buildx en la PC, y docker compose en el
# servidor. En el servidor usa la carpeta ~/yankees-web.
set -euo pipefail

TARGET="${1:-orangepi@192.168.1.77}"
PLATFORM="${2:-linux/arm64}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONTEXT="$(mktemp -d)"
trap 'rm -rf "$CONTEXT"' EXIT

echo "==> Compilando la app web"
(cd "$ROOT" && flutter build web --release --no-wasm-dry-run)

echo "==> Armando la imagen ($PLATFORM)"
cp "$ROOT/deploy/web/Dockerfile" "$ROOT/deploy/web/nginx.conf" "$CONTEXT/"
cp -r "$ROOT/build/web" "$CONTEXT/html"
docker buildx build --platform "$PLATFORM" -t yankees-web:latest --load "$CONTEXT"

echo "==> Enviando a $TARGET"
ssh "$TARGET" 'mkdir -p ~/yankees-web'
scp -q "$ROOT/deploy/web/compose.yaml" "$TARGET:yankees-web/compose.yaml"
docker save yankees-web:latest | gzip -1 | ssh "$TARGET" 'gunzip | docker load'

echo "==> Reiniciando"
ssh "$TARGET" 'cd ~/yankees-web && docker compose up -d --remove-orphans && docker image prune -f >/dev/null && docker compose ps'
