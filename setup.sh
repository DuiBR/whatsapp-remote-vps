#!/usr/bin/env bash
set -Eeuo pipefail

# Repositório padrão. Altere uma única vez depois de enviar os arquivos ao GitHub.
DEFAULT_REPOSITORY="DuiBR/whatsapp-remote-vps"
DEFAULT_REF="main"

REPOSITORY="${WR_GITHUB_REPOSITORY:-$DEFAULT_REPOSITORY}"
REF="${WR_GITHUB_REF:-$DEFAULT_REF}"
KEEP_DOWNLOAD=0
INSTALL_ARGS=()
TMP_DIR=""
USE_TTY=0

C_RESET='\033[0m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'

info() { printf '%b[INFO]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b[AVISO]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf '%b[ERRO]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
WhatsApp Remote VPS — instalador via GitHub

Uso recomendado:
  curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash

Sem --auto, a instalação é guiada e lê as respostas diretamente do terminal.
As senhas ficam visíveis durante a digitação. Para instalação sem perguntas, use --auto.

Opções do bootstrap:
  --repository DONO/REPOSITORIO   Substitui o repositório configurado no arquivo
  --ref BRANCH_OU_TAG             Branch ou tag a baixar (padrão: main)
  --keep-download                 Mantém os arquivos temporários para diagnóstico
  -h, --help                      Exibe esta ajuda

As demais opções são encaminhadas ao install.sh, por exemplo:
  --auto
  --repair
  --desktop-user whatsapp
  --geometry 1280x720
  --ip 164.152.48.215
  --domain remoto.exemplo.com
  --email admin@exemplo.com
  --no-swap

Sem opções, o instalador usa o modo guiado quando há terminal disponível; sem TTY, usa --auto.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository)
      [[ $# -ge 2 ]] || die "Falta o valor de --repository."
      REPOSITORY="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || die "Falta o valor de --ref."
      REF="$2"
      shift 2
      ;;
    --keep-download)
      KEEP_DOWNLOAD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      INSTALL_ARGS+=("$1")
      shift
      ;;
  esac
done

[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || \
  die "Repositório inválido: '$REPOSITORY'. Use DONO/REPOSITORIO."

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  die "Execute como root. Exemplo: curl -fsSL URL | sudo bash"
fi

HAS_AUTO=0
for arg in "${INSTALL_ARGS[@]}"; do
  [[ "$arg" == "--auto" ]] && HAS_AUTO=1
done

if (( HAS_AUTO == 0 )); then
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    USE_TTY=1
  else
    warn "Terminal interativo não disponível; ativando --auto."
    INSTALL_ARGS+=(--auto)
  fi
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  command -v apt-get >/dev/null 2>&1 || die "apt-get não encontrado."
  info "Instalando dependências mínimas do bootstrap..."
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar gzip
fi

TMP_DIR="$(mktemp -d /tmp/whatsapp-remote-github.XXXXXX)"
cleanup() {
  if [[ "$KEEP_DOWNLOAD" == "1" ]]; then
    warn "Arquivos temporários mantidos em: $TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT
trap 'die "Falha na linha $LINENO."' ERR

ARCHIVE="$TMP_DIR/source.tar.gz"
OWNER="${REPOSITORY%%/*}"
REPO="${REPOSITORY#*/}"

# Tenta primeiro como branch e depois como tag.
BRANCH_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/${REF}.tar.gz"
TAG_URL="https://github.com/${OWNER}/${REPO}/archive/refs/tags/${REF}.tar.gz"

CURL_ARGS=(
  --fail --location --silent --show-error
  --retry 4 --retry-delay 2 --connect-timeout 15 --max-time 300
)

if [[ -n "${WR_GITHUB_TOKEN:-}" ]]; then
  CURL_ARGS+=(--header "Authorization: Bearer ${WR_GITHUB_TOKEN}")
fi

info "Baixando ${REPOSITORY} (${REF})..."
if ! curl "${CURL_ARGS[@]}" "$BRANCH_URL" -o "$ARCHIVE"; then
  warn "A referência não foi localizada como branch; tentando como tag..."
  curl "${CURL_ARGS[@]}" "$TAG_URL" -o "$ARCHIVE" || \
    die "Não foi possível baixar o repositório. Confirme se ele é público e se a branch/tag existe."
fi

[[ -s "$ARCHIVE" ]] || die "O arquivo baixado está vazio."
tar -tzf "$ARCHIVE" >/dev/null || die "O arquivo recebido não é um tar.gz válido."

tar -xzf "$ARCHIVE" -C "$TMP_DIR"
SOURCE_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -name "${REPO}-*" | head -n1 || true)"
[[ -n "$SOURCE_DIR" && -f "$SOURCE_DIR/install.sh" && -f "$SOURCE_DIR/lib/common.sh" ]] || \
  die "Estrutura inválida: install.sh ou lib/common.sh não encontrado na raiz do repositório."

chmod 755 "$SOURCE_DIR"/*.sh "$SOURCE_DIR/lib/common.sh"
info "Executando o instalador universal..."
cd "$SOURCE_DIR"
if (( USE_TTY == 1 )); then
  bash ./install.sh "${INSTALL_ARGS[@]}" < /dev/tty
else
  bash ./install.sh "${INSTALL_ARGS[@]}"
fi

info "Instalação pelo GitHub concluída."
