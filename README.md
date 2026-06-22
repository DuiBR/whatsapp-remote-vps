# WhatsApp Remote VPS Universal

## Instalação automática pelo GitHub

Para iniciar a instalação guiada diretamente pelo GitHub, execute:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

Para informar o IP durante a instalação:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash -s -- --ip 164.152.48.215
```

Para reparar ou atualizar preservando o perfil:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash -s -- --repair --auto
```

Consulte `GITHUB_SETUP.md` para publicar o repositório.

---

Ambiente gráfico leve e persistente para manter o WhatsApp Web aberto 24 horas em uma VPS, com acesso remoto pelo navegador do celular ou computador.

## Compatibilidade

| Sistema | Versões | x86_64 / amd64 | aarch64 / arm64 |
|---|---:|:---:|:---:|
| Ubuntu | 20.04, 22.04, 24.04 | Sim | Sim |
| Debian | 11, 12 | Sim | Sim |

O instalador detecta automaticamente:

- distribuição e versão;
- arquitetura da CPU;
- quantidade de memória;
- necessidade de swap;
- navegador compatível;
- IPv4 público;
- caminhos do TigerVNC, noVNC e Websockify;
- instalação anterior da versão 1.x ou 2.x.

### Navegador selecionado

- **x86_64/amd64:** Google Chrome Stable; se a instalação falhar, usa Chromium.
- **Debian 11/12 arm64:** Chromium do repositório oficial Debian.
- **Ubuntu arm64:** Chromium Snap oficial da Canonical.

O perfil do navegador é persistente e não é apagado em reparos ou atualizações.

## Componentes

- Openbox e Tint2;
- TigerVNC restrito ao localhost;
- noVNC e Websockify;
- Nginx com autenticação por usuário/senha;
- HTTPS por IP com certificado autoassinado;
- HTTPS por domínio com Let's Encrypt;
- Chrome ou Chromium com reinício automático;
- systemd para iniciar tudo depois do reboot;
- configuração móvel com ponteiro e toque ativos;
- swap automática em VPS com pouca memória;
- menu para alteração de usuários, senhas e resolução.

## Instalação guiada

```bash
sudo apt update
sudo apt install unzip -y
unzip whatsapp-remote-universal-v2.0.0.zip
cd whatsapp-remote-universal-v2.0.0
sudo bash install.sh
```

O instalador perguntará:

- usuário Linux do desktop;
- resolução;
- usuário web;
- senha VNC;
- senha web;
- acesso pelo IP ou domínio.

As senhas são exibidas normalmente enquanto são digitadas. Pressionar Enter sem informar uma senha gera uma senha segura automaticamente.


### Instalação por link com senhas visíveis

O comando padrão abre a instalação guiada e lê as respostas pelo terminal, mesmo usando `curl | bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

As senhas VNC e web aparecem em texto normal durante a digitação. Use esse modo apenas em um terminal privado. Para instalar sem perguntas e gerar credenciais automaticamente:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash -s -- --auto
```

## Instalação completamente automática

```bash
sudo bash install.sh --auto
```

Padrões usados:

```text
Usuário Linux: whatsapp
Usuário web: remoteadmin
Resolução: 1280x720
Acesso: HTTPS pelo IPv4 detectado
Senhas: geradas automaticamente
```

Depois da instalação:

```bash
sudo cat /root/whatsapp-remote-credentials.txt
```

O arquivo possui permissão `600` e somente o root consegue lê-lo.

## Instalação automática com dados personalizados

```bash
export WR_DESKTOP_USER="whatsapp"
export WR_WEB_USER="remoteadmin"
export WR_VNC_PASSWORD="12345678"
export WR_WEB_PASSWORD="uma-senha-web-forte"
export WR_GEOMETRY="1280x720"

sudo -E bash install.sh --auto
```

Para informar o IP manualmente:

```bash
sudo -E bash install.sh --auto --ip 164.152.48.215
```

Para instalar diretamente com domínio:

```bash
sudo -E bash install.sh --auto \
  --domain whatsapp.seudominio.com.br \
  --email seuemail@dominio.com
```

O domínio precisa estar apontado para a VPS antes da emissão do certificado.

## Acesso

Por IP:

```text
https://IP_DA_VPS/
```

O navegador exibirá um aviso porque o certificado por IP é autoassinado.

Por domínio:

```text
https://whatsapp.seudominio.com.br/
```

A URL abre o noVNC automaticamente com:

- reconexão automática;
- escala para tela do celular;
- modo somente visualização desativado;
- ponto do cursor ativado;
- WebSocket encaminhado pelo Nginx.

## Oracle Cloud

Libere no NSG ou Security List:

```text
TCP 443 — acesso HTTPS
TCP 80  — somente quando usar domínio/Let's Encrypt
TCP 22  — SSH, preferencialmente restrito ao seu IP
```

Não libere publicamente:

```text
TCP 5901 — VNC interno
TCP 6080 — noVNC interno
```

## Gerenciador

Após instalar:

```bash
sudo whatsapp-remote
```

Menu disponível:

```text
1) Alterar usuário e senha web
2) Alterar senha VNC
3) Alterar usuário Linux do desktop
4) Alterar resolução
5) Configurar acesso HTTPS pelo IP
6) Configurar acesso HTTPS por domínio
7) Ver status
8) Reiniciar serviços
9) Ver informações de acesso
10) Ver logs
11) Reparar instalação
```

Comandos diretos:

```bash
sudo whatsapp-remote web-credentials
sudo whatsapp-remote vnc-password
sudo whatsapp-remote desktop-user
sudo whatsapp-remote resolution
sudo whatsapp-remote access-ip
sudo whatsapp-remote access-domain
sudo whatsapp-remote status
sudo whatsapp-remote restart
sudo whatsapp-remote logs
sudo whatsapp-remote repair
```

### Alterar usuário e senha de acesso

```bash
sudo whatsapp-remote web-credentials
```

### Alterar senha VNC

```bash
sudo whatsapp-remote vnc-password
```

O protocolo VNC clássico considera somente os primeiros 8 caracteres.

### Alterar o usuário Linux do desktop

```bash
sudo whatsapp-remote desktop-user
```

O perfil do navegador e a sessão vinculada do WhatsApp são movidos para o novo diretório do usuário.

## Diagnóstico

```bash
sudo whatsapp-remote status
```

Ou:

```bash
sudo bash status.sh
```

Logs:

```bash
sudo whatsapp-remote logs
```

Logs individuais:

```bash
sudo journalctl -u whatsapp-desktop -n 100 --no-pager
sudo journalctl -u whatsapp-novnc -n 100 --no-pager
sudo journalctl -u nginx -n 100 --no-pager
```

Portas internas:

```bash
sudo ss -lntp | grep -E '(:5901|:6080|:443)'
```

## Reparar ou atualizar sem perder a sessão

Execute o novo instalador sobre uma instalação existente:

```bash
sudo bash install.sh --repair --auto
```

Ou use:

```bash
sudo whatsapp-remote repair
```

O instalador reconhece a configuração da versão 1.x, preserva o usuário, o perfil do Chrome e a sessão do WhatsApp.

## Arquivos importantes

```text
/etc/whatsapp-remote/config.env         Configuração principal
/opt/whatsapp-remote/                   Instalador e gerenciador
/usr/local/sbin/whatsapp-remote         Comando do gerenciador
/home/USUARIO/.config/...               Perfil persistente do navegador
/home/USUARIO/.vnc/passwd               Senha VNC em formato criptografado
/etc/nginx/.htpasswd-whatsapp           Autenticação web em hash bcrypt
/root/whatsapp-remote-credentials.txt   Credenciais exibidas na instalação
/var/log/whatsapp-remote-install.log    Log do instalador
```

## Desinstalação

```bash
sudo bash uninstall.sh
```

O desinstalador pergunta separadamente se deve remover:

- usuário e perfil do navegador;
- sessão vinculada do WhatsApp;
- swap criada pelo projeto.

Os pacotes do sistema e o navegador são mantidos para evitar remoções indesejadas.
