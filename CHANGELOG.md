# CHANGELOG

## 2.2.1 — Correção da validação no GitHub

- Corrigida a falha de instalação quando `.gitignore` e `.gitattributes` não são enviados pelo navegador do celular.
- Arquivos ocultos do GitHub deixaram de ser obrigatórios para a instalação.
- `VERSION` e arquivos de documentação deixaram de bloquear a validação do pacote.
- A validação obrigatória agora verifica a presença e a sintaxe dos scripts essenciais.
- O checksum passou a ser uma camada complementar: diferenças geram aviso, mas não interrompem uma instalação estruturalmente válida.
- Mensagens de diagnóstico mais claras para uploads realizados pelo navegador do GitHub.

## 2.2.0 — Instalador inteligente e Manager completo

- Adicionado menu principal diretamente no comando de instalação pelo GitHub.
- Instalação automática recomendada com uma única escolha.
- Assistente personalizado baseado em uma tela de revisão, sem perguntas desnecessárias.
- Opções para voltar, corrigir, detectar novamente e restaurar escolhas inteligentes.
- Detecção automática de Ubuntu 20.04/22.04/24.04 e Debian 11/12.
- Detecção automática de amd64/x86-64 e arm64/aarch64.
- Detecção de IP público por múltiplos serviços e metadata v2 da Oracle Cloud.
- Detecção de provedor, IP privado, RAM, swap e espaço livre.
- Resolução recomendada de acordo com a memória disponível.
- Criação inteligente de swap com modos automático, ativado ou desativado.
- Recuperação e repetição automática de operações APT.
- Fallback automático de Google Chrome para Chromium.
- Backup de configuração antes de instalação, reparação e alterações críticas.
- Integridade do pacote validada pelo `MANIFEST.sha256` no bootstrap.
- Manager redesenhado com painel de URL, IP, serviços, RAM, swap e disco.
- Menu para alterar usuário/senha web, senha VNC, usuário Linux e resolução.
- Menu para alternar entre acesso por IP e por domínio.
- Controle intuitivo de iniciar, parar, reiniciar e ativar serviços no boot.
- Reparação automática de permissões, arquivos, credenciais ausentes e serviços.
- Atualização/reparação direta pelo GitHub preservando a sessão do WhatsApp.
- Menu de logs por componente e acompanhamento ao vivo.
- Desinstalação assistida com preservação padrão do perfil.
- Senhas continuam visíveis durante digitação e revisão.
- noVNC configurado para toque em celular, ponteiro visível e reconexão.

## 2.1.1

- Senhas visíveis durante a instalação e alteração posterior.
- Repositório padrão configurado como `DuiBR/whatsapp-remote-vps`.

## 2.1.0

- Bootstrap de instalação e atualização pelo GitHub.

## 2.0.0

- Compatibilidade universal Ubuntu/Debian, amd64/arm64.
