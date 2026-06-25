# Changelog

## 2.5.1 — Correção de core dump do Chrome

- Corrige automaticamente proprietário e permissão `4755` do `chrome-sandbox`.
- Adiciona preflight executado como root antes de cada inicialização do navegador.
- Inicia o Chrome dentro de uma sessão D-Bus dedicada.
- Adiciona fallback seguro para sandbox por user namespace quando a tentativa padrão falha rapidamente.
- Mantém o modo sem sandbox desativado por padrão e sinaliza qualquer uso emergencial.
- Cria log dedicado em `/var/log/whatsapp-remote/browser.log`.
- Exibe no status o modo de sandbox e a causa real de falhas/core dump.
- Adiciona `menu` → **Reparar somente o navegador/Chrome**.
- Desabilita core dumps do serviço para não ocupar o disco da VPS.

# 📋 Changelog

## 2.5.0 — Navegador supervisionado e status do WhatsApp

- Corrigida a falha recorrente em que Desktop/VNC, noVNC e Nginx ficavam ativos, mas o Chrome/Chromium não iniciava.
- Criado o serviço systemd dedicado `whatsapp-browser.service`, independente do autostart do Openbox.
- O navegador agora é reiniciado automaticamente pelo systemd após crash, encerramento inesperado ou reboot.
- O reparo recria e habilita o serviço do navegador, remove travas antigas do perfil e aguarda a abertura real do Chrome.
- A última mensagem do journal do navegador passa a aparecer no diagnóstico quando a inicialização falha.
- Implementada recuperação inteligente do perfil persistente mais completo entre caminhos antigos e atuais, evitando perda da sessão após atualização.
- Adicionada porta local de diagnóstico Chrome DevTools em `127.0.0.1:9222`, nunca exposta publicamente.
- Adicionado detector local do estado do WhatsApp Web: conectado, aguardando QR Code, carregando, offline ou indeterminado.
- O estado da sessão aparece no painel principal, no diagnóstico e no comando `whatsapp-remote whatsapp-status`.
- Adicionada opção 14 no Manager para verificar a conexão do WhatsApp Web.
- Menu de logs agora inclui o serviço do navegador e acompanhamento ao vivo.
- Desinstalador atualizado para remover corretamente o novo serviço e o verificador local.

## 2.4.0 — Assistente contextual e diagnóstico preventivo

- O comando oficial via `curl | sudo bash` agora identifica o contexto antes de agir.
- Em uma máquina nova, pergunta claramente entre instalação automática e manual/personalizada.
- Em máquinas com instalação anterior, oferece reparar, abrir o Manager, diagnosticar, reinstalar ou desinstalar.
- Detecção ampliada para instalações completas, antigas e parcialmente danificadas.
- Resumo de sistema exibido antes da operação: distribuição, arquitetura, provedor, IP, RAM e disco.
- Resumo rápido da instalação existente antes de reparar ou remover.
- Manager principal ampliado com sistema, kernel, IP público/privado, serviços, navegador, recursos e carga.
- Novo painel automático de saúde com erros e avisos em linguagem direta.
- Diagnóstico de serviços inativos, falha no boot, portas internas, HTTPS, navegador, perfil, permissões e credenciais.
- Alerta quando as portas VNC/noVNC estão expostas fora do localhost.
- Alerta quando o IP público mudou e a URL/certificado por IP ficou desatualizada.
- Verificação de certificado HTTPS ausente, vencido ou próximo do vencimento.
- Alertas de pouca RAM, ausência de swap, memória disponível baixa e pouco espaço em disco.
- Validação final da instalação passa a aguardar também a inicialização do navegador.
- O instalador deixa de afirmar que tudo foi validado quando ainda existem falhas.
- README totalmente reorganizado com ícones, tabelas, fluxos de instalação, menu, segurança e solução de problemas.

## 2.3.1

- Corrigido o comando `menu` que procurava `lib/common.sh` em `/usr/local/sbin/lib`.
- O comando `whatsapp-remote` agora é um wrapper robusto que executa o Manager em `/opt/whatsapp-remote`.
- `manage.sh` resolve links simbólicos e possui fallback automático para o diretório de instalação.
- A versão salva por instalações antigas não sobrescreve mais a versão atual do código.
- Atualizações existentes passam a mostrar corretamente a versão instalada.

## 2.3.0 — Menu global, credenciais e reinstalação completa

- Adicionado comando global `menu`.
- Visualização e alteração de credenciais.
- Reinstalação completa pelo Manager.
- Atualização e reparação preservando o perfil do WhatsApp.

## 2.2.1 — Validação tolerante

- Arquivos ocultos deixaram de ser obrigatórios.
- Checksums complementares não bloqueiam uma estrutura válida.

## 2.2.0 — Instalador inteligente

- Menu de instalação e Manager.
- Instalação automática ou personalizada.
- Detecção de sistema, arquitetura, IP, provedor, RAM e disco.
