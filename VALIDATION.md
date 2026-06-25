# ✅ Validação da versão 2.4.0

Validações executadas antes da geração do pacote:

- `bash -n` em todos os scripts Bash;
- verificação dos arquivos obrigatórios;
- validação do menu para máquina nova;
- validação da detecção de instalação completa, antiga ou parcial;
- verificação das ações de reparação, Manager, status, reinstalação e desinstalação;
- verificação do wrapper global `menu`;
- verificação das funções de diagnóstico preventivo;
- confirmação de que o status detalhado não interrompe o Manager quando encontra problemas;
- geração de `MANIFEST.sha256` para scripts essenciais;
- teste de integridade do ZIP.

A instalação integral ainda deve ser testada em uma VPS real, porque systemd, Nginx, VNC, navegador e pacotes APT dependem do sistema operacional e da rede do provedor.
