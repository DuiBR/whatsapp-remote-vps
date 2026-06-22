# Validação realizada

Versão: 2.0.0

## Verificações concluídas

- Sintaxe Bash validada em todos os scripts com `bash -n`.
- Sintaxe validada também nos dois scripts gerados durante a instalação:
  - `/usr/local/bin/whatsapp-desktop-start`;
  - `/usr/local/bin/whatsapp-browser`.
- Fragmentos do Nginx validados com `nginx -t` em configuração temporária.
- Testadas as validações de:
  - usuário Linux;
  - resolução;
  - IPv4;
  - gravação e leitura segura do arquivo de configuração.
- Confirmada ausência de IP público fixo codificado no instalador.
- Confirmada preservação do perfil legado `.config/google-chrome-whatsapp` durante migração.

## Limite desta validação

O pacote foi construído para a matriz declarada, mas não foi executado integralmente em todas as dez combinações de sistema e arquitetura em máquinas reais. O instalador registra falhas em `/var/log/whatsapp-remote-install.log` e inclui reparo automatizado pelo comando `sudo whatsapp-remote repair`.


## Validação 2.1.1

- Entrada de senha visível em `install.sh` e `manage.sh`.
- Leitura interativa via `/dev/tty` no bootstrap executado por pipe.
- Repositório padrão definido como `DuiBR/whatsapp-remote-vps`.
