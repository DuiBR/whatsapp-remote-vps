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
INSTALL_STATE="none"
INSTALL_MARKERS=()
MANAGER_TARGET=""
BOOTSTRAP_SUPPORTED=0

if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_CYAN=$'\033[1;36m'; C_BLUE=$'\033[1;34m'
else
  C_RESET='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_BLUE=''
fi
info() { printf '%b[INFO]%b %s\n' "$C_BLUE" "$C_RESET" "$*"; }
warn() { printf '%b[AVISO]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf '%b[ERRO]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
ok() { printf '%b[OK]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
pause_tty() { read -r -p "Pressione Enter para continuar..." _ < /dev/tty || true; }

usage() {
  cat <<'USAGE'
WhatsApp Remote VPS — instalador inteligente via GitHub

Comando recomendado:
  curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash

Sem parâmetros:
  • em uma máquina nova, pergunta se deseja instalação automática ou manual;
  • ao detectar uma instalação anterior, oferece reparar, gerenciar, diagnosticar,
    reinstalar do zero ou desinstalar.

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

bootstrap_public_ip() {
  local ip endpoint
  command -v curl >/dev/null 2>&1 || return 1
  for endpoint in https://api.ipify.org https://checkip.amazonaws.com https://ifconfig.me/ip; do
    ip="$(curl -4 -fsS --connect-timeout 2 --max-time 5 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { printf '%s' "$ip"; return 0; }
  done
  return 1
}

bootstrap_provider() {
  local vendor product
  vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
  case "${vendor} ${product}" in
    *Oracle*|*OCI*) printf 'Oracle Cloud' ;;
    *Amazon*|*EC2*) printf 'AWS' ;;
    *Google*) printf 'Google Cloud' ;;
    *Microsoft*|*Azure*) printf 'Microsoft Azure' ;;
    *) printf 'VPS/servidor' ;;
  esac
}

detect_existing_installation() {
  INSTALL_MARKERS=()
  [[ -r /etc/whatsapp-remote/config.env ]] && INSTALL_MARKERS+=("configuração atual")
  [[ -r /etc/whatsapp-remote.conf ]] && INSTALL_MARKERS+=("configuração antiga")
  [[ -d /opt/whatsapp-remote ]] && INSTALL_MARKERS+=("arquivos em /opt")
  [[ -f /etc/systemd/system/whatsapp-desktop.service || -f /lib/systemd/system/whatsapp-desktop.service ]] && INSTALL_MARKERS+=("serviço desktop")
  [[ -f /etc/systemd/system/whatsapp-browser.service || -f /lib/systemd/system/whatsapp-browser.service ]] && INSTALL_MARKERS+=("serviço navegador")
  [[ -f /etc/systemd/system/whatsapp-novnc.service || -f /lib/systemd/system/whatsapp-novnc.service ]] && INSTALL_MARKERS+=("serviço noVNC")
  if [[ -e /usr/local/sbin/whatsapp-remote ]] \
    || grep -q 'WHATSAPP_REMOTE_MENU_WRAPPER' /usr/local/bin/menu 2>/dev/null; then
    INSTALL_MARKERS+=("comando Manager")
  fi
  [[ -f /etc/nginx/sites-available/whatsapp-remote ]] && INSTALL_MARKERS+=("site Nginx")

  if [[ -x /opt/whatsapp-remote/manage.sh && -r /opt/whatsapp-remote/lib/common.sh ]]; then
    MANAGER_TARGET="/opt/whatsapp-remote/manage.sh"
  elif [[ -x /usr/local/sbin/whatsapp-remote ]]; then
    MANAGER_TARGET="/usr/local/sbin/whatsapp-remote"
  else
    MANAGER_TARGET=""
  fi

  if (( ${#INSTALL_MARKERS[@]} == 0 )); then
    INSTALL_STATE="none"
  elif [[ -r /etc/whatsapp-remote/config.env && -x /opt/whatsapp-remote/manage.sh ]]; then
    INSTALL_STATE="complete"
  elif [[ -r /etc/whatsapp-remote.conf ]]; then
    INSTALL_STATE="legacy"
  else
    INSTALL_STATE="partial"
  fi
}

bootstrap_system_summary() {
  local os_name="desconhecido" os_id="" os_version="" arch mem disk ip provider compatibility
  BOOTSTRAP_SUPPORTED=0
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_version="${VERSION_ID:-}"
    os_name="${PRETTY_NAME:-${os_id:-Linux} ${os_version}}"
  fi
  arch="$(uname -m 2>/dev/null || echo desconhecida)"
  case "${os_id}:${os_version}:${arch}" in
    ubuntu:20.04:x86_64|ubuntu:20.04:aarch64|ubuntu:22.04:x86_64|ubuntu:22.04:aarch64|ubuntu:24.04:x86_64|ubuntu:24.04:aarch64|debian:11:x86_64|debian:11:aarch64|debian:12:x86_64|debian:12:aarch64)
      BOOTSTRAP_SUPPORTED=1 ;;
  esac
  if (( BOOTSTRAP_SUPPORTED == 1 )); then
    compatibility="suportado"
  else
    compatibility="não suportado por esta versão"
  fi
  mem="$(free -h 2>/dev/null | awk '/Mem:/ {print $2}' || true)"
  disk="$(df -h / 2>/dev/null | awk 'NR==2 {print $4}' || true)"
  ip="$(bootstrap_public_ip || true)"
  provider="$(bootstrap_provider)"
  printf ' Sistema:      %s\n' "$os_name" > /dev/tty
  printf ' Arquitetura:  %s\n' "$arch" > /dev/tty
  printf ' Compatível:   %s\n' "$compatibility" > /dev/tty
  printf ' Provedor:     %s\n' "$provider" > /dev/tty
  printf ' IP público:   %s\n' "${ip:-não detectado}" > /dev/tty
  printf ' RAM / disco:  %s / %s livres\n' "${mem:-indisponível}" "${disk:-indisponível}" > /dev/tty
}

bootstrap_service_state() {
  local service="$1" state
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  [[ "$state" == "active" ]] && printf '%bativo%b' "$C_GREEN" "$C_RESET" || printf '%binativo%b' "$C_RED" "$C_RESET"
}

bootstrap_existing_health() {
  local errors=0 warnings=0 browser_state="inativo" state_label markers_text="" marker
  case "$INSTALL_STATE" in
    complete) state_label="completa" ;;
    legacy) state_label="versão antiga — migração disponível" ;;
    partial) state_label="parcial ou danificada" ;;
    *) state_label="$INSTALL_STATE" ;;
  esac
  for marker in "${INSTALL_MARKERS[@]}"; do
    markers_text+="${markers_text:+, }${marker}"
  done
  printf '\n%bResumo da instalação encontrada%b\n' "$C_BOLD" "$C_RESET" > /dev/tty
  printf ' Estado detectado: %s\n' "$state_label" > /dev/tty
  printf ' Componentes: %s\n' "${markers_text:-não identificados}" > /dev/tty
  printf ' Desktop: %b | Browser: %b | noVNC: %b | Nginx: %b\n' \
    "$(bootstrap_service_state whatsapp-desktop.service)" \
    "$(bootstrap_service_state whatsapp-browser.service)" \
    "$(bootstrap_service_state whatsapp-novnc.service)" \
    "$(bootstrap_service_state nginx)" > /dev/tty
  pgrep -f 'chrome|chromium' >/dev/null 2>&1 && browser_state="ativo"
  printf ' Navegador: %s\n' "$browser_state" > /dev/tty

  [[ -r /etc/whatsapp-remote/config.env || -r /etc/whatsapp-remote.conf ]] || errors=$((errors + 1))
  systemctl is-active --quiet whatsapp-desktop.service 2>/dev/null || errors=$((errors + 1))
  systemctl is-active --quiet whatsapp-browser.service 2>/dev/null || warnings=$((warnings + 1))
  systemctl is-active --quiet whatsapp-novnc.service 2>/dev/null || errors=$((errors + 1))
  systemctl is-active --quiet nginx 2>/dev/null || errors=$((errors + 1))
  [[ "$browser_state" == "ativo" ]] || warnings=$((warnings + 1))
  [[ -n "$MANAGER_TARGET" ]] || warnings=$((warnings + 1))

  if (( errors == 0 && warnings == 0 )); then
    printf ' Saúde rápida: %bnenhum problema detectado%b\n' "$C_GREEN" "$C_RESET" > /dev/tty
  else
    printf ' Saúde rápida: %b%s erro(s)%b e %b%s aviso(s)%b\n' \
      "$C_RED" "$errors" "$C_RESET" "$C_YELLOW" "$warnings" "$C_RESET" > /dev/tty
    printf ' Recomendação: execute a reparação automática antes de usar.\n' > /dev/tty
  fi
}

run_local_manager() {
  local command="${1:-menu}"
  if [[ -x /opt/whatsapp-remote/manage.sh && -r /opt/whatsapp-remote/lib/common.sh ]]; then
    bash /opt/whatsapp-remote/manage.sh "$command" < /dev/tty > /dev/tty 2>&1
    return $?
  fi
  if [[ -x /usr/local/sbin/whatsapp-remote ]]; then
    /usr/local/sbin/whatsapp-remote "$command" < /dev/tty > /dev/tty 2>&1
    return $?
  fi
  return 1
}

new_install_menu() {
  local choice
  while true; do
    clear </dev/tty 2>/dev/null || true
    printf '%bWhatsApp Remote VPS%b\n' "$C_BOLD$C_CYAN" "$C_RESET" > /dev/tty
    printf 'Assistente de instalação inteligente\n' > /dev/tty
    printf '%s\n' '────────────────────────────────────────────────────────────' > /dev/tty
    bootstrap_system_summary
    printf '\n%bNenhuma instalação anterior foi encontrada.%b\n\n' "$C_GREEN" "$C_RESET" > /dev/tty
    cat > /dev/tty <<'MENU'
  1) Instalação automática recomendada
     Detecta tudo e aplica as melhores configurações.

  2) Instalação manual/personalizada
     Permite revisar e corrigir usuário, senhas, resolução e acesso.

  3) Ver compatibilidade e requisitos
  0) Sair
MENU
    printf '\n' > /dev/tty
    read -r -p "Escolha: " choice < /dev/tty
    case "$choice" in
      1)
        if (( BOOTSTRAP_SUPPORTED == 0 )); then warn "Este sistema/arquitetura não é compatível com esta versão."; pause_tty; continue; fi
        INSTALL_ARGS=(--auto); ACTION="install"; return 0 ;;
      2)
        if (( BOOTSTRAP_SUPPORTED == 0 )); then warn "Este sistema/arquitetura não é compatível com esta versão."; pause_tty; continue; fi
        INSTALL_ARGS=(); ACTION="install"; return 0 ;;
      3)
        cat > /dev/tty <<'DETAILS'

Compatível com:
  • Ubuntu 20.04, 22.04 e 24.04
  • Debian 11 e 12
  • x86-64/amd64 e arm64/aarch64
  • systemd e acesso root

O instalador detecta IP, arquitetura, RAM, disco, swap e navegador.
Portas externas: TCP 443; TCP 80 somente para domínio/Let's Encrypt.
Portas 5901 e 6080 devem permanecer fechadas para a Internet.

DETAILS
        pause_tty ;;
      0) echo "Instalação cancelada." > /dev/tty; exit 0 ;;
      *) warn "Opção inválida."; pause_tty ;;
    esac
  done
}

existing_install_menu() {
  local choice confirmation
  while true; do
    clear </dev/tty 2>/dev/null || true
    printf '%bWhatsApp Remote VPS%b\n' "$C_BOLD$C_CYAN" "$C_RESET" > /dev/tty
    printf 'Instalação anterior detectada\n' > /dev/tty
    printf '%s\n' '────────────────────────────────────────────────────────────' > /dev/tty
    bootstrap_system_summary
    bootstrap_existing_health
    printf '\n' > /dev/tty
    cat > /dev/tty <<'MENU'
  1) Reparar/atualizar preservando a sessão do WhatsApp
  2) Abrir o Manager
  3) Ver status e diagnóstico detalhado
  4) Reinstalar tudo do zero (apaga a sessão)
  5) Desinstalar
  0) Sair sem alterar nada
MENU
    printf '\n' > /dev/tty
    read -r -p "Escolha: " choice < /dev/tty
    case "$choice" in
      1) INSTALL_ARGS=(--repair --auto); ACTION="install"; return 0 ;;
      2)
        if ! run_local_manager menu; then
          warn "O Manager local está ausente ou danificado. Escolha a opção 1 para reparar."
          pause_tty
        fi ;;
      3)
        if run_local_manager status; then
          pause_tty
        else
          warn "O diagnóstico completo não está disponível. Escolha a opção 1 para reparar."
          pause_tty
        fi ;;
      4)
        printf '\n%bATENÇÃO:%b esta opção apaga o perfil do navegador e desconecta o WhatsApp.\n' "$C_RED" "$C_RESET" > /dev/tty
        read -r -p "Digite REINSTALAR para confirmar: " confirmation < /dev/tty
        if [[ "$confirmation" == "REINSTALAR" ]]; then ACTION="reinstall"; return 0; fi
        warn "Confirmação inválida; nenhuma alteração foi feita."; pause_tty ;;
      5)
        printf '\nEsta opção removerá os serviços e o acesso remoto.\n' > /dev/tty
        read -r -p "Digite DESINSTALAR para continuar: " confirmation < /dev/tty
        if [[ "$confirmation" == "DESINSTALAR" ]]; then ACTION="uninstall"; return 0; fi
        warn "Confirmação inválida; nenhuma alteração foi feita."; pause_tty ;;
      0) echo "Nenhuma alteração realizada." > /dev/tty; exit 0 ;;
      *) warn "Opção inválida."; pause_tty ;;
    esac
  done
}

detect_existing_installation
if (( ${#INSTALL_ARGS[@]} == 0 )); then
  if (( USE_TTY == 1 )); then
    if [[ "$INSTALL_STATE" == "none" ]]; then new_install_menu; else existing_install_menu; fi
  else
    if [[ "$INSTALL_STATE" == "none" ]]; then
      warn "Terminal interativo indisponível; usando instalação automática."
      INSTALL_ARGS=(--auto)
    else
      warn "Instalação anterior detectada e terminal interativo indisponível; usando reparação automática."
      INSTALL_ARGS=(--repair --auto)
    fi
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

REQUIRED_FILES=(install.sh manage.sh repair.sh status.sh uninstall.sh lib/common.sh)
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
    warn "A estrutura e a sintaxe foram validadas; a operação continuará."
  fi
fi

chmod 755 "$SOURCE_DIR"/*.sh "$SOURCE_DIR/lib/common.sh"
cd "$SOURCE_DIR"
case "$ACTION" in
  install)
    info "Executando o instalador universal..."
    if (( USE_TTY == 1 )); then bash ./install.sh "${INSTALL_ARGS[@]}" < /dev/tty; else bash ./install.sh "${INSTALL_ARGS[@]}"; fi
    info "Operação concluída. Abra o menu digitando: menu"
    ;;
  uninstall)
    info "Abrindo o desinstalador..."
    if (( USE_TTY == 1 )); then bash ./uninstall.sh < /dev/tty; else bash ./uninstall.sh --yes; fi
    ;;
  reinstall)
    info "Criando uma instalação limpa..."
    bash ./uninstall.sh --purge --yes --keep-swap
    bash ./install.sh --auto
    ok "Reinstalação concluída. Abra o menu digitando: menu"
    ;;
  *) die "Ação interna inválida: $ACTION" ;;
esac
