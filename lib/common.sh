#!/usr/bin/env bash
# Funções compartilhadas do WhatsApp Remote VPS.

PROJECT_NAME="WhatsApp Remote VPS"
PROJECT_VERSION="2.3.0"
GITHUB_REPOSITORY_DEFAULT="DuiBR/whatsapp-remote-vps"
GITHUB_REF_DEFAULT="main"
INSTALL_DIR="/opt/whatsapp-remote"
CONFIG_DIR="/etc/whatsapp-remote"
CONFIG_FILE="${CONFIG_DIR}/config.env"
CONFIG_BACKUP_DIR="/var/backups/whatsapp-remote"
CREDENTIALS_FILE="/root/whatsapp-remote-credentials.txt"
INSTALL_LOG="/var/log/whatsapp-remote-install.log"
SERVICE_DESKTOP="whatsapp-desktop.service"
SERVICE_NOVNC="whatsapp-novnc.service"
NGINX_SITE="/etc/nginx/sites-available/whatsapp-remote"
NGINX_LINK="/etc/nginx/sites-enabled/whatsapp-remote"
HTPASSWD_FILE="/etc/nginx/.htpasswd-whatsapp"
SSL_DIR="/etc/nginx/ssl-whatsapp"
MENU_COMMAND="/usr/local/bin/menu"

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
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  : "${APP_USER:?APP_USER ausente}"
  : "${APP_GROUP:?APP_GROUP ausente}"
  : "${APP_HOME:?APP_HOME ausente}"
  : "${PROFILE_DIR:=${APP_HOME}/.config/chrome-whatsapp}"
  : "${APP_UID:?APP_UID ausente}"
  : "${APP_GID:?APP_GID ausente}"
  : "${APP_USER_MANAGED:=0}"
  : "${DISPLAY_NUMBER:=1}"
  : "${GEOMETRY:=1280x720}"
  : "${VNC_PORT:=$((5900 + DISPLAY_NUMBER))}"
  : "${NOVNC_PORT:=6080}"
  : "${BROWSER_BIN:?BROWSER_BIN ausente}"
  : "${BROWSER_TYPE:=chromium}"
  : "${LOW_RAM:=0}"
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
    printf 'PROJECT_VERSION=%q\n' "$PROJECT_VERSION"
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
    printf 'BROWSER_BIN=%q\n' "$BROWSER_BIN"
    printf 'BROWSER_TYPE=%q\n' "$BROWSER_TYPE"
    printf 'LOW_RAM=%q\n' "$LOW_RAM"
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

for _ in $(seq 1 80); do
  DISPLAY=":${DISPLAY_NUMBER}" xdpyinfo >/dev/null 2>&1 && break
  sleep 0.25
done
DISPLAY=":${DISPLAY_NUMBER}" xdpyinfo >/dev/null 2>&1 || { echo "O servidor gráfico não iniciou corretamente."; exit 1; }
exec dbus-run-session -- openbox-session
SCRIPT
  chmod 755 /usr/local/bin/whatsapp-desktop-start

  cat > /usr/local/bin/whatsapp-browser <<'SCRIPT'
#!/usr/bin/env bash
set -u
source /etc/whatsapp-remote/config.env
export HOME="$APP_HOME"
export USER="$APP_USER"
export LOGNAME="$APP_USER"
export DISPLAY=":${DISPLAY_NUMBER}"
export XDG_RUNTIME_DIR="/run/user/${APP_UID}"

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
  --disable-features=Translate,MediaRouter
  --start-maximized
)
if [[ "$LOW_RAM" == "1" ]]; then
  COMMON_FLAGS+=(--process-per-site --renderer-process-limit=3)
fi
while true; do
  "$BROWSER_BIN" "${COMMON_FLAGS[@]}" "https://web.whatsapp.com/" || true
  sleep 4
done
SCRIPT
  chmod 755 /usr/local/bin/whatsapp-browser
}

render_openbox_config() {
  install -d -m 755 -o "$APP_USER" -g "$APP_GROUP" "$APP_HOME/.config/openbox"
  cat > "$APP_HOME/.config/openbox/autostart" <<'AUTOSTART'
xset s off -dpms s noblank >/dev/null 2>&1 &
tint2 >/dev/null 2>&1 &
/usr/local/bin/whatsapp-browser >>"$HOME/whatsapp-browser.log" 2>&1 &
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
TimeoutStartSec=60
TimeoutStopSec=25
KillMode=control-group
OOMScoreAdjust=-200

[Install]
WantedBy=multi-user.target
SERVICE

  cat > "/etc/systemd/system/$SERVICE_NOVNC" <<SERVICE
[Unit]
Description=noVNC local para WhatsApp Web
After=network-online.target ${SERVICE_DESKTOP}
Wants=network-online.target
Requires=${SERVICE_DESKTOP}

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

restart_stack() {
  systemctl stop "$SERVICE_NOVNC" 2>/dev/null || true
  systemctl restart "$SERVICE_DESKTOP"
  wait_port 127.0.0.1 "$VNC_PORT" 60 || {
    journalctl -u "$SERVICE_DESKTOP" -n 100 --no-pager >&2 || true
    die "A porta VNC ${VNC_PORT} não abriu."
  }
  systemctl restart "$SERVICE_NOVNC"
  wait_port 127.0.0.1 "$NOVNC_PORT" 45 || {
    journalctl -u "$SERVICE_NOVNC" -n 100 --no-pager >&2 || true
    die "A porta noVNC ${NOVNC_PORT} não abriu."
  }
  if command_exists nginx && nginx -t >/dev/null 2>&1; then systemctl restart nginx; fi
}

start_stack() {
  systemctl start "$SERVICE_DESKTOP"
  wait_port 127.0.0.1 "$VNC_PORT" 60 || return 1
  systemctl start "$SERVICE_NOVNC"
  wait_port 127.0.0.1 "$NOVNC_PORT" 45 || return 1
  systemctl start nginx
}

stop_stack() {
  systemctl stop "$SERVICE_NOVNC" "$SERVICE_DESKTOP" 2>/dev/null || true
}

service_badge() {
  local service="$1" state
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  if [[ "$state" == "active" ]]; then printf '%bATIVO%b' "$C_GREEN" "$C_RESET"
  else printf '%b%s%b' "$C_RED" "${state:-inativo}" "$C_RESET"; fi
}

port_badge() {
  local port="$1"
  if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"; then
    printf '%bATIVA%b' "$C_GREEN" "$C_RESET"
  else
    printf '%bINATIVA%b' "$C_RED" "$C_RESET"
  fi
}

show_status() {
  load_config
  local current_ip uptime_text
  current_ip="$(detect_public_ip || true)"
  uptime_text="$(uptime -p 2>/dev/null || true)"
  printf '%-27s %s\n' "Projeto:" "$PROJECT_NAME $PROJECT_VERSION"
  printf '%-27s %s\n' "Sistema:" "${OS_ID} ${OS_VERSION} (${ARCH})"
  printf '%-27s %s\n' "Provedor detectado:" "$(detect_cloud_provider)"
  printf '%-27s %s\n' "IP público atual:" "${current_ip:-não detectado}"
  printf '%-27s %s\n' "URL configurada:" "$(access_url)"
  printf '%-27s %s\n' "Usuário web:" "$WEB_USER"
  printf '%-27s %s\n' "Usuário desktop:" "$APP_USER"
  printf '%-27s %s\n' "Navegador:" "$BROWSER_TYPE"
  printf '%-27s %s\n' "Resolução:" "$GEOMETRY"
  printf '%-27s %b\n' "Desktop/VNC:" "$(service_badge "$SERVICE_DESKTOP")"
  printf '%-27s %b\n' "noVNC:" "$(service_badge "$SERVICE_NOVNC")"
  printf '%-27s %b\n' "Nginx:" "$(service_badge nginx)"
  printf '%-27s %b\n' "Porta VNC ${VNC_PORT}:" "$(port_badge "$VNC_PORT")"
  printf '%-27s %b\n' "Porta noVNC ${NOVNC_PORT}:" "$(port_badge "$NOVNC_PORT")"
  printf '%-27s %b\n' "Porta HTTPS 443:" "$(port_badge 443)"
  printf '%-27s %s\n' "Chrome/Chromium:" "$(pgrep -u "$APP_USER" -f 'chrome|chromium' >/dev/null 2>&1 && echo ativo || echo inativo)"
  printf '%-27s %s\n' "Memória usada/total:" "$(free -h | awk '/Mem:/ {print $3 "/" $2}')"
  printf '%-27s %s\n' "Swap usada/total:" "$(free -h | awk '/Swap:/ {print $3 "/" $2}')"
  printf '%-27s %s\n' "Disco livre em /:" "$(df -h / | awk 'NR==2 {print $4}')"
  printf '%-27s %s\n' "Tempo ligado:" "${uptime_text:-indisponível}"
}

quick_healthcheck() {
  load_config
  local failures=0
  systemctl is-active --quiet "$SERVICE_DESKTOP" || failures=$((failures + 1))
  systemctl is-active --quiet "$SERVICE_NOVNC" || failures=$((failures + 1))
  systemctl is-active --quiet nginx || failures=$((failures + 1))
  wait_port 127.0.0.1 "$VNC_PORT" 1 || failures=$((failures + 1))
  wait_port 127.0.0.1 "$NOVNC_PORT" 1 || failures=$((failures + 1))
  wait_port 0.0.0.0 443 1 || failures=$((failures + 1))
  return "$failures"
}
