#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
require_root

ASSUME_YES=0
PURGE=0
KEEP_SWAP=0

usage() {
  cat <<USAGE
Uso: sudo bash uninstall.sh [opções]

Sem opções, abre o desinstalador interativo e preserva o perfil por padrão.

Opções:
  --yes         Não solicita a confirmação inicial
  --purge       Remove usuário desktop, perfil do navegador e sessão do WhatsApp
  --keep-swap   Não pergunta sobre a remoção de /swapfile
  -h, --help    Exibe esta ajuda
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) ASSUME_YES=1; shift ;;
    --purge) PURGE=1; shift ;;
    --keep-swap) KEEP_SWAP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opção desconhecida: $1" ;;
  esac
done

APP_USER="" APP_HOME=""
if [[ -r "$CONFIG_FILE" ]]; then load_config; fi

ui_header "Desinstalação"
echo "Esta operação removerá:"
echo "  • serviços systemd do desktop e noVNC"
echo "  • configuração Nginx deste projeto"
echo "  • comandos 'menu' e 'whatsapp-remote'"
echo "  • arquivos instalados e credenciais do projeto"
echo
if (( PURGE == 1 )); then
  warn "Modo PURGE: o usuário desktop e o perfil/sessão do WhatsApp também serão apagados."
else
  echo "Por padrão, o usuário Linux e o perfil do WhatsApp serão preservados."
fi

if (( ASSUME_YES == 0 )); then
  echo
  read -r -p "Digite REMOVER para continuar ou 0 para voltar: " confirmation
  [[ "$confirmation" == "0" ]] && exit 0
  [[ "$confirmation" == "REMOVER" ]] || { echo "Desinstalação cancelada."; exit 0; }
fi

backup_current_config
systemctl disable --now "$SERVICE_NOVNC" "$SERVICE_DESKTOP" 2>/dev/null || true
rm -f "/etc/systemd/system/$SERVICE_NOVNC" "/etc/systemd/system/$SERVICE_DESKTOP"
rm -f /usr/local/bin/whatsapp-desktop-start /usr/local/bin/whatsapp-browser /usr/local/bin/whatsapp-chrome
rm -f /usr/local/sbin/whatsapp-remote
remove_menu_command
rm -f "$NGINX_LINK" "$NGINX_SITE"
rm -f /etc/nginx/sites-enabled/whatsapp-remote-ip /etc/nginx/sites-enabled/whatsapp-remote
rm -f /etc/nginx/sites-available/whatsapp-remote-ip
rm -f "$HTPASSWD_FILE"
rm -rf "$SSL_DIR"
systemctl daemon-reload
if command_exists nginx && nginx -t >/dev/null 2>&1; then systemctl reload nginx || true; fi

REMOVE_PROFILE="n"
DELETE_ACCOUNT="n"
if (( PURGE == 1 )); then
  REMOVE_PROFILE="s"
  if [[ "${APP_USER_MANAGED:-0}" == "1" ]]; then DELETE_ACCOUNT="s"; fi
elif [[ -n "$APP_USER" ]] && id "$APP_USER" >/dev/null 2>&1; then
  echo
  if ui_yes_no "Remover também o usuário '$APP_USER' e APAGAR o perfil/sessão do WhatsApp?" n; then
    REMOVE_PROFILE="s"
    DELETE_ACCOUNT="s"
  fi
fi

rm -rf "$CONFIG_DIR" "$INSTALL_DIR"
rm -f "$CREDENTIALS_FILE" /etc/whatsapp-remote.conf

if [[ "$REMOVE_PROFILE" == "s" && -n "$APP_USER" ]] && id "$APP_USER" >/dev/null 2>&1; then
  pkill -KILL -u "$APP_USER" 2>/dev/null || true
  if [[ "$DELETE_ACCOUNT" == "s" && "$(id -u "$APP_USER")" != "0" ]]; then
    userdel -r "$APP_USER" 2>/dev/null || true
  else
    if [[ -n "${APP_HOME:-}" && "$APP_HOME" != "/" ]]; then
      if [[ -n "${PROFILE_DIR:-}" && "$PROFILE_DIR" == "$APP_HOME"/* ]]; then rm -rf "$PROFILE_DIR"; fi
      rm -rf "$APP_HOME/.vnc" "$APP_HOME/.config/openbox" 2>/dev/null || true
    fi
    warn "A conta Linux '$APP_USER' foi preservada por segurança; apenas os dados deste projeto foram apagados."
  fi
elif [[ -n "$APP_HOME" ]]; then
  echo "Perfil preservado em: $APP_HOME"
fi

if (( KEEP_SWAP == 0 )) && [[ -f /swapfile ]] && grep -qE '^/swapfile\s' /etc/fstab; then
  echo
  if ui_yes_no "Remover também /swapfile? Faça isso somente se ela foi criada para este projeto." n; then
    swapoff /swapfile 2>/dev/null || true
    sed -i '\|^/swapfile[[:space:]]|d' /etc/fstab
    rm -f /swapfile /etc/sysctl.d/99-whatsapp-remote.conf
  fi
fi
ok "Desinstalação concluída. Backups de configuração foram mantidos em $CONFIG_BACKUP_DIR."
