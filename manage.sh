#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_root

prompt_password_twice() {
  local label="$1" min_length="$2" first second
  while true; do
    read -r -p "$label (visível): " first
    [[ ${#first} -ge min_length ]] || { warn "Use pelo menos ${min_length} caracteres."; continue; }
    read -r -p "Repita a senha (visível): " second
    [[ "$first" == "$second" ]] || { warn "As senhas não conferem."; continue; }
    printf '%s' "$first"
    return 0
  done
}

change_web_credentials() {
  load_config
  local username password
  read -r -p "Novo usuário web [${WEB_USER}]: " username
  username="${username:-$WEB_USER}"
  is_valid_web_user "$username" || die "Usuário web inválido."
  password="$(prompt_password_twice 'Nova senha web (mínimo 10 caracteres)' 10)"
  set_web_credentials "$username" "$password"
  save_config
  systemctl reload nginx
  write_credentials_file "" "$password"
  unset password
  ok "Usuário e senha web alterados."
  echo "Usuário web: $WEB_USER"
  echo "Arquivo protegido: $CREDENTIALS_FILE"
}

change_vnc_password() {
  load_config
  local password
  password="$(prompt_password_twice 'Nova senha VNC (mínimo 8; somente os 8 primeiros são usados)' 8)"
  set_vnc_password "$password"
  restart_stack
  write_credentials_file "$password" ""
  unset password
  ok "Senha VNC alterada e serviços reiniciados."
}

change_desktop_user() {
  load_config
  local old_user="$APP_USER" old_group="$APP_GROUP" old_home="$APP_HOME"
  local new_user new_home new_group
  read -r -p "Novo usuário Linux do desktop: " new_user
  is_valid_linux_user "$new_user" || die "Usuário inválido: $new_user"
  [[ "$new_user" != "$old_user" ]] || { info "O usuário já é $old_user."; return 0; }
  ! id "$new_user" >/dev/null 2>&1 || die "O usuário $new_user já existe."

  warn "O desktop será reiniciado, mas o perfil e a sessão do WhatsApp serão preservados."
  systemctl stop "$SERVICE_NOVNC" "$SERVICE_DESKTOP" 2>/dev/null || true
  pkill -KILL -u "$old_user" 2>/dev/null || true
  sleep 1

  usermod -l "$new_user" "$old_user"
  if [[ "$old_group" == "$old_user" ]] && getent group "$old_group" >/dev/null; then
    groupmod -n "$new_user" "$old_group"
  fi
  new_home="/home/$new_user"
  usermod -d "$new_home" -m "$new_user"

  APP_USER="$new_user"
  APP_HOME="$new_home"
  APP_GROUP="$(id -gn "$new_user")"
  APP_UID="$(id -u "$new_user")"
  APP_GID="$(id -g "$new_user")"
  if [[ "$PROFILE_DIR" == "$old_home"/* ]]; then
    PROFILE_DIR="$new_home/${PROFILE_DIR#"$old_home"/}"
  fi

  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME"
  save_config
  render_runtime_scripts
  render_openbox_config
  render_systemd_units
  configure_novnc_mobile_defaults
  systemctl enable "$SERVICE_DESKTOP" "$SERVICE_NOVNC" >/dev/null
  restart_stack
  write_credentials_file "" ""
  ok "Usuário Linux alterado de $old_user para $APP_USER."
}

change_resolution() {
  load_config
  local geometry
  read -r -p "Nova resolução [${GEOMETRY}]: " geometry
  geometry="${geometry:-$GEOMETRY}"
  is_valid_geometry "$geometry" || die "Resolução inválida. Exemplo: 1280x720"
  GEOMETRY="$geometry"
  save_config
  restart_stack
  ok "Resolução alterada para $GEOMETRY."
}

configure_ip_access_menu() {
  load_config
  local ip
  ip="$(detect_public_ip || true)"
  read -r -p "IPv4 público [${ip:-${PUBLIC_IP:-}}]: " answer
  ip="${answer:-${ip:-${PUBLIC_IP:-}}}"
  is_valid_ipv4 "$ip" || die "IPv4 inválido."
  configure_nginx_ip "$ip"
  open_local_firewall 0
  write_credentials_file "" ""
  ok "Acesso por IP configurado: $(access_url)"
}

configure_domain_access_menu() {
  load_config
  local domain email
  read -r -p "Domínio já apontado para esta VPS [${DOMAIN:-}]: " domain
  domain="${domain:-${DOMAIN:-}}"
  read -r -p "E-mail do Let's Encrypt: " email
  configure_nginx_domain "$domain" "$email"
  open_local_firewall 1
  write_credentials_file "" ""
  ok "Acesso por domínio configurado: $(access_url)"
}

repair_installation() {
  detect_platform
  load_config
  id "$APP_USER" >/dev/null 2>&1 || die "Usuário $APP_USER não existe."
  APP_GROUP="$(id -gn "$APP_USER")"
  APP_UID="$(id -u "$APP_USER")"
  APP_GID="$(id -g "$APP_USER")"
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME/.vnc" "$APP_HOME/.config/openbox" "$PROFILE_DIR" 2>/dev/null || true
  chmod 600 "$APP_HOME/.vnc/passwd"
  save_config
  render_runtime_scripts
  render_openbox_config
  configure_novnc_mobile_defaults
  render_systemd_units
  systemctl enable "$SERVICE_DESKTOP" "$SERVICE_NOVNC" >/dev/null
  restart_stack
  ok "Instalação reparada."
  show_status
}

show_logs() {
  echo "===== DESKTOP / VNC ====="
  journalctl -u "$SERVICE_DESKTOP" -n 80 --no-pager || true
  echo
  echo "===== NOVNC ====="
  journalctl -u "$SERVICE_NOVNC" -n 80 --no-pager || true
  echo
  echo "===== NGINX ====="
  journalctl -u nginx -n 40 --no-pager || true
}

show_info() {
  load_config
  echo "URL: $(access_url)"
  echo "Usuário web: $WEB_USER"
  echo "Usuário Linux do desktop: $APP_USER"
  echo "Perfil persistente: $PROFILE_DIR"
  echo "Credenciais iniciais/alteradas: $CREDENTIALS_FILE"
  echo "As senhas em hash não podem ser recuperadas; podem ser redefinidas neste gerenciador."
}

restart_menu() {
  load_config
  restart_stack
  ok "Desktop, noVNC e Nginx reiniciados."
  show_status
}

menu() {
  while true; do
    clear 2>/dev/null || true
    echo "============================================================"
    echo " $PROJECT_NAME — gerenciador $PROJECT_VERSION"
    echo "============================================================"
    echo " 1) Alterar usuário e senha web"
    echo " 2) Alterar senha VNC"
    echo " 3) Alterar usuário Linux do desktop"
    echo " 4) Alterar resolução"
    echo " 5) Configurar acesso HTTPS pelo IP"
    echo " 6) Configurar acesso HTTPS por domínio"
    echo " 7) Ver status"
    echo " 8) Reiniciar serviços"
    echo " 9) Ver informações de acesso"
    echo "10) Ver logs"
    echo "11) Reparar instalação"
    echo " 0) Sair"
    echo
    read -r -p "Escolha: " option
    echo
    case "$option" in
      1) change_web_credentials ;;
      2) change_vnc_password ;;
      3) change_desktop_user ;;
      4) change_resolution ;;
      5) configure_ip_access_menu ;;
      6) configure_domain_access_menu ;;
      7) show_status ;;
      8) restart_menu ;;
      9) show_info ;;
      10) show_logs ;;
      11) repair_installation ;;
      0) exit 0 ;;
      *) warn "Opção inválida." ;;
    esac
    echo
    read -r -p "Pressione Enter para continuar..." _
  done
}

help_text() {
  cat <<HELP
Uso: sudo whatsapp-remote [comando]

Comandos:
  menu                 Abre o menu interativo
  web-credentials      Altera usuário e senha da autenticação HTTPS
  vnc-password         Altera a senha da sessão VNC
  desktop-user         Renomeia o usuário Linux preservando o perfil
  resolution           Altera a resolução remota
  access-ip             Configura HTTPS por IP
  access-domain         Configura HTTPS por domínio/Let's Encrypt
  status                Exibe diagnóstico
  restart               Reinicia toda a pilha
  info                  Exibe URL e usuários
  logs                  Exibe logs recentes
  repair                Repara permissões, serviços e configurações
  help                  Exibe esta ajuda
HELP
}

case "${1:-menu}" in
  menu) menu ;;
  web-credentials) change_web_credentials ;;
  vnc-password) change_vnc_password ;;
  desktop-user) change_desktop_user ;;
  resolution) change_resolution ;;
  access-ip) configure_ip_access_menu ;;
  access-domain) configure_domain_access_menu ;;
  status) show_status ;;
  restart) restart_menu ;;
  info) show_info ;;
  logs) show_logs ;;
  repair) repair_installation ;;
  help|-h|--help) help_text ;;
  *) die "Comando desconhecido: $1. Use: whatsapp-remote help" ;;
esac
