# Validação

Versão 2.2.1 validada com:

- `bash -n` em todos os scripts principais;
- verificação da presença dos arquivos essenciais;
- manifesto SHA-256 limitado aos scripts do projeto;
- simulação de upload sem `.gitignore` e `.gitattributes`;
- simulação de checksum divergente com continuidade após validação estrutural;
- geração e leitura do pacote ZIP.

O `MANIFEST.sha256` é complementar. A proteção principal do bootstrap é a origem HTTPS do repositório configurado, combinada com validação de estrutura e sintaxe antes da execução.
