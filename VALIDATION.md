# Validação da versão 2.2.0

Validações automatizadas realizadas no pacote:

- `bash -n` em todos os scripts Bash.
- Verificação de permissões executáveis.
- Validação das referências internas entre scripts.
- Validação do JSON obrigatório do noVNC.
- Validação de todos os arquivos pelo `MANIFEST.sha256`.
- Testes isolados das funções de validação de IPv4, usuário, domínio, e-mail e resolução.
- Teste de exibição da ajuda de `setup.sh` e `install.sh`.
- Teste do menu do bootstrap em ambiente simulado.

A instalação completa precisa ser executada em uma VPS real para validar rede, repositórios APT, regras do provedor e comportamento do navegador daquela imagem específica.
