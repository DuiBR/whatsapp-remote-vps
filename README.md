# WhatsApp Remote VPS

Ambiente gráfico leve e persistente para manter o WhatsApp Web ativo em uma VPS e controlá-lo pelo navegador do celular ou computador.

## Compatibilidade

- Ubuntu 20.04, 22.04 e 24.04
- Debian 11 e 12
- amd64/x86-64 e arm64/aarch64
- Google Chrome Stable em amd64, com fallback inteligente para Chromium
- Chromium em arm64

O instalador detecta automaticamente sistema, arquitetura, RAM, disco, provedor, IP público, navegador e necessidade de swap.

## Instalação pelo GitHub

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

Para instalar sem perguntas:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash -s -- --auto
```

## Abrir o menu

Depois da instalação, basta digitar:

```bash
menu
```

Também continuam disponíveis:

```bash
sudo whatsapp-remote
sudo whatsapp-remote status
sudo whatsapp-remote repair
sudo whatsapp-remote update
```

O comando `menu` funciona para root e, quando executado por um usuário comum, solicita privilégios por `sudo`.

## Opções do Manager

```text
1) Visualizar usuários e senhas
2) Alterar usuário e senha do acesso web (remoteadmin)
3) Alterar senha do desktop remoto (VNC)
4) Alterar usuário Linux do desktop
5) Alterar resolução
6) Configurar IP ou domínio
7) Iniciar, parar ou reiniciar serviços
8) Ver status detalhado
9) Reparação automática
10) Atualizar/reparar pelo GitHub
11) Ver logs e diagnóstico
12) Reinstalar tudo do zero
13) Desinstalar
0) Sair
```

## Visualização de credenciais

A opção 1 mostra:

- URL de acesso;
- usuário do desktop remoto;
- senha VNC;
- usuário web, normalmente `remoteadmin`;
- senha web.

As senhas são mantidas em:

```text
/root/whatsapp-remote-credentials.txt
```

O arquivo possui permissão `600` e pode ser lido apenas por root. Instalações antigas cujas senhas já foram perdidas por armazenamento somente em hash precisam redefini-las uma vez pelo menu.

## Reinstalação completa

A opção **Reinstalar tudo do zero**:

- baixa e valida o instalador antes de apagar qualquer coisa;
- remove serviços, configurações, certificados e credenciais;
- remove o usuário desktop e o perfil do navegador;
- desconecta a sessão atual do WhatsApp;
- reinstala automaticamente com novas credenciais;
- preserva a swap e os pacotes do sistema.

Depois será necessário escanear um novo QR Code.

## Atualizar preservando a sessão

```bash
menu
```

Escolha **Atualizar/reparar pelo GitHub**. Ou execute:

```bash
sudo whatsapp-remote update
```

A atualização normal preserva o perfil do navegador e a sessão vinculada do WhatsApp.

## Acesso remoto

A instalação por IP usa certificado autoassinado:

```text
https://IP_DA_VPS/
```

O navegador poderá exibir um aviso de certificado. Para domínio, use o menu para configurar Let's Encrypt.

Libere externamente:

- TCP 443 para acesso HTTPS;
- TCP 80 somente quando usar domínio e Let's Encrypt.

Não exponha publicamente:

- TCP 5901;
- TCP 6080.

## Comandos diretos

```bash
menu
sudo whatsapp-remote info
sudo whatsapp-remote web-credentials
sudo whatsapp-remote vnc-password
sudo whatsapp-remote desktop-user
sudo whatsapp-remote resolution
sudo whatsapp-remote access-ip
sudo whatsapp-remote access-domain
sudo whatsapp-remote start
sudo whatsapp-remote stop
sudo whatsapp-remote restart
sudo whatsapp-remote status
sudo whatsapp-remote repair
sudo whatsapp-remote update
sudo whatsapp-remote reinstall
sudo whatsapp-remote logs
sudo whatsapp-remote uninstall
```

## Arquivos principais

```text
setup.sh              Bootstrap via GitHub
install.sh            Instalador universal
manage.sh             Manager e menu
repair.sh             Reparação rápida
status.sh             Diagnóstico
uninstall.sh          Desinstalação e purge
lib/common.sh         Funções compartilhadas
```

## Segurança

- VNC e noVNC escutam apenas em `127.0.0.1`.
- O acesso externo passa pelo Nginx em HTTPS.
- O arquivo de credenciais é acessível somente por root.
- Uma eventual instalação prévia de `/usr/local/bin/menu` é salva em backup antes da criação do comando deste projeto.
- A reinstalação completa exige confirmação escrita e confirmação adicional.
