#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

AUTO=0
REPAIR_ONLY=0
REQUESTED_USER="${WR_DESKTOP_USER:-}"
REQUESTED_GEOMETRY="${WR_GEOMETRY:-}"
REQUESTED_ACCESS="${WR_ACCESS_MODE:-}"
REQUESTED_IP="${WR_PUBLIC_IP:-}"
REQUESTED_DOMAIN="${WR_DOMAIN:-}"
REQUESTED_EMAIL="${WR_EMAIL:-}"
VNC_PASSWORD="${WR_VNC_PASSWORD:-}"
WEB_USER_INPUT="${WR_WEB_USER:-}"
WEB_PASSWORD="${WR_WEB_PASSWORD:-}"
NO_SWAP="${WR_NO_SWAP:-0}"

usage() {
  cat <<USAGE
$PROJECT_NAME $PROJECT_VERSION

Uso:
  sudo bash install.sh                 Instalação guiada
  sudo bash install.sh --auto          Instalação 100% automática
  sudo bash install.sh --repair        Reinstala e repara preservando a sessão

Opções:
  --auto                     Gera usuários/senhas padrão automaticamente
  --repair                   Preserva instalação, perfil e credenciais existentes
  --desktop-user USUARIO     Usuário Linux do desktop
  --geometry LARGURAxALTURA  Resolução, exemplo: 1280x720
  --ip ENDERECO              Configura acesso HTTPS por IPv4
  --domain DOMINIO           Configura acesso HTTPS por domínio
  --email EMAIL              E-mail do Let's Encrypt, usado com --domain
  --no-swap                  Não cria swap automaticamente
  -h, --help                 Exibe esta ajuda

Senhas por variáveis de ambiente (não ficam no histórico do comando):
  WR_VNC_PASSWORD='12345678' WR_WEB_PASSWORD='senha-forte' sudo -E bash install.sh --auto
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto) AUTO=1; shift ;;
    --repair) REPAIR_ONLY=1; shift ;;
    --desktop-user) [[ $# -ge 2 ]] || die "Falta valor para --desktop-user"; REQUESTED_USER="$2"; shift 2 ;;
    --geometry) [[ $# -ge 2 ]] || die "Falta valor para --geometry"; REQUESTED_GEOMETRY="$2"; shift 2 ;;
    --ip) [[ $# -ge 2 ]] || die "Falta valor para --ip"; REQUESTED_ACCESS="ip"; REQUESTED_IP="$2"; shift 2 ;;
    --domain) [[ $# -ge 2 ]] || die "Falta valor para --domain"; REQUESTED_ACCESS="domain"; REQUESTED_DOMAIN="$2"; shift 2 ;;
    --email) [[ $# -ge 2 ]] || die "Falta valor para --email"; REQUESTED_EMAIL="$2"; shift 2 ;;
    --no-swap) NO_SWAP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opção desconhecida: $1" ;;
  esac
done

require_root
install -d -m 755 /var/log
exec > >(tee -a /var/log/whatsapp-remote-install.log) 2>&1
trap 'printf "\n%b[ERRO]%b Falha na linha %s. Consulte /var/log/whatsapp-remote-install.log\n" "$C_RED" "$C_RESET" "$LINENO" >&2' ERR

detect_platform
info "Detectado: $OS_NAME | arquitetura $ARCH"
command_exists systemctl || die "Este instalador exige systemd."

EXISTING=0
LEGACY=0
if [[ -r "$CONFIG_FILE" ]]; then
  EXISTING=1
  load_config
elif [[ -r /etc/whatsapp-remote.conf ]]; then
  EXISTING=1
  LEGACY=1
  # Migração da versão 1.x.
  # shellcheck disable=SC1091
  source /etc/whatsapp-remote.conf
  APP_GROUP="$(id -gn "$APP_USER")"
  APP_GID="$(id -g "$APP_USER")"
  DISPLAY_NUMBER="${DISPLAY_NUMBER:-1}"
  GEOMETRY="${GEOMETRY:-1280x720}"
  VNC_PORT="$((5900 + DISPLAY_NUMBER))"
  NOVNC_PORT=6080
  PROFILE_DIR="$APP_HOME/.config/google-chrome-whatsapp"
  ACCESS_MODE="ip"
  PUBLIC_IP=""
  DOMAIN=""
  WEB_USER="remoteadmin"
  info "Instalação 1.x encontrada; os dados serão migrados sem apagar a sessão."
fi

if (( EXISTING == 1 )); then
  info "Instalação existente encontrada para o usuário ${APP_USER}."
  if [[ -n "$REQUESTED_USER" && "$REQUESTED_USER" != "$APP_USER" ]]; then
    die "Para renomear uma instalação existente, conclua o reparo e use: whatsapp-remote desktop-user"
  fi
  REQUESTED_USER="$APP_USER"
  REQUESTED_GEOMETRY="${REQUESTED_GEOMETRY:-$GEOMETRY}"
  WEB_USER_INPUT="${WEB_USER_INPUT:-${WEB_USER:-remoteadmin}}"
fi

if [[ -z "$REQUESTED_USER" ]]; then
  if (( AUTO == 1 )); then
    REQUESTED_USER="whatsapp"
  else
    read -r -p "Usuário Linux do desktop [whatsapp]: " REQUESTED_USER
    REQUESTED_USER="${REQUESTED_USER:-whatsapp}"
  fi
fi
is_valid_linux_user "$REQUESTED_USER" || die "Usuário Linux inválido: $REQUESTED_USER"
APP_USER="$REQUESTED_USER"

if [[ -z "$REQUESTED_GEOMETRY" ]]; then
  if (( AUTO == 1 )); then
    REQUESTED_GEOMETRY="1280x720"
  else
    read -r -p "Resolução remota [1280x720]: " REQUESTED_GEOMETRY
    REQUESTED_GEOMETRY="${REQUESTED_GEOMETRY:-1280x720}"
  fi
fi
is_valid_geometry "$REQUESTED_GEOMETRY" || die "Resolução inválida: $REQUESTED_GEOMETRY"
GEOMETRY="$REQUESTED_GEOMETRY"
DISPLAY_NUMBER="${DISPLAY_NUMBER:-1}"
VNC_PORT="$((5900 + DISPLAY_NUMBER))"
NOVNC_PORT="${NOVNC_PORT:-6080}"

if [[ -z "$WEB_USER_INPUT" ]]; then
  if (( AUTO == 1 )); then
    WEB_USER_INPUT="remoteadmin"
  else
    read -r -p "Usuário da autenticação web [remoteadmin]: " WEB_USER_INPUT
    WEB_USER_INPUT="${WEB_USER_INPUT:-remoteadmin}"
  fi
fi
is_valid_web_user "$WEB_USER_INPUT" || die "Usuário web inválido."
WEB_USER="$WEB_USER_INPUT"

# Em atualização, preserva as senhas se os arquivos já existem.
NEED_VNC_PASSWORD=1
NEED_WEB_PASSWORD=1
if (( EXISTING == 1 )) && [[ -s "${APP_HOME:-/nonexistent}/.vnc/passwd" ]] && [[ -z "$VNC_PASSWORD" ]]; then
  NEED_VNC_PASSWORD=0
fi
if (( EXISTING == 1 )) && [[ -s "$HTPASSWD_FILE" ]] && [[ -z "$WEB_PASSWORD" ]]; then
  NEED_WEB_PASSWORD=0
  WEB_USER="$(cut -d: -f1 "$HTPASSWD_FILE" | head -n1 || printf '%s' "$WEB_USER")"
fi

if (( NEED_VNC_PASSWORD == 1 )) && [[ -z "$VNC_PASSWORD" ]]; then
  if (( AUTO == 1 )); then
    VNC_PASSWORD="$(random_password 8)"
  else
    read -r -p "Senha VNC visível (mínimo 8 caracteres; Enter gera automaticamente): " VNC_PASSWORD
    VNC_PASSWORD="${VNC_PASSWORD:-$(random_password 8)}"
  fi
fi
if (( NEED_VNC_PASSWORD == 1 )) && [[ ${#VNC_PASSWORD} -lt 8 ]]; then
  die "A senha VNC precisa ter pelo menos 8 caracteres."
fi

if (( NEED_WEB_PASSWORD == 1 )) && [[ -z "$WEB_PASSWORD" ]]; then
  if (( AUTO == 1 )); then
    WEB_PASSWORD="$(random_password 18)"
  else
    read -r -p "Senha web visível (mínimo 10 caracteres; Enter gera automaticamente): " WEB_PASSWORD
    WEB_PASSWORD="${WEB_PASSWORD:-$(random_password 18)}"
  fi
fi
if (( NEED_WEB_PASSWORD == 1 )) && [[ ${#WEB_PASSWORD} -lt 10 ]]; then
  die "A senha web precisa ter pelo menos 10 caracteres."
fi

info "Atualizando pacotes necessários..."
export DEBIAN_FRONTEND=noninteractive
wait_for_apt
apt-get update
apt-get install -y --no-install-recommends \
  openbox tint2 xterm dbus-x11 x11-utils xauth \
  tigervnc-standalone-server tigervnc-tools \
  novnc websockify \
  nginx apache2-utils openssl curl wget ca-certificates gnupg unzip \
  procps iproute2 psmisc fonts-liberation fonts-noto-color-emoji

create_swap_if_needed() {
  [[ "$NO_SWAP" == "1" ]] && { warn "Criação automática de swap desativada."; return 0; }
  swapon --show --noheadings | grep -q . && return 0
  local mem_kb swap_mb free_mb fs
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  if (( mem_kb < 1600000 )); then
    swap_mb=2048
  elif (( mem_kb < 3000000 )); then
    swap_mb=1024
  else
    return 0
  fi
  free_mb="$(df -Pm / | awk 'NR==2 {print $4}')"
  if (( free_mb < swap_mb + 1024 )); then
    warn "Disco insuficiente para criar ${swap_mb} MB de swap."
    return 0
  fi
  info "Memória baixa e nenhuma swap ativa; criando ${swap_mb} MB em /swapfile..."
  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  fs="$(findmnt -no FSTYPE / 2>/dev/null || true)"
  if [[ "$fs" == "btrfs" ]]; then
    touch /swapfile
    chattr +C /swapfile 2>/dev/null || true
  fi
  if ! fallocate -l "${swap_mb}M" /swapfile 2>/dev/null; then
    dd if=/dev/zero of=/swapfile bs=1M count="$swap_mb" status=progress
  fi
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -qE '^/swapfile\s' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  cat > /etc/sysctl.d/99-whatsapp-remote.conf <<'SYSCTL'
vm.swappiness=30
vm.vfs_cache_pressure=80
SYSCTL
  sysctl --system >/dev/null || true
}
create_swap_if_needed

install_chromium_snap() {
  info "Instalando Chromium Snap para ${OS_ID} ${OS_VERSION} ${ARCH}..."
  apt-get install -y --no-install-recommends snapd apparmor
  systemctl enable --now apparmor 2>/dev/null || true
  systemctl enable --now snapd.socket
  for _ in $(seq 1 60); do
    snap version >/dev/null 2>&1 && break
    sleep 2
  done
  snap version >/dev/null 2>&1 || die "O snapd não iniciou corretamente."
  if ! snap list chromium >/dev/null 2>&1; then
    snap install chromium
  else
    snap refresh chromium >/dev/null 2>&1 || true
  fi
  [[ -x /snap/bin/chromium ]] || die "Chromium Snap não foi encontrado em /snap/bin/chromium."
  BROWSER_BIN="/snap/bin/chromium"
  BROWSER_TYPE="Chromium Snap"
}

install_browser() {
  BROWSER_BIN=""
  BROWSER_TYPE=""

  if [[ "$ARCH" == "amd64" ]]; then
    if command_exists google-chrome-stable; then
      BROWSER_BIN="$(command -v google-chrome-stable)"
      BROWSER_TYPE="Google Chrome Stable"
      return 0
    fi
    info "Instalando Google Chrome Stable para x86_64..."
    local tmp_deb
    tmp_deb="$(mktemp --suffix=.deb)"
    if wget -qO "$tmp_deb" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
      && apt-get install -y "$tmp_deb"; then
      rm -f "$tmp_deb"
      BROWSER_BIN="$(command -v google-chrome-stable)"
      BROWSER_TYPE="Google Chrome Stable"
      return 0
    fi
    rm -f "$tmp_deb"
    warn "A instalação do Google Chrome falhou; será usado Chromium."
  fi

  # Debian fornece Chromium nativo para amd64 e arm64 nas versões suportadas.
  if [[ "$OS_ID" == "debian" ]]; then
    info "Instalando Chromium do repositório Debian para ${ARCH}..."
    apt-get install -y --no-install-recommends chromium
    BROWSER_BIN="$(command -v chromium)"
    BROWSER_TYPE="Chromium (Debian)"
    return 0
  fi

  install_chromium_snap
}
install_browser
ok "Navegador selecionado: $BROWSER_TYPE"

if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd -m -U -s /bin/bash "$APP_USER"
fi
APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
APP_GROUP="$(id -gn "$APP_USER")"
APP_UID="$(id -u "$APP_USER")"
APP_GID="$(id -g "$APP_USER")"

if [[ -z "${PROFILE_DIR:-}" ]]; then
  if [[ "$BROWSER_TYPE" == "Chromium Snap" ]]; then
    # O confinamento do Snap permite gravação persistente na área própria do aplicativo.
    PROFILE_DIR="$APP_HOME/snap/chromium/common/whatsapp-profile"
  elif [[ -d "$APP_HOME/.config/google-chrome-whatsapp" ]]; then
    PROFILE_DIR="$APP_HOME/.config/google-chrome-whatsapp"
  else
    PROFILE_DIR="$APP_HOME/.config/chrome-whatsapp"
  fi
fi
install -d -m 700 -o "$APP_USER" -g "$APP_GROUP" "$PROFILE_DIR"
install -d -m 700 -o "$APP_USER" -g "$APP_GROUP" "$APP_HOME/.vnc"

if (( NEED_VNC_PASSWORD == 1 )); then
  set_vnc_password "$VNC_PASSWORD"
else
  chown "$APP_USER:$APP_GROUP" "$APP_HOME/.vnc/passwd"
  chmod 600 "$APP_HOME/.vnc/passwd"
fi
if (( NEED_WEB_PASSWORD == 1 )); then
  set_web_credentials "$WEB_USER" "$WEB_PASSWORD"
else
  chown root:www-data "$HTPASSWD_FILE"
  chmod 640 "$HTPASSWD_FILE"
fi

MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
if (( MEM_KB < 2000000 )); then LOW_RAM=1; else LOW_RAM=0; fi
ACCESS_MODE="${ACCESS_MODE:-ip}"
PUBLIC_IP="${PUBLIC_IP:-}"
DOMAIN="${DOMAIN:-}"

install -d -m 755 "$INSTALL_DIR"
cp -a "$SCRIPT_DIR/." "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR"/*.sh "$INSTALL_DIR/lib/common.sh"
ln -sfn "$INSTALL_DIR/manage.sh" /usr/local/sbin/whatsapp-remote

save_config
render_runtime_scripts
rm -f /usr/local/bin/whatsapp-chrome 2>/dev/null || true
render_openbox_config
configure_novnc_mobile_defaults
render_systemd_units
systemctl enable "$SERVICE_DESKTOP" "$SERVICE_NOVNC" >/dev/null
restart_stack

if [[ -z "$REQUESTED_ACCESS" ]]; then
  if (( EXISTING == 1 )) && [[ -s "$NGINX_SITE" ]]; then
    REQUESTED_ACCESS="preserve"
  elif (( AUTO == 1 )); then
    REQUESTED_ACCESS="ip"
  else
    echo
    echo "Forma de acesso remoto:"
    echo "  1) HTTPS pelo IP (automático; certificado autoassinado)"
    echo "  2) HTTPS por domínio (Let's Encrypt)"
    read -r -p "Escolha [1]: " access_choice
    case "${access_choice:-1}" in
      1) REQUESTED_ACCESS="ip" ;;
      2) REQUESTED_ACCESS="domain" ;;
      *) die "Opção inválida." ;;
    esac
  fi
fi

if [[ "$REQUESTED_ACCESS" == "preserve" ]]; then
  if [[ -z "$PUBLIC_IP" && "${ACCESS_MODE:-ip}" == "ip" ]]; then
    PUBLIC_IP="$(detect_public_ip || true)"
  fi
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  save_config
  if [[ "${ACCESS_MODE:-ip}" == "domain" ]]; then
    open_local_firewall 1
  else
    open_local_firewall 0
  fi
elif [[ "$REQUESTED_ACCESS" == "domain" ]]; then
  if [[ -z "$REQUESTED_DOMAIN" ]]; then
    if (( AUTO == 1 )); then die "Informe WR_DOMAIN ou --domain para acesso por domínio."; fi
    read -r -p "Domínio já apontado para esta VPS: " REQUESTED_DOMAIN
  fi
  if [[ -z "$REQUESTED_EMAIL" ]]; then
    if (( AUTO == 1 )); then die "Informe WR_EMAIL ou --email para acesso por domínio."; fi
    read -r -p "E-mail do Let's Encrypt: " REQUESTED_EMAIL
  fi
  configure_nginx_domain "$REQUESTED_DOMAIN" "$REQUESTED_EMAIL"
  open_local_firewall 1
else
  if [[ -z "$REQUESTED_IP" ]]; then
    REQUESTED_IP="$(detect_public_ip || true)"
  fi
  if [[ -z "$REQUESTED_IP" ]] && (( AUTO == 0 )); then
    read -r -p "Não consegui detectar o IPv4 público. Informe-o: " REQUESTED_IP
  fi
  is_valid_ipv4 "$REQUESTED_IP" || die "Não foi possível detectar um IPv4 público. Use: --ip ENDERECO"
  configure_nginx_ip "$REQUESTED_IP"
  open_local_firewall 0
fi

save_config
write_credentials_file \
  "$([[ $NEED_VNC_PASSWORD -eq 1 ]] && printf '%s' "$VNC_PASSWORD" || true)" \
  "$([[ $NEED_WEB_PASSWORD -eq 1 ]] && printf '%s' "$WEB_PASSWORD" || true)"
unset VNC_PASSWORD WEB_PASSWORD WR_VNC_PASSWORD WR_WEB_PASSWORD || true

rm -f /etc/whatsapp-remote.conf 2>/dev/null || true

echo
ok "Instalação concluída e validada."
echo "Sistema:              $OS_NAME ($ARCH)"
echo "Navegador:           $BROWSER_TYPE"
echo "Usuário desktop:     $APP_USER"
echo "Perfil persistente:  $PROFILE_DIR"
echo "Acesso:              $(access_url)"
echo "Credenciais:         $CREDENTIALS_FILE"
echo "Gerenciador:         sudo whatsapp-remote"
echo
echo "Na Oracle Cloud, libere TCP 443 no NSG/Security List da instância."
echo "Para domínio/Let's Encrypt, libere também TCP 80."
echo "Não exponha publicamente as portas ${VNC_PORT} e ${NOVNC_PORT}."
echo
show_status
