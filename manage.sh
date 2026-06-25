#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f -- "$SCRIPT_PATH" 2>/dev/null || printf '%s' "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
if [[ ! -r "$SCRIPT_DIR/lib/common.sh" && -r /opt/whatsapp-remote/lib/common.sh ]]; then
  SCRIPT_DIR="/opt/whatsapp-remote"
fi
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
require_root

prompt_password_twice() {
  local label="$1" min_length="$2" first second
  while true; do
    read -r -p "$label (visível; 0 para voltar): " first
    [[ "$first" == "0" ]] && return 1
    [[ ${#first} -ge min_length ]] || { warn "Use pelo menos ${min_length} caracteres."; continue; }
    read -r -p "Repita a senha (visível): " second
    [[ "$first" == "$second" ]] || { warn "As senhas não conferem."; continue; }
    printf '%s' "$first"
    return 0
  done
}

confirm_action() {
  local text="$1"
  ui_yes_no "$text" n
}

manager_dashboard() {
  load_config
  local d b n w ip private_ip browser whatsapp_raw whatsapp_message mem swap disk load_text
  d="$(systemctl is-active "$SERVICE_DESKTOP" 2>/dev/null || true)"
  b="$(systemctl is-active "$SERVICE_BROWSER" 2>/dev/null || true)"
  n="$(systemctl is-active "$SERVICE_NOVNC" 2>/dev/null || true)"
  w="$(systemctl is-active nginx 2>/dev/null || true)"
  ip="$(detect_public_ip || true)"
  private_ip="$(detect_private_ip || true)"
  browser="$(browser_is_running && echo ativo || echo inativo)"
  whatsapp_raw="$(whatsapp_session_status || true)"
  whatsapp_message="${whatsapp_raw#*|}"
  mem="$(free -h | awk '/Mem:/ {print $3 "/" $2 " (livre " $7 ")"}')"
  swap="$(free -h | awk '/Swap:/ {print $3 "/" $2}')"
  disk="$(df -h / | awk 'NR==2 {print $4}')"
  load_text="$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || true)"

  printf ' URL:          %s\n' "$(access_url)"
  printf ' IP público:   %s | IP privado: %s\n' "${ip:-não detectado}" "${private_ip:-não detectado}"
  printf ' Sistema:      %s %s (%s) | Kernel: %s\n' "$OS_ID" "$OS_VERSION" "$ARCH" "$(uname -r 2>/dev/null || echo '?')"
  printf ' Serviços:     Desktop %s | Browser %s | noVNC %s | Nginx %s | Processo %s\n' "$d" "$b" "$n" "$w" "$browser"
  printf ' WhatsApp:     %s\n' "${whatsapp_message:-estado não confirmado}"
  printf ' Recursos:     RAM %s | Swap %s | Disco %s | Carga %s\n' "$mem" "$swap" "$disk" "${load_text:-?}"
  echo
  show_health_summary compact || true
}

change_web_credentials() {
  load_config
  local username password answer
  ui_header "Alterar login do acesso web"
  echo "Usuário atual: $WEB_USER"
  read -r -p "Novo usuário [${WEB_USER}; 0 para voltar]: " answer
  [[ "$answer" == "0" ]] && return 0
  username="${answer:-$WEB_USER}"
  is_valid_web_user "$username" || { warn "Usuário web inválido."; return 1; }
  password="$(prompt_password_twice 'Nova senha web — mínimo 10 caracteres' 10)" || return 0
  set_web_credentials "$username" "$password"
  save_config
  nginx -t
  systemctl reload nginx
  write_credentials_file "" "$password"
  unset password
  ok "Usuário e senha web alterados."
  echo "Novo usuário: $WEB_USER"
  echo "Credenciais salvas em: $CREDENTIALS_FILE"
}

change_vnc_password() {
  load_config
  local password
  ui_header "Alterar senha da sessão VNC"
  echo "A senha VNC é solicitada dentro da página noVNC."
  password="$(prompt_password_twice 'Nova senha VNC — mínimo 8 caracteres' 8)" || return 0
  set_vnc_password "$password"
  restart_stack
  write_credentials_file "$password" ""
  unset password
  ok "Senha VNC alterada e serviços reiniciados."
}

change_desktop_user() {
  load_config
  local old_user="$APP_USER" old_group="$APP_GROUP" old_home="$APP_HOME"
  local new_user new_home
  ui_header "Alterar usuário Linux do desktop"
  echo "Usuário atual: $old_user"
  echo "O perfil do navegador e a sessão do WhatsApp serão preservados."
  read -r -p "Novo usuário [0 para voltar]: " new_user
  [[ "$new_user" == "0" ]] && return 0
  is_valid_linux_user "$new_user" || { warn "Usuário inválido: $new_user"; return 1; }
  [[ "$new_user" != "$old_user" ]] || { info "O usuário já é $old_user."; return 0; }
  ! id "$new_user" >/dev/null 2>&1 || { warn "O usuário $new_user já existe."; return 1; }
  confirm_action "Confirmar a alteração de '$old_user' para '$new_user'?" || return 0

  backup_current_config
  systemctl stop "$SERVICE_NOVNC" "$SERVICE_BROWSER" "$SERVICE_DESKTOP" 2>/dev/null || true
  pkill -KILL -u "$old_user" 2>/dev/null || true
  sleep 1
  usermod -l "$new_user" "$old_user"
  if [[ "$old_group" == "$old_user" ]] && getent group "$old_group" >/dev/null; then groupmod -n "$new_user" "$old_group"; fi
  new_home="/home/$new_user"
  usermod -d "$new_home" -m "$new_user"

  APP_USER="$new_user"
  APP_HOME="$new_home"
  APP_GROUP="$(id -gn "$new_user")"
  APP_UID="$(id -u "$new_user")"
  APP_GID="$(id -g "$new_user")"
  if [[ "$PROFILE_DIR" == "$old_home"/* ]]; then PROFILE_DIR="$new_home/${PROFILE_DIR#"$old_home"/}"; fi
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME"
  save_config
  render_runtime_scripts
  render_openbox_config
  render_systemd_units
  configure_novnc_mobile_defaults
  systemctl enable "$SERVICE_DESKTOP" "$SERVICE_BROWSER" "$SERVICE_NOVNC" >/dev/null
  restart_stack
  write_credentials_file "" ""
  ok "Usuário alterado de $old_user para $APP_USER."
}

change_resolution() {
  load_config
  local choice geometry
  while true; do
    ui_header "Alterar resolução do desktop remoto"
    echo "Atual: $GEOMETRY"
    echo
    echo "  1) 1024x768  — menor consumo"
    echo "  2) 1280x720  — recomendado"
    echo "  3) 1366x768"
    echo "  4) 1600x900"
    echo "  5) Informar manualmente"
    echo "  0) Voltar"
    echo
    read -r -p "Escolha: " choice
    case "$choice" in
      1) geometry="1024x768" ;;
      2) geometry="1280x720" ;;
      3) geometry="1366x768" ;;
      4) geometry="1600x900" ;;
      5) read -r -p "Resolução no formato LARGURAxALTURA: " geometry ;;
      0) return 0 ;;
      *) warn "Opção inválida."; ui_pause; continue ;;
    esac
    is_valid_geometry "$geometry" || { warn "Resolução inválida."; ui_pause; continue; }
    GEOMETRY="$geometry"
    save_config
    restart_stack
    ok "Resolução alterada para $GEOMETRY."
    return 0
  done
}

configure_ip_access_menu() {
  load_config
  local detected ip answer
  detected="$(detect_public_ip || true)"
  ui_header "Configurar acesso HTTPS pelo IP"
  echo "IP detectado: ${detected:-não detectado}"
  echo "IP configurado: ${PUBLIC_IP:-nenhum}"
  read -r -p "IPv4 público [${detected:-${PUBLIC_IP:-}}; 0 para voltar]: " answer
  [[ "$answer" == "0" ]] && return 0
  ip="${answer:-${detected:-${PUBLIC_IP:-}}}"
  is_valid_ipv4 "$ip" || { warn "IPv4 inválido."; return 1; }
  backup_current_config
  configure_nginx_ip "$ip"
  open_local_firewall 0
  write_credentials_file "" ""
  ok "Acesso por IP configurado: $(access_url)"
  echo "O navegador exibirá aviso porque o certificado por IP é autoassinado."
}

configure_domain_access_menu() {
  load_config
  local domain email answer
  ui_header "Configurar acesso por domínio"
  echo "Antes de continuar, o domínio deve apontar para o IP desta VPS."
  read -r -p "Domínio [${DOMAIN:-}; 0 para voltar]: " answer
  [[ "$answer" == "0" ]] && return 0
  domain="${answer:-${DOMAIN:-}}"
  is_valid_domain "$domain" || { warn "Domínio inválido."; return 1; }
  read -r -p "E-mail do Let's Encrypt: " email
  is_valid_email "$email" || { warn "E-mail inválido."; return 1; }
  backup_current_config
  configure_nginx_domain "$domain" "$email"
  open_local_firewall 1
  write_credentials_file "" ""
  ok "Acesso por domínio configurado: $(access_url)"
}

access_menu() {
  local choice
  while true; do
    ui_header "Configuração de acesso remoto"
    load_config
    echo "Atual: $(access_url)"
    echo
    echo "  1) Detectar IP e configurar HTTPS pelo IP"
    echo "  2) Configurar domínio e certificado Let's Encrypt"
    echo "  3) Mostrar informações de firewall"
    echo "  0) Voltar"
    echo
    read -r -p "Escolha: " choice
    case "$choice" in
      1) configure_ip_access_menu; ui_pause ;;
      2) configure_domain_access_menu; ui_pause ;;
      3)
        echo "Libere externamente TCP 443. Para domínio/Let's Encrypt, libere também TCP 80."
        echo "Mantenha 5901 e 6080 fechadas para a Internet."
        ui_pause
        ;;
      0) return 0 ;;
      *) warn "Opção inválida."; ui_pause ;;
    esac
  done
}

repair_installation() {
  ui_header "Reparação automática"
  detect_platform
  load_config
  backup_current_config
  local generated_vnc="" generated_web=""
  info "Verificando usuário, permissões e diretórios..."
  if ! id "$APP_USER" >/dev/null 2>&1; then
    warn "Usuário $APP_USER não existe; recriando."
    useradd -m -U -s /bin/bash "$APP_USER"
    APP_USER_MANAGED=1
    APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
  fi
  APP_GROUP="$(id -gn "$APP_USER")"
  APP_UID="$(id -u "$APP_USER")"
  APP_GID="$(id -g "$APP_USER")"
  CDP_PORT="${CDP_PORT:-9222}"
  recover_profile_dir
  install -d -m 700 -o "$APP_USER" -g "$APP_GROUP" "$APP_HOME/.vnc" "$PROFILE_DIR"
  install -d -m 755 -o "$APP_USER" -g "$APP_GROUP" "$APP_HOME/.config/openbox"

  if [[ ! -s "$APP_HOME/.vnc/passwd" ]]; then
    generated_vnc="$(random_password 8)"
    set_vnc_password "$generated_vnc"
    warn "A senha VNC estava ausente e foi recriada."
  else
    chown "$APP_USER:$APP_GROUP" "$APP_HOME/.vnc/passwd"
    chmod 600 "$APP_HOME/.vnc/passwd"
  fi
  if [[ ! -s "$HTPASSWD_FILE" ]]; then
    generated_web="$(random_password 18)"
    set_web_credentials "${WEB_USER:-remoteadmin}" "$generated_web"
    warn "A autenticação web estava ausente e foi recriada."
  else
    chown root:www-data "$HTPASSWD_FILE"
    chmod 640 "$HTPASSWD_FILE"
  fi

  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME/.vnc" "$APP_HOME/.config/openbox" "$PROFILE_DIR" 2>/dev/null || true
  save_config
  render_runtime_scripts
  render_openbox_config
  configure_novnc_mobile_defaults
  render_systemd_units
  install_menu_command
  systemctl enable "$SERVICE_DESKTOP" "$SERVICE_BROWSER" "$SERVICE_NOVNC" nginx >/dev/null
  nginx -t
  restart_stack
  write_credentials_file "$generated_vnc" "$generated_web"
  if browser_is_running; then
    ok "Reparação concluída; navegador iniciado e supervisionado pelo systemd."
  else
    warn "A reparação foi aplicada, mas o navegador não iniciou. O erro real será mostrado no diagnóstico abaixo."
  fi
  show_status
  return 0
}

update_from_github() {
  load_config
  local repository="${GITHUB_REPOSITORY:-$GITHUB_REPOSITORY_DEFAULT}"
  local ref="${GITHUB_REF:-$GITHUB_REF_DEFAULT}"
  local tmp
  ui_header "Atualizar e reparar pelo GitHub"
  echo "Repositório: $repository"
  echo "Referência:  $ref"
  echo "O perfil e a sessão do WhatsApp serão preservados."
  confirm_action "Baixar a versão atual e executar reparação completa?" || return 0
  tmp="$(mktemp)"
  curl -fsSL --retry 4 --connect-timeout 15 --max-time 120 \
    "https://raw.githubusercontent.com/${repository}/${ref}/setup.sh" -o "$tmp" || {
      rm -f "$tmp"
      warn "Não foi possível baixar o setup.sh."
      return 1
    }
  chmod 700 "$tmp"
  bash "$tmp" --repository "$repository" --ref "$ref" --repair --auto
  rm -f "$tmp"
  ok "Atualização/reparação concluída."
}

show_logs_menu() {
  local choice
  while true; do
    ui_header "Logs e diagnóstico"
    echo "  1) Desktop/VNC — últimas 100 linhas"
    echo "  2) Navegador/Chrome — últimas 100 linhas"
    echo "  3) noVNC — últimas 100 linhas"
    echo "  4) Nginx — últimas 100 linhas"
    echo "  5) Instalação — últimas 120 linhas"
    echo "  6) Acompanhar navegador ao vivo (Ctrl+C para sair)"
    echo "  7) Acompanhar Desktop/VNC ao vivo (Ctrl+C para sair)"
    echo "  8) Verificar conexão atual do WhatsApp"
    echo "  0) Voltar"
    echo
    read -r -p "Escolha: " choice
    case "$choice" in
      1) journalctl -u "$SERVICE_DESKTOP" -n 100 --no-pager; ui_pause ;;
      2) journalctl -u "$SERVICE_BROWSER" -n 100 --no-pager; ui_pause ;;
      3) journalctl -u "$SERVICE_NOVNC" -n 100 --no-pager; ui_pause ;;
      4) journalctl -u nginx -n 100 --no-pager; ui_pause ;;
      5) tail -n 120 "$INSTALL_LOG" 2>/dev/null || warn "Log não encontrado."; ui_pause ;;
      6) journalctl -u "$SERVICE_BROWSER" -f || true ;;
      7) journalctl -u "$SERVICE_DESKTOP" -f || true ;;
      8) load_config; echo "WhatsApp Web: $(whatsapp_status_message)"; ui_pause ;;
      0) return 0 ;;
      *) warn "Opção inválida."; ui_pause ;;
    esac
  done
}

show_info() {
  load_config
  local vnc_password="" web_password=""
  vnc_password="$(credential_value 'Senha VNC' || true)"
  web_password="$(credential_value 'Senha web' || true)"

  ui_header "Usuários e senhas de acesso"
  printf '%bURL de acesso%b\n' "$C_BOLD" "$C_RESET"
  echo "  $(access_url)"
  echo
  printf '%bDesktop remoto%b\n' "$C_BOLD" "$C_RESET"
  echo "  Usuário: $APP_USER"
  if [[ -n "$vnc_password" ]]; then
    echo "  Senha:   $vnc_password"
  else
    echo "  Senha:   não armazenada"
    echo "  Ação:    use a opção 'Alterar senha do desktop remoto (VNC)'."
  fi
  echo
  printf '%bAcesso web / remoteadmin%b\n' "$C_BOLD" "$C_RESET"
  echo "  Usuário: $WEB_USER"
  if [[ -n "$web_password" ]]; then
    echo "  Senha:   $web_password"
  else
    echo "  Senha:   não armazenada"
    echo "  Ação:    use a opção 'Alterar usuário e senha do acesso web'."
  fi
  echo
  echo "Perfil persistente:     $PROFILE_DIR"
  echo "Arquivo protegido:      $CREDENTIALS_FILE"
  echo
  echo "O noVNC normalmente solicita somente a senha do desktop remoto."
  echo "As credenciais são exibidas apenas para root e ficam em arquivo com permissão 600."
}

service_menu() {
  local choice
  while true; do
    ui_header "Controle dos serviços"
    manager_dashboard
    echo
    echo "  1) Iniciar todos"
    echo "  2) Parar desktop, navegador e noVNC"
    echo "  3) Reiniciar todos"
    echo "  4) Ativar inicialização automática"
    echo "  5) Desativar inicialização automática"
    echo "  0) Voltar"
    echo
    read -r -p "Escolha: " choice
    case "$choice" in
      1) load_config; start_stack && ok "Serviços iniciados." || warn "Falha ao iniciar; consulte os logs."; ui_pause ;;
      2) load_config; confirm_action "Parar o acesso remoto agora?" && { stop_stack; ok "Desktop e noVNC parados."; }; ui_pause ;;
      3) load_config; restart_stack; ok "Serviços reiniciados."; ui_pause ;;
      4) systemctl enable "$SERVICE_DESKTOP" "$SERVICE_BROWSER" "$SERVICE_NOVNC" nginx >/dev/null; ok "Inicialização automática ativada."; ui_pause ;;
      5) confirm_action "Desativar a inicialização automática?" && { systemctl disable "$SERVICE_DESKTOP" "$SERVICE_BROWSER" "$SERVICE_NOVNC" >/dev/null; ok "Inicialização automática desativada."; }; ui_pause ;;
      0) return 0 ;;
      *) warn "Opção inválida."; ui_pause ;;
    esac
  done
}

reinstall_from_scratch() {
  load_config
  local repository="${GITHUB_REPOSITORY:-$GITHUB_REPOSITORY_DEFAULT}"
  local ref="${GITHUB_REF:-$GITHUB_REF_DEFAULT}"
  local tmp_setup confirmation

  ui_header "Reinstalar tudo do zero"
  warn "Esta operação APAGARÁ o perfil do navegador e desconectará o WhatsApp."
  warn "Também removerá o usuário desktop, credenciais, certificados e configurações do projeto."
  echo
  echo "Depois da reinstalação será necessário escanear um novo QR Code."
  echo "A swap e os pacotes do sistema serão preservados para evitar alterações desnecessárias."
  echo
  read -r -p "Digite REINSTALAR para continuar ou 0 para voltar: " confirmation
  [[ "$confirmation" == "0" ]] && return 0
  [[ "$confirmation" == "REINSTALAR" ]] || { warn "Confirmação inválida. Operação cancelada."; return 0; }
  confirm_action "Confirmar exclusão completa e reinstalação automática?" || return 0

  info "Baixando previamente o instalador para evitar ficar sem o Manager em caso de falha de rede..."
  tmp_setup="$(mktemp /tmp/whatsapp-remote-reinstall.XXXXXX.sh)"
  if ! curl -fsSL --retry 4 --retry-delay 2 --connect-timeout 15 --max-time 180 \
    "https://raw.githubusercontent.com/${repository}/${ref}/setup.sh" -o "$tmp_setup"; then
    rm -f "$tmp_setup"
    warn "Não foi possível baixar o instalador. Nada foi removido."
    return 1
  fi
  bash -n "$tmp_setup" || { rm -f "$tmp_setup"; warn "O instalador baixado possui erro de sintaxe. Nada foi removido."; return 1; }
  chmod 700 "$tmp_setup"

  backup_current_config
  info "Removendo a instalação atual e o perfil do WhatsApp..."
  bash "$INSTALL_DIR/uninstall.sh" --purge --yes --keep-swap

  info "Iniciando instalação limpa e automática..."
  exec bash "$tmp_setup" --repository "$repository" --ref "$ref" --auto
}

run_uninstall() {
  ui_header "Desinstalar o sistema"
  warn "Esta opção remove serviços e acesso remoto. O perfil só será apagado se você confirmar dentro do desinstalador."
  confirm_action "Abrir o desinstalador?" || return 0
  exec bash "$INSTALL_DIR/uninstall.sh"
}

main_menu() {
  local option
  while true; do
    ui_header "Manager $PROJECT_VERSION"
    if [[ -r "$CONFIG_FILE" ]]; then
      if ! (manager_dashboard); then
        warn "A configuração existe, mas está incompleta ou inválida. Use Reparação automática ou reinstale do zero."
      fi
    else
      warn "Instalação/configuração não encontrada. Use Atualizar/reparar pelo GitHub ou reinstale do zero."
    fi
    echo
    echo "  1) Visualizar usuários e senhas"
    echo "  2) Alterar usuário e senha do acesso web (remoteadmin)"
    echo "  3) Alterar senha do desktop remoto (VNC)"
    echo "  4) Alterar usuário Linux do desktop"
    echo "  5) Alterar resolução"
    echo "  6) Configurar IP ou domínio"
    echo "  7) Iniciar, parar ou reiniciar serviços"
    echo "  8) Status, diagnóstico e conexão do WhatsApp"
    echo "  9) Reparação automática"
    echo " 10) Atualizar/reparar pelo GitHub"
    echo " 11) Ver logs e diagnóstico"
    echo " 12) Reinstalar tudo do zero"
    echo " 13) Desinstalar"
    echo " 14) Verificar conexão do WhatsApp Web"
    echo "  0) Sair"
    echo
    read -r -p "Escolha: " option
    case "$option" in
      1) show_info; ui_pause ;;
      2) change_web_credentials; ui_pause ;;
      3) change_vnc_password; ui_pause ;;
      4) change_desktop_user; ui_pause ;;
      5) change_resolution; ui_pause ;;
      6) access_menu ;;
      7) service_menu ;;
      8) ui_header "Status e diagnóstico completo"; show_status; ui_pause ;;
      9) repair_installation; ui_pause ;;
      10) update_from_github; ui_pause ;;
      11) show_logs_menu ;;
      12) reinstall_from_scratch ;;
      13) run_uninstall ;;
      14) load_config; ui_header "Conexão do WhatsApp Web"; echo "Status: $(whatsapp_status_message)"; echo; echo "Observação: a detecção é local e não envia dados da sessão para serviços externos."; ui_pause ;;
      0) exit 0 ;;
      *) warn "Opção inválida."; ui_pause ;;
    esac
  done
}

help_text() {
  cat <<HELP
Uso: menu
     sudo whatsapp-remote [comando]

Comandos:
  menu                 Abre o Manager interativo
  info                 Mostra URL, usuários e senhas armazenadas
  web-credentials      Altera usuário e senha web
  vnc-password         Altera a senha VNC
  desktop-user         Renomeia o usuário Linux preservando o perfil
  resolution           Altera a resolução remota
  access-ip            Detecta/configura acesso HTTPS por IP
  access-domain        Configura domínio e Let's Encrypt
  start                Inicia a pilha
  stop                 Para desktop e noVNC
  restart              Reinicia toda a pilha
  status               Exibe status, recursos e causas de falhas
  repair               Repara permissões, serviços e configuração
  update               Atualiza/repara pelo GitHub
  logs                 Abre o menu de logs
  reinstall            Reinstala tudo do zero e apaga a sessão do WhatsApp
  whatsapp-status      Verifica se a sessão está conectada, aguardando QR ou offline
  uninstall            Abre o desinstalador
  help                 Exibe esta ajuda
HELP
}

case "${1:-menu}" in
  menu|manager) main_menu ;;
  info) show_info ;;
  web-credentials) change_web_credentials ;;
  vnc-password) change_vnc_password ;;
  desktop-user) change_desktop_user ;;
  resolution) change_resolution ;;
  access-ip) configure_ip_access_menu ;;
  access-domain) configure_domain_access_menu ;;
  start) load_config; start_stack; show_status ;;
  stop) load_config; stop_stack; show_status ;;
  restart) load_config; restart_stack; show_status ;;
  status) show_status ;;
  repair) repair_installation ;;
  update) update_from_github ;;
  logs) show_logs_menu ;;
  whatsapp-status) load_config; echo "$(whatsapp_status_message)" ;;
  reinstall) reinstall_from_scratch ;;
  uninstall) run_uninstall ;;
  help|-h|--help) help_text ;;
  *) die "Comando desconhecido: $1. Use: whatsapp-remote help" ;;
esac
