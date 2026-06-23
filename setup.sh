#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_REPOSITORY="DuiBR/whatsapp-remote-vps"
DEFAULT_REF="main"
REPOSITORY="${WR_GITHUB_REPOSITORY:-$DEFAULT_REPOSITORY}"
REF="${WR_GITHUB_REF:-$DEFAULT_REF}"
KEEP_DOWNLOAD=0
INSTALL_ARGS=()
TMP_DIR=""
USE_TTY=0
ACTION="install"

if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_CYAN=$'\033[1;36m'
else
  C_RESET='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_CYAN=''
fi
info() { printf '%b[INFO]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b[AVISO]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf '%b[ERRO]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
pause_tty() { read -r -p "Pressione Enter para continuar..." _ < /dev/tty || true; }

usage() {
  cat <<'USAGE'
WhatsApp Remote VPS — instalador e Manager via GitHub

Comando principal:
  curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash

Sem parâmetros, abre um menu intuitivo com instalação, reparação, status e Manager.

Opções do bootstrap:
  --repository DONO/REPOSITORIO   Usa outro repositório
  --ref BRANCH_OU_TAG             Branch ou tag (padrão: main)
  --keep-download                 Mantém arquivos temporários
  -h, --help                      Exibe esta ajuda

Opções encaminhadas ao instalador:
  --auto
  --repair
  --desktop-user whatsapp
  --geometry 1280x720
  --ip 164.152.48.215
  --domain remoto.exemplo.com
  --email admin@exemplo.com
  --swap auto|on|off

Exemplo totalmente automático:
  curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash -s -- --auto
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository)
      [[ $# -ge 2 ]] || die "Falta o valor de --repository."
      REPOSITORY="$2"; shift 2 ;;
    --ref)
      [[ $# -ge 2 ]] || die "Falta o valor de --ref."
      REF="$2"; shift 2 ;;
    --keep-download)
      KEEP_DOWNLOAD=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      INSTALL_ARGS+=("$1"); shift ;;
  esac
done

[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "Repositório inválido: $REPOSITORY"
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Execute como root. Exemplo: curl -fsSL URL | sudo bash"

if [[ -r /dev/tty && -w /dev/tty ]]; then USE_TTY=1; fi

bootstrap_menu() {
  local choice installed="não"
  [[ -x /usr/local/sbin/whatsapp-remote ]] && installed="sim"
  while true; do
    clear </dev/tty 2>/dev/null || true
    printf '%bWhatsApp Remote VPS%b\n' "$C_BOLD$C_CYAN" "$C_RESET" > /dev/tty
    printf 'Instalador inteligente via GitHub\n' > /dev/tty
    printf '%s\n' '────────────────────────────────────────────────────────────' > /dev/tty
    printf ' Repositório: %s (%s)\n' "$REPOSITORY" "$REF" > /dev/tty
    printf ' Instalado nesta máquina: %s\n\n' "$installed" > /dev/tty
    cat > /dev/tty <<'MENU'
  1) Instalação automática recomendada
  2) Instalação personalizada com revisão das informações
  3) Atualizar e reparar preservando a sessão do WhatsApp
  4) Abrir o Manager
  5) Ver status detalhado
  6) Ver logs
  7) Desinstalar
  0) Sair
MENU
    printf '\n' > /dev/tty
    read -r -p "Escolha: " choice < /dev/tty
    case "$choice" in
      1) INSTALL_ARGS=(--auto); ACTION="install"; return 0 ;;
      2) INSTALL_ARGS=(); ACTION="install"; return 0 ;;
      3) INSTALL_ARGS=(--repair --auto); ACTION="install"; return 0 ;;
      4)
        if [[ -x /usr/local/sbin/whatsapp-remote ]]; then exec /usr/local/sbin/whatsapp-remote menu < /dev/tty; fi
        warn "O sistema ainda não está instalado."; pause_tty ;;
      5)
        if [[ -x /usr/local/sbin/whatsapp-remote ]]; then /usr/local/sbin/whatsapp-remote status > /dev/tty 2>&1 || true; else warn "O sistema ainda não está instalado."; fi
        pause_tty ;;
      6)
        if [[ -x /usr/local/sbin/whatsapp-remote ]]; then /usr/local/sbin/whatsapp-remote logs < /dev/tty; else warn "O sistema ainda não está instalado."; pause_tty; fi
        ;;
      7)
        if [[ -x /usr/local/sbin/whatsapp-remote ]]; then exec /usr/local/sbin/whatsapp-remote uninstall < /dev/tty; fi
        warn "O sistema ainda não está instalado."; pause_tty ;;
      0) echo "Encerrado." > /dev/tty; exit 0 ;;
      *) warn "Opção inválida."; pause_tty ;;
    esac
  done
}

if (( ${#INSTALL_ARGS[@]} == 0 )); then
  if (( USE_TTY == 1 )); then
    bootstrap_menu
  else
    warn "Terminal interativo indisponível; usando instalação automática."
    INSTALL_ARGS=(--auto)
  fi
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  command -v apt-get >/dev/null 2>&1 || die "apt-get não encontrado."
  info "Instalando dependências mínimas..."
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar gzip coreutils
fi

TMP_DIR="$(mktemp -d /tmp/whatsapp-remote-github.XXXXXX)"
cleanup() {
  if [[ "$KEEP_DOWNLOAD" == "1" ]]; then warn "Arquivos temporários mantidos em: $TMP_DIR"; else rm -rf "$TMP_DIR"; fi
}
trap cleanup EXIT
trap 'die "Falha na linha $LINENO."' ERR

ARCHIVE="$TMP_DIR/source.tar.gz"
OWNER="${REPOSITORY%%/*}"
REPO="${REPOSITORY#*/}"
BRANCH_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/${REF}.tar.gz"
TAG_URL="https://github.com/${OWNER}/${REPO}/archive/refs/tags/${REF}.tar.gz"
CURL_ARGS=(--fail --location --silent --show-error --retry 4 --retry-delay 2 --connect-timeout 15 --max-time 300)
[[ -n "${WR_GITHUB_TOKEN:-}" ]] && CURL_ARGS+=(--header "Authorization: Bearer ${WR_GITHUB_TOKEN}")

info "Baixando ${REPOSITORY} (${REF})..."
if ! curl "${CURL_ARGS[@]}" "$BRANCH_URL" -o "$ARCHIVE"; then
  warn "A referência não foi localizada como branch; tentando como tag..."
  curl "${CURL_ARGS[@]}" "$TAG_URL" -o "$ARCHIVE" || die "Não foi possível baixar o repositório."
fi
[[ -s "$ARCHIVE" ]] || die "O arquivo baixado está vazio."
tar -tzf "$ARCHIVE" >/dev/null || die "O arquivo recebido não é um tar.gz válido."
tar -xzf "$ARCHIVE" -C "$TMP_DIR"
SOURCE_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -name "${REPO}-*" | head -n1 || true)"
[[ -n "$SOURCE_DIR" && -f "$SOURCE_DIR/install.sh" && -f "$SOURCE_DIR/lib/common.sh" ]] || die "Estrutura inválida no repositório."

# Validação em duas camadas:
# 1) estrutura e sintaxe são obrigatórias;
# 2) o MANIFEST é complementar e não bloqueia instalações quando arquivos
#    opcionais foram omitidos ou normalizados pelo upload via navegador.
REQUIRED_FILES=(
  install.sh
  manage.sh
  repair.sh
  status.sh
  uninstall.sh
  lib/common.sh
)

for required_file in "${REQUIRED_FILES[@]}"; do
  [[ -s "$SOURCE_DIR/$required_file" ]] || die "Arquivo obrigatório ausente ou vazio: $required_file"
done

info "Validando estrutura e sintaxe dos scripts..."
for script_file in setup.sh "${REQUIRED_FILES[@]}"; do
  bash -n "$SOURCE_DIR/$script_file" || die "Erro de sintaxe detectado em: $script_file"
done

if [[ -f "$SOURCE_DIR/MANIFEST.sha256" ]]; then
  info "Conferindo checksums do pacote..."
  if ! (cd "$SOURCE_DIR" && sha256sum -c MANIFEST.sha256 --quiet); then
    warn "Alguns checksums diferem do pacote original."
    warn "Isso é comum quando arquivos foram enviados ou editados pelo navegador do GitHub."
    warn "A estrutura e a sintaxe foram validadas; a instalação continuará com segurança."
  fi
fi

chmod 755 "$SOURCE_DIR"/*.sh "$SOURCE_DIR/lib/common.sh"
info "Executando o instalador universal..."
cd "$SOURCE_DIR"
if (( USE_TTY == 1 )); then
  bash ./install.sh "${INSTALL_ARGS[@]}" < /dev/tty
else
  bash ./install.sh "${INSTALL_ARGS[@]}"
fi
info "Operação concluída. Abra o menu com: sudo whatsapp-remote"
