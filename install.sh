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
SWAP_MODE="${WR_SWAP_MODE:-auto}"
GITHUB_REPOSITORY="${WR_GITHUB_REPOSITORY:-$GITHUB_REPOSITORY_DEFAULT}"
GITHUB_REF="${WR_GITHUB_REF:-$GITHUB_REF_DEFAULT}"
EXISTING=0
LEGACY=0
NEED_VNC_PASSWORD=1
NEED_WEB_PASSWORD=1

usage() {
  cat <<USAGE
$PROJECT_NAME $PROJECT_VERSION

Uso:
  sudo bash install.sh                  Instalação inteligente com menu
  sudo bash install.sh --auto           Instalação totalmente automática
  sudo bash install.sh --repair --auto  Atualiza/repara preservando a sessão

Opções:
  --auto                     Não faz perguntas e aplica escolhas recomendadas
  --repair                   Repara/atualiza uma instalação existente
  --desktop-user USUARIO     Usuário Linux do desktop
  --geometry LARGURAxALTURA  Resolução, exemplo: 1280x720
  --ip ENDERECO              Acesso HTTPS por IPv4
  --domain DOMINIO           Acesso HTTPS por domínio
  --email EMAIL              E-mail do Let's Encrypt
  --swap auto|on|off         Gerenciamento de swap
  --no-swap                  Equivalente a --swap off
  -h, --help                 Exibe esta ajuda

Variáveis opcionais:
  WR_DESKTOP_USER, WR_WEB_USER, WR_VNC_PASSWORD, WR_WEB_PASSWORD,
  WR_GEOMETRY, WR_PUBLIC_IP, WR_DOMAIN, WR_EMAIL e WR_SWAP_MODE.
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
    --swap) [[ $# -ge 2 ]] || die "Falta valor para --swap"; SWAP_MODE="$2"; shift 2 ;;
    --no-swap) SWAP_MODE="off"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opção desconhecida: $1" ;;
  esac
done

case "$SWAP_MODE" in auto|on|off) ;; *) die "Use --swap auto, on ou off." ;; esac

require_root
install -d -m 755 /var/log
exec > >(tee -a "$INSTALL_LOG") 2>&1
trap 'printf "\n%b[ERRO]%b Falha na linha %s. Consulte %s\n" "$C_RED" "$C_RESET" "$LINENO" "$INSTALL_LOG" >&2' ERR

preflight_checks
DETECTED_IP="$(detect_public_ip || true)"
DETECTED_PRIVATE_IP="$(detect_private_ip || true)"
DETECTED_PROVIDER="$(detect_cloud_provider)"
MEM_MB="$(memory_mb)"
DISK_MB="$(disk_free_mb)"
RECOMMENDED_GEOMETRY="$(recommended_geometry)"
RECOMMENDED_SWAP="$(recommended_swap_mb)"

# Descobre e migra configurações existentes sem apagar o perfil do navegador.
if [[ -r "$CONFIG_FILE" ]]; then
  EXISTING=1
  load_config
elif [[ -r /etc/whatsapp-remote.conf ]]; then
  EXISTING=1
  LEGACY=1
  # shellcheck disable=SC1091
  source /etc/whatsapp-remote.conf
  APP_GROUP="$(id -gn "$APP_USER")"
  APP_UID="$(id -u "$APP_USER")"
  APP_GID="$(id -g "$APP_USER")"
  DISPLAY_NUMBER="${DISPLAY_NUMBER:-1}"
  GEOMETRY="${GEOMETRY:-1280x720}"
  VNC_PORT="$((5900 + DISPLAY_NUMBER))"
  NOVNC_PORT=6080
  PROFILE_DIR="$APP_HOME/.config/google-chrome-whatsapp"
  ACCESS_MODE="ip"
  PUBLIC_IP="${DETECTED_IP:-}"
  DOMAIN=""
  WEB_USER="remoteadmin"
  BROWSER_BIN="${BROWSER_BIN:-/usr/bin/google-chrome-stable}"
  BROWSER_TYPE="${BROWSER_TYPE:-Google Chrome Stable}"
  LOW_RAM=1
  APP_USER_MANAGED=0
  info "Instalação antiga encontrada; ela será migrada preservando a sessão."
fi

prepare_defaults() {
  if (( EXISTING == 1 )); then
    local installed_user="$APP_USER"
    if [[ -n "$REQUESTED_USER" && "$REQUESTED_USER" != "$installed_user" ]]; then
      die "Para alterar o usuário Linux de uma instalação existente, use: sudo whatsapp-remote desktop-user"
    fi
    REQUESTED_USER="$installed_user"
    REQUESTED_GEOMETRY="${REQUESTED_GEOMETRY:-$GEOMETRY}"
    WEB_USER_INPUT="${WEB_USER_INPUT:-${WEB_USER:-remoteadmin}}"
    if [[ -z "$REQUESTED_ACCESS" ]]; then REQUESTED_ACCESS="preserve"; fi
    if [[ -s "$APP_HOME/.vnc/passwd" && -z "$VNC_PASSWORD" ]]; then
      NEED_VNC_PASSWORD=0
    elif [[ -z "$VNC_PASSWORD" ]]; then
      VNC_PASSWORD="$(random_password 8)"
    fi
    if [[ -s "$HTPASSWD_FILE" && -z "$WEB_PASSWORD" ]]; then
      NEED_WEB_PASSWORD=0
      WEB_USER_INPUT="$(cut -d: -f1 "$HTPASSWD_FILE" | head -n1 || printf '%s' "$WEB_USER_INPUT")"
    elif [[ -z "$WEB_PASSWORD" ]]; then
      WEB_PASSWORD="$(random_password 18)"
    fi
    return
  fi

  REQUESTED_USER="${REQUESTED_USER:-whatsapp}"
  REQUESTED_GEOMETRY="${REQUESTED_GEOMETRY:-$RECOMMENDED_GEOMETRY}"
  WEB_USER_INPUT="${WEB_USER_INPUT:-remoteadmin}"
  VNC_PASSWORD="${VNC_PASSWORD:-$(random_password 8)}"
  WEB_PASSWORD="${WEB_PASSWORD:-$(random_password 18)}"
  REQUESTED_ACCESS="${REQUESTED_ACCESS:-ip}"
  REQUESTED_IP="${REQUESTED_IP:-$DETECTED_IP}"
}
prepare_defaults

validate_choices() {
  is_valid_linux_user "$REQUESTED_USER" || { warn "Usuário Linux inválido: $REQUESTED_USER"; return 1; }
  is_valid_web_user "$WEB_USER_INPUT" || { warn "Usuário web inválido."; return 1; }
  is_valid_geometry "$REQUESTED_GEOMETRY" || { warn "Resolução inválida: $REQUESTED_GEOMETRY"; return 1; }
  if (( NEED_VNC_PASSWORD == 1 )) && [[ ${#VNC_PASSWORD} -lt 8 ]]; then warn "A senha VNC precisa ter pelo menos 8 caracteres."; return 1; fi
  if (( NEED_WEB_PASSWORD == 1 )) && [[ ${#WEB_PASSWORD} -lt 10 ]]; then warn "A senha web precisa ter pelo menos 10 caracteres."; return 1; fi
  case "$REQUESTED_ACCESS" in
    preserve) (( EXISTING == 1 )) || { warn "Não há configuração anterior para preservar."; return 1; } ;;
    ip) is_valid_ipv4 "$REQUESTED_IP" || { warn "IPv4 inválido ou não detectado: ${REQUESTED_IP:-vazio}"; return 1; } ;;
    domain)
      is_valid_domain "$REQUESTED_DOMAIN" || { warn "Domínio inválido: ${REQUESTED_DOMAIN:-vazio}"; return 1; }
      is_valid_email "$REQUESTED_EMAIL" || { warn "E-mail inválido: ${REQUESTED_EMAIL:-vazio}"; return 1; }
      ;;
    *) warn "Modo de acesso inválido."; return 1 ;;
  esac
}

password_label() {
  local value="$1" needed="$2"
  if (( needed == 0 )); then printf '%s' 'mantida (não será alterada)'; else printf '%s' "$value"; fi
}

show_install_summary() {
  ui_header "Assistente inteligente de instalação"
  printf "%bDetecção automática%b\n" "$C_BOLD" "$C_RESET"
  printf '  Sistema:            %s\n' "$OS_NAME"
  printf '  Arquitetura:        %s\n' "$ARCH"
  printf '  Provedor:           %s\n' "$DETECTED_PROVIDER"
  printf '  IP público:         %s\n' "${DETECTED_IP:-não detectado}"
  printf '  IP privado:         %s\n' "${DETECTED_PRIVATE_IP:-não detectado}"
  printf '  Memória:            %s MB\n' "$MEM_MB"
  printf '  Disco livre:        %s MB\n' "$DISK_MB"
  printf '  Instalação atual:   %s\n' "$([[ $EXISTING -eq 1 ]] && echo encontrada || echo nova)"
  echo
  printf "%bConfiguração que será aplicada%b\n" "$C_BOLD" "$C_RESET"
  printf '  1) Usuário desktop: %s\n' "$REQUESTED_USER"
  printf '  2) Usuário web:     %s\n' "$WEB_USER_INPUT"
  printf '  3) Senha VNC:       %s\n' "$(password_label "$VNC_PASSWORD" "$NEED_VNC_PASSWORD")"
  printf '  4) Senha web:       %s\n' "$(password_label "$WEB_PASSWORD" "$NEED_WEB_PASSWORD")"
  printf '  5) Resolução:       %s\n' "$REQUESTED_GEOMETRY"
  case "$REQUESTED_ACCESS" in
    ip) printf '  6) Acesso:          HTTPS pelo IP %s\n' "${REQUESTED_IP:-não detectado}" ;;
    domain) printf '  6) Acesso:          HTTPS pelo domínio %s\n' "$REQUESTED_DOMAIN" ;;
    preserve) printf '  6) Acesso:          preservar configuração atual (%s)\n' "$(access_url)" ;;
  esac
  printf '  7) Swap:            %s' "$SWAP_MODE"
  [[ "$SWAP_MODE" == "auto" ]] && printf ' (recomendação: %s MB)' "$RECOMMENDED_SWAP"
  printf '\n'
  ui_rule
  echo "  I) Iniciar instalação com essas informações"
  echo "  1-7) Alterar a informação correspondente"
  echo "  8) Detectar novamente o IP público"
  echo "  9) Restaurar escolhas inteligentes"
  echo "  0) Cancelar e sair"
}

edit_access() {
  while true; do
    ui_header "Forma de acesso remoto"
    echo "  1) HTTPS pelo IP público (recomendado e automático)"
    echo "  2) HTTPS por domínio com Let's Encrypt"
    (( EXISTING == 1 )) && echo "  3) Preservar a configuração atual"
    echo "  0) Voltar sem alterar"
    echo
    read -r -p "Escolha: " choice
    case "$choice" in
      1)
        REQUESTED_ACCESS="ip"
        local suggested_ip
        suggested_ip="${DETECTED_IP:-${PUBLIC_IP:-}}"
        read -r -p "IPv4 público [${suggested_ip}]: " answer
        REQUESTED_IP="${answer:-$suggested_ip}"
        if ! is_valid_ipv4 "$REQUESTED_IP"; then warn "IPv4 inválido."; ui_pause; continue; fi
        return
        ;;
      2)
        REQUESTED_ACCESS="domain"
        read -r -p "Domínio já apontado para a VPS [${REQUESTED_DOMAIN:-}]: " answer
        REQUESTED_DOMAIN="${answer:-$REQUESTED_DOMAIN}"
        is_valid_domain "$REQUESTED_DOMAIN" || { warn "Domínio inválido."; ui_pause; continue; }
        read -r -p "E-mail para o Let's Encrypt [${REQUESTED_EMAIL:-}]: " answer
        REQUESTED_EMAIL="${answer:-$REQUESTED_EMAIL}"
        is_valid_email "$REQUESTED_EMAIL" || { warn "E-mail inválido."; ui_pause; continue; }
        return
        ;;
      3) if (( EXISTING == 1 )); then REQUESTED_ACCESS="preserve"; return; fi ;;
      0) return ;;
      *) warn "Opção inválida."; ui_pause ;;
    esac
  done
}

edit_swap() {
  while true; do
    ui_header "Gerenciamento de swap"
    echo "  1) Automático — o instalador decide conforme RAM e swap existente"
    echo "  2) Ativar — cria swap se não existir"
    echo "  3) Desativar — não cria nem remove swap"
    echo "  0) Voltar"
    echo
    read -r -p "Escolha: " choice
    case "$choice" in
      1) SWAP_MODE="auto"; return ;;
      2) SWAP_MODE="on"; return ;;
      3) SWAP_MODE="off"; return ;;
      0) return ;;
      *) warn "Opção inválida."; ui_pause ;;
    esac
  done
}

restore_smart_defaults() {
  if (( EXISTING == 0 )); then
    REQUESTED_USER="whatsapp"
    WEB_USER_INPUT="remoteadmin"
    REQUESTED_GEOMETRY="$RECOMMENDED_GEOMETRY"
    VNC_PASSWORD="$(random_password 8)"
    WEB_PASSWORD="$(random_password 18)"
    NEED_VNC_PASSWORD=1
    NEED_WEB_PASSWORD=1
    REQUESTED_ACCESS="ip"
    REQUESTED_IP="$DETECTED_IP"
  else
    REQUESTED_USER="$APP_USER"
    WEB_USER_INPUT="${WEB_USER:-remoteadmin}"
    REQUESTED_GEOMETRY="$GEOMETRY"
    REQUESTED_ACCESS="preserve"
    if [[ -s "$APP_HOME/.vnc/passwd" ]]; then
      VNC_PASSWORD=""
      NEED_VNC_PASSWORD=0
    else
      VNC_PASSWORD="$(random_password 8)"
      NEED_VNC_PASSWORD=1
    fi
    if [[ -s "$HTPASSWD_FILE" ]]; then
      WEB_PASSWORD=""
      NEED_WEB_PASSWORD=0
    else
      WEB_PASSWORD="$(random_password 18)"
      NEED_WEB_PASSWORD=1
    fi
  fi
  SWAP_MODE="auto"
}

interactive_wizard() {
  local choice answer
  while true; do
    show_install_summary
    echo
    read -r -p "Escolha [I]: " choice
    choice="${choice:-I}"
    case "${choice^^}" in
      I)
        if validate_choices; then
          echo
          if ui_yes_no "Confirmar e começar agora?" s; then return 0; fi
        else
          ui_pause
        fi
        ;;
      1)
        if (( EXISTING == 1 )); then
          warn "O usuário instalado é alterado com segurança pelo Manager após o reparo."
          ui_pause
        else
          read -r -p "Usuário Linux do desktop [${REQUESTED_USER}]: " answer
          answer="${answer:-$REQUESTED_USER}"
          if is_valid_linux_user "$answer"; then REQUESTED_USER="$answer"; else warn "Usuário inválido."; ui_pause; fi
        fi
        ;;
      2)
        read -r -p "Usuário da autenticação web [${WEB_USER_INPUT}]: " answer
        answer="${answer:-$WEB_USER_INPUT}"
        if is_valid_web_user "$answer"; then
          if [[ "$answer" != "$WEB_USER_INPUT" && $EXISTING -eq 1 && $NEED_WEB_PASSWORD -eq 0 ]]; then
            NEED_WEB_PASSWORD=1
            WEB_PASSWORD="$(random_password 18)"
          fi
          WEB_USER_INPUT="$answer"
        else warn "Usuário web inválido."; ui_pause; fi
        ;;
      3)
        read -r -p "Nova senha VNC visível (mínimo 8; Enter gera): " answer
        VNC_PASSWORD="${answer:-$(random_password 8)}"
        if (( ${#VNC_PASSWORD} >= 8 )); then NEED_VNC_PASSWORD=1; else warn "Use no mínimo 8 caracteres."; ui_pause; fi
        ;;
      4)
        read -r -p "Nova senha web visível (mínimo 10; Enter gera): " answer
        WEB_PASSWORD="${answer:-$(random_password 18)}"
        if (( ${#WEB_PASSWORD} >= 10 )); then NEED_WEB_PASSWORD=1; else warn "Use no mínimo 10 caracteres."; ui_pause; fi
        ;;
      5)
        read -r -p "Resolução [${REQUESTED_GEOMETRY}]: " answer
        answer="${answer:-$REQUESTED_GEOMETRY}"
        if is_valid_geometry "$answer"; then REQUESTED_GEOMETRY="$answer"; else warn "Use formato como 1280x720."; ui_pause; fi
        ;;
      6) edit_access ;;
      7) edit_swap ;;
      8)
        info "Detectando novamente..."
        DETECTED_IP="$(detect_public_ip || true)"
        [[ -n "$DETECTED_IP" ]] && { REQUESTED_IP="$DETECTED_IP"; ok "IP detectado: $DETECTED_IP"; } || warn "Não foi possível detectar o IP."
        sleep 1
        ;;
      9) restore_smart_defaults ;;
      0) echo "Instalação cancelada."; exit 0 ;;
      *) warn "Opção inválida."; ui_pause ;;
    esac
  done
}

if (( AUTO == 0 )); then
  interactive_wizard
else
  validate_choices || die "As escolhas automáticas não puderam ser validadas. Informe os parâmetros manualmente."
fi

APP_USER="$REQUESTED_USER"
GEOMETRY="$REQUESTED_GEOMETRY"
WEB_USER="$WEB_USER_INPUT"
DISPLAY_NUMBER="${DISPLAY_NUMBER:-1}"
VNC_PORT="$((5900 + DISPLAY_NUMBER))"
NOVNC_PORT="${NOVNC_PORT:-6080}"

stage() {
  local current="$1" total="$2" text="$3"
  printf '\n%b[%s/%s]%b %s\n' "$C_BOLD$C_CYAN" "$current" "$total" "$C_RESET" "$text"
}

create_swap_if_needed() {
  if [[ "$SWAP_MODE" == "off" ]]; then info "Criação de swap desativada."; return 0; fi
  if swapon --show --noheadings | grep -q .; then ok "Swap já está ativa; nenhuma alteração necessária."; return 0; fi

  local swap_mb="$RECOMMENDED_SWAP" free_mb fs
  if [[ "$SWAP_MODE" == "on" && "$swap_mb" == "0" ]]; then swap_mb=1024; fi
  if [[ "$swap_mb" == "0" ]]; then info "A quantidade de RAM não exige swap automática."; return 0; fi
  free_mb="$(disk_free_mb)"
  if (( free_mb < swap_mb + 1024 )); then warn "Disco insuficiente para criar ${swap_mb} MB de swap."; return 0; fi

  info "Criando ${swap_mb} MB de swap em /swapfile..."
  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  fs="$(findmnt -no FSTYPE / 2>/dev/null || true)"
  if [[ "$fs" == "btrfs" ]]; then touch /swapfile; chattr +C /swapfile 2>/dev/null || true; fi
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
  ok "Swap configurada."
}

install_chromium_snap() {
  info "Instalando Chromium Snap para ${OS_ID} ${OS_VERSION} ${ARCH}..."
  apt_install_retry snapd apparmor
  systemctl enable --now apparmor 2>/dev/null || true
  systemctl enable --now snapd.socket
  local i
  for i in $(seq 1 60); do snap version >/dev/null 2>&1 && break; sleep 2; done
  snap version >/dev/null 2>&1 || die "O snapd não iniciou corretamente."
  if ! snap list chromium >/dev/null 2>&1; then snap install chromium; else snap refresh chromium >/dev/null 2>&1 || true; fi
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
    if curl -fL --retry 4 --connect-timeout 15 --max-time 300 \
      https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o "$tmp_deb" \
      && DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_deb"; then
      rm -f "$tmp_deb"
      BROWSER_BIN="$(command -v google-chrome-stable)"
      BROWSER_TYPE="Google Chrome Stable"
      return 0
    fi
    rm -f "$tmp_deb"
    warn "O Google Chrome falhou; o instalador usará Chromium."
  fi
  if [[ "$OS_ID" == "debian" ]]; then
    apt_install_retry chromium
    BROWSER_BIN="$(command -v chromium)"
    BROWSER_TYPE="Chromium (Debian)"
  else
    install_chromium_snap
  fi
}

stage 1 7 "Preparando e protegendo a instalação atual"
backup_current_config

stage 2 7 "Atualizando pacotes e instalando o ambiente gráfico"
apt_recover
apt_update_retry
apt_install_retry \
  openbox tint2 xterm dbus-x11 x11-utils xauth \
  tigervnc-standalone-server tigervnc-tools \
  novnc websockify nginx apache2-utils openssl curl wget ca-certificates gnupg unzip \
  procps iproute2 psmisc fonts-liberation fonts-noto-color-emoji
create_swap_if_needed

stage 3 7 "Selecionando e instalando o navegador correto"
install_browser
ok "Navegador selecionado: $BROWSER_TYPE"

stage 4 7 "Criando usuário, perfil persistente e credenciais"
if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd -m -U -s /bin/bash "$APP_USER"
  APP_USER_MANAGED=1
else
  APP_USER_MANAGED="${APP_USER_MANAGED:-0}"
fi
APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
APP_GROUP="$(id -gn "$APP_USER")"
APP_UID="$(id -u "$APP_USER")"
APP_GID="$(id -g "$APP_USER")"
if [[ -z "${PROFILE_DIR:-}" ]]; then
  if [[ "$BROWSER_TYPE" == "Chromium Snap" ]]; then
    PROFILE_DIR="$APP_HOME/snap/chromium/common/whatsapp-profile"
  elif [[ -d "$APP_HOME/.config/google-chrome-whatsapp" ]]; then
    PROFILE_DIR="$APP_HOME/.config/google-chrome-whatsapp"
  else
    PROFILE_DIR="$APP_HOME/.config/chrome-whatsapp"
  fi
fi
install -d -m 700 -o "$APP_USER" -g "$APP_GROUP" "$PROFILE_DIR" "$APP_HOME/.vnc"
if (( NEED_VNC_PASSWORD == 1 )); then set_vnc_password "$VNC_PASSWORD"; else chown "$APP_USER:$APP_GROUP" "$APP_HOME/.vnc/passwd"; chmod 600 "$APP_HOME/.vnc/passwd"; fi
if (( NEED_WEB_PASSWORD == 1 )); then set_web_credentials "$WEB_USER" "$WEB_PASSWORD"; else chown root:www-data "$HTPASSWD_FILE"; chmod 640 "$HTPASSWD_FILE"; fi
MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
if (( MEM_KB < 2000000 )); then LOW_RAM=1; else LOW_RAM=0; fi
ACCESS_MODE="${ACCESS_MODE:-ip}"
PUBLIC_IP="${PUBLIC_IP:-}"
DOMAIN="${DOMAIN:-}"

stage 5 7 "Instalando serviços persistentes e suporte para celular"
install -d -m 755 "$INSTALL_DIR"
if [[ "$(readlink -f "$SCRIPT_DIR")" != "$(readlink -f "$INSTALL_DIR")" ]]; then
  rm -rf "$INSTALL_DIR"/*
  cp -a "$SCRIPT_DIR/." "$INSTALL_DIR/"
fi
chmod 755 "$INSTALL_DIR"/*.sh "$INSTALL_DIR/lib/common.sh"
ln -sfn "$INSTALL_DIR/manage.sh" /usr/local/sbin/whatsapp-remote
install_menu_command
save_config
render_runtime_scripts
render_openbox_config
configure_novnc_mobile_defaults
render_systemd_units
systemctl enable "$SERVICE_DESKTOP" "$SERVICE_NOVNC" >/dev/null
restart_stack

stage 6 7 "Configurando acesso HTTPS"
case "$REQUESTED_ACCESS" in
  preserve)
    if [[ -z "$PUBLIC_IP" && "${ACCESS_MODE:-ip}" == "ip" ]]; then PUBLIC_IP="${DETECTED_IP:-$(detect_public_ip || true)}"; fi
    [[ -s "$NGINX_SITE" ]] || {
      warn "A configuração anterior do Nginx não existe; recriando acesso por IP."
      REQUESTED_ACCESS="ip"
      REQUESTED_IP="${PUBLIC_IP:-$DETECTED_IP}"
    }
    if [[ "$REQUESTED_ACCESS" == "preserve" ]]; then
      nginx -t
      systemctl enable --now nginx
      systemctl reload nginx
      save_config
      [[ "$ACCESS_MODE" == "domain" ]] && open_local_firewall 1 || open_local_firewall 0
    fi
    ;;
esac
if [[ "$REQUESTED_ACCESS" == "domain" ]]; then
  configure_nginx_domain "$REQUESTED_DOMAIN" "$REQUESTED_EMAIL"
  open_local_firewall 1
elif [[ "$REQUESTED_ACCESS" == "ip" ]]; then
  REQUESTED_IP="${REQUESTED_IP:-$DETECTED_IP}"
  is_valid_ipv4 "$REQUESTED_IP" || die "Não foi possível detectar o IPv4 público. Use --ip ENDERECO."
  configure_nginx_ip "$REQUESTED_IP"
  open_local_firewall 0
fi

stage 7 7 "Validando serviços, portas e navegador"
save_config
write_credentials_file \
  "$([[ $NEED_VNC_PASSWORD -eq 1 ]] && printf '%s' "$VNC_PASSWORD" || true)" \
  "$([[ $NEED_WEB_PASSWORD -eq 1 ]] && printf '%s' "$WEB_PASSWORD" || true)"
unset VNC_PASSWORD WEB_PASSWORD WR_VNC_PASSWORD WR_WEB_PASSWORD || true
rm -f /etc/whatsapp-remote.conf 2>/dev/null || true

sleep 2
quick_healthcheck || {
  warn "A validação encontrou um componente indisponível; executando reparo rápido."
  restart_stack
}

printf '\n'
ui_rule
ok "Instalação concluída e validada."
printf '  Sistema:             %s (%s)\n' "$OS_NAME" "$ARCH"
printf '  Navegador:          %s\n' "$BROWSER_TYPE"
printf '  Usuário desktop:    %s\n' "$APP_USER"
printf '  URL de acesso:      %s\n' "$(access_url)"
printf '  Credenciais:        %s\n' "$CREDENTIALS_FILE"
printf '  Menu/Manager:       menu  (ou sudo whatsapp-remote)\n'
ui_rule
printf '\n'
if [[ "$DETECTED_PROVIDER" == "Oracle Cloud" ]]; then
  echo "Oracle Cloud: libere TCP 443 no NSG/Security List; para domínio, libere também TCP 80."
else
  echo "No firewall do provedor, libere TCP 443; para domínio, libere também TCP 80."
fi
echo "Não exponha publicamente as portas ${VNC_PORT} e ${NOVNC_PORT}."
echo
show_status
