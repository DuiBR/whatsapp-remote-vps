# Changelog

## 2.3.0 — Menu global, credenciais e reinstalação completa

- Adicionado comando global `menu` para abrir o Manager diretamente no terminal.
- O comando solicita `sudo` automaticamente quando executado sem privilégios de root.
- Adicionada opção para visualizar usuário e senha do desktop remoto.
- Adicionada visualização do usuário e senha do acesso web/remoteadmin.
- Credenciais conhecidas agora são preservadas ao reparar, alterar IP, domínio, usuário ou resolução.
- Arquivo de credenciais reorganizado e protegido com permissão `600`.
- Adicionada opção **Reinstalar tudo do zero**.
- A reinstalação baixa e valida o bootstrap antes de remover a instalação atual.
- A reinstalação completa apaga perfil, sessão do WhatsApp, usuário desktop, certificados e credenciais.
- Swap e pacotes do sistema são preservados durante a reinstalação completa.
- Desinstalador ganhou modos `--purge`, `--yes` e `--keep-swap`.
- Reparação automática recria o comando `menu` quando necessário.
- Um comando `menu` preexistente é salvo em backup antes de ser substituído.
- Melhorados textos, avisos e ajuda do Manager.

## 2.2.1 — Validação tolerante a uploads pelo navegador

- Arquivos ocultos deixaram de ser obrigatórios.
- Checksums complementares não bloqueiam uma estrutura válida.
- Mantida validação obrigatória de estrutura e sintaxe Bash.

## 2.2.0 — Instalador inteligente

- Menu de instalação e Manager.
- Instalação automática ou personalizada.
- Detecção de sistema, arquitetura, IP, provedor, RAM e disco.
- Reparação, atualização, logs, status e desinstalação.
