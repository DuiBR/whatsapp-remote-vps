#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
require_root

APP_USER="" APP_HOME=""
if [[ -r "$CONFIG_FILE" ]]; then load_config; fi
ui_header "Desinstalação"
echo "Esta operação removerá:"
echo "  • serviços systemd do desktop e noVNC"
echo "  • configuração Nginx deste projeto"
echo "  • Manager e arquivos instalados"
echo
echo "Por padrão, o usuário Linux e o perfil do WhatsApp serão preservados."
echo
read -r -p "Digite REMOVER para continuar ou 0 para voltar: " confirmation
[[ "$confirmation" == "0" ]] && exit 0
[[ "$confirmation" == "REMOVER" ]] || { echo "Desinstalação cancelada."; exit 0; }

backup_current_config
systemctl disable --now "$SERVICE_NOVNC" "$SERVICE_DESKTOP" 2>/dev/null || true
rm -f "/etc/systemd/system/$SERVICE_NOVNC" "/etc/systemd/system/$SERVICE_DESKTOP"
rm -f /usr/local/bin/whatsapp-desktop-start /usr/local/bin/whatsapp-browser /usr/local/bin/whatsapp-chrome
rm -f /usr/local/sbin/whatsapp-remote
rm -f "$NGINX_LINK" "$NGINX_SITE"
rm -f /etc/nginx/sites-enabled/whatsapp-remote-ip /etc/nginx/sites-enabled/whatsapp-remote
rm -f /etc/nginx/sites-available/whatsapp-remote-ip
rm -f "$HTPASSWD_FILE"
rm -rf "$SSL_DIR"
systemctl daemon-reload
if command_exists nginx && nginx -t >/dev/null 2>&1; then systemctl reload nginx || true; fi

REMOVE_USER="n"
if [[ -n "$APP_USER" ]] && id "$APP_USER" >/dev/null 2>&1; then
  echo
  if ui_yes_no "Remover também o usuário '$APP_USER' e APAGAR o perfil/sessão do WhatsApp?" n; then REMOVE_USER="s"; fi
fi

rm -rf "$CONFIG_DIR" "$INSTALL_DIR"
rm -f "$CREDENTIALS_FILE" /etc/whatsapp-remote.conf

if [[ "$REMOVE_USER" == "s" ]]; then
  pkill -KILL -u "$APP_USER" 2>/dev/null || true
  userdel -r "$APP_USER" 2>/dev/null || true
else
  [[ -n "$APP_HOME" ]] && echo "Perfil preservado em: $APP_HOME"
fi

if [[ -f /swapfile ]] && grep -qE '^/swapfile\s' /etc/fstab; then
  echo
  if ui_yes_no "Remover também /swapfile? Faça isso somente se ela foi criada para este projeto." n; then
    swapoff /swapfile 2>/dev/null || true
    sed -i '\|^/swapfile[[:space:]]|d' /etc/fstab
    rm -f /swapfile /etc/sysctl.d/99-whatsapp-remote.conf
  fi
fi
ok "Desinstalação concluída. Backups de configuração foram mantidos em $CONFIG_BACKUP_DIR."
