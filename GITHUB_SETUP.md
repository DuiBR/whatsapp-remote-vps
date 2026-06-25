# 🚀 Publicação no GitHub

Repositório:

```text
https://github.com/DuiBR/whatsapp-remote-vps
```

Envie o conteúdo desta pasta diretamente para a raiz do repositório.

## Atualizar pelo terminal

```bash
unzip whatsapp-remote-github-v2.5.0.zip
git clone https://github.com/DuiBR/whatsapp-remote-vps.git
cp -a whatsapp-remote-github-v2.5.0/. whatsapp-remote-vps/
cd whatsapp-remote-vps
git add -A
git commit -m "WhatsApp Remote VPS v2.5.0"
git push origin main
```

## Instalação interativa

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

O instalador detecta automaticamente se a máquina é nova ou se já existe uma instalação.

## Instalação automática

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --auto
```

## Reparação automática

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --repair --auto
```

## Manager

```bash
menu
```
