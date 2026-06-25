# 🟢 WhatsApp Remote VPS

> **Versão 2.5.2:** navegador supervisionado separadamente e verificação local da conexão do WhatsApp.
>
> Execute o **WhatsApp Web 24 horas por dia** em uma VPS com desktop remoto acessível pelo navegador do celular ou computador.

O projeto instala e configura automaticamente um ambiente gráfico leve com **Openbox**, **TigerVNC**, **noVNC**, **Nginx HTTPS** e **Google Chrome/Chromium**. A sessão do navegador é persistente e volta automaticamente depois de uma reinicialização da VPS.

---

## ✨ Principais recursos

- 🤖 instalação automática com escolhas inteligentes;
- 🧭 instalação manual com revisão e opção de voltar/corrigir;
- 🔎 detecção automática do sistema, arquitetura, IP público, RAM, disco e provedor;
- 🌐 acesso remoto pelo navegador usando HTTPS;
- 📱 controles de toque configurados para celular;
- ♻️ reinício automático e serviço systemd dedicado para o navegador;
- 💾 perfil persistente do Chrome/Chromium com recuperação automática do perfil antigo mais completo;
- ✅ detecção local de sessão conectada, QR Code pendente, carregamento ou falta de conexão;
- 🩺 diagnóstico que mostra serviços, portas, recursos, causa real da falha do navegador e estado da sessão;
- 🛠️ reparação automática preservando a sessão do WhatsApp;
- 🔐 alteração e visualização de usuários e senhas pelo Manager;
- 🧹 reinstalação completa ou desinstalação assistida;
- ⌨️ menu administrativo aberto digitando apenas `menu`.

---

## ✅ Compatibilidade

| Sistema | Versões | amd64 / x86-64 | arm64 / aarch64 |
|---|---|:---:|:---:|
| Ubuntu | 20.04, 22.04 e 24.04 | ✅ | ✅ |
| Debian | 11 e 12 | ✅ | ✅ |

### Navegador selecionado automaticamente

- **amd64/x86-64:** Google Chrome Stable, com fallback para Chromium;
- **arm64/aarch64 no Debian:** Chromium do repositório oficial;
- **arm64/aarch64 no Ubuntu:** Chromium Snap.

### Requisitos mínimos

- acesso `root` ou `sudo`;
- `systemd`;
- conexão com a Internet;
- pelo menos **500 MB de RAM**;
- pelo menos **2,5 GB livres** em disco.

> 💡 Em máquinas com pouca RAM, o instalador cria swap automaticamente quando necessário.

---

## 🚀 Instalação pelo terminal

Execute o comando:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

### 🆕 Em uma máquina sem instalação anterior

O assistente mostrará:

```text
1) Instalação automática recomendada
2) Instalação manual/personalizada
3) Ver compatibilidade e requisitos
0) Sair
```

#### 1️⃣ Instalação automática

Escolhe automaticamente:

- usuário do desktop;
- usuário web;
- senhas seguras;
- resolução adequada à memória;
- necessidade de swap;
- navegador compatível;
- IPv4 público;
- certificado HTTPS por IP;
- serviços e inicialização automática.

#### 2️⃣ Instalação manual

Apresenta todas as informações detectadas e permite:

- alterar usuário do desktop;
- alterar usuário web;
- definir ou gerar senhas;
- escolher resolução;
- usar IP ou domínio;
- alterar o comportamento da swap;
- voltar e corrigir qualquer informação antes de instalar.

### ♻️ Quando uma instalação anterior é detectada

O mesmo comando não sobrescreve silenciosamente a instalação. Ele mostra:

```text
1) Reparar/atualizar preservando a sessão do WhatsApp
2) Abrir o Manager
3) Ver status e diagnóstico detalhado
4) Reinstalar tudo do zero
5) Desinstalar
0) Sair sem alterar nada
```

A detecção considera configurações atuais ou antigas, serviços systemd, arquivos em `/opt`, comandos do Manager e configuração do Nginx. Instalações incompletas também são identificadas.

---

## ⚡ Instalação totalmente automática

Para instalar sem perguntas:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --auto
```

Para informar o IP manualmente:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --auto --ip 164.152.48.215
```

Para atualizar/reparar preservando a sessão:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh |
sudo bash -s -- --repair --auto
```

---

## 🧭 Manager administrativo

Depois da instalação, digite:

```bash
menu
```

Também funciona:

```bash
sudo whatsapp-remote
```

### Opções do menu

```text
1) Visualizar usuários e senhas
2) Alterar usuário e senha do acesso web (remoteadmin)
3) Alterar senha do desktop remoto (VNC)
4) Alterar usuário Linux do desktop
5) Alterar resolução
6) Configurar IP ou domínio
7) Iniciar, parar ou reiniciar serviços
8) Status e diagnóstico completo
9) Reparação automática
10) Atualizar/reparar pelo GitHub
11) Ver logs e diagnóstico
12) Reinstalar tudo do zero
13) Desinstalar
14) Verificar conexão do WhatsApp Web
0) Sair
```

---

## 🩺 Painel de saúde e diagnóstico

O menu principal mostra imediatamente:

- URL e IP público/privado;
- sistema, arquitetura e kernel;
- estado do Desktop/VNC, serviço dedicado do navegador, noVNC, Nginx e processo do Chrome/Chromium;
- estado estimado do WhatsApp Web: conectado, aguardando QR Code, carregando, offline ou não confirmado;
- RAM, swap, disco e carga do sistema;
- quantidade de erros e avisos;
- descrição direta do problema e ação recomendada.

O diagnóstico completo verifica, entre outros pontos:

- serviços inativos ou desabilitados no boot;
- portas VNC, noVNC e HTTPS;
- exposição insegura das portas 5901 ou 6080;
- serviço do navegador parado, processo do Chrome/Chromium ausente e última mensagem real do journal;
- mudança do IP público;
- erros na configuração do Nginx;
- certificado ausente, inválido, vencido ou perto de vencer;
- usuário desktop, perfil e permissões;
- senha VNC e autenticação web;
- pouca memória, ausência de swap e pouco disco;
- comandos `menu` e `whatsapp-remote` ausentes;
- arquivo de credenciais ausente.

Para abrir diretamente:

```bash
sudo whatsapp-remote status
```

---

## 🔐 Usuários e senhas

No menu, escolha:

```text
1) Visualizar usuários e senhas
```

São exibidos:

- URL de acesso;
- usuário web, normalmente `remoteadmin`;
- senha web;
- usuário Linux do desktop, normalmente `whatsapp`;
- senha VNC.

As credenciais ficam protegidas em:

```text
/root/whatsapp-remote-credentials.txt
```

Permissão utilizada:

```text
600 — somente root pode ler
```

> ⚠️ As senhas são visíveis durante a digitação por escolha do projeto. Faça a configuração em um terminal privado e evite gravações de tela.

---

## 🌐 Acesso remoto

Após instalar por IP, abra:

```text
https://IP_DA_VPS/
```

O certificado por IP é autoassinado. O navegador poderá exibir um aviso de segurança na primeira conexão.

### Portas externas

| Porta | Uso | Deve ser liberada? |
|---:|---|:---:|
| TCP 443 | acesso remoto HTTPS | ✅ |
| TCP 80 | domínio e Let's Encrypt | somente com domínio |
| TCP 5901 | VNC interno | ❌ |
| TCP 6080 | noVNC interno | ❌ |
| TCP 9222 | diagnóstico local do WhatsApp/Chrome | ❌ |

> ☁️ Na Oracle Cloud, libere TCP 443 no **NSG** ou na **Security List**. A VPS não consegue verificar automaticamente o firewall externo do provedor.

---

## 📲 Conectar o WhatsApp

1. Abra a URL exibida no final da instalação.
2. Informe o usuário e a senha web.
3. Informe a senha VNC quando solicitada.
4. No celular, abra o WhatsApp.
5. Entre em **Dispositivos conectados**.
6. Toque em **Conectar dispositivo**.
7. Escaneie o QR Code exibido no desktop remoto.

O perfil fica salvo e é reutilizado após reinicializações da VPS.

### ✅ Verificar se o WhatsApp está conectado

No menu principal, o estado aparece automaticamente. Também é possível executar:

```bash
sudo whatsapp-remote whatsapp-status
```

Estados possíveis:

- **Sessão conectada:** a lista de conversas foi detectada;
- **Aguardando leitura do QR Code:** o aparelho ainda precisa ser vinculado;
- **WhatsApp Web carregando:** aguarde alguns segundos;
- **Sessão aberta, mas sem conexão:** o site abriu, porém está offline;
- **Estado não confirmado:** a interface mudou ou ainda não terminou de carregar.

A verificação é feita **localmente**, pela porta `127.0.0.1:9222`, sem enviar conteúdo da sessão para serviços externos. Como a interface do WhatsApp Web pode mudar, o resultado é uma detecção inteligente e não uma API oficial.

---

## 🛠️ Reparação automática

A reparação preserva o perfil do navegador e a sessão do WhatsApp. Ela recria ou corrige:

- usuário e diretórios;
- permissões;
- arquivos de senha;
- configuração do Openbox;
- scripts de inicialização;
- serviço systemd dedicado do navegador, separado do Openbox;
- recuperação de travas antigas do perfil do Chrome;
- escolha automática do perfil persistente mais completo encontrado;
- serviços systemd;
- padrões móveis do noVNC;
- comandos `menu` e `whatsapp-remote`;
- Nginx e serviços da pilha.

Pelo menu:

```text
9) Reparação automática
```

Ou pelo terminal:

```bash
sudo whatsapp-remote repair
```

---

## 🔄 Atualização pelo GitHub

```bash
sudo whatsapp-remote update
```

Ou execute novamente o instalador e selecione **Reparar/atualizar preservando a sessão do WhatsApp**:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

---

## 🧹 Reinstalação completa

No menu:

```text
12) Reinstalar tudo do zero
```

Essa opção:

- baixa e valida o instalador antes de remover a instalação atual;
- apaga o perfil do navegador;
- desconecta a sessão atual do WhatsApp;
- remove usuário, credenciais, certificados e configurações;
- preserva a swap e os pacotes já instalados;
- executa uma instalação automática limpa.

> 🚨 Depois será necessário escanear um novo QR Code.

---

## ⌨️ Comandos diretos

```bash
menu
sudo whatsapp-remote info
sudo whatsapp-remote web-credentials
sudo whatsapp-remote vnc-password
sudo whatsapp-remote desktop-user
sudo whatsapp-remote resolution
sudo whatsapp-remote access-ip
sudo whatsapp-remote access-domain
sudo whatsapp-remote start
sudo whatsapp-remote stop
sudo whatsapp-remote restart
sudo whatsapp-remote status
sudo whatsapp-remote repair
sudo whatsapp-remote update
sudo whatsapp-remote reinstall
sudo whatsapp-remote logs
sudo whatsapp-remote whatsapp-status
sudo whatsapp-remote uninstall
```

---

## 📜 Logs

```bash
journalctl -u whatsapp-desktop.service -n 100 --no-pager
journalctl -u whatsapp-browser.service -n 100 --no-pager
journalctl -u whatsapp-novnc.service -n 100 --no-pager
journalctl -u nginx -n 100 --no-pager
tail -n 120 /var/log/whatsapp-remote-install.log
```

Também estão disponíveis pelo menu:

```text
11) Ver logs e diagnóstico
```

---

## 📁 Estrutura do projeto

```text
setup.sh              Bootstrap e menu via GitHub
install.sh            Instalador universal
manage.sh             Manager administrativo
repair.sh             Reparação rápida
status.sh             Status e diagnóstico
uninstall.sh          Desinstalação e limpeza
lib/common.sh         Funções compartilhadas
tests/validate.sh     Validação estática do pacote
```

Arquivos instalados:

```text
/opt/whatsapp-remote/
/etc/whatsapp-remote/config.env
/root/whatsapp-remote-credentials.txt
/var/log/whatsapp-remote-install.log
```

---

## 🛡️ Segurança

- VNC, noVNC e a porta de diagnóstico `9222` devem escutar somente em `127.0.0.1`;
- o acesso público passa pelo Nginx em HTTPS;
- a autenticação web utiliza `htpasswd` com bcrypt;
- as credenciais ficam disponíveis somente para `root`;
- o diagnóstico alerta se as portas internas forem expostas;
- configurações são copiadas antes de alterações críticas;
- reinstalação e desinstalação exigem confirmação explícita.

---

## 🆘 Solução rápida de problemas

### O menu não abre

```bash
sudo /opt/whatsapp-remote/manage.sh repair
```

Ou execute novamente o instalador e escolha a reparação:

```bash
curl -fsSL https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh | sudo bash
```

### O noVNC abre, mas não conecta

```bash
sudo whatsapp-remote status
sudo whatsapp-remote repair
```

### O WhatsApp Web não está rodando

A versão 2.5.2 usa um serviço exclusivo para o navegador. Verifique:

```bash
sudo systemctl status whatsapp-browser.service --no-pager
sudo journalctl -u whatsapp-browser.service -n 100 --no-pager
```

Depois execute:

```bash
sudo whatsapp-remote repair
```

O reparo agora procura automaticamente perfis antigos como `.config/google-chrome-whatsapp`, remove travas deixadas por encerramentos anormais e mostra a última mensagem real do navegador caso ele ainda não inicie.

### O IP da VPS mudou

```bash
sudo whatsapp-remote access-ip
```

### Acesso externo não abre

Confirme TCP 443 no firewall do provedor. As regras do NSG/Security List não podem ser verificadas de dentro da VPS.

---

## 📌 Observações

- O projeto mantém o navegador ativo, mas o próprio WhatsApp pode solicitar uma nova vinculação de dispositivo.
- Não use a VPS para automações que violem os termos do WhatsApp.
- Faça backup antes de reinstalar tudo do zero.

## 🧰 Correção automática do navegador

A versão 2.5.2 inclui um preflight que corrige automaticamente o `chrome-sandbox`, prepara DBus e remove travas antigas antes de iniciar o navegador. Se o Chrome não abrir:

```bash
menu
```

Escolha **15) Reparar somente o navegador/Chrome**. Também é possível usar:

```bash
sudo whatsapp-remote browser-repair
```

O diagnóstico informa o modo de sandbox e mantém um log dedicado em:

```text
/var/log/whatsapp-remote/browser.log
```

O modo sem sandbox permanece bloqueado por padrão por segurança.

## 🧯 Correção do erro Crashpad

A versão **2.5.2** corrige automaticamente o erro:

```text
chrome_crashpad_handler: --database is required
```

A correção cria os diretórios locais exigidos pelo Chrome, ajusta as permissões do usuário desktop, remove flags antigas de crash reporting e utiliza o binário real do Google Chrome quando disponível. Para aplicar numa instalação existente:

```bash
curl -fsSL "https://raw.githubusercontent.com/DuiBR/whatsapp-remote-vps/main/setup.sh?v=2.5.2" | sudo bash -s -- --repair --auto
```

Depois confira:

```bash
sudo whatsapp-remote browser-repair
sudo whatsapp-remote status
```
