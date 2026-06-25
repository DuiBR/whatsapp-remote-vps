# 📋 Changelog

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
