Antes de qualquer tarefa, leia o PEDIDOS.md inteiro. Ao terminar algo, marque o item como [x] com data e commit. Nunca remova nem simplifique um pedido sem minha aprovação.

DECISÃO DEFINITIVA (Fernando, 2026-10-15) — detalhes no topo do PEDIDOS.md:
- Beta Cube Remote = nosso fork CONGELADO (congelado em `9cb56871e`, tag `remote-freeze`; os 4 commits de 06/10 entram se passarem na bateria da VM). PROIBIDO sincronizar/mergear com o RustDesk oficial e adicionar qualquer função nova no código do Remote. Permitido só: branding (nome, ícones, cores, textos) e correção de bug crítico, sempre testada na VM.
- Nada de "RustDesk" pode aparecer para o cliente (executável, janela, bandeja, instalador, textos, ícones, serviço do Windows).
- Funções Beta Cube vivem em 2 programas separados: Beta Cube Agent (serviço Windows invisível, base `C:\projetos\Beta Cube Monitor`) e Beta Cube Painel (app nativo Windows + Android, nunca navegador). O que já está no Remote (quick_actions.rs etc.) é portado para eles; só se remove do Remote depois que a versão nova estiver testada.

## Regras de trabalho do Fernando (trazidas da memória do Claude, 2026-10-15)

Fonte: `C:\Users\Morttificarum\.claude-antigo\projects\C--Users-mortt\memory\`. Nada abaixo é invenção; se algo conflitar com um pedido explícito do Fernando na hora, vale o pedido dele.

**Fluxo de trabalho (feedback_betacube_workflow)**
- Mostrar o diff antes de commitar. Não juntar "fazer a edição" e "commitar" num passo só, mesmo com a edição aprovada antes — esperar o "pode commitar" depois de ver o diff.
- Commit e push são duas aprovações separadas: commitar local não autoriza push; o Fernando quer revisar o diff no GitHub antes de subir. *(Em 2026-10-15 ele pediu explicitamente "commit + push" juntos em tarefas específicas; nesses casos vale o que ele pediu.)*
- Edições em massa (ex.: trocar "RustDesk" por "Beta Cube Remote" em 50 arquivos de tradução) devem se restringir às linhas/chaves exatas, sem find-replace cego, e provar com `git diff` que o resto ficou intacto antes de dizer que terminou.
- Quando algo parecer errado, reverificar no arquivo/commit real antes de concordar (o Fernando já se enganou sobre o que estava commitado; mostrar o diff resolveu).
- Quando o CI falhar, puxar o log real do job (`gh api repos/.../actions/jobs/<id>/logs`) e achar a linha do erro antes de propor correção; adivinhar pelo sintoma desperdiçou ciclos.
- Quando um rename/refactor quebra ferramentas que assumem o nome antigo, não perseguir cada referência uma a uma a cada ciclo de CI (30-40 min cada, hoje ~1h20): avisar o Fernando e oferecer reverter o identificador interno/invisível (ex.: nome do crate Rust). Precedente: `Cargo.toml` voltou para `name = "rustdesk"` / `default-run = "rustdesk"`; o nome do crate não aparece para o cliente.
- Máquina do Fernando sem Flutter/Android SDK/VS Build Tools: builds reais só pelo GitHub Actions (`build-fork.yml` → `flutter-build.yml`; instalador por `build-betacube.yml -f fork_tag=...`). `cargo` e `gh` existem para ajustes de lockfile e CI. Validar a sintaxe do NSIS localmente com `makensis` (NSIS) antes de gastar um ciclo de CI.
- Servidor remoto (SSH): nunca pedir para colar chave privada no chat; pedir host, usuário e caminho local da chave e usar `ssh -i <caminho>`. Em produção com dados de cliente: primeiro diagnóstico somente leitura, ações que alteram só com aprovação explícita.

**Checklist de release (regra fixa, 2026-10-06)** — nenhuma versão nova do Remote vai para instalador de loja sem passar nos 7 passos, na VM **E** no PC real do Fernando, com prova de cada um; ele não testa em loja, só recebe o caminho do instalador depois que todos passarem:
1. Instalar por cima de uma versão antiga (não só instalação limpa). 2. Exatamente um atalho (sem duplicado). 3. Serviço do Windows criado e rodando (`sc.exe query`). 4. Janela abre normal, com ID/senha visíveis (não branca). 5. Registro confirmado no hbbs. 6. Conexão remota funciona com a janela do app fechada. 7. Reiniciar o PC: tudo volta sozinho, sem passo manual.
Antes de dizer "corrigido/validado" ou de regenerar os 32 instaladores, verificar os 7 e informar qual evidência cobre cada passo (a regra existe porque o bug de conexão foi declarado resolvido várias vezes com teste só na VM ou parcial).

**PowerShell:** sempre escrever `sc.exe`, nunca `sc` puro (é alias de `Set-Content` e cria arquivo em vez de consultar o serviço; já criou um arquivo `query` em `C:\Windows\System32`). Vale também para comandos dados ao Fernando.

**Elevação (feedback_elevation_scope):** nunca deixar mecanismo de elevação permanente (ex.: Tarefa Agendada como SYSTEM) e nunca criar "runner" genérico que executa comando arbitrário lido de arquivo (foi o `BetaCubeElevRunner`; o Fernando pediu remoção e confirmação). Se precisar de elevação sem interromper: criar a tarefa na hora, apontando para um .ps1 específico já definido, e removê-la (`Unregister-ScheduledTask` + arquivos de apoio) ao terminar, avisando o Fernando.

**VMs Oracle (feedback_low_ram_oracle_vm):** NUNCA rodar `dnf install` (ou operação pesada de pacote) na VM Beta Cube (`vm-glpi-rustdesk`) nem na da RH-360 — ~1 GB de RAM, travam por OOM (2026-10-01: GLPI, hbbs/hbbr, bridge e MeshCentral fora do ar até reboot pelo console Oracle). Preferir binário estático, script leve (ex.: `acme.sh` em vez de `certbot`) ou construir fora e enviar por `scp`. Se for inevitável, avisar e pegar OK explícito. Correção do kdump (dobra a RAM útil): `systemctl disable --now kdump` + `grubby --update-kernel=ALL --remove-args="crashkernel" --args="crashkernel=no"` (editar só `/etc/default/grub` não basta no OL9/BLS) + reboot. Essas VMs demoram 9-10+ min para o SSH voltar depois de reboot; conferir o console Oracle antes de escalar.

**Sem ferramenta de navegador para uso próprio (feedback_no_browser_tools):** o Fernando só usa programas instalados no dia a dia (acesso remoto, painel de gestão, admin). Nunca instalar nem propor painel web para uso dele sem perguntar antes. O GLPI fica (ele o usa no navegador por necessidade). Vale para a ferramenta dele, não para produtos feitos para terceiros (CD360, RH360).

**Infra/deploy (reference_betacube_vm)**
- Tudo roda na VM Oracle `vm-glpi-rustdesk` (usuário `opc`, IP atual `140.238.184.251`, que é Ephemeral — por isso os clientes usam `remote.betacube.com.br`). Compose único: `/opt/glpi/docker-compose.yml` (glpi-app/db/nginx, rustdesk-hbbs/hbbr, betacube-bridge; MeshCentral foi desativado em 2026-10-02). Conferir esse arquivo antes de assumir que um serviço não é container. Verificar se o IP continua válido antes de confiar em documento antigo que o cite.
- Firewall tem **duas camadas** e as duas precisam abrir: `firewalld` na VM (via SSH) **e** a Security List/NSG da Oracle (só o Fernando, no console OCI).
- Deploy do bridge: `/opt/betacube-bridge/` é cópia de arquivos, **sem git**. `scp` dos arquivos de `app/`, depois em `/opt/glpi`: `docker compose build betacube-bridge && docker compose up -d --force-recreate betacube-bridge`. `docker compose restart` **não** recarrega `env_file`.
- Certs de `helpdesk.betacube.com.br` por **acme.sh** (webroot `/opt/glpi/acme-webroot`, certs em `/opt/glpi/certs/helpdesk/`), renovação no cron do `opc` com reload do nginx; alerta de expiração diário (`ops/check-cert-expiry.sh`); DNS do `remote` mantido por `ops/check-ip-and-update-dns.sh`.
- Tokens GLPI do bridge ficam em `/opt/betacube-bridge/.env` na VM; o token do Cloudflare fica fora de qualquer repo (ver `reference_cloudflare_betacube.md` na memória). **Nunca commitar token, senha ou chave** — este repositório é público.

**Teste na VM BetaCubeTeste (reference_betacubeteste_vm)** — credenciais e forma de acesso ficam em `C:\Users\Morttificarum\.claude\projects\C--Users-Morttificarum\memory\reference_betacubeteste_vm.md` (**não copiar para o repo**). Recriada em 2026-10-15 em `C:\VMs\BetaCubeTeste` (disco original, Geração 1 por ser MBR, Default Switch, 4 GB, 2 CPUs).
- Acesso do Claude: usuário do host nos Administradores do Hyper-V + PowerShell Direct (`Invoke-Command -VMName`), sem rede/SSH, só depois do boot completo.
- O grupo local de admin no guest pt-BR chama "Administradores", não "Administrators" (checagem com o nome em inglês dá falso negativo).
- UAC desativado só nessa VM de teste (nunca no PC real nem em máquina de loja).
- `Copy-VMFile` é só host→guest (exige o serviço de integração "Interface de Serviço de Convidado"); para trazer arquivo do guest, ler bytes dentro do `Invoke-Command` e converter em Base64.
- PowerShell Direct não tem desktop: para capturar janela real, registrar Tarefa Agendada com `LogonType Interactive` (sessão 1) e disparar.
- **Armadilha dos Checkpoints Automáticos:** com `AutomaticCheckpointsEnabled=True` qualquer alteração feita com a VM ligada é descartada no próximo Stop+Start. Conferir que está `False` antes de contar com configuração/software persistente.
- Método de teste do pinpad: simular na VM (portas COM fantasma, serviço falso "WNB Monitor", Driver Booster real, bloqueio de Windows Update real); hardware físico fica sem teste até a loja.

**Armadilhas do instalador (do histórico do rebrand)**
- Usar o `.msi` do build (extraído com `msiexec /a`, script `.github/scripts/extract-rustdesk-msi.ps1`), nunca o `.exe` portátil: o stub portátil extrai sempre em `%LOCALAPPDATA%\rustdesk`, ignorando o `APP_NAME`.
- NSIS: `File "/oname=X" "src"` (aspas no token inteiro `/oname=valor`); `APP_EXE` tem que ser `"Beta Cube Remote.exe"` (com espaço), igual ao `{app_name}.exe` do `--install`.
- Rodar `--silent-install` a partir de `$TEMP\BetaCubeRemoteInstallSrc`, nunca de `$INSTDIR`: `get_uninstall()` faz `rd /s /q` incondicional do diretório de instalação e apagava o app em execução.
- Sempre `sc` com `{app_name}` entre aspas (nome com espaço). `api-server` sempre com a porta `:21114`.
- A config (server/key/relay/preset-note) precisa chegar ao perfil do LocalService; fix em `dfbe64e65` (staging em `C:\ProgramData\Beta Cube Remote\config` + `Config::set_option`).
- Rebrand que NÃO foi tocado de propósito (decisão de 2026-09-08): `MyTheme.button` (`#2C8CFF`), cor azul isolada do link do chat, arquivos de empacotamento Linux (`rustdesk.desktop`, `rustdesk.service`, RPM/DEB/PKGBUILD) — só Windows/macOS/Android importam; renomear às cegas arrisca quebrar o unit systemd/IDs. `applicationId "com.carriez.flutter_hbb"` do Android fica (renomear exigiria mover o pacote Kotlin inteiro, sem teste local); o rótulo "RustDesk" do Android foi trocado em 2026-10-15 por ordem do Fernando.

**Bridge (project_betacube_bridge) — decisões que continuam valendo**
- O GLPI é a fonte da verdade de quais máquinas existem e de qual loja são (`entities_id`); o bridge **não** cria banco paralelo de dispositivos. Cria o Computer na entidade padrão no primeiro contato e depois só mexe no campo `comment` — nunca sobrescreve `entities_id` (reatribuição manual do técnico tem que permanecer).
- O SQLite local guarda só o que o GLPI não modela (heartbeat, log de eventos de conexão/arquivo/alarme).
- Protocolo reverso-engenheirado do fonte do fork (`src/hbbs_http/sync.rs`, `src/server/connection.rs`, `src/common.rs`): `POST /api/heartbeat`, `/api/sysinfo`, `/api/sysinfo_ver`, `/api/audit/{conn,file,alarm}`; deliberadamente **sem** `/api/login*`, `/api/ab*`, `/api/oidc/*` (heartbeat/sysinfo sem autenticação por design). Antes de escrever código novo "para a app fazer X automaticamente" em nível de protocolo, conferir o fonte do fork — pode já existir.
- `ENABLE_CRITICAL_ALERTS` é desligado por padrão no bridge; alerta crítico só para servidor, com cooldown de 4 h. O token do Telegram vive em variáveis de ambiente, nunca hardcoded.
- Rede (Fase 6): o bridge não alcança controladores na LAN da loja; ele enfileira um comando de relay HTTP que o agente da própria loja executa. Credenciais dos controladores são cifradas (Fernet, `NETWORK_CREDENTIALS_KEY` no `.env` do bridge); perder/rotacionar essa chave obriga recadastrar todos os controladores.
- `restart_services` (WNB Monitor/TLS Client, Tomcat, SITEF) deve manter o ciclo garantido parar → verificar → matar por PID → iniciar (`Restart-Service -Force` pode não fazer nada com processo "pendurado").

**Beta Cube Monitor (project_betacube_monitor_prototype)** — protótipo Python em `C:\projetos\Beta Cube Monitor`; é fonte da **lógica** de detecção a portar para o Agent (decisão de 2026-10-15), não um produto a manter instalado. Já portados ao bridge: `telegram_bot.py`. A portar: `disk_health.py` (`Get-PhysicalDisk` + `Get-StorageReliabilityCounter`: desgaste, erros não corrigidos, temperatura, horas ligado), `power_health.py` (Event ID 41 Kernel-Power; nobreak em bateria via `Win32_Battery`, `BatteryStatus == 1`), `windows_health.py` (erros críticos do Event Log nas últimas 24 h; serviços críticos parados: wuauserv, WinDefend, Dnscache, BITS, EventLog, RpcSs; atualizações pendentes; uptime; disco <10% livre). `security_scanner.py`/`windows_defender_scan.py` pertencem à fase do antivírus, não à de monitoramento de hardware — não misturar. `agendador.py` fica obsoleto no Agent (o loop próprio substitui). O `betacube_config.ini` real contém segredos (token do Telegram, chave do VirusTotal): nunca commitar; a chave do VirusTotal só entra em uso na fase do antivírus.

AGENTS.md
