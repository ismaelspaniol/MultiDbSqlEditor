#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.4.0}"
LAZBUILD="${LAZBUILD:-lazbuild}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Compilando e executando testes unitarios..."
"$LAZBUILD" tests/MultiDbSqlEditorTests.lpi
./tests/bin/MultiDbSqlEditorTests --all --format=plain

echo "[2/4] Compilando MultiDbSqlEditor (Release)..."
"$LAZBUILD" --build-mode=Release MultiDbSqlEditor.lpi

echo "[3/4] Montando pacote Linux x86_64..."
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

mkdir -p release
TAR_PATH="release/MultiDbSqlEditor-v${VERSION}-linux-x86_64.tar.gz"
rm -f "$TAR_PATH"

cp bin/MultiDbSqlEditor "$STAGE_DIR/"
chmod +x "$STAGE_DIR/MultiDbSqlEditor"
cp README.md ARQUITETURA.md "$STAGE_DIR/"
if [ -d bin/clients ]; then
  cp -a bin/clients "$STAGE_DIR/clients"
fi

tar -czf "$TAR_PATH" -C "$STAGE_DIR" .
echo "[4/4] Pacote gerado: $TAR_PATH ($(stat -c%s "$TAR_PATH" 2>/dev/null || wc -c < "$TAR_PATH") bytes)"
