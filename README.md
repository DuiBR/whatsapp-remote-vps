# WhatsApp Remote VPS

Instalador universal para manter o WhatsApp Web aberto 24 horas em uma VPS, com Chrome/Chromium, desktop Openbox, TigerVNC, noVNC, Nginx e acesso HTTPS pelo navegador do celular ou computador.

## Compatibilidade

| Sistema | amd64 / x86-64 | arm64 / aarch64 |
|---|:---:|:---:|
| Ubuntu 20.04 | ✅ | ✅ |
| Ubuntu 22.04 | ✅ | ✅ |
| Ubuntu 24.04 | ✅ | ✅ |
| Debian 11 | ✅ | ✅ |
| Debian 12 | ✅ | ✅ |

- **amd64:** Google Chrome Stable, com fallback inteligente para Chromium.
- **arm64:** Chromium nativo no Debian e Chromium Snap no Ubuntu.
- **Memória baixa:** detecta a RAM, cria swap quando necessário e reduz processos do navegador.
- **Celular:** noVNC configurado para toque, ponteiro visível, escala automática e reconexão.


## Upload pelo navegador do GitHub

Ao enviar os arquivos pelo celular, `.gitignore` e `.gitattributes` podem ficar ocultos no seletor. Eles são opcionais e não impedem a instalação. Os arquivos essenciais são `setup.sh`, `install.sh`, `manage.sh`, `repair.sh`, `status.sh`, `uninstall.sh` e `lib/common.sh`.

A partir da versão 2.2.1, diferenças no `MANIFEST.sha256` geram apenas um aviso quando a estrutura e a sintaxe dos scripts estiverem válidas.

## Instalação pelo menu

Execute como root ou com `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

O menu inicial oferece:

```text
1) Instalação automática recomendada
2) Instalação personalizada com revisão das informações
3) Atualizar e reparar preservando a sessão do WhatsApp
4) Abrir o Manager
5) Ver status detalhado
6) Ver logs
7) Desinstalar
0) Sair
```

## Instalação automática

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --auto
```

O instalador detecta automaticamente:

- distribuição e versão;
- arquitetura do processador;
- provedor de nuvem quando possível;
- IPv4 público, inclusive pela metadata da Oracle Cloud;
- memória, swap e espaço em disco;
- navegador compatível;
- instalação anterior e perfil já conectado do WhatsApp.

As credenciais geradas ficam em:

```bash
sudo cat /root/whatsapp-remote-credentials.txt
```

## Instalação personalizada

A opção personalizada não obriga a responder várias perguntas. Primeiro, o instalador detecta tudo, gera escolhas recomendadas e apresenta uma tela de revisão:

```text
1) Usuário desktop
2) Usuário web
3) Senha VNC
4) Senha web
5) Resolução
6) IP ou domínio
7) Swap
8) Detectar novamente o IP
9) Restaurar escolhas inteligentes
I) Instalar
0) Cancelar
```

É possível voltar, corrigir qualquer informação e revisar tudo antes de instalar. As senhas ficam visíveis durante a digitação, conforme solicitado.

## Manager

Após a instalação:

```bash
sudo whatsapp-remote
```

O Manager possui painel com URL, IP atual, serviços, RAM, swap e disco, além das opções:

```text
1) Ver acesso e credenciais
2) Alterar usuário e senha web
3) Alterar senha VNC
4) Alterar usuário Linux do desktop
5) Alterar resolução
6) Configurar IP ou domínio
7) Iniciar, parar ou reiniciar serviços
8) Ver status detalhado
9) Reparação automática
10) Atualizar/reparar pelo GitHub
11) Ver logs e diagnóstico
12) Desinstalar
0) Sair
```

### Comandos diretos

```bash
sudo whatsapp-remote status
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
sudo whatsapp-remote repair
sudo whatsapp-remote update
sudo whatsapp-remote logs
sudo whatsapp-remote uninstall
```

## Instalação com parâmetros

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --auto --ip 164.152.48.215 --geometry 1280x720
```

Por domínio:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --auto \
  --domain whatsapp.exemplo.com \
  --email admin@exemplo.com
```

Credenciais por variáveis, evitando colocá-las na linha principal do comando:

```bash
export WR_DESKTOP_USER='whatsapp'
export WR_WEB_USER='remoteadmin'
export WR_VNC_PASSWORD='SenhaVNC'
export WR_WEB_PASSWORD='SenhaWebMuitoForte'

curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo -E bash -s -- --auto

unset WR_DESKTOP_USER WR_WEB_USER WR_VNC_PASSWORD WR_WEB_PASSWORD
```

## Atualizar e reparar

Pelo Manager:

```bash
sudo whatsapp-remote update
```

Ou pelo link:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --repair --auto
```

A atualização preserva o perfil do navegador, a sessão conectada do WhatsApp, as credenciais e a forma de acesso já configurada.

## Firewall

Libere no firewall do provedor:

```text
TCP 443 — acesso HTTPS
TCP 80  — necessário quando usar domínio e Let's Encrypt
```

Não exponha publicamente:

```text
TCP 5901 — VNC interno
TCP 6080 — noVNC interno
```

Na Oracle Cloud, a porta deve ser liberada no NSG ou na Security List da VCN. O instalador também ajusta UFW/firewalld quando eles já estiverem ativos no sistema.

## Acesso

Pelo IP:

```text
https://IP_DA_VPS/
```

O certificado por IP é autoassinado, portanto o navegador exibirá um aviso de segurança. Por domínio, o instalador usa Let's Encrypt.

## Arquivos principais

```text
setup.sh       Bootstrap e menu via GitHub
install.sh     Instalação inteligente e revisão das informações
manage.sh      Manager instalado como whatsapp-remote
repair.sh      Reparação rápida
status.sh      Diagnóstico
uninstall.sh   Desinstalação assistida
lib/common.sh  Funções compartilhadas
```

## Logs e configuração

```text
/var/log/whatsapp-remote-install.log
/etc/whatsapp-remote/config.env
/opt/whatsapp-remote/
/var/backups/whatsapp-remote/
```

O perfil persistente fica no diretório do usuário Linux criado pelo instalador. Não remova esse usuário nem sua pasta pessoal se quiser preservar a sessão do WhatsApp.
