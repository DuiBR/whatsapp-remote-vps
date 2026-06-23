# Publicação no GitHub

Repositório configurado no projeto:

```text
https://github.com/DuiBR/whatsapp-remote-vps
```

## Enviar a versão para o repositório

Extraia o ZIP e copie o conteúdo para a raiz do repositório:

```bash
git clone https://github.com/DuiBR/whatsapp-remote-vps.git
cp -a whatsapp-remote-github-v2.2.0/. whatsapp-remote-vps/
cd whatsapp-remote-vps

git add -A
git commit -m "WhatsApp Remote VPS v2.2.0 — instalador inteligente e Manager"
git push origin main
```

Os arquivos `setup.sh`, `install.sh` e a pasta `lib` devem aparecer diretamente na raiz do GitHub.

## Testar o link

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

## Criar uma versão fixa

```bash
git tag -a v2.2.0 -m "WhatsApp Remote VPS v2.2.0"
git push origin v2.2.0
```

Instalar a tag:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --ref v2.2.0
```

## Repositório privado

Para repositório privado, exporte temporariamente um token com permissão de leitura:

```bash
export WR_GITHUB_TOKEN='TOKEN'
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo -E bash
unset WR_GITHUB_TOKEN
```

Nunca grave tokens dentro dos scripts ou faça commit de credenciais.
