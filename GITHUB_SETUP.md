# Publicação no GitHub

Repositório esperado:

```text
https://github.com/DuiBR/whatsapp-remote-vps
```

Envie o conteúdo desta pasta diretamente para a raiz do repositório.

## Atualização pelo terminal

```bash
unzip whatsapp-remote-github-v2.3.0.zip
git clone https://github.com/DuiBR/whatsapp-remote-vps.git
cp -a whatsapp-remote-github-v2.3.0/. whatsapp-remote-vps/
cd whatsapp-remote-vps
git add -A
git commit -m "WhatsApp Remote VPS v2.3.0"
git push origin main
```

## Instalação

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

## Atualizar uma máquina existente

```bash
curl -fsSL "https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh?v=2.3.0" | sudo bash -s -- --repair --auto
```

Depois da atualização, o Manager abre digitando:

```bash
menu
```
