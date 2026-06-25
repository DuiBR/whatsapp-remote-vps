# Validação da versão 2.3.0

Validações executadas antes da geração do pacote:

- `bash -n` em todos os scripts Bash;
- verificação dos arquivos obrigatórios;
- teste da leitura e preservação das credenciais antigas;
- verificação do wrapper global `menu`;
- validação das opções do desinstalador;
- geração de `MANIFEST.sha256` para scripts essenciais;
- teste de integridade do arquivo ZIP.

A instalação completa deve ser validada na VPS, pois serviços systemd, Nginx, VNC e pacotes APT dependem do sistema real.
