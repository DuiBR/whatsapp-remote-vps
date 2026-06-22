# Publicação e instalação pelo GitHub

## 1. Criar o repositório

Crie um repositório público vazio no GitHub, por exemplo:

```text
whatsapp-remote-vps
```

Não adicione README, .gitignore ou licença durante a criação, pois estes arquivos já estão no projeto.

## 2. Configurar o instalador por link

Edite `setup.sh` e altere:

```bash
DEFAULT_REPOSITORY="DuiBR/whatsapp-remote-vps"
```

Exemplo:

```bash
DEFAULT_REPOSITORY="DuiBR/whatsapp-remote-vps"
```

## 3. Enviar os arquivos

Os arquivos devem ficar diretamente na raiz do repositório:

```text
setup.sh
install.sh
manage.sh
repair.sh
status.sh
uninstall.sh
lib/common.sh
README.md
```

## 4. Instalar por um único link

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

O comando sem parâmetros executa o modo guiado quando há um terminal disponível. As senhas aparecem durante a digitação.

Para instalação totalmente automática, sem perguntas:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash -s -- --auto
```

Instalar informando o IP:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash -s -- --ip 164.152.48.215
```

Reparar ou atualizar preservando o perfil do WhatsApp:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash -s -- --repair --auto
```

Instalar uma tag específica:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash -s -- --ref v2.1.1 --auto
```

## Repositório privado

O comando simples funciona diretamente em repositórios públicos. Para repositórios privados, a própria obtenção de `setup.sh` exige autenticação. Não coloque token fixo no arquivo, no README ou na URL.
