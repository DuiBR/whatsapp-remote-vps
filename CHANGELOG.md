# CHANGELOG

## 2.1.1 — Senhas visíveis e repositório configurado

- Senhas VNC e web agora aparecem em texto normal durante a digitação.
- A alteração de senhas pelo gerenciador também usa entrada visível e confirmação visível.
- `setup.sh` configurado para `DuiBR/whatsapp-remote-vps`.
- Instalação por `curl | bash` usa o terminal (`/dev/tty`) no modo guiado.
- O modo sem argumentos passa a ser guiado quando há TTY; `--auto` mantém a instalação sem perguntas.
- Em ambientes sem terminal, o bootstrap ativa `--auto` automaticamente.

## 2.1.0 — Instalação pelo GitHub

- Adicionado `setup.sh` para instalação automática por link no terminal.
- Download automático da branch ou tag configurada.
- Encaminhamento das opções para o instalador universal.
- Suporte opcional a `WR_GITHUB_REPOSITORY`, `WR_GITHUB_REF` e `WR_GITHUB_TOKEN`.
- Adicionados `.gitignore`, `.gitattributes` e guia de publicação.
- Validação da estrutura e do arquivo compactado antes da execução.
- O modo sem argumentos executa `--auto`.

## 2.0.0 — Instalador universal

- Compatibilidade adicionada para Ubuntu 20.04, 22.04 e 24.04.
- Compatibilidade adicionada para Debian 11 e 12.
- Suporte a x86_64/amd64 e aarch64/arm64.
- Detecção automática de sistema, versão, arquitetura, RAM, swap, navegador e IPv4.
- Google Chrome Stable automático no amd64.
- Chromium automático no arm64 e fallback no amd64.
- Instalação guiada e modo `--auto` sem interação.
- Migração automática da configuração 1.x preservando a sessão do WhatsApp.
- Acesso HTTPS por IP configurado durante a instalação.
- Opção de domínio com certificado Let's Encrypt.
- Configurações móveis do noVNC: toque, ponteiro, escala e reconexão.
- Novo gerenciador `whatsapp-remote` com menu interativo.
- Alteração de usuário e senha web.
- Alteração da senha VNC.
- Renomeação do usuário Linux preservando o perfil do navegador.
- Alteração de resolução e forma de acesso.
- Reparo, status, reinício e logs centralizados.
- Credenciais iniciais gravadas em arquivo root com permissão `600`.
- Serviços systemd reforçados com recuperação automática.
- Portas VNC/noVNC mantidas exclusivamente no localhost.

## 1.2.0

- Correção das permissões de `/etc/whatsapp-remote.conf`.
- Correção do ciclo `activating/deactivating` dos serviços.
- Adição do `repair.sh`.

## 1.1.0

- Openbox e Tint2 para VPS de baixa memória.
- Swap automática de 2 GB.
- Nginx, noVNC e perfil persistente do navegador.
