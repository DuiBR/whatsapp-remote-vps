#!/usr/bin/env bash
# Funções compartilhadas do WhatsApp Remote VPS.

PROJECT_NAME="WhatsApp Remote VPS"
PROJECT_VERSION="2.5.2"
GITHUB_REPOSITORY_DEFAULT="DuiBR/whatsapp-remote-vps"
GITHUB_REF_DEFAULT="main"
INSTALL_DIR="/opt/whatsapp-remote"
CONFIG_DIR="/etc/whatsapp-remote"
CONFIG_FILE="${CONFIG_DIR}/config.env"
CONFIG_BACKUP_DIR="/var/backups/whatsapp-remote"
CREDENTIALS_FILE="/root/whatsapp-remote-credentials.txt"
INSTALL_LOG="/var/log/whatsapp-remote-install.log"
SERVICE_DESKTOP="whatsapp-desktop.service"
SERVICE_BROWSER="whatsapp-browser.service"
SERVICE_NOVNC="whatsapp-novnc.service"
NGINX_SITE="/etc/nginx/sites-available/whatsapp-remote"
NGINX_LINK="/etc/nginx/sites-enabled/whatsapp-remote"
HTPASSWD_FILE="/etc/nginx/.htpasswd-whatsapp"
SSL_DIR="/etc/nginx/ssl-whatsapp"
MENU_COMMAND="/usr/local/bin/menu"
WHATSAPP_STATUS_HELPER="/usr/local/bin/whatsapp-session-status"
BROWSER_LOG_DIR="/var/log/whatsapp-remote"
BROWSER_LOG_FILE="${BROWSER_LOG_DIR}/browser.log"
BROWSER_STATE_FILE=""

if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[1;31m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_BLUE=$'\033[1;34m'
  C_CYAN=$'\033[1;36m'
  C_GRAY=$'\033[0;37m'
else
  C_RESET='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_GRAY=''
fi

info() { printf "%b[INFO]%b %s\n" "$C_BLUE" "$C_RESET" "$*"; }
ok() { printf "%b[OK]%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%b[AVISO]%b %s\n" "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf "%b[ERRO]%b %s\n" "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

ui_clear() { clear 2>/dev/null || printf '\n'; }
ui_rule() { printf '%s\n' '────────────────────────────────────────────────────────────'; }
ui_header() {
  local subtitle="${1:-}"
  ui_clear
  printf "%b%s%b\n" "$C_BOLD$C_CYAN" "$PROJECT_NAME" "$C_RESET"
  [[ -n "$subtitle" ]] && printf '%s\n' "$subtitle"
  ui_rule
}
ui_pause() {
  [[ -r /dev/tty ]] || return 0
  printf '\n'
  read -r -p "Pressione Enter para continuar..." _ < /dev/tty || true
}
ui_yes_no() {
  local prompt="$1" default="${2:-n}" answer suffix
  if [[ "$default" == "s" ]]; then suffix='[S/n]'; else suffix='[s/N]'; fi
  while true; do
    read -r -p "$prompt $suffix: " answer
    answer="${answer:-$default}"
    case "$answer" in
      s|S|sim|SIM|Sim|y|Y|yes|YES|Yes) return 0 ;;
      n|N|nao|não|NAO|NÃO|No|NO|no) return 1 ;;
      *) warn "Responda com s ou n." ;;
    esac
  done
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Execute como root. Exemplo: sudo bash $0"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }
shell_quote() { printf '%q' "$1"; }

is_valid_linux_user() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || return 1
  [[ "$1" != "root" ]]
}

is_valid_web_user() {
  [[ -n "$1" && "$1" != *:* && "$1" != *$'\n'* && ${#1} -le 64 ]]
}

is_valid_geometry() {
  [[ "$1" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]] || return 1
  local width="${1%x*}" height="${1#*x}"
  (( width >= 800 && width <= 7680 && height >= 600 && height <= 4320 ))
}

is_valid_ipv4() {
  local ip="$1" IFS=. octets=() octet
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
  done
}

is_public_ipv4() {
  local ip="$1" a b
  is_valid_ipv4 "$ip" || return 1
  IFS=. read -r a b _ _ <<< "$ip"
  (( a == 10 || a == 127 || a == 0 )) && return 1
  (( a == 169 && b == 254 )) && return 1
  (( a == 172 && b >= 16 && b <= 31 )) && return 1
  (( a == 192 && b == 168 )) && return 1
  (( a >= 224 )) && return 1
  return 0
}

is_valid_domain() {
  [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

is_valid_email() {
  [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

random_password() {
  local length="${1:-16}" result=""
  if command_exists openssl; then
    result="$(openssl rand -base64 64 2>/dev/null | tr -dc 'A-Za-z0-9@#%+=_' | head -c "$length" || true)"
  fi
  if (( ${#result} < length )); then
    result="$(tr -dc 'A-Za-z0-9@#%+=_' </dev/urandom | head -c "$length" || true)"
  fi
  [[ ${#result} -ge length ]] || die "Não foi possível gerar uma senha segura."
  printf '%s' "$result"
}

wait_for_apt() {
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
    (( waited == 0 )) && info "Aguardando outro processo APT terminar..."
    sleep 3
    waited=$((waited + 3))
    (( waited < 600 )) || die "O APT permaneceu bloqueado por mais de 10 minutos."
  done
}

apt_recover() {
  wait_for_apt
  dpkg --configure -a >/dev/null 2>&1 || true
  DEBIAN_FRONTEND=noninteractive apt-get -f install -y >/dev/null 2>&1 || true
}

apt_update_retry() {
  local attempt
  wait_for_apt
  for attempt in 1 2 3; do
    if DEBIAN_FRONTEND=noninteractive apt-get update; then return 0; fi
    warn "apt-get update falhou (tentativa ${attempt}/3)."
    apt_recover
    sleep $((attempt * 3))
  done
  die "Não foi possível atualizar os repositórios APT."
}

apt_install_retry() {
  local attempt
  wait_for_apt
  for attempt in 1 2 3; do
    if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; then return 0; fi
    warn "Instalação de pacotes falhou (tentativa ${attempt}/3)."
    apt_recover
    sleep $((attempt * 3))
  done
  die "Não foi possível instalar os pacotes necessários: $*"
}

detect_platform() {
  [[ -r /etc/os-release ]] || die "Não foi possível identificar o sistema operacional."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-}"
  OS_VERSION="${VERSION_ID:-}"
  OS_NAME="${PRETTY_NAME:-${OS_ID} ${OS_VERSION}}"

  case "$OS_ID:$OS_VERSION" in
    ubuntu:20.04|ubuntu:22.04|ubuntu:24.04|debian:11|debian:12) ;;
    *) die "Sistema não suportado: ${OS_NAME}. Compatíveis: Ubuntu 20.04/22.04/24.04 e Debian 11/12." ;;
  esac

  local raw_arch
  raw_arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "$raw_arch" in
    amd64|x86_64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) die "Arquitetura não suportada: ${raw_arch}. Compatíveis: x86_64/amd64 e aarch64/arm64." ;;
  esac

  export OS_ID OS_VERSION OS_NAME ARCH
}

detect_cloud_provider() {
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

detect_private_ip() {
  local ip
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
  is_valid_ipv4 "$ip" && printf '%s' "$ip"
}

detect_public_ip() {
  local ip="" endpoint metadata

  # Oracle Cloud Instance Metadata v2, quando disponível.
  metadata="$(curl -4 -fsS --connect-timeout 1 --max-time 2 \
    -H 'Authorization: Bearer Oracle' \
    http://169.254.169.254/opc/v2/vnics/ 2>/dev/null || true)"
  if [[ -n "$metadata" ]]; then
    ip="$(printf '%s' "$metadata" | grep -oE '"publicIp"[[:space:]]*:[[:space:]]*"([0-9]{1,3}\.){3}[0-9]{1,3}"' | head -n1 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)"
    if is_public_ipv4 "$ip"; then printf '%s' "$ip"; return 0; fi
  fi

  for endpoint in \
    "https://api.ipify.org" \
    "https://checkip.amazonaws.com" \
    "https://ifconfig.me/ip" \
    "https://icanhazip.com"; do
    ip="$(curl -4 -fsS --connect-timeout 4 --max-time 8 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
    if is_public_ipv4 "$ip"; then printf '%s' "$ip"; return 0; fi
  done

  # Último recurso: endereço global diretamente atribuído à interface.
  while read -r ip; do
    if is_public_ipv4 "$ip"; then printf '%s' "$ip"; return 0; fi
  done < <(ip -o -4 addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}')
  return 1
}

memory_mb() { awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo; }
disk_free_mb() { df -Pm / | awk 'NR==2 {print $4}'; }

recommended_geometry() {
  local mem
  mem="$(memory_mb)"
  if (( mem < 900 )); then printf '1024x768'; else printf '1280x720'; fi
}

recommended_swap_mb() {
  local mem current_swap
  mem="$(memory_mb)"
  current_swap="$(awk '/SwapTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
  if (( current_swap > 0 )); then printf '0'; return; fi
  if (( mem < 1600 )); then printf '2048'
  elif (( mem < 3000 )); then printf '1024'
  else printf '0'
  fi
}

preflight_checks() {
  detect_platform
  command_exists systemctl || die "Este instalador exige systemd."
  command_exists apt-get || die "apt-get não encontrado."
  local free_mb mem_mb
  free_mb="$(disk_free_mb)"
  mem_mb="$(memory_mb)"
  (( free_mb >= 2500 )) || die "Espaço insuficiente. São necessários pelo menos 2,5 GB livres; disponível: ${free_mb} MB."
  (( mem_mb >= 500 )) || warn "A máquina possui somente ${mem_mb} MB de RAM. O sistema tentará criar swap, mas pode ficar lento."
  if ! getent hosts github.com >/dev/null 2>&1 && ! getent hosts dl.google.com >/dev/null 2>&1; then
    warn "A resolução DNS parece indisponível. A instalação poderá falhar ao baixar pacotes."
  fi
}

backup_current_config() {
  [[ -d "$CONFIG_DIR" || -d "$INSTALL_DIR" ]] || return 0
  install -d -m 700 "$CONFIG_BACKUP_DIR"
  local stamp archive
  stamp="$(date +%Y%m%d-%H%M%S)"
  archive="$CONFIG_BACKUP_DIR/config-${stamp}.tar.gz"
  tar -czf "$archive" \
    --ignore-failed-read \
    "$CONFIG_DIR" "$HTPASSWD_FILE" "$NGINX_SITE" "$SSL_DIR" 2>/dev/null || true
  chmod 600 "$archive" 2>/dev/null || true
}

load_config() {
  [[ -r "$CONFIG_FILE" ]] || die "Configuração não encontrada: $CONFIG_FILE"
  local runtime_project_name="$PROJECT_NAME"
  local runtime_project_version="$PROJECT_VERSION"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  # A configuração antiga não pode sobrescrever a versão do código instalado.
  PROJECT_NAME="$runtime_project_name"
  PROJECT_VERSION="$runtime_project_version"
  : "${APP_USER:?APP_USER ausente}"
  : "${APP_GROUP:?APP_GROUP ausente}"
  : "${APP_HOME:?APP_HOME ausente}"
  : "${PROFILE_DIR:=${APP_HOME}/.config/chrome-whatsapp}"
  : "${APP_UID:?APP_UID ausente}"
  : "${APP_GID:?APP_GID ausente}"
  BROWSER_STATE_FILE="/run/user/${APP_UID}/whatsapp-remote-browser.state"
  : "${APP_USER_MANAGED:=0}"
  : "${DISPLAY_NUMBER:=1}"
  : "${GEOMETRY:=1280x720}"
  : "${VNC_PORT:=$((5900 + DISPLAY_NUMBER))}"
  : "${NOVNC_PORT:=6080}"
  : "${CDP_PORT:=9222}"
  : "${BROWSER_BIN:?BROWSER_BIN ausente}"
  : "${BROWSER_TYPE:=chromium}"
  : "${LOW_RAM:=0}"
  : "${BROWSER_SANDBOX_MODE:=auto}"
  : "${ALLOW_UNSANDBOXED_FALLBACK:=0}"
  : "${ACCESS_MODE:=ip}"
  : "${PUBLIC_IP:=}"
  : "${DOMAIN:=}"
  : "${WEB_USER:=remoteadmin}"
  : "${GITHUB_REPOSITORY:=$GITHUB_REPOSITORY_DEFAULT}"
  : "${GITHUB_REF:=$GITHUB_REF_DEFAULT}"
}

save_config() {
  install -d -m 750 -o root -g "$APP_GROUP" "$CONFIG_DIR"
  local tmp
  tmp="$(mktemp)"
  {
    printf 'OS_ID=%q\n' "$OS_ID"
    printf 'OS_VERSION=%q\n' "$OS_VERSION"
    printf 'ARCH=%q\n' "$ARCH"
    printf 'APP_USER=%q\n' "$APP_USER"
    printf 'APP_GROUP=%q\n' "$APP_GROUP"
    printf 'APP_HOME=%q\n' "$APP_HOME"
    printf 'PROFILE_DIR=%q\n' "$PROFILE_DIR"
    printf 'APP_UID=%q\n' "$APP_UID"
    printf 'APP_GID=%q\n' "$APP_GID"
    printf 'APP_USER_MANAGED=%q\n' "${APP_USER_MANAGED:-0}"
    printf 'DISPLAY_NUMBER=%q\n' "$DISPLAY_NUMBER"
    printf 'GEOMETRY=%q\n' "$GEOMETRY"
    printf 'VNC_PORT=%q\n' "$VNC_PORT"
    printf 'NOVNC_PORT=%q\n' "$NOVNC_PORT"
    printf 'CDP_PORT=%q\n' "${CDP_PORT:-9222}"
    printf 'BROWSER_BIN=%q\n' "$BROWSER_BIN"
    printf 'BROWSER_TYPE=%q\n' "$BROWSER_TYPE"
    printf 'LOW_RAM=%q\n' "$LOW_RAM"
    printf 'BROWSER_SANDBOX_MODE=%q\n' "${BROWSER_SANDBOX_MODE:-auto}"
    printf 'ALLOW_UNSANDBOXED_FALLBACK=%q\n' "${ALLOW_UNSANDBOXED_FALLBACK:-0}"
    printf 'ACCESS_MODE=%q\n' "$ACCESS_MODE"
    printf 'PUBLIC_IP=%q\n' "$PUBLIC_IP"
    printf 'DOMAIN=%q\n' "$DOMAIN"
    printf 'WEB_USER=%q\n' "$WEB_USER"
    printf 'GITHUB_REPOSITORY=%q\n' "${GITHUB_REPOSITORY:-$GITHUB_REPOSITORY_DEFAULT}"
    printf 'GITHUB_REF=%q\n' "${GITHUB_REF:-$GITHUB_REF_DEFAULT}"
  } > "$tmp"
  chown root:"$APP_GROUP" "$tmp"
  chmod 640 "$tmp"
  mv -f "$tmp" "$CONFIG_FILE"
}

find_vnc_password_command() {
  local candidate
  for candidate in tigervncpasswd vncpasswd; do
    if command_exists "$candidate"; then command -v "$candidate"; return 0; fi
  done
  return 1
}

set_vnc_password() {
  local password="$1" pass_cmd
  [[ ${#password} -ge 8 ]] || die "A senha VNC precisa ter pelo menos 8 caracteres."
  pass_cmd="$(find_vnc_password_command)" || die "tigervncpasswd/vncpasswd não encontrado."
  install -d -m 700 -o "$APP_USER" -g "$APP_GROUP" "$APP_HOME/.vnc"
  printf '%s\n' "$password" | "$pass_cmd" -f > "$APP_HOME/.vnc/passwd"
  chown "$APP_USER:$APP_GROUP" "$APP_HOME/.vnc/passwd"
  chmod 600 "$APP_HOME/.vnc/passwd"
}

set_web_credentials() {
  local username="$1" password="$2"
  is_valid_web_user "$username" || die "Usuário web inválido."
  [[ ${#password} -ge 10 ]] || die "A senha web precisa ter pelo menos 10 caracteres."
  command_exists htpasswd || die "Comando htpasswd não encontrado."
  htpasswd -bcB "$HTPASSWD_FILE" "$username" "$password" >/dev/null
  chown root:www-data "$HTPASSWD_FILE"
  chmod 640 "$HTPASSWD_FILE"
  WEB_USER="$username"
}

credential_value() {
  local label="$1" value=""
  [[ -r "$CREDENTIALS_FILE" ]] || return 1
  value="$(awk -v prefix="${label}: " 'index($0,prefix)==1 {sub(prefix,""); print; exit}' "$CREDENTIALS_FILE" 2>/dev/null || true)"
  [[ -n "$value" && "$value" != não\ recuperável* && "$value" != não\ armazenada* ]] || return 1
  printf '%s' "$value"
}

write_credentials_file() {
  local vnc_password="${1:-}" web_password="${2:-}"
  local previous_vnc="" previous_web=""

  previous_vnc="$(credential_value 'Senha VNC' || true)"
  previous_web="$(credential_value 'Senha web' || true)"
  [[ -n "$vnc_password" ]] || vnc_password="$previous_vnc"
  [[ -n "$web_password" ]] || web_password="$previous_web"

  umask 077
  {
    echo "$PROJECT_NAME $PROJECT_VERSION"
    echo "Atualizado em: $(date -Is)"
    echo "URL: $(access_url)"
    echo
    echo "ACESSO WEB"
    echo "Usuário web: $WEB_USER"
    if [[ -n "$web_password" ]]; then
      echo "Senha web: $web_password"
    else
      echo "Senha web: não armazenada; redefina com 'menu' ou 'whatsapp-remote web-credentials'"
    fi
    echo
    echo "DESKTOP REMOTO"
    echo "Usuário do desktop Linux: $APP_USER"
    if [[ -n "$vnc_password" ]]; then
      echo "Senha VNC: $vnc_password"
    else
      echo "Senha VNC: não armazenada; redefina com 'menu' ou 'whatsapp-remote vnc-password'"
    fi
    echo
    echo "Observação: o noVNC normalmente solicita apenas a senha VNC."
    echo "Observação: o protocolo VNC clássico considera somente os primeiros 8 caracteres."
  } > "$CREDENTIALS_FILE"
  chmod 600 "$CREDENTIALS_FILE"
}

install_manager_command() {
  local target="/usr/local/sbin/whatsapp-remote"
  rm -f "$target"
  cat > "$target" <<'MANAGER_WRAPPER'
#!/usr/bin/env bash
# WHATSAPP_REMOTE_MANAGER_WRAPPER
set -Eeuo pipefail
TARGET="/opt/whatsapp-remote/manage.sh"
if [[ ! -x "$TARGET" ]]; then
  echo "WhatsApp Remote VPS não está instalado corretamente: $TARGET não encontrado." >&2
  exit 1
fi
exec "$TARGET" "$@"
MANAGER_WRAPPER
  chmod 755 "$target"
}

install_menu_command() {
  local target="$MENU_COMMAND" backup=""
  if [[ -e "$target" ]] && ! grep -q 'WHATSAPP_REMOTE_MENU_WRAPPER' "$target" 2>/dev/null; then
    backup="${target}.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a "$target" "$backup"
    warn "Já existia um comando 'menu'. Backup criado em: $backup"
  fi

  cat > "$target" <<'MENU_WRAPPER'
#!/usr/bin/env bash
# WHATSAPP_REMOTE_MENU_WRAPPER
set -e
MANAGER="/usr/local/sbin/whatsapp-remote"
if [[ ! -x "$MANAGER" ]]; then
  echo "WhatsApp Remote VPS ainda não está instalado corretamente." >&2
  exit 1
fi
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  exec "$MANAGER" menu "$@"
fi
if command -v sudo >/dev/null 2>&1; then
  exec sudo "$MANAGER" menu "$@"
fi
echo "Este menu exige privilégios de administrador. Execute: sudo whatsapp-remote" >&2
exit 1
MENU_WRAPPER
  chmod 755 "$target"
}

remove_menu_command() {
  if [[ -f "$MENU_COMMAND" ]] && grep -q 'WHATSAPP_REMOTE_MENU_WRAPPER' "$MENU_COMMAND" 2>/dev/null; then
    rm -f "$MENU_COMMAND"
  fi
}

access_url() {
  if [[ "${ACCESS_MODE:-ip}" == "domain" && -n "${DOMAIN:-}" ]]; then
    printf 'https://%s/' "$DOMAIN"
  elif [[ -n "${PUBLIC_IP:-}" ]]; then
    printf 'https://%s/' "$PUBLIC_IP"
  else
    printf 'https://IP_DA_VPS/'
  fi
}

find_novnc_webroot() {
  local path
  for path in /usr/share/novnc /usr/share/noVNC /opt/novnc; do
    if [[ -f "$path/vnc.html" ]]; then printf '%s' "$path"; return 0; fi
  done
  return 1
}

configure_novnc_mobile_defaults() {
  local webroot
  webroot="$(find_novnc_webroot)" || die "Diretório web do noVNC não encontrado."
  cat > "$webroot/mandatory.json" <<'JSON'
{
  "view_only": false,
  "resize": "scale",
  "reconnect": true,
  "reconnect_delay": 3000,
  "show_dot": true
}
JSON
  chmod 644 "$webroot/mandatory.json"
}


profile_dir_score() {
  local path="$1" size_kb=0 score=0
  [[ -d "$path" ]] || { printf '0'; return 0; }
  size_kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}' || echo 0)"
  [[ "$size_kb" =~ ^[0-9]+$ ]] || size_kb=0
  score="$size_kb"
  [[ -f "$path/Local State" ]] && score=$((score + 100000))
  [[ -d "$path/Default" ]] && score=$((score + 100000))
  [[ -f "$path/Default/Cookies" || -f "$path/Default/Network/Cookies" ]] && score=$((score + 250000))
  [[ -d "$path/Default/IndexedDB" ]] && score=$((score + 150000))
  printf '%s' "$score"
}

recover_profile_dir() {
  local configured="${PROFILE_DIR:-}" default_path candidate best="" best_score=-1 score
  local candidates=()

  if [[ "${BROWSER_TYPE:-}" == "Chromium Snap" ]]; then
    default_path="$APP_HOME/snap/chromium/common/whatsapp-profile"
  else
    default_path="$APP_HOME/.config/chrome-whatsapp"
  fi

  [[ -n "$configured" ]] && candidates+=("$configured")
  candidates+=(
    "$APP_HOME/.config/google-chrome-whatsapp"
    "$APP_HOME/.config/chrome-whatsapp"
    "$APP_HOME/snap/chromium/common/whatsapp-profile"
  )

  local seen='|'
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    [[ "$seen" == *"|$candidate|"* ]] && continue
    seen+="$candidate|"
    score="$(profile_dir_score "$candidate")"
    if (( score > best_score )); then
      best="$candidate"
      best_score="$score"
    fi
  done

  if [[ -z "$best" || "$best_score" -le 0 ]]; then best="$default_path"; fi
  if [[ -n "$configured" && "$configured" != "$best" ]]; then
    local configured_score
    configured_score="$(profile_dir_score "$configured")"
    if (( best_score > configured_score )); then
      warn "Perfil persistente mais completo encontrado em $best; ele será reutilizado para preservar a sessão do WhatsApp."
    else
      best="$configured"
    fi
  fi
  PROFILE_DIR="$best"
  install -d -m 700 -o "$APP_USER" -g "$APP_GROUP" "$PROFILE_DIR"
  chown -R "$APP_USER:$APP_GROUP" "$PROFILE_DIR" 2>/dev/null || true
}

render_runtime_scripts() {
  cat > /usr/local/bin/whatsapp-desktop-start <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
source /etc/whatsapp-remote/config.env
export HOME="$APP_HOME"
export USER="$APP_USER"
export LOGNAME="$APP_USER"
export DISPLAY=":${DISPLAY_NUMBER}"
export XDG_RUNTIME_DIR="/run/user/${APP_UID}"

install -d -m 700 "$XDG_RUNTIME_DIR"
rm -f "/tmp/.X${DISPLAY_NUMBER}-lock" 2>/dev/null || true
rm -f "/tmp/.X11-unix/X${DISPLAY_NUMBER}" 2>/dev/null || true

cleanup() {
  if [[ -n "${VNC_PID:-}" ]] && kill -0 "$VNC_PID" 2>/dev/null; then
    kill "$VNC_PID" 2>/dev/null || true
    wait "$VNC_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

XTIGERVNC="$(command -v Xtigervnc || command -v Xvnc || true)"
[[ -n "$XTIGERVNC" ]] || { echo "Xtigervnc/Xvnc não encontrado."; exit 1; }

"$XTIGERVNC" ":${DISPLAY_NUMBER}" \
  -localhost yes \
  -rfbport "$VNC_PORT" \
  -geometry "$GEOMETRY" \
  -depth 24 \
  -SecurityTypes VncAuth \
  -PasswordFile "$APP_HOME/.vnc/passwd" \
  -AlwaysShared \
  -AcceptKeyEvents \
  -AcceptPointerEvents \
  -SendCutText \
  -AcceptCutText &
VNC_PID=$!

for _ in $(seq 1 120); do
  DISPLAY=":${DISPLAY_NUMBER}" xdpyinfo >/dev/null 2>&1 && break
  sleep 0.25
done
DISPLAY=":${DISPLAY_NUMBER}" xdpyinfo >/dev/null 2>&1 || { echo "O servidor gráfico não iniciou corretamente."; exit 1; }
exec dbus-run-session -- openbox-session
SCRIPT
  chmod 755 /usr/local/bin/whatsapp-desktop-start

  cat > /usr/local/sbin/whatsapp-browser-preflight <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
source /etc/whatsapp-remote/config.env

LOG_DIR="/var/log/whatsapp-remote"
LOG_FILE="$LOG_DIR/browser.log"
RUNTIME_DIR="/run/user/${APP_UID}"

install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" "$LOG_DIR"
touch "$LOG_FILE"
chown "$APP_USER:$APP_GROUP" "$LOG_FILE"
chmod 0640 "$LOG_FILE"
install -d -m 0700 -o "$APP_UID" -g "$APP_GID" "$RUNTIME_DIR"
install -d -m 0700 -o "$APP_USER" -g "$APP_GROUP" \
  "$PROFILE_DIR" \
  "$PROFILE_DIR/Crash Reports" \
  "$APP_HOME/.cache" \
  "$APP_HOME/.local" \
  "$APP_HOME/.local/share" \
  "$APP_HOME/.local/share/applications" \
  "$APP_HOME/.config/google-chrome" \
  "$APP_HOME/.config/google-chrome/Crash Reports" \
  "$APP_HOME/.config/chromium" \
  "$APP_HOME/.config/chromium/Crash Reports"

chmod 1777 /tmp 2>/dev/null || true
[[ -d /dev/shm ]] && chmod 1777 /dev/shm 2>/dev/null || true

if command -v dbus-uuidgen >/dev/null 2>&1; then
  dbus-uuidgen --ensure=/etc/machine-id >/dev/null 2>&1 || true
  install -d -m 0755 /var/lib/dbus
  if [[ -s /etc/machine-id && ! -e /var/lib/dbus/machine-id ]]; then
    ln -s /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || cp -f /etc/machine-id /var/lib/dbus/machine-id
  fi
fi

REAL_BROWSER="$(readlink -f "$BROWSER_BIN" 2>/dev/null || printf '%s' "$BROWSER_BIN")"
for SANDBOX in \
  "$(dirname "$REAL_BROWSER")/chrome-sandbox" \
  /opt/google/chrome/chrome-sandbox \
  /usr/lib/chromium/chrome-sandbox \
  /usr/lib/chromium-browser/chrome-sandbox; do
  [[ -f "$SANDBOX" ]] || continue
  chown root:root "$SANDBOX" 2>/dev/null || true
  chmod 4755 "$SANDBOX" 2>/dev/null || true
  break
done

rm -f "$PROFILE_DIR/SingletonLock" "$PROFILE_DIR/SingletonSocket" "$PROFILE_DIR/SingletonCookie" 2>/dev/null || true
chown "$APP_USER:$APP_GROUP" "$PROFILE_DIR" "$LOG_DIR" "$LOG_FILE" 2>/dev/null || true
chown -R "$APP_USER:$APP_GROUP" \
  "$PROFILE_DIR/Crash Reports" \
  "$APP_HOME/.cache" \
  "$APP_HOME/.local" \
  "$APP_HOME/.config/google-chrome" \
  "$APP_HOME/.config/chromium" 2>/dev/null || true
SCRIPT
  chmod 755 /usr/local/sbin/whatsapp-browser-preflight

  cat > /usr/local/bin/whatsapp-browser <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
ulimit -c 0 2>/dev/null || true
source /etc/whatsapp-remote/config.env
export HOME="$APP_HOME"
export USER="$APP_USER"
export LOGNAME="$APP_USER"
export DISPLAY=":${DISPLAY_NUMBER}"
export XDG_RUNTIME_DIR="/run/user/${APP_UID}"
export XDG_CONFIG_HOME="$APP_HOME/.config"
export XDG_CACHE_HOME="$APP_HOME/.cache"
export XDG_DATA_HOME="$APP_HOME/.local/share"

LOG_DIR="/var/log/whatsapp-remote"
LOG_FILE="$LOG_DIR/browser.log"
STATE_FILE="/run/user/${APP_UID}/whatsapp-remote-browser.state"

for _ in $(seq 1 120); do
  DISPLAY=":${DISPLAY_NUMBER}" xdpyinfo >/dev/null 2>&1 && break
  sleep 0.5
done
DISPLAY=":${DISPLAY_NUMBER}" xdpyinfo >/dev/null 2>&1 || { echo "Display :${DISPLAY_NUMBER} indisponível para o navegador."; exit 1; }

install -d -m 700 \
  "$PROFILE_DIR" \
  "$PROFILE_DIR/Crash Reports" \
  "$XDG_RUNTIME_DIR" \
  "$XDG_CACHE_HOME" \
  "$XDG_DATA_HOME" \
  "$XDG_DATA_HOME/applications" \
  "$XDG_CONFIG_HOME/google-chrome" \
  "$XDG_CONFIG_HOME/google-chrome/Crash Reports" \
  "$XDG_CONFIG_HOME/chromium" \
  "$XDG_CONFIG_HOME/chromium/Crash Reports"
rm -f "$PROFILE_DIR/SingletonLock" "$PROFILE_DIR/SingletonSocket" "$PROFILE_DIR/SingletonCookie" 2>/dev/null || true

# O wrapper /usr/bin/google-chrome-stable executa integrações de desktop que não
# são necessárias numa VPS. O binário real é mais previsível sob systemd e foi
# o caminho utilizado pelas versões que funcionavam antes do serviço dedicado.
BROWSER_EXEC="$BROWSER_BIN"
if [[ "$BROWSER_BIN" == *google-chrome* && -x /opt/google/chrome/chrome ]]; then
  BROWSER_EXEC="/opt/google/chrome/chrome"
elif [[ "$BROWSER_BIN" == *google-chrome* && -x /opt/google/chrome/google-chrome ]]; then
  BROWSER_EXEC="/opt/google/chrome/google-chrome"
fi

COMMON_FLAGS=(
  --user-data-dir="$PROFILE_DIR"
  --no-first-run
  --no-default-browser-check
  --password-store=basic
  --disable-dev-shm-usage
  --disable-session-crashed-bubble
  --disable-gpu
  --disable-extensions
  --disable-sync
  --disable-background-mode
  --noerrdialogs
  --ozone-platform=x11
  --disable-features=Translate,MediaRouter
  --remote-debugging-address=127.0.0.1
  --remote-debugging-port="${CDP_PORT:-9222}"
  "--remote-allow-origins=*"
  --start-maximized
)
if [[ "$LOW_RAM" == "1" ]]; then
  COMMON_FLAGS+=(--process-per-site --renderer-process-limit=2 "--js-flags=--max-old-space-size=256")
fi

write_state() {
  local mode="$1" status="$2" detail="${3:-}"
  umask 022
  printf 'mode=%s\nstatus=%s\ndetail=%s\nupdated=%s\n' "$mode" "$status" "$detail" "$(date -Is)" > "$STATE_FILE"
}

run_mode() {
  local mode="$1" start rc elapsed
  local sandbox_flags=()
  case "$mode" in
    secure) ;;
    userns) sandbox_flags+=(--disable-setuid-sandbox) ;;
    none) sandbox_flags+=(--no-sandbox) ;;
    *) echo "Modo de sandbox inválido: $mode"; return 64 ;;
  esac

  write_state "$mode" starting
  {
    echo
    echo "===== $(date -Is) | iniciando navegador | sandbox=$mode ====="
    echo "Binário configurado: $BROWSER_BIN"
    echo "Binário executado:   $BROWSER_EXEC"
    echo "Perfil:              $PROFILE_DIR"
    echo "Crashpad DB:          $XDG_CONFIG_HOME/google-chrome/Crash Reports"
  } >> "$LOG_FILE"

  start="$(date +%s)"
  set +e
  dbus-run-session -- "$BROWSER_EXEC" "${COMMON_FLAGS[@]}" "${sandbox_flags[@]}" "https://web.whatsapp.com/" \
    > >(tee -a "$LOG_FILE") 2>&1
  rc=$?
  set -e
  elapsed=$(( $(date +%s) - start ))
  write_state "$mode" exited "rc=$rc elapsed=${elapsed}s"
  printf 'Navegador encerrou: modo=%s rc=%s duração=%ss\n' "$mode" "$rc" "$elapsed" | tee -a "$LOG_FILE"
  LAST_ELAPSED="$elapsed"
  return "$rc"
}

requested="${BROWSER_SANDBOX_MODE:-auto}"
case "$requested" in
  secure|userns|none)
    if [[ "$requested" == "none" && "${ALLOW_UNSANDBOXED_FALLBACK:-0}" != "1" ]]; then
      echo "Modo sem sandbox bloqueado. Defina ALLOW_UNSANDBOXED_FALLBACK=1 somente em emergência." | tee -a "$LOG_FILE"
      exit 78
    fi
    run_mode "$requested"
    exit $?
    ;;
  auto) ;;
  *) echo "BROWSER_SANDBOX_MODE inválido: $requested" | tee -a "$LOG_FILE"; exit 64 ;;
esac

if run_mode secure; then exit 0; else secure_rc=$?; fi
if (( ${LAST_ELAPSED:-0} >= 20 )); then exit "$secure_rc"; fi

echo "Tentativa segura falhou rapidamente; testando sandbox por user namespace." | tee -a "$LOG_FILE"
if run_mode userns; then exit 0; else userns_rc=$?; fi
if (( ${LAST_ELAPSED:-0} >= 20 )); then exit "$userns_rc"; fi

if [[ "${ALLOW_UNSANDBOXED_FALLBACK:-0}" == "1" ]]; then
  echo "AVISO: iniciando em modo emergencial sem sandbox." | tee -a "$LOG_FILE"
  run_mode none
  exit $?
fi

echo "Todas as tentativas protegidas falharam. Consulte $LOG_FILE." | tee -a "$LOG_FILE"
exit "$userns_rc"
SCRIPT
  chmod 755 /usr/local/bin/whatsapp-browser

  cat > "$WHATSAPP_STATUS_HELPER" <<'PYTHON'
#!/usr/bin/env python3
# Consulta localmente o Chrome DevTools e estima o estado do WhatsApp Web.
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import urllib.parse
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 9222


def emit(code: str, message: str) -> None:
    print(f"{code}|{message}")


def recv_exact(sock: socket.socket, length: int) -> bytes:
    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            raise ConnectionError("WebSocket encerrado")
        data += chunk
    return data


def send_frame(sock: socket.socket, payload: bytes, opcode: int = 1) -> None:
    mask = os.urandom(4)
    size = len(payload)
    header = bytearray([0x80 | opcode])
    if size < 126:
        header.append(0x80 | size)
    elif size < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", size))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", size))
    header.extend(mask)
    masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    sock.sendall(bytes(header) + masked)


def recv_message(sock: socket.socket) -> str:
    fragments = []
    while True:
        first, second = recv_exact(sock, 2)
        fin = bool(first & 0x80)
        opcode = first & 0x0F
        masked = bool(second & 0x80)
        length = second & 0x7F
        if length == 126:
            length = struct.unpack("!H", recv_exact(sock, 2))[0]
        elif length == 127:
            length = struct.unpack("!Q", recv_exact(sock, 8))[0]
        mask = recv_exact(sock, 4) if masked else b""
        payload = recv_exact(sock, length) if length else b""
        if masked:
            payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        if opcode == 8:
            raise ConnectionError("WebSocket fechado")
        if opcode == 9:
            send_frame(sock, payload, 10)
            continue
        if opcode in (0, 1):
            fragments.append(payload)
            if fin:
                return b"".join(fragments).decode("utf-8", "replace")


def websocket_eval(ws_url: str, expression: str):
    parsed = urllib.parse.urlparse(ws_url)
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or 80
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    sock = socket.create_connection((host, port), timeout=2.5)
    sock.settimeout(3.0)
    key = base64.b64encode(os.urandom(16)).decode()
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Origin: http://127.0.0.1:{PORT}\r\n\r\n"
    )
    sock.sendall(request.encode())
    response = b""
    while b"\r\n\r\n" not in response and len(response) < 65536:
        response += sock.recv(4096)
    if b" 101 " not in response.split(b"\r\n", 1)[0]:
        raise ConnectionError("Handshake DevTools recusado")
    expected = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    if expected.lower() not in response.decode("latin1", "ignore").lower():
        raise ConnectionError("Resposta WebSocket inválida")
    command = {
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {"expression": expression, "returnByValue": True, "awaitPromise": True},
    }
    send_frame(sock, json.dumps(command).encode())
    while True:
        message = json.loads(recv_message(sock))
        if message.get("id") == 1:
            sock.close()
            return message.get("result", {}).get("result", {}).get("value", {})


try:
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/list", timeout=2.0) as response:
        pages = json.load(response)
except Exception:
    emit("BROWSER_UNAVAILABLE", "Navegador inativo ou diagnóstico local indisponível")
    sys.exit(1)

page = next((p for p in pages if p.get("type") == "page" and "web.whatsapp.com" in p.get("url", "")), None)
if not page or not page.get("webSocketDebuggerUrl"):
    emit("PAGE_UNAVAILABLE", "WhatsApp Web ainda não abriu")
    sys.exit(2)

expression = r'''(() => {
  const visible = (el) => !!el && !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
  const anyVisible = (selectors) => selectors.some((selector) => {
    try { return Array.from(document.querySelectorAll(selector)).some(visible); } catch (_) { return false; }
  });
  const text = (document.body?.innerText || '').toLowerCase();
  const connected = anyVisible([
    '#pane-side',
    '[data-testid="chat-list"]',
    '[data-testid="chatlist-header"]',
    '[aria-label="Chat list"]',
    '[aria-label="Lista de conversas"]',
    '[aria-label="Lista de chats"]'
  ]);
  const qr = anyVisible([
    '[data-testid="qrcode"]',
    'canvas[aria-label*="Scan"]',
    'canvas[aria-label*="Escane"]',
    'div[data-ref]'
  ]) || [
    'scan this qr code', 'escaneie este código qr', 'escaneie o código qr',
    'use whatsapp on your computer', 'usar o whatsapp no seu computador',
    'link with phone number', 'conectar com número de telefone'
  ].some((term) => text.includes(term));
  const offline = [
    'computer not connected', 'computador não conectado', 'sem conexão',
    'no internet connection', 'sem conexão com a internet', 'trying to reach phone',
    'tentando conectar ao telefone', 'whatsapp is not available right now'
  ].some((term) => text.includes(term));
  return {
    connected,
    qr,
    offline,
    readyState: document.readyState,
    title: document.title || '',
    bodyPresent: !!document.body
  };
})()'''

try:
    state = websocket_eval(page["webSocketDebuggerUrl"], expression)
except Exception:
    emit("UNKNOWN", "WhatsApp Web aberto, mas não foi possível confirmar a sessão")
    sys.exit(3)

if state.get("offline"):
    emit("OFFLINE", "Sessão aberta, mas o WhatsApp Web está sem conexão")
elif state.get("connected"):
    emit("CONNECTED", "Sessão conectada e interface de conversas carregada")
elif state.get("qr"):
    emit("QR_REQUIRED", "Aguardando leitura do QR Code")
elif state.get("readyState") != "complete" or not state.get("bodyPresent"):
    emit("LOADING", "WhatsApp Web carregando")
else:
    emit("UNKNOWN", "WhatsApp Web aberto; estado da sessão não confirmado")
PYTHON
  chmod 755 "$WHATSAPP_STATUS_HELPER"
}

render_openbox_config() {
  install -d -m 755 -o "$APP_USER" -g "$APP_GROUP" "$APP_HOME/.config/openbox"
  cat > "$APP_HOME/.config/openbox/autostart" <<'AUTOSTART'
xset s off -dpms s noblank >/dev/null 2>&1 &
tint2 >/dev/null 2>&1 &
AUTOSTART
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME/.config/openbox"
  chmod 755 "$APP_HOME/.config/openbox/autostart"
}

render_systemd_units() {
  local novnc_web websockify_bin
  novnc_web="$(find_novnc_webroot)" || die "Diretório web do noVNC não encontrado."
  websockify_bin="$(command -v websockify)" || die "websockify não encontrado."

  cat > "/etc/systemd/system/$SERVICE_DESKTOP" <<SERVICE
[Unit]
Description=Desktop Openbox persistente para WhatsApp Web
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
Environment=HOME=${APP_HOME}
Environment=XDG_RUNTIME_DIR=/run/user/${APP_UID}
ExecStartPre=+/usr/bin/install -d -m 0700 -o ${APP_UID} -g ${APP_GID} /run/user/${APP_UID}
ExecStart=/usr/local/bin/whatsapp-desktop-start
Restart=always
RestartSec=5
TimeoutStartSec=75
TimeoutStopSec=25
KillMode=control-group
OOMScoreAdjust=-200

[Install]
WantedBy=multi-user.target
SERVICE

  cat > "/etc/systemd/system/$SERVICE_BROWSER" <<SERVICE
[Unit]
Description=Navegador persistente do WhatsApp Web
After=network-online.target ${SERVICE_DESKTOP}
Wants=network-online.target
Requires=${SERVICE_DESKTOP}
StartLimitIntervalSec=0

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
Environment=HOME=${APP_HOME}
Environment=USER=${APP_USER}
Environment=LOGNAME=${APP_USER}
Environment=DISPLAY=:${DISPLAY_NUMBER}
Environment=XDG_RUNTIME_DIR=/run/user/${APP_UID}
ExecStartPre=+/usr/local/sbin/whatsapp-browser-preflight
ExecStart=/usr/local/bin/whatsapp-browser
Restart=always
RestartSec=5
TimeoutStartSec=90
TimeoutStopSec=30
KillMode=control-group
OOMScoreAdjust=-350
LimitCORE=0

[Install]
WantedBy=multi-user.target
SERVICE

  cat > "/etc/systemd/system/$SERVICE_NOVNC" <<SERVICE
[Unit]
Description=noVNC local para WhatsApp Web
After=network-online.target ${SERVICE_DESKTOP}
Wants=network-online.target
Requires=${SERVICE_DESKTOP}
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=${websockify_bin} --web=${novnc_web} 127.0.0.1:${NOVNC_PORT} 127.0.0.1:${VNC_PORT}
Restart=always
RestartSec=5
OOMScoreAdjust=-300

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
}

write_nginx_proxy_locations() {
  cat <<NGINX
    location = / {
        return 302 /vnc.html?autoconnect=1&reconnect=1&resize=scale&path=websockify&view_only=0&show_dot=1;
    }

    location /websockify {
        auth_basic "WhatsApp Remote";
        auth_basic_user_file ${HTPASSWD_FILE};
        proxy_pass http://127.0.0.1:${NOVNC_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header Origin "";
        proxy_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location / {
        auth_basic "WhatsApp Remote";
        auth_basic_user_file ${HTPASSWD_FILE};
        proxy_pass http://127.0.0.1:${NOVNC_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
    }
NGINX
}

write_nginx_ip_site() {
  local default_flag="${1:-default_server}"
  {
    cat <<NGINX
server {
    listen 443 ssl ${default_flag};
    listen [::]:443 ssl ${default_flag};
    server_name _ ${PUBLIC_IP};
    ssl_certificate ${SSL_DIR}/whatsapp-ip.crt;
    ssl_certificate_key ${SSL_DIR}/whatsapp-ip.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;
NGINX
    write_nginx_proxy_locations
    echo "}"
  } > "$NGINX_SITE"
}

configure_nginx_ip() {
  local ip="$1"
  is_valid_ipv4 "$ip" || die "IPv4 inválido: $ip"
  PUBLIC_IP="$ip"
  ACCESS_MODE="ip"
  DOMAIN=""

  install -d -m 700 "$SSL_DIR"
  openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
    -keyout "$SSL_DIR/whatsapp-ip.key" \
    -out "$SSL_DIR/whatsapp-ip.crt" \
    -subj "/CN=${PUBLIC_IP}" \
    -addext "subjectAltName=IP:${PUBLIC_IP}" >/dev/null 2>&1
  chmod 600 "$SSL_DIR/whatsapp-ip.key"
  chmod 644 "$SSL_DIR/whatsapp-ip.crt"

  rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/whatsapp-remote-ip
  ln -sfn "$NGINX_SITE" "$NGINX_LINK"
  write_nginx_ip_site default_server
  if ! nginx -t >/dev/null 2>&1; then
    warn "Já existe outro servidor HTTPS padrão no Nginx; usando configuração sem default_server."
    write_nginx_ip_site ""
  fi
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  save_config
}

configure_nginx_domain() {
  local domain="$1" email="$2"
  is_valid_domain "$domain" || die "Domínio inválido: $domain"
  is_valid_email "$email" || die "E-mail inválido: $email"
  DOMAIN="${domain,,}"
  ACCESS_MODE="domain"

  apt_update_retry
  apt_install_retry certbot python3-certbot-nginx
  {
    cat <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
NGINX
    write_nginx_proxy_locations
    echo "}"
  } > "$NGINX_SITE"

  rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/whatsapp-remote-ip
  ln -sfn "$NGINX_SITE" "$NGINX_LINK"
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  certbot --nginx -d "$DOMAIN" --redirect --non-interactive --agree-tos -m "$email"
  save_config
}

open_local_firewall() {
  local include_http="${1:-0}"
  if command_exists ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
    (( include_http == 1 )) && ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
  fi
  if command_exists firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    (( include_http == 1 )) && firewall-cmd --permanent --add-service=http >/dev/null
    firewall-cmd --permanent --add-service=https >/dev/null
    firewall-cmd --reload >/dev/null
  fi
}

wait_port() {
  local _host="$1" port="$2" timeout="${3:-30}" elapsed=0
  while (( elapsed < timeout )); do
    if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"; then return 0; fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

browser_is_running() {
  pgrep -u "$APP_USER" -af 'chrome|chromium' 2>/dev/null     | grep -v 'crashpad_handler'     | grep -q -- '--user-data-dir='
}

wait_for_browser() {
  local timeout="${1:-45}" elapsed=0
  while (( elapsed < timeout )); do
    if browser_is_running; then return 0; fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

browser_failure_detail() {
  local message result file_message core_message
  result="$(systemctl show "$SERVICE_BROWSER" -p Result --value 2>/dev/null || true)"
  file_message="$(tail -n 80 "$BROWSER_LOG_FILE" 2>/dev/null \
    | grep -Eai 'FATAL|ERROR|sandbox|zygote|namespace|permission denied|trace/breakpoint|segmentation|core|crashpad|database is required' \
    | tail -n 1 | tr '\n' ' ' | cut -c1-240 || true)"
  message="$(journalctl -u "$SERVICE_BROWSER" -n 35 --no-pager -o cat 2>/dev/null \
    | grep -Ev '^[[:space:]]*$|Scheduled restart job|Stopped |Started ' \
    | tail -n 1 | tr '\n' ' ' | cut -c1-220 || true)"
  core_message="$(coredumpctl info "$BROWSER_BIN" --no-pager 2>/dev/null \
    | grep -E 'Signal:|Command Line:|Message:' | tail -n 2 | tr '\n' ' ' | cut -c1-220 || true)"
  if [[ -n "$file_message" ]]; then
    printf 'resultado=%s; %s' "${result:-desconhecido}" "$file_message"
  elif [[ -n "$message" ]]; then
    printf 'resultado=%s; %s' "${result:-desconhecido}" "$message"
  elif [[ -n "$core_message" ]]; then
    printf 'resultado=%s; %s' "${result:-desconhecido}" "$core_message"
  else
    printf 'resultado=%s; consulte %s e journalctl -u %s -n 100' "${result:-desconhecido}" "$BROWSER_LOG_FILE" "$SERVICE_BROWSER"
  fi
}
browser_sandbox_helper() {
  local real candidate
  real="$(readlink -f "$BROWSER_BIN" 2>/dev/null || printf '%s' "$BROWSER_BIN")"
  for candidate in \
    "$(dirname "$real")/chrome-sandbox" \
    /opt/google/chrome/chrome-sandbox \
    /usr/lib/chromium/chrome-sandbox \
    /usr/lib/chromium-browser/chrome-sandbox; do
    [[ -f "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

browser_sandbox_mode_active() {
  if [[ -r "$BROWSER_STATE_FILE" ]]; then
    awk -F= '$1=="mode" {print $2; exit}' "$BROWSER_STATE_FILE" 2>/dev/null || true
  fi
}

browser_sandbox_status() {
  local mode helper owner perms mount_opts
  mode="$(browser_sandbox_mode_active)"
  helper="$(browser_sandbox_helper || true)"
  case "$mode" in
    secure) printf 'protegido (sandbox padrão)' ;;
    userns) printf 'protegido por user namespace (fallback automático)' ;;
    none) printf 'SEM SANDBOX — modo emergencial' ;;
    *)
      if [[ -n "$helper" ]]; then
        owner="$(stat -c '%U:%G' "$helper" 2>/dev/null || true)"
        perms="$(stat -c '%a' "$helper" 2>/dev/null || true)"
        mount_opts="$(findmnt -no OPTIONS -T "$helper" 2>/dev/null || true)"
        if [[ "$owner" == "root:root" && "$perms" == "4755" && "$mount_opts" != *nosuid* ]]; then
          printf 'preparado (helper SUID válido)'
        else
          printf 'incompatível (helper=%s permissão=%s mount=%s)' "${owner:-?}" "${perms:-?}" "${mount_opts:-?}"
        fi
      else
        printf 'não confirmado'
      fi
      ;;
  esac
}

whatsapp_session_status() {
  if ! browser_is_running; then
    printf '%s' 'BROWSER_UNAVAILABLE|Navegador inativo'
    return 1
  fi
  if [[ ! -x "$WHATSAPP_STATUS_HELPER" ]]; then
    printf '%s' 'UNKNOWN|Verificação da sessão ainda não instalada'
    return 2
  fi
  "$WHATSAPP_STATUS_HELPER" "${CDP_PORT:-9222}" 2>/dev/null || true
}

whatsapp_status_message() {
  local raw
  raw="$(whatsapp_session_status || true)"
  printf '%s' "${raw#*|}"
}

restart_stack() {
  [[ -x /usr/local/sbin/whatsapp-browser-preflight ]] && /usr/local/sbin/whatsapp-browser-preflight || true
  systemctl stop "$SERVICE_NOVNC" "$SERVICE_BROWSER" 2>/dev/null || true
  systemctl restart "$SERVICE_DESKTOP"
  wait_port 127.0.0.1 "$VNC_PORT" 60 || {
    journalctl -u "$SERVICE_DESKTOP" -n 100 --no-pager >&2 || true
    die "A porta VNC ${VNC_PORT} não abriu."
  }
  systemctl restart "$SERVICE_BROWSER"
  if ! wait_for_browser 60; then
    journalctl -u "$SERVICE_BROWSER" -n 80 --no-pager >&2 || true
    warn "O navegador não iniciou: $(browser_failure_detail)"
  fi
  systemctl restart "$SERVICE_NOVNC"
  wait_port 127.0.0.1 "$NOVNC_PORT" 45 || {
    journalctl -u "$SERVICE_NOVNC" -n 100 --no-pager >&2 || true
    die "A porta noVNC ${NOVNC_PORT} não abriu."
  }
  if command_exists nginx && nginx -t >/dev/null 2>&1; then systemctl restart nginx; fi
}

start_stack() {
  [[ -x /usr/local/sbin/whatsapp-browser-preflight ]] && /usr/local/sbin/whatsapp-browser-preflight || true
  systemctl start "$SERVICE_DESKTOP"
  wait_port 127.0.0.1 "$VNC_PORT" 60 || return 1
  systemctl start "$SERVICE_BROWSER"
  wait_for_browser 60 || return 1
  systemctl start "$SERVICE_NOVNC"
  wait_port 127.0.0.1 "$NOVNC_PORT" 45 || return 1
  systemctl start nginx
}

stop_stack() {
  systemctl stop "$SERVICE_NOVNC" "$SERVICE_BROWSER" "$SERVICE_DESKTOP" 2>/dev/null || true
}

service_badge() {
  local service="$1" state
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  if [[ "$state" == "active" ]]; then printf '%bATIVO%b' "$C_GREEN" "$C_RESET"
  else printf '%b%s%b' "$C_RED" "${state:-inativo}" "$C_RESET"; fi
}

port_is_listening() {
  local port="$1"
  ss -lntH 2>/dev/null | awk -v suffix=":${port}" '$4 ~ (suffix "$" ) {found=1} END {exit !found}'
}

port_is_publicly_exposed() {
  local port="$1" address
  while read -r address; do
    [[ -n "$address" ]] || continue
    case "$address" in
      127.0.0.1:"$port"|\[::1\]:"$port"|::1:"$port") ;;
      *) return 0 ;;
    esac
  done < <(ss -lntH 2>/dev/null | awk -v suffix=":${port}" '$4 ~ (suffix "$" ) {print $4}')
  return 1
}

port_badge() {
  local port="$1"
  if port_is_listening "$port"; then
    printf '%bATIVA%b' "$C_GREEN" "$C_RESET"
  else
    printf '%bINATIVA%b' "$C_RED" "$C_RESET"
  fi
}

service_failure_detail() {
  local service="$1" result message
  result="$(systemctl show "$service" -p Result --value 2>/dev/null || true)"
  message="$(journalctl -u "$service" -p err --since '-30 minutes' -n 1 --no-pager -o cat 2>/dev/null | tr '\n' ' ' | cut -c1-180 || true)"
  if [[ -n "$message" ]]; then
    printf 'resultado=%s; %s' "${result:-desconhecido}" "$message"
  else
    printf 'resultado=%s' "${result:-desconhecido}"
  fi
}

HEALTH_ERRORS=()
HEALTH_WARNINGS=()
health_error() { HEALTH_ERRORS+=("$*"); }
health_warning() { HEALTH_WARNINGS+=("$*"); }

collect_health_issues() {
  HEALTH_ERRORS=()
  HEALTH_WARNINGS=()

  local current_ip="" mem_mb swap_mb available_mb disk_mb cert_file="" config_mode="" profile_owner=""
  current_ip="$(detect_public_ip || true)"
  mem_mb="$(memory_mb 2>/dev/null || echo 0)"
  swap_mb="$(awk '/SwapTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  available_mb="$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  disk_mb="$(disk_free_mb 2>/dev/null || echo 0)"

  [[ -r "$CONFIG_FILE" ]] || health_error "Arquivo de configuração ausente ou ilegível: $CONFIG_FILE"
  id "$APP_USER" >/dev/null 2>&1 || health_error "Usuário desktop '$APP_USER' não existe."
  [[ -d "$APP_HOME" ]] || health_error "Diretório do usuário desktop não existe: $APP_HOME"
  [[ -d "$PROFILE_DIR" ]] || health_error "Perfil persistente do navegador não existe: $PROFILE_DIR"
  [[ -s "$APP_HOME/.vnc/passwd" ]] || health_error "Senha VNC ausente: $APP_HOME/.vnc/passwd"
  [[ -s "$HTPASSWD_FILE" ]] || health_error "Autenticação web ausente: $HTPASSWD_FILE"
  [[ -x "$BROWSER_BIN" ]] || health_error "Navegador configurado não foi encontrado ou não é executável: $BROWSER_BIN"
  [[ -x /usr/local/bin/whatsapp-desktop-start ]] || health_error "Inicializador do desktop está ausente."
  [[ -x /usr/local/bin/whatsapp-browser ]] || health_error "Inicializador do navegador está ausente."
  [[ -x /usr/local/sbin/whatsapp-browser-preflight ]] || health_error "Preflight de compatibilidade do navegador está ausente."
  [[ -x "$WHATSAPP_STATUS_HELPER" ]] || health_warning "Verificador da sessão do WhatsApp está ausente; a reparação pode recriá-lo."
  [[ -x /usr/local/sbin/whatsapp-remote ]] || health_warning "Comando 'whatsapp-remote' ausente; a reparação pode recriá-lo."
  [[ -x "$MENU_COMMAND" ]] || health_warning "Comando global 'menu' ausente; a reparação pode recriá-lo."

  if [[ -r "$CONFIG_FILE" ]]; then
    config_mode="$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || true)"
    [[ -z "$config_mode" || "${config_mode: -1}" == "0" ]] || health_warning "A configuração pode ser lida por outros usuários (permissão $config_mode)."
  fi
  if [[ -d "$PROFILE_DIR" ]] && id "$APP_USER" >/dev/null 2>&1; then
    profile_owner="$(stat -c '%U' "$PROFILE_DIR" 2>/dev/null || true)"
    [[ -z "$profile_owner" || "$profile_owner" == "$APP_USER" ]] || health_error "O perfil do navegador pertence a '$profile_owner', mas deveria pertencer a '$APP_USER'."
  fi

  local service
  for service in "$SERVICE_DESKTOP" "$SERVICE_BROWSER" "$SERVICE_NOVNC" nginx; do
    if ! systemctl is-active --quiet "$service" 2>/dev/null; then
      health_error "Serviço $service está inativo ($(service_failure_detail "$service"))."
    fi
    if ! systemctl is-enabled --quiet "$service" 2>/dev/null; then
      health_warning "Serviço $service não está habilitado para iniciar com a VPS."
    fi
  done

  port_is_listening "$VNC_PORT" || health_error "Porta VNC interna $VNC_PORT não está escutando."
  port_is_listening "$NOVNC_PORT" || health_error "Porta noVNC interna $NOVNC_PORT não está escutando."
  port_is_listening 443 || health_error "Porta HTTPS 443 não está escutando."
  port_is_publicly_exposed "$VNC_PORT" && health_error "RISCO DE SEGURANÇA: a porta VNC $VNC_PORT está exposta fora do localhost."
  port_is_publicly_exposed "$NOVNC_PORT" && health_error "RISCO DE SEGURANÇA: a porta noVNC $NOVNC_PORT está exposta fora do localhost."
  port_is_publicly_exposed "${CDP_PORT:-9222}" && health_error "RISCO DE SEGURANÇA: a porta de diagnóstico ${CDP_PORT:-9222} está exposta fora do localhost."

  nginx -t >/dev/null 2>&1 || health_error "A configuração do Nginx contém erro; execute 'nginx -t' para detalhes."
  if ! browser_is_running; then
    if grep -Fq 'chrome_crashpad_handler: --database is required' "$BROWSER_LOG_FILE" 2>/dev/null; then
      health_error "Chrome não conseguiu inicializar o banco local do Crashpad. Atualize/repare para recriar os diretórios do usuário e remover flags de crash obsoletas."
    fi
    health_error "Chrome/Chromium não está em execução ($(browser_failure_detail))."
  else
    local active_sandbox
    active_sandbox="$(browser_sandbox_mode_active)"
    [[ "$active_sandbox" == "none" ]] && health_error "O navegador está funcionando SEM sandbox. Use Reparar navegador para restaurar a proteção."
    [[ "$active_sandbox" == "userns" ]] && health_warning "O navegador usa fallback por user namespace porque o helper SUID não iniciou corretamente."
    local whatsapp_raw whatsapp_code whatsapp_message
    whatsapp_raw="$(whatsapp_session_status || true)"
    whatsapp_code="${whatsapp_raw%%|*}"
    whatsapp_message="${whatsapp_raw#*|}"
    case "$whatsapp_code" in
      CONNECTED) ;;
      QR_REQUIRED) health_warning "$whatsapp_message; abra a URL remota e vincule o aparelho." ;;
      OFFLINE) health_error "$whatsapp_message." ;;
      LOADING|PAGE_UNAVAILABLE) health_warning "$whatsapp_message; aguarde alguns segundos." ;;
      *) health_warning "$whatsapp_message." ;;
    esac
  fi

  if [[ "$ACCESS_MODE" == "ip" ]]; then
    cert_file="$SSL_DIR/whatsapp-ip.crt"
    if [[ -n "$PUBLIC_IP" && -n "$current_ip" && "$PUBLIC_IP" != "$current_ip" ]]; then
      health_error "O IP público mudou: configurado $PUBLIC_IP, atual $current_ip. Reconfigure o acesso por IP."
    fi
  elif [[ "$ACCESS_MODE" == "domain" && -n "$DOMAIN" ]]; then
    cert_file="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  fi

  if [[ -n "$cert_file" ]]; then
    if [[ ! -r "$cert_file" ]]; then
      health_error "Certificado HTTPS ausente: $cert_file"
    elif command_exists openssl; then
      openssl x509 -checkend 0 -noout -in "$cert_file" >/dev/null 2>&1 || health_error "O certificado HTTPS está vencido ou inválido."
      if openssl x509 -checkend 0 -noout -in "$cert_file" >/dev/null 2>&1 \
        && ! openssl x509 -checkend 1209600 -noout -in "$cert_file" >/dev/null 2>&1; then
        health_warning "O certificado HTTPS vence em menos de 14 dias."
      fi
    fi
  fi

  (( mem_mb > 1600 || swap_mb > 0 )) || health_warning "A VPS possui pouca RAM (${mem_mb} MB) e nenhuma swap ativa."
  (( available_mb >= 100 )) || health_warning "Memória disponível muito baixa: ${available_mb} MB."
  if (( disk_mb < 1024 )); then
    health_error "Espaço livre crítico em /: ${disk_mb} MB."
  elif (( disk_mb < 3072 )); then
    health_warning "Pouco espaço livre em /: ${disk_mb} MB."
  fi
  [[ -r "$CREDENTIALS_FILE" ]] || health_warning "Arquivo de credenciais não encontrado; as senhas podem precisar ser redefinidas."
  [[ -n "$current_ip" ]] || health_warning "Não foi possível detectar o IP público atual."
}

show_health_summary() {
  local mode="${1:-full}" limit=999 shown=0 item
  [[ "$mode" == "compact" ]] && limit=6
  collect_health_issues

  if (( ${#HEALTH_ERRORS[@]} == 0 && ${#HEALTH_WARNINGS[@]} == 0 )); then
    printf '%bSaúde do sistema: OK — nenhum problema detectado.%b\n' "$C_GREEN" "$C_RESET"
    return 0
  fi

  printf '%bSaúde do sistema: %s erro(s), %s aviso(s).%b\n' \
    "$C_BOLD" "${#HEALTH_ERRORS[@]}" "${#HEALTH_WARNINGS[@]}" "$C_RESET"
  for item in "${HEALTH_ERRORS[@]}"; do
    (( shown >= limit )) && break
    printf '  %b✖ ERRO:%b %s\n' "$C_RED" "$C_RESET" "$item"
    shown=$((shown + 1))
  done
  for item in "${HEALTH_WARNINGS[@]}"; do
    (( shown >= limit )) && break
    printf '  %b⚠ AVISO:%b %s\n' "$C_YELLOW" "$C_RESET" "$item"
    shown=$((shown + 1))
  done
  if (( shown < ${#HEALTH_ERRORS[@]} + ${#HEALTH_WARNINGS[@]} )); then
    printf '  … use a opção de status/diagnóstico para visualizar todos os problemas.\n'
  fi
  printf '  Ação recomendada: execute %bReparação automática%b pelo menu.\n' "$C_BOLD" "$C_RESET"
  return 1
}

certificate_expiry_text() {
  local cert_file=""
  if [[ "$ACCESS_MODE" == "domain" && -n "$DOMAIN" ]]; then
    cert_file="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  elif [[ "$ACCESS_MODE" == "ip" ]]; then
    cert_file="$SSL_DIR/whatsapp-ip.crt"
  fi
  if [[ -r "$cert_file" ]] && command_exists openssl; then
    openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | sed 's/^notAfter=//' || printf 'indisponível'
  else
    printf 'não encontrado'
  fi
}

show_status() {
  load_config
  local current_ip private_ip uptime_text profile_size browser_state auto_start load_text cpu_count whatsapp_raw whatsapp_message
  current_ip="$(detect_public_ip || true)"
  private_ip="$(detect_private_ip || true)"
  uptime_text="$(uptime -p 2>/dev/null || true)"
  profile_size="$(du -sh "$PROFILE_DIR" 2>/dev/null | awk '{print $1}' || true)"
  browser_state="$(browser_is_running && echo ativo || echo inativo)"
  whatsapp_raw="$(whatsapp_session_status || true)"
  whatsapp_message="${whatsapp_raw#*|}"
  if systemctl is-enabled --quiet "$SERVICE_DESKTOP" 2>/dev/null \
    && systemctl is-enabled --quiet "$SERVICE_BROWSER" 2>/dev/null \
    && systemctl is-enabled --quiet "$SERVICE_NOVNC" 2>/dev/null \
    && systemctl is-enabled --quiet nginx 2>/dev/null; then auto_start="ativada"; else auto_start="incompleta"; fi
  load_text="$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || true)"
  cpu_count="$(nproc 2>/dev/null || echo '?')"

  printf '%-29s %s\n' "Projeto:" "$PROJECT_NAME $PROJECT_VERSION"
  printf '%-29s %s\n' "Hostname:" "$(hostname 2>/dev/null || echo indisponível)"
  printf '%-29s %s\n' "Sistema:" "${OS_ID} ${OS_VERSION} (${ARCH})"
  printf '%-29s %s\n' "Kernel:" "$(uname -r 2>/dev/null || echo indisponível)"
  printf '%-29s %s\n' "CPU / carga:" "${cpu_count} núcleo(s) / ${load_text:-indisponível}"
  printf '%-29s %s\n' "Provedor detectado:" "$(detect_cloud_provider)"
  printf '%-29s %s\n' "IP público atual:" "${current_ip:-não detectado}"
  printf '%-29s %s\n' "IP privado:" "${private_ip:-não detectado}"
  printf '%-29s %s\n' "URL configurada:" "$(access_url)"
  printf '%-29s %s\n' "Modo de acesso:" "$ACCESS_MODE"
  printf '%-29s %s\n' "Certificado vence em:" "$(certificate_expiry_text)"
  printf '%-29s %s\n' "Usuário web:" "$WEB_USER"
  printf '%-29s %s\n' "Usuário desktop:" "$APP_USER"
  printf '%-29s %s\n' "Navegador:" "$BROWSER_TYPE"
  printf '%-29s %s\n' "Resolução:" "$GEOMETRY"
  printf '%-29s %s\n' "Perfil do navegador:" "$PROFILE_DIR (${profile_size:-0B})"
  printf '%-29s %b\n' "Desktop/VNC:" "$(service_badge "$SERVICE_DESKTOP")"
  printf '%-29s %b\n' "Serviço do navegador:" "$(service_badge "$SERVICE_BROWSER")"
  printf '%-29s %b\n' "noVNC:" "$(service_badge "$SERVICE_NOVNC")"
  printf '%-29s %b\n' "Nginx:" "$(service_badge nginx)"
  printf '%-29s %b\n' "Porta VNC ${VNC_PORT}:" "$(port_badge "$VNC_PORT")"
  printf '%-29s %b\n' "Porta noVNC ${NOVNC_PORT}:" "$(port_badge "$NOVNC_PORT")"
  printf '%-29s %b\n' "Porta HTTPS 443:" "$(port_badge 443)"
  printf '%-29s %s\n' "Chrome/Chromium:" "$browser_state"
  printf '%-29s %s\n' "Sandbox do navegador:" "$(browser_sandbox_status)"
  printf '%-29s %s\n' "Log do navegador:" "$BROWSER_LOG_FILE"
  printf '%-29s %s\n' "WhatsApp Web:" "${whatsapp_message:-estado não confirmado}"
  printf '%-29s %s\n' "Inicialização automática:" "$auto_start"
  printf '%-29s %s\n' "Memória usada/total:" "$(free -h | awk '/Mem:/ {print $3 "/" $2 " (disponível " $7 ")"}')"
  printf '%-29s %s\n' "Swap usada/total:" "$(free -h | awk '/Swap:/ {print $3 "/" $2}')"
  printf '%-29s %s\n' "Disco livre em /:" "$(df -h / | awk 'NR==2 {print $4 " de " $2}')"
  printf '%-29s %s\n' "Tempo ligado:" "${uptime_text:-indisponível}"
  printf '%-29s %s\n' "Firewall da nuvem:" "não verificável pela VPS; confirme TCP 443 no provedor"
  echo
  show_health_summary full || true
}

quick_healthcheck() {
  load_config
  local failures=0
  systemctl is-active --quiet "$SERVICE_DESKTOP" || failures=$((failures + 1))
  systemctl is-active --quiet "$SERVICE_BROWSER" || failures=$((failures + 1))
  systemctl is-active --quiet "$SERVICE_NOVNC" || failures=$((failures + 1))
  systemctl is-active --quiet nginx || failures=$((failures + 1))
  wait_port 127.0.0.1 "$VNC_PORT" 1 || failures=$((failures + 1))
  wait_port 127.0.0.1 "$NOVNC_PORT" 1 || failures=$((failures + 1))
  wait_port 0.0.0.0 443 1 || failures=$((failures + 1))
  wait_for_browser 5 || failures=$((failures + 1))
  return "$failures"
}
