#!/usr/bin/env bash
# Funções compartilhadas do WhatsApp Remote VPS.

PROJECT_NAME="WhatsApp Remote VPS"
PROJECT_VERSION="2.0.0"
INSTALL_DIR="/opt/whatsapp-remote"
CONFIG_DIR="/etc/whatsapp-remote"
CONFIG_FILE="${CONFIG_DIR}/config.env"
CREDENTIALS_FILE="/root/whatsapp-remote-credentials.txt"
SERVICE_DESKTOP="whatsapp-desktop.service"
SERVICE_NOVNC="whatsapp-novnc.service"
NGINX_SITE="/etc/nginx/sites-available/whatsapp-remote"
NGINX_LINK="/etc/nginx/sites-enabled/whatsapp-remote"
HTPASSWD_FILE="/etc/nginx/.htpasswd-whatsapp"
SSL_DIR="/etc/nginx/ssl-whatsapp"

C_RESET='\033[0m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'

info() { printf "%b[INFO]%b %s\n" "$C_BLUE" "$C_RESET" "$*"; }
ok() { printf "%b[OK]%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%b[AVISO]%b %s\n" "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf "%b[ERRO]%b %s\n" "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Execute como root: sudo bash $0"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

shell_quote() { printf '%q' "$1"; }

is_valid_linux_user() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]
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
  local ip="$1" IFS=. octets=()
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  read -r -a octets <<< "$ip"
  local octet
  for octet in "${octets[@]}"; do
    (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
  done
}

is_valid_domain() {
  [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

random_password() {
  local length="${1:-16}" result=""
  if command_exists openssl; then
    result="$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9@#%+=_' | head -c "$length" || true)"
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
    (( waited < 300 )) || die "O APT permaneceu bloqueado por mais de 5 minutos."
  done
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

detect_public_ip() {
  local ip="" endpoint
  for endpoint in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://icanhazip.com"; do
    ip="$(curl -4 -fsS --connect-timeout 4 --max-time 8 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
    if is_valid_ipv4 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 1
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
  } > "$tmp"
  chown root:"$APP_GROUP" "$tmp"
  chmod 640 "$tmp"
  mv -f "$tmp" "$CONFIG_FILE"
}

find_vnc_password_command() {
  local candidate
  for candidate in tigervncpasswd vncpasswd; do
    if command_exists "$candidate"; then
      command -v "$candidate"
      return 0
    fi
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

write_credentials_file() {
  local vnc_password="${1:-}" web_password="${2:-}"
  umask 077
  {
    echo "$PROJECT_NAME $PROJECT_VERSION"
    echo "Gerado em: $(date -Is)"
    echo "URL: $(access_url)"
    echo "Usuário web: $WEB_USER"
    if [[ -n "$web_password" ]]; then
      echo "Senha web: $web_password"
    else
      echo "Senha web: não recuperável; altere com 'whatsapp-remote web-credentials'"
    fi
    echo "Usuário do desktop Linux: $APP_USER"
    if [[ -n "$vnc_password" ]]; then
      echo "Senha VNC: $vnc_password"
    else
      echo "Senha VNC: não recuperável; altere com 'whatsapp-remote vnc-password'"
    fi
    echo "Observação: o VNC clássico utiliza somente os primeiros 8 caracteres da senha."
  } > "$CREDENTIALS_FILE"
  chmod 600 "$CREDENTIALS_FILE"
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
    if [[ -f "$path/vnc.html" ]]; then
      printf '%s' "$path"
      return 0
    fi
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

  cat > /etc/systemd/system/$SERVICE_DESKTOP <<SERVICE
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
TimeoutStartSec=45
TimeoutStopSec=20
KillMode=control-group
OOMScoreAdjust=-200

[Install]
WantedBy=multi-user.target
SERVICE

  cat > /etc/systemd/system/$SERVICE_NOVNC <<SERVICE
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

  {
    cat <<NGINX
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate ${SSL_DIR}/whatsapp-ip.crt;
    ssl_certificate_key ${SSL_DIR}/whatsapp-ip.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
NGINX
    write_nginx_proxy_locations
    echo "}"
  } > "$NGINX_SITE"

  rm -f /etc/nginx/sites-enabled/default
  rm -f /etc/nginx/sites-enabled/whatsapp-remote-ip
  ln -sfn "$NGINX_SITE" "$NGINX_LINK"
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  save_config
}

configure_nginx_domain() {
  local domain="$1" email="$2"
  is_valid_domain "$domain" || die "Domínio inválido: $domain"
  [[ "$email" == *@*.* ]] || die "E-mail inválido: $email"
  DOMAIN="${domain,,}"
  ACCESS_MODE="domain"

  wait_for_apt
  apt-get update
  apt-get install -y --no-install-recommends certbot python3-certbot-nginx

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

  rm -f /etc/nginx/sites-enabled/default
  rm -f /etc/nginx/sites-enabled/whatsapp-remote-ip
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
  local host="$1" port="$2" timeout="${3:-30}" elapsed=0
  while (( elapsed < timeout )); do
    if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

restart_stack() {
  systemctl stop "$SERVICE_NOVNC" 2>/dev/null || true
  systemctl restart "$SERVICE_DESKTOP"
  wait_port 127.0.0.1 "$VNC_PORT" 45 || {
    journalctl -u "$SERVICE_DESKTOP" -n 80 --no-pager >&2 || true
    die "A porta VNC ${VNC_PORT} não abriu."
  }
  systemctl restart "$SERVICE_NOVNC"
  wait_port 127.0.0.1 "$NOVNC_PORT" 30 || {
    journalctl -u "$SERVICE_NOVNC" -n 80 --no-pager >&2 || true
    die "A porta noVNC ${NOVNC_PORT} não abriu."
  }
  if command_exists nginx && nginx -t >/dev/null 2>&1; then
    systemctl restart nginx
  fi
}

show_status() {
  load_config
  printf '%-28s %s\n' "Projeto:" "$PROJECT_NAME ${PROJECT_VERSION}"
  printf '%-28s %s\n' "Sistema:" "${OS_ID} ${OS_VERSION} (${ARCH})"
  printf '%-28s %s\n' "Usuário desktop:" "$APP_USER"
  printf '%-28s %s\n' "Navegador:" "$BROWSER_TYPE — $BROWSER_BIN"
  printf '%-28s %s\n' "Resolução:" "$GEOMETRY"
  printf '%-28s %s\n' "URL:" "$(access_url)"
  printf '%-28s %s\n' "Desktop Openbox:" "$(systemctl is-active "$SERVICE_DESKTOP" 2>/dev/null || true)"
  printf '%-28s %s\n' "noVNC:" "$(systemctl is-active "$SERVICE_NOVNC" 2>/dev/null || true)"
  printf '%-28s %s\n' "Nginx:" "$(systemctl is-active nginx 2>/dev/null || true)"
  printf '%-28s %s\n' "VNC local ${VNC_PORT}:" "$(ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${VNC_PORT}$" && echo ativa || echo inativa)"
  printf '%-28s %s\n' "noVNC local ${NOVNC_PORT}:" "$(ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${NOVNC_PORT}$" && echo ativa || echo inativa)"
  printf '%-28s %s\n' "HTTPS 443:" "$(ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)443$' && echo ativa || echo inativa)"
  printf '%-28s %s\n' "Chrome/Chromium:" "$(pgrep -u "$APP_USER" -f 'chrome|chromium' >/dev/null 2>&1 && echo ativo || echo inativo)"
  printf '%-28s %s\n' "Memória disponível:" "$(free -h | awk '/Mem:/ {print $7}')"
  printf '%-28s %s\n' "Swap usada/total:" "$(free -h | awk '/Swap:/ {print $3 "/" $2}')"
}
