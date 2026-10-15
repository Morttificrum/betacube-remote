# Backlog — Beta Cube Remote

Toda sessão de trabalho começa lendo este arquivo (ver regra em
`CLAUDE.md`). Todo pedido novo do usuário entra aqui imediatamente,
mesmo que a implementação só comece depois. **Nada muda pra "Feito" sem
evidência de teste real anexada.**

Levantamento feito em 2026-09-25 a partir do histórico de commits dos
dois repositórios (`betacube-remote`, `betacube-bridge`) e da sessão em
andamento. Onde não achei nenhum registro (git log, código, notas), digo
isso explicitamente em vez de supor.

## Onde paramos

*Atualizar sempre que terminar uma etapa, e sempre antes de qualquer
`/compact`.*

- **DECISÃO DE ARQUITETURA (2026-10-07): fork pausado, 3 programas
  separados.** Causa: bisseção do bug "janela branca/sem janela" achou
  a causa real sem gastar build nenhum — é a feature "proteção das
  lojas" (`preset-note` não-vazio = nunca mostra janela, desde
  `2941d1132`/24-09) funcionando como projetada, só que o instalador
  `TesteVM` usado pra validar o checklist TEM `STORE_NAME` setado — o
  próprio teste contradizia a própria feature. Não era bug de código.
  Mas a decisão foi: **parar de remendar o fork mesmo assim** — virou
  remendo em cima de remendo (sc-quoting → silent-install → config em 3
  lugares → stop-service preso → atalho duplicado → proteção de loja
  quebrando a janela, cada fix achando uma "causa raiz definitiva" que
  não era a última). Plano completo, sem código, em
  `Cerebro Claude/Projects/Beta Cube Remote - Decisao Arquitetura
  2026-10-07.md`:
  1. **Acesso Remoto** = RustDesk oficial puro (sem fork), só
     servidor/chave via mecanismo nativo de custom client. Zero mudança
     de código/UI/serviço. **Entrega de hoje.**
  2. **Beta Cube Agent** (loja) — serviço Windows separado: heartbeat,
     sensores, inventário, Ações Rápidas (pinpad Gertec etc). Não mexe
     no RustDesk.
  3. **Beta Cube Painel** (PC do Fernando) — app desktop: lojas>
     máquinas, status, Ações Rápidas, botão Conectar, chamado GLPI
     automático.
  4. Reaproveita bridge/banco/lógica de sensores-ações-GLPI. **NÃO**
     reaproveita o código Rust/Dart do fork — vira só referência de
     leitura.
  5. Checklist dos 7 passos (`AGENTS.md`) vale pra cada peça antes de ir
     pra loja. Ordem: (1) RustDesk oficial hoje, (2) Agent v1
     heartbeat/inventário 1-2 dias, (3) Agent v2 Ações Rápidas 2-3
     dias, (4) Painel v1 lista+Conectar 1-2 dias, (5) Painel v2 Ações
     Rápidas+GLPI 1-2 dias, (6) rollout nas 33 lojas sem prazo fixo.
  **`betacube-remote` (o fork) fica pausado — sem commit novo até
  decisão em contrário.**
- **Reformulação dos alertas de offline (betacube-bridge, pedida
  2026-10-06, NÃO INICIADA)** — alertas atuais considerados inúteis
  (repetem a cada 4h, uma mensagem por máquina, duplicados). **Nova
  lógica final (2ª mensagem do usuário supera as regras de frequência
  da 1ª, mas os itens 3 e 7 abaixo continuam valendo como ações
  separadas):**
  1. Agrupa por LOJA (entidade/preset-note), não por máquina isolada.
  2. Uma máquina offline, resto da loja online = problema real: UM
     alerta + abre chamado no GLPI da loja daquela máquina.
  3. Loja inteira cai junto (janela de poucos minutos): dentro do
     horário normal de fechamento da loja = silêncio; fora do horário =
     UM alerta "Loja X inteira offline — possível queda de
     internet/energia".
  4. Aprende o padrão de horário de liga/desliga de cada máquina pelo
     histórico (2-3 semanas de heartbeat) — alerta só quando foge do
     padrão (ex. caiu no meio do expediente). Loja que nunca desliga à
     noite continua vigiada à noite. **Enquanto não tem histórico
     suficiente (primeiras semanas), usa só as regras 2, 3 (horário
     padrão de fechamento 22h-7h) e 5.**
  5. Aviso de desligamento normal do Windows nunca gera alerta (já
     existe, manter).
  6. Servidor da loja (ex. dtmserver) tem prioridade: cai com o resto
     da loja ligado → alerta na hora, sem esperar padrão/janela.
  7. Quando a máquina ou a loja volta: UM aviso "voltou" (não um por
     máquina se foi queda da loja inteira).
  - **Ações adicionais da 1ª mensagem, independentes da lógica acima:**
    - **Duplicados**: fatal1ty e dtmserver alertam 2x por rodada —
      reinstalação cria `rustdesk_id` novo, o registro antigo do mesmo
      hostname/loja fica esquecido no banco. Juntar/arquivar o registro
      antigo quando aparece um ID novo pro mesmo hostname/preset-note,
      e limpar os duplicados que já existem hoje.
    - **Marcação "não monitorar" por máquina**: `betacubeteste`
      (VM de teste) e `fatal1ty_990fx_killer` (PC do usuário) nunca
      geram alerta.
    - **GLPI**: `caixa02`, `caixa06` e `diretoria` aparecem vinculadas
      à entidade raiz "Beta Cube Soluções em TI" em vez da loja certa —
      confirmar de qual loja são e corrigir o vínculo no GLPI.
  - **Teste obrigatório**: com dados simulados no bridge, nunca
    testando direto contra lojas reais.
- **Regra fixa de release (2026-10-06)**: nenhuma versão nova vai pra
  loja sem passar nos 7 passos do checklist obrigatório (ver `AGENTS.md`)
  na VM E no PC do usuário, com prova de cada um — instalar por cima,
  1 atalho só, serviço criado/rodando, janela abre normal com ID/senha,
  registro no hbbs, conexão com janela fechada, reinício e tudo volta
  sozinho. Usuário não testa em loja — só recebe o instalador depois de
  todos passarem.
- **Bug do `stop-service` preso + atalho duplicado + tela branca
  (2026-10-06, EM ANDAMENTO)** — três causas raiz distintas, achadas
  testando o instalador `TesteVM` (STORE_NAME setado) na VM e no PC do
  usuário:
  1. `stop-service='Y'` preso (ver "Desinstalar serviço" da GUI, nunca
     volta pra vazio) fazia `get_create_service()` pular a criação do
     serviço em qualquer reinstalação. Fix (`39a89fef8`): `install_me()`
     zera `stop-service` sempre.
  2. Atalho duplicado no Menu Iniciar: NSIS sem `SetShellVarContext all`
     criava a pasta per-user, resíduo nunca limpo pela rotina de dedupe
     do lado Rust (que roda ANTES desse `CreateShortcut`). Fix
     (`34233b89c`): `SetShellVarContext all` nos dois Sections do NSIS.
  3. **Tela branca** (causa real, não tinha nada a ver com
     stop-service nem servidor embutido — teoria descartada pelo
     próprio usuário): `flutter/lib/main.dart` (commit `2941d1132`,
     24/09, proteção das lojas) faz `return;` simples quando
     `preset-note` não está vazio (qualquer build com STORE_NAME, como
     o `TesteVM`) — mas a janela nativa (Win32/engine) já foi criada
     pelo embedder ANTES do Dart chegar nesse ponto. `return` sem nunca
     chamar `windowManager` deixa essa janela vazia visível pra sempre.
     Nunca foi notado porque ninguém tinha testado visualmente um
     instalador com STORE_NAME até agora — só via heartbeat/hbbs. Fix
     (`dea0c43a2`): `windowManager.ensureInitialized()` +
     `windowManager.hide()` antes do `return`.
  - **Falta**: rebuild do fork (inclui mudança em Dart/`app.so`, não só
    Rust/NSIS — precisa do ciclo completo de ~45min), testar os 7 passos
    do checklist na VM e no PC do usuário, só depois regenerar os 32
    instaladores de loja de novo (3ª vez).
- **Duas specs novas, prioridade alta (pedidas 2026-10-06, depois do
  fix acima)** — motivo de urgência: AnyDesk grátis impõe espera de
  100s por acesso, quanto antes as lojas migrarem mais rápido o usuário
  abandona o AnyDesk:
  1. **3 botões "Pinpad Gertec"** (especificação final, substitui o
     rascunho anterior — procedimento real usado hoje na loja J&L, 2
     caixas com pinpad parado):
     - **Botão 1 — "Diagnóstico do caixa"** (só leitura, não muda nada):
       portas COM (`Get-PnpDevice -Class Ports`), destacando portas
       fantasma (status Unknown) e qual COM é o Gertec PIN Pad PPC;
       driver Gertec instalado + versão (Driver/WebAPI/DLL/Serial
       Manager); serviço "WNB Monitor" existe/rodando?; Driver Booster
       (ou similar) instalado?; Windows Update bloqueado pra drivers?
       (`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\
       ExcludeWUDriversInQualityUpdate = 1`).
     - **Botão 2 — "Corrigir pinpad"**: (a) instala driver Gertec
       (Gertec-Full-Installer 2.2.2.0, biblioteca de arquivos do
       programa — checar se tem flag silenciosa, senão abre o
       instalador); (b) remove portas COM fantasma
       (`pnputil /remove-device` nas de status Unknown); (c) limpa
       `ComDB` (mesma chave acima), SEMPRE com backup do valor antes;
       (d) reinicia serviço "WNB Monitor"; (e) mostra em qual COM o
       pinpad ficou, com opção de forçar uma COM específica (a que o
       PDV da loja espera).
     - **Botão 3 — "Blindar caixa"** (pede confirmação antes): bloqueia
       Windows Update de atualizar drivers (chave acima); desinstala
       Driver Booster e similares se existirem; registra no inventário
       da máquina que foi blindada.
     - **Regras de confirmação/segurança (2026-10-06, clarificado)**:
       Diagnóstico é 100% somente leitura, zero alteração. Corrigir
       pinpad e Blindar caixa mostram a lista EXATA do que vão fazer
       ANTES de qualquer ação, e só executam passo a passo com
       confirmação do usuário a cada passo — nunca tudo de uma vez sem
       checkpoint. Todo valor alterado (ComDB, chaves de registro) tem
       backup automático antes da mudança, com opção de desfazer.
     - **Método de teste (2026-10-06)**: usuário não tem bancada com
       pinpad/Datamaxi físico e não testa em máquina de cliente — testar
       tudo que der por simulação na VM: portas COM virtuais deixadas
       como fantasma (status Unknown), serviço falso chamado "WNB
       Monitor", Driver Booster instalado de verdade na VM, bloqueio do
       Windows Update aplicado de verdade. O que não for simulável na VM
       (hardware físico do pinpad) fica sem teste real até a loja.
     - Regras gerais: toda ação gera log; ações que apagam/desinstalam
       pedem confirmação explícita; testar na VM antes simulando porta
       fantasma + serviço parado. Não iniciado.
  2. **GLPI automático por sessão** — toda sessão de acesso remoto
     abre/atualiza um chamado na entidade da loja, com máquina,
     horário de início/fim e as Ações Rápidas executadas; usuário só
     completa descrição/solução no final. Hoje nada vai pro GLPI
     automaticamente. Não iniciado.
- **Migração IP→nome (2026-10-06)**: IP `140.238.184.251` é Ephemeral na
  Oracle — se mudasse sem avisar, as 33 lojas caiam de uma vez. Criado
  `remote.betacube.com.br` (A record, DNS only/nuvem cinza — UDP não
  passa pelo proxy da Cloudflare) via API, apontando pro IP atual.
  `installer/betacube-installer.nsi` usa esse nome agora (commit
  `9cb56871e`) em vez do IP direto. Script novo
  `ops/check-ip-and-update-dns.sh` no cron da VM (a cada 5min, leve, sem
  dnf) detecta se o IP mudou e atualiza o registro sozinho + avisa no
  Telegram — testado de propósito quebrando o DNS, corrigiu e avisou
  certinho. Validado na VM `BetaCubeTeste` que registra no hbbs usando o
  nome (não o IP) antes de regenerar os 32. Os 32 instaladores de loja
  foram gerados de novo com esse fix (06/10 00:01-00:05) e substituíram
  os anteriores na pasta `instaladores/` — nenhum arquivo antigo sobrou.
- **BUG DE CONEXÃO RESOLVIDO e validado (2026-10-05)**. Causa raiz real
  tinha 3 partes (config no perfil errado + ACL do LocalService + cache
  em memória do `Config` — ver detalhe abaixo) + o `sc create`/`sc start`
  nunca reiniciando o serviço num reinstall por-cima. Commit final:
  `dfbe64e65`. **Bateria completa passou na VM `BetaCubeTeste`**: 5
  reinícios + queda/volta de rede, sem clique nenhum, serviço se
  autocorrige e registra no hbbs sozinho a cada vez (`rendezvous_reachable
  = 1` confirmado de fora em todos os 6 checkpoints). Os 32 instaladores
  de loja foram **regenerados** com esse binário validado (mesmo
  `fork_tag=betacube-build`, tamanhos consistentes entre si — confirmado
  que todos saíram do mesmo build) e substituíram os de 24/09 na pasta
  `instaladores/` (nada do build quebrado sobrou).
  **Próximo passo**: o usuário instala loja por loja, conforme acessa
  cada uma no dia a dia (sem prazo/lote definido). Critério pra saber
  quem já foi atualizada: loja com a versão nova aparece **online na aba
  Equipment mesmo com a janela do app fechada** (serviço registrando
  direto) — quem ainda está na versão antiga só aparece online com a
  janela aberta.
- **Causa raiz DEFINITIVA do "nunca registra no hbbs" (2026-10-02/03)**:
  não é rede, não é o serviço não existir (isso já tinha sido corrigido).
  É onde a config fica salva. O NSIS escreve o toml (server/key/relay/
  preset-note) em `$APPDATA\Beta Cube Remote\config\` de quem RODA o
  instalador (NSIS pede `RequestExecutionLevel admin`, nunca SYSTEM);
  `install_me()` faz a mesma coisa via `Config::set_option`. O serviço
  de fundo (`--server`, lançado pelo SCM) roda como a conta
  **LocalService**, com perfil PRÓPRIO — o código só redireciona pro
  perfil do LocalService (`patch()` em `hbb_common/config.rs`) quando o
  processo atual É a conta SYSTEM de verdade, o que nunca acontece numa
  instalação normal por duplo clique. Resultado: o serviço nunca vê o
  server/key da Beta Cube, cai no servidor público do RustDesk
  (`rs-ny.rustdesk.com`, confirmado no log da VM), nunca registra no
  hbbs — mesmo com o serviço "Em execução" e tudo certo no resto. Só
  "funciona" com a janela do app aberta porque aí é o processo do
  usuário interativo rodando (que tem a config certa), não o serviço.
  **Fix** (commit `7190de524`, `src/platform/windows.rs` +
  `src/core_main.rs`): `install_me()` agora copia os tomls pro perfil
  do LocalService sempre, independente de quem instalou. Autocorreção
  no início do `--server`: se o perfil do LocalService não tiver
  `custom-rendezvous-server` configurado, copia de outro perfil de
  usuário já configurado ou cai pra licença embutida no exe —
  instalações já feitas (incluindo as de loja de 24/09) se corrigem só
  com a atualização, sem precisar reinstalar do zero.
  **Falta**: build do fork, reinstalar por-cima na VM `BetaCubeTeste`,
  confirmar o toml certo no perfil do LocalService + registro no hbbs,
  só então rodar a bateria de 5 reinícios + queda de rede.
- **Interrupção 2026-10-01/02 (não planejada)**: durante o teste da VM,
  o 500 na aba Equipment + alertas Telegram de hora em hora levaram a um
  desvio pra infra (ver seção "Incidente de infra" abaixo). Resolvido:
  cert do helpdesk renovado (acme.sh, auto-renovação), fallback no
  `/internal/equipment`, alerta de expiração de cert, e um fix de RAM na
  VM Oracle (kdump) depois de eu travar a VM tentando instalar via
  `dnf` — **nunca mais rodar dnf nessa VM nem na da RH-360**. Pendente:
  `manage.betacube.com.br` sem DNS (não deu pra renovar o cert dele), e
  confirmar com o usuário se as 29 lojas sem heartbeat nunca registrado
  já têm o instalador novo instalado ou só foram geradas em 24/09.
- **Item em andamento**: Bug de conexão (offline após reboot / "só
  funciona com a janela aberta") — duas causas raiz REAIS corrigidas
  (instalador silencioso + aspas no `sc`). Build do fork já rodou. Na VM
  `BetaCubeTeste` o serviço sobe "Em execução", Automatic — falta a
  bateria de aceite (5 reinícios + queda de rede + registro no hbbs,
  conectando de fora).
- **Investigação de rede ENCERRADA (2026-09-26)**: rede não é o
  problema. Security List da Oracle já libera UDP 21116 e o pacote
  chega (contador do iptables confirmado subindo 5/5). A regra ACCEPT
  udp/21116 só tinha 72 pacotes em 2 semanas porque os clientes não
  enviam nada — sem serviço rodando, não há o que sincronizar. Explica
  os alertas de todas as lojas: mesma causa raiz do bug de conexão, não
  um problema de firewall/porta separado.
- **Último passo feito**: commit `34618275f` (`--install` →
  `--silent-install`) + commit `755fcb214` (aspas em `{app_name}` nos
  `sc create/start/stop/delete/failure`). Build do fork rodou. Serviço
  confirmado "Em execução"/Automatic na VM depois da instalação nova.
- **Próximo passo**:
  1. Na VM `BetaCubeTeste`: instalar a versão nova do zero, confirmar
     serviço "Em execução" + registro no hbbs + bateria de 5 reinícios +
     queda de rede, conectando de fora a cada passo.
  2. Preparar a atualização por-cima nas lojas via AnyDesk (sem clique
     nenhum) e testar esse caminho de update-por-cima na própria VM
     antes de aplicar em loja real.
  3. Pendência nova: clientes conectam no IP direto
     `140.238.184.251`, que é Ephemeral na Oracle (pode mudar). Planejar
     migração pra `helpdesk.betacube.com.br` (já tem DNS apontado, ver
     nota do projeto GLPI+RustDesk).
  - Só depois de tudo isso passar: regenerar os 33 instaladores de loja
    e começar a Fase 1 do plano de dispositivos protegidos.

## Resumo

| Item | Status | Pedido em |
|---|---|---|
| Bug de conexão (offline após reboot) | **Feito (2026-10-05)** | 2026-09-24 |
| Proteção das lojas | Em andamento | 2026-09-24 |
| Catálogo de drivers VID/PID (v1) | Em andamento | 2026-09-24 |
| Dispositivos protegidos + ponto de restauração + verificação de porta | Planejado | 2026-09-25 (não documentado antes) |
| Biblioteca de arquivos Beta Cube | Planejado | 2026-09-25 (não documentado antes) |
| Modo manutenção | Pendente — escopo indefinido | não documentado |
| Sidebar de Quick Actions + layout PC Manager + aba Ferramentas | Pendente | nesta sessão, data exata não registrada |
| Atualização remota das lojas já instaladas (sem serviço) | Pendente | 2026-09-25 |
| Watchdog de heartbeat reabre chamado a cada 4h pra dispositivo zumbi antigo | Pendente | 2026-09-25 |
| Cert TLS do helpdesk vencido + 500 no Equipment | Feito | 2026-10-01 (achado durante teste de VM) |
| Cert TLS do manage.betacube.com.br (sem DNS) | Obsoleto — MeshCentral desativado 2026-10-02 | 2026-10-01 |
| Confirmar se as 29 lojas sem heartbeat já têm o instalador novo instalado | Respondido: só as 4 mesmas foram instaladas | 2026-10-02 |
| Bug `stop-service` preso + atalho duplicado | Em andamento | 2026-10-06 |
| Ação Rápida "Pinpad PPC930" | Não iniciado | 2026-10-06 |
| GLPI automático por sessão (chamado por acesso remoto) | Não iniciado | 2026-10-06 |
| Reformulação dos alertas de offline (por loja + padrão de horário) | Não iniciado | 2026-10-06 |
| caixa02/caixa06/diretoria com entidade GLPI errada | Não iniciado | 2026-10-06 |

---

## Incidente de infra (2026-10-01/02): cert vencido + VM travada por dnf

- **Descrição**: durante a bateria de teste da VM, achado que a aba
  Equipment do cliente dava HTTP 500 e o Telegram mandava "tudo fora do
  ar" de hora em hora. Investigação achou duas causas reais:
  1. Cert Let's Encrypt do `helpdesk.betacube.com.br` (90 dias, emitido
     03/07) venceu em 01/10 16:03 UTC — nunca teve renovação automática
     configurada (sem certbot, sem cron, nada). `/internal/equipment`
     (`main.py:400`) chamava o GLPI sem try/except, então toda chamada
     falhando com `CERTIFICATE_VERIFY_FAILED` virava 500 puro.
  2. Os alertas de "tudo fora do ar" eram REAIS, não bug: de 33
     instaladores de loja gerados em 24/09, só 4 (Itaquera,
     Vila-Guilherme, Pinheiro-e-Pinheiro, Isabela-FCO) já chegaram a
     mandar heartbeat pro bridge alguma vez — e pararam entre 17/09 e
     25/09. As outras 29 nunca registraram nenhum heartbeat, nunca —
     sem evidência de terem sido instaladas de fato ainda. O cooldown de
     4h por dispositivo, com várias lojas defasadas, parecia "alerta a
     cada hora".
- **Acidente no meio do diagnóstico**: tentei instalar `certbot` via
  `dnf install epel-release` na VM Oracle (só tinha 9Mi RAM livre na
  hora) — travou a VM inteira por OOM (SSH/HTTPS pendurados ~10min,
  todos os 7 containers fora do ar). Só voltou com reboot pelo console
  Oracle. Causa raiz: `crashkernel=448M` reservado pro kdump numa VM de
  1GB RAM (quase metade da RAM perdida à toa). **Regra nova: nunca
  rodar dnf nessa VM nem na da RH-360** — ver `CLAUDE.md` global do
  Cérebro.
- **Corrigido**:
  - Kdump desabilitado + `crashkernel=no` via `grubby --update-kernel=ALL`
    (editar só `/etc/default/grub` + `grub2-mkconfig` NÃO basta no
    OL9/RHEL9 — usa BLS, as entradas de boot têm `options` fixa própria).
    RAM utilizável dobrou: 498Mi → 945Mi.
  - Cert do helpdesk renovado via **acme.sh** (não certbot — mais leve),
    usando o webroot que já existia em `/opt/glpi/acme-webroot`.
    Auto-renovação no cron do `opc` (4x/dia) com `--reloadcmd` que
    recarrega o `glpi-nginx` sozinho. Válido até 2026-11-29.
  - `/internal/equipment` (bridge) agora tem try/except: se o GLPI
    falhar, cai pra lista local (`db.list_devices()`) em vez de 500,
    com header `X-Glpi-Status: degraded`. Deployado (rebuild +
    `docker compose up -d betacube-bridge`), testado com `curl` (200 OK).
  - Alerta novo no Telegram: `ops/check-cert-expiry.sh` (cron diário
    08:00 no host) avisa quando qualquer cert tem ≤14 dias pra vencer.
    Testado (disparou alerta real pro manage, que está vencido).
- **Falta pra virar "Feito" por completo**:
  - `manage.betacube.com.br` continua sem cert — **sem registro DNS
    nenhum** (NXDOMAIN) no Cloudflare, precisa resolver isso antes.
  - Confirmar com o usuário se as 29 lojas "silenciosas" já têm o
    instalador de 24/09 rodando ou só foram geradas e nunca instaladas —
    muda a prioridade do rollout dos 33 instaladores novos.

---

## Bug de conexão (offline após reboot / só funciona com a janela aberta)

- **Descrição**: nas máquinas de loja com o instalador de loja, o acesso
  remoto só funciona enquanto a janela do app está aberta. Fechou a
  janela → "computador remoto está offline". Depois de reiniciar o PC, o
  ícone aparece na bandeja mas continua offline — não volta sozinho.
  Caso real relatado: caixa01, loja Itaquera, 24/09 (só recuperado via
  AnyDesk de reserva). Usuário relata que "já foi corrigido antes e
  voltou".
- **Pedido em**: 2026-09-24.
- **Status**: **FEITO (2026-10-05)** — validado com bateria real completa
  na VM `BetaCubeTeste`: 5 reinícios + queda/volta de rede, zero clique,
  serviço registra no hbbs sozinho em todos os 6 checkpoints
  (`rendezvous_reachable=1` confirmado de fora a cada um). Instaladores
  dos 32 clientes regenerados com o binário validado (commit
  `dfbe64e65`) e substituídos na pasta `instaladores/`.
- **Causa raiz encontrada** (investigação de código, evidência em
  `src/platform/windows.rs`): o registro real no rendezvous só existe
  dentro do processo filho `--server`, lançado pelo serviço via
  `launch_server()`/`launch_privileged_process()`. Falha nesse
  lançamento (ex.: sem sessão de console disponível,
  `GetCurrentSession() == 0xFFFFFFFF`) era engolida em silêncio, e o
  loop de retry do serviço tinha um `continue` que pulava a checagem de
  relançamento sempre que a sessão fosse 0xFFFFFFFF — nunca tentava de
  novo enquanto isso persistisse.
- **Fix 1** (commit `0ded43a68`) — relança mesmo sem sessão de console
  detectável, loga toda falha de lançamento (antes invisível), e
  adiciona um watchdog independente por Tarefa Agendada (SYSTEM, a cada
  1 min, checa se o processo `--server` está de pé e reinicia o serviço
  se não estiver). **Nunca foi realmente exercitado por um teste — ver
  Fix 2 e 3 abaixo, achados DEPOIS: o serviço nunca existia pra este fix
  ter chance de atuar.**
- **Fix 2** (commit `34618275f`, achado testando na VM com `vmconnect`
  de verdade) — o instalador chamava `Beta Cube Remote.exe --install`
  (sem flag), que abre uma tela Flutter de confirmação ("Instalação" —
  caminho, checkboxes, "Aceitar e Instalar"/"Executar sem instalar") e
  espera clique humano. Numa instalação remota de loja, ninguém sabe que
  precisa clicar ali depois do NSIS já ter dito "Concluir" — o app fica
  em modo portátil pra sempre. Troca `--install` por `--silent-install`
  (já existia em `core_main.rs`, pula a tela).
- **Fix 3** (commit `755fcb214`, achado reinstalando depois do Fix 2 —
  arquivos instalavam certinho mas o serviço continuava não existindo)
  — **causa raiz real e mais profunda**: TODO `sc create/start/stop/
  delete/failure` no código (10 ocorrências, só em `windows.rs`) chama
  `{app_name}` sem aspas. "RustDesk" (nome original, sem espaço) nunca
  expôs isso; "Beta Cube Remote" (nosso rebrand, com espaço) faz o
  `sc.exe` ler só "Beta" como nome do serviço e falhar silenciosamente
  em "Cube"/"Remote" — sem parar o resto do `.bat`, sem nenhum sinal de
  erro. **O serviço nunca foi criado em NENHUMA instalação, em nenhum
  ambiente, desde que o rebrand começou.** Fix: aspas em todo `{app_name}`
  nesses comandos.
- **Fix 4** (commit `7190de524`, 2026-10-02/03) — causa raiz MAIS
  profunda ainda: com o serviço já existindo e rodando, o toml com
  server/key/relay/preset-note é escrito no perfil de QUEM RODA o
  instalador (NSIS pede admin, nunca SYSTEM), mas o serviço de fundo
  roda como a conta LocalService, com perfil próprio — nunca vê essa
  config, cai no servidor público do RustDesk, nunca registra no hbbs.
  Ver detalhe completo na seção "Causa raiz DEFINITIVA" abaixo.
- **Fix 5** (commit `dfbe64e65`, 2026-10-03/05) — três problemas em
  cima do Fix 4, achados testando de novo: (a) reinstalar por-cima de
  serviço já rodando nunca reiniciava o processo (`sc create`/`sc start`
  falham silenciosamente se já existe/já rodando) — corrigido com
  `sc stop` antes; (b) copiar config direto pro perfil do LocalService
  depende de ACL que Administrator não garante ter — corrigido com
  staging em `C:\ProgramData\Beta Cube Remote\config` (sempre legível)
  + `icacls` reforçando leitura pro LocalService; (c) `Config` é
  cacheado em memória por processo — só trocar o arquivo no disco não
  afeta o processo já rodando, só o próximo restart — corrigido
  aplicando via `Config::set_option` (memória + disco juntos).
- **Validado (2026-10-05)**: bateria completa na VM `BetaCubeTeste` —
  5 reinícios + queda/volta de rede, zero clique, registro no hbbs
  confirmado em todos os 6 checkpoints. **Nada falta** — os 32
  instaladores de loja já foram regenerados com o binário validado.

## Proteção das lojas (sem janela/bandeja, serviço reinicia sozinho, sem falso alerta à noite)

- **Descrição**: nenhum componente com janela/ícone de bandeja pode
  aparecer pro funcionário em máquina de loja — só o serviço em segundo
  plano. Serviço reinicia sozinho em segundos se for finalizado. Se a
  máquina ficar offline de verdade (processo morto/travado), o bridge
  avisa (Telegram/painel) com nome da loja e da máquina — mas SEM
  disparar alerta em desligamento normal do Windows (loja fecha o caixa
  à noite).
- **Pedido em**: 2026-09-24.
- **Status**: Em andamento.
- **Implementado**: commit `2941d1132` — `preset-note` (mesmo sinal do
  nome da loja) suprime UI/tray em máquina de loja; `sc failure` reduzido
  de 60s/60s/300s pra 5s/5s/5s; serviço avisa o bridge no evento nativo
  de shutdown do Windows (`/api/shutdown_notice`); watchdog de heartbeat
  parado no bridge (`evaluate_offline_watchdog`) só alerta se não houver
  esse aviso mais recente que o último heartbeat.
- **Falta pra virar "Feito"**: teste de aceite real — matar o processo
  via Gerenciador de Tarefas e confirmar volta em segundos; confirmar
  visualmente que não aparece janela nem ícone numa máquina com
  `STORE_NAME`; confirmar que um desligamento normal não dispara alerta.
  Nenhum desses 3 foi testado numa máquina de verdade ainda.

## Catálogo de drivers por VID/PID (v1)

- **Descrição**: "Install driver" lista dispositivos com problema
  (VID/PID), consulta um catálogo no bridge, instala com 1 clique se
  conhecido, oferece driver nativo (usbser) pra CDC/ACM genérico, e deixa
  cadastrar um aparelho desconhecido na hora (nome + .inf/.zip). Caso de
  teste combinado: CDC ACM Comm do caixa01, loja Itaquera.
- **Pedido em**: 2026-09-24.
- **Status**: Em andamento.
- **Implementado**: commit `2941d1132` (cliente) + `e24a059` (bridge,
  endpoints `/internal/driver_catalog`). Bridge já implantado e
  verificado respondendo (`HTTP 200` no endpoint de lookup).
- **Falta pra virar "Feito"**: nunca foi testado contra o dispositivo
  real (CDC ACM Comm, caixa01/Itaquera) nem contra nenhum outro
  dispositivo de verdade.

## Dispositivos protegidos + ponto de restauração + verificação de porta COM

- **Descrição**: o instalador de drivers nunca atualiza sozinho SAT,
  impressora fiscal/térmica, pinpad (Gertec etc.), balança ou placa de
  rede — aparecem marcados como "protegido" na lista e só atualizam com
  confirmação item a item. Ponto de restauração antes de qualquer
  instalação. Depois, confere se a porta COM de cada dispositivo
  continua a mesma (antes/depois). Objetivo declarado: substituir a
  dependência de ferramentas de terceiro tipo SDI (Snappy Driver
  Installer) pro fluxo de drivers da loja.
- **Pedido em**: usuário relata ter pedido "há umas duas semanas"
  (~2026-09-11) — **sem nenhum registro encontrado em commits, código ou
  notas desta sessão até 2026-09-25**, quando foi replanejado do zero.
- **Status**: Planejado (plano aprovado em 2026-09-25, ver seção "Fase
  1" do plano na íntegra — decisões já fechadas: ponto de restauração
  que falha BLOQUEIA a instalação, com botão explícito "Prosseguir sem
  ponto de restauração"). Implementação ainda não iniciada.
- **Falta pra virar "Feito"**: implementar + testar contra um
  dispositivo protegido de verdade (ou a placa de rede da própria VM de
  teste) confirmando que a ação pede confirmação extra e não toca sem
  ela; confirmar ponto de restauração aparece em
  `Get-ComputerRestorePoint` depois de uma instalação.

## Biblioteca de arquivos Beta Cube

- **Descrição**: área no bridge pra subir instaladores/drivers de uso
  frequente (Gertec PPC930, D-SAT Device Manager, drivers de impressora,
  SITEF) com nome/categoria/versão. Dentro da sessão remota: escolher um
  arquivo e "Enviar pra esta máquina" (download direto bridge→loja, sem
  passar pelo PC do técnico) ou "Enviar e instalar". O catálogo de
  drivers VID/PID passa a usar essa mesma biblioteca, sem duplicar
  arquivo. Mostra espaço usado; se o disco não comportar, usa Object
  Storage da Oracle — mas SEMPRE avisando antes de trocar de backend,
  nunca troca silenciosa.
- **Pedido em**: mesma situação do item anterior — usuário relata ter
  pedido há ~2 semanas, sem registro encontrado até 2026-09-25.
- **Status**: Planejado (plano aprovado em 2026-09-25). Implementação
  ainda não iniciada.
- **Falta pra virar "Feito"**: implementar + testar upload de um arquivo
  real, "Enviar pra esta máquina" numa sessão real (ou na VM de teste), e
  confirmar (pelo log do agente/bridge) que o download foi direto pra
  máquina remota, sem passar pelo tráfego do Flutter do técnico.

## Modo manutenção (aviso na tela do caixa + progresso + bloqueio de reinício)

- **Descrição** (como o usuário descreveu agora, 2026-09-25): um "modo
  manutenção" que avisa na tela do caixa, mostra progresso, e bloqueia
  reinício.
- **Pedido em**: não informado na mensagem que trouxe este item pro
  backlog — **zero registro em git log ou código nos dois
  repositórios**, e sem detalhe suficiente ainda pra planejar (quando
  entra em modo manutenção — manual
  ou automático? o que exatamente aparece na tela do caixa — um overlay,
  uma janela? "bloqueio de reinício" impede o quê exatamente — o usuário
  de reiniciar manualmente, ou o watchdog/`sc failure` de reiniciar o
  serviço?).
- **Status**: Pendente — escopo indefinido. Preciso que o usuário
  descreva de novo antes de virar plano.

## Sidebar de Quick Actions dentro da sessão + layout estilo PC Manager + aba Ferramentas

- **Descrição**: painel lateral colapsável (estilo PC Manager) embutido
  na janela de sessão remota, reaproveitando a lógica/componente das
  Quick Actions já existente (sem duplicar), com trilho de categorias
  (Visão geral, Sistema, Impressoras e portas, Loja/PDV, Programas,
  Segurança, Histórico, Ferramentas), cards com progresso/resultado
  inline, ações de risco com borda/ícone vermelho legível. Grade grande
  "Ferramentas": abrir PowerShell/CMD admin, Gerenciador de Tarefas,
  Gerenciador de Dispositivos, Serviços, Visualizador de Eventos,
  Impressoras, Regedit, Conexões de Rede, Programas e Recursos,
  Inicialização, Opções de Energia; diagnóstico de rede (ipconfig, ping,
  Test-NetConnection, flushdns, renovar IP, reset winsock com
  confirmação, scan de rede local); ferramentas de sistema/loja (sincronia
  de hora, info de máquina/BIOS/ativação, captura de tela remota);
  ações de energia/sessão (reiniciar/desligar/modo de segurança/reinício
  agendado com confirmação, bloquear, encerrar sessão, enviar mensagem);
  produtividade ("Meus scripts", "Favoritos", busca rápida Ctrl+K).
- **Pedido em**: nesta mesma sessão, em 4 mensagens coladas seguidas,
  antes do bug do "Install driver" interromper o trabalho e redirecionar
  pro catálogo de drivers/proteção das lojas. Data exata não registrada
  em commit (a feature nunca chegou a ser implementada).
- **Status**: Pendente — especificação já detalhada (acima), mas nunca
  retomada depois da interrupção.
- **Falta pra virar "Feito"**: nem começou. Plano + implementação +
  teste visual numa sessão remota real.

## Atualização remota das lojas já instaladas (sem serviço)

- **Descrição**: todas as lojas já instaladas nunca tiveram o serviço
  do Windows de verdade (ver bug de conexão, Fix 2/Fix 3 acima) — rodam
  em modo portátil desde sempre. Depois que a bateria de testes passar
  na VM (instalação limpa), preparar um jeito de rodar o instalador novo
  **por cima** dessas máquinas via acesso remoto: sem clique nenhum,
  confirmando ao final que o serviço fica "Em execução". Testar esse
  caminho de atualização-por-cima na VM também (não só instalação limpa
  numa máquina virgem) antes de aplicar em loja real.
- **Pedido em**: 2026-09-25.
- **Status**: Pendente — aguardando a bateria de instalação limpa passar
  primeiro.
- **Falta pra virar "Feito"**: implementar o caminho de update remoto +
  testar update-por-cima na VM (não só instalação limpa) + só depois
  aplicar numa loja real.

## Watchdog de heartbeat reabre chamado a cada 4h pra dispositivo zumbi antigo

- **Descrição**: em 2026-09-25, pouco depois do watchdog de heartbeat
  (`evaluate_offline_watchdog`, parte do commit `2941d1132`) entrar em
  produção pela primeira vez, uma sequência de "alertas críticos" e
  chamados GLPI novos apareceu pra várias máquinas ao mesmo tempo.
  **Causa confirmada** (consulta direta no banco do bridge): não é um
  incidente novo — são registros de dispositivo antigos/de teste (o PC
  do próprio usuário, "fatal1ty_990fx_killer", registrado várias vezes
  ao longo da sessão; duplicatas de caixa01/caixa02/caixa06/dtmserver/
  diretoria de antes do fix de colisão de hostname, commit `bddc9aa`)
  que já estavam offline entre 16 e 403 HORAS (até 16 dias). O cooldown
  de 4h (`alert_cooldown_hours`) está funcionando certo — o problema é
  que ele nunca PARA de repetir pra um dispositivo que nunca mais volta:
  reabre chamado novo no GLPI a cada 4h, pra sempre, sem distinguir
  "ficou offline agora" de "está morto há semanas".
- **Pedido em**: 2026-09-25 (usuário pediu verificação; causa encontrada
  na mesma sessão).
- **Status**: Pendente — causa raiz confirmada, fix ainda não
  implementado (não foi pedido ainda, só o diagnóstico).
- **Fix proposto** (não implementado): parar de reabrir chamado depois
  de N repetições sem recuperação (ex.: 1-2x), ou exigir confirmação
  manual pra "silenciar"/decomissionar um dispositivo zumbi, em vez de
  cooldown puro de 4h pra sempre. Limpar os registros duplicados de
  caixa01/02/06/dtmserver/diretoria/fatal1ty_990fx_killer do banco
  (`devices`/`alerts`) separadamente, já que são lixo de teste/da
  colisão antiga, não máquinas reais monitoradas.
- **Falta pra virar "Feito"**: decidir com o usuário se implementa o fix
  proposto (ou outro) e limpa os registros zumbis.
