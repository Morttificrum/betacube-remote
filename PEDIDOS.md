# PEDIDOS — Beta Cube Remote

> **Regra para o Claude Code:** leia este arquivo INTEIRO no início de toda sessão neste repositório.
> Nada aqui pode ser esquecido, reinterpretado ou trocado por "versão simplificada" sem o Fernando aprovar.
> Ao concluir um item: marque `[x]`, anote a data e o commit. Ao começar: marque `[~]`.
> Item só é `[x]` depois de testado na VM Hyper-V (nunca em máquina de cliente).

Legenda: `[ ]` pendente · `[~]` em andamento · `[x]` entregue e testado

> **Este arquivo é a fonte única de verdade** (desde 2026-10-15). O antigo `BACKLOG.md` foi unificado aqui e virou só um ponteiro; o texto integral dele continua no histórico do git (commit `7c56d3c44`, `git show 7c56d3c44:BACKLOG.md`).
> Nota sobre status: onde consta "código existe, falta teste", o item continua `[ ]`/`[~]` — só vira `[x]` depois de testado na VM.

---

## ✅ DECISÃO DEFINITIVA DE ARQUITETURA (Fernando, 2026-10-15) — substitui o aviso de divergência de 2026-10-07

- **Beta Cube Remote = nosso fork, CONGELADO** na última versão que funcionava em produção com o servidor próprio. Commit/build exato do congelamento: **`9cb56871e`** (confirmado por Fernando em 2026-10-15; tag git `remote-freeze`). Contém o fix do offline `dfbe64e65` (validado na VM em 05/10) + servidor por nome. Os 4 commits de 06/10 (`39a89fef8`, `c51c0b6f3`, `34233b89c`, `dea0c43a2`) são correções de bug crítico: **rebuild + bateria completa na VM (reboot e queda de rede); se passarem, entram sem nova aprovação** — só reportar o resultado ao Fernando. Atenção: o release `betacube-build` foi sobrescrito em 07/10 e não guarda mais o binário de produção; os instaladores de 06/10 00:01 em `instaladores/` (não versionados) são o único artefato — manter cópia..
- **PROIBIDO:** sincronizar/mergear com o repositório oficial do RustDesk; adicionar qualquer função nova ao código do Remote. **Permitido no Remote só:** branding (nome, ícones, cores, textos) e correção de bug crítico, sempre testada na VM Hyper-V.
- **Nada de "RustDesk" pode aparecer para o cliente** (executável, janela, bandeja, instalador, textos, ícones, serviço do Windows). Pendências levantadas em 2026-10-15 estão na seção 2 (Branding).
- **Todas as funções Beta Cube saem do Remote** e vão para 2 programas com marca Beta Cube:
  1. **Beta Cube Agent** — serviço Windows invisível em cada máquina de loja. Base: `C:\projetos\Beta Cube Monitor` (Python).
  2. **Beta Cube Painel** — app nativo (Windows + Android, **NUNCA navegador**) com lojas/máquinas e botões rápidos que agem na máquina via Agent.
- Funções que já estão no Remote (`src/quick_actions.rs`, aba Equipment, etc.) são **portadas** para o Agent/Painel. **Só se remove do Remote depois que a versão nova estiver testada e funcionando.**
- Efeito sobre os pedidos abaixo: **nenhum pedido foi removido.** Os itens de §3 em diante (e as Quick Actions, monitoramento, drivers, rede, IA) passam a ser implementados no Agent ou no Painel, não no Remote. A frase de §0 "um único app reúne tudo" fica substituída por esta decisão (Remote + Agent + Painel). O bridge/banco/lógica de sensores-ações-GLPI são reaproveitados; o código Rust/Dart do fork serve só de referência de leitura.
- Ordem prevista (herdada do plano de 2026-10-07): Agent v1 (heartbeat/inventário) → Agent v2 (Ações Rápidas) → Painel v1 (lista + Conectar) → Painel v2 (Ações Rápidas + GLPI) → rollout nas 33 lojas, sem prazo fixo.

---
**Regra fixa de release (2026-10-06):** nenhuma versão vai pra loja sem passar nos 7 passos do checklist (`AGENTS.md`) na VM **e** no PC do Fernando, com prova de cada um: instalar por cima, 1 atalho só, serviço criado/rodando, janela abre normal com ID/senha, registro no hbbs, conexão com janela fechada, reinício e tudo volta sozinho. Fernando não testa em loja.

---

## 0. Regras de arquitetura (valem para tudo)

- [ ] Núcleo do RustDesk **congelado** na última release estável. Proibido mexer no motor (Rust/Flutter), exceto branding e servidor.
- [ ] Toda funcionalidade Beta Cube fica em módulo/agente separado (`betacube-agent`). Se o agente falhar, o acesso remoto continua funcionando.
- [ ] Tudo nativo (.exe / .apk). **Nada via navegador.** Referência de qualidade: AnyDesk / TeamViewer.
- [ ] Um único app reúne tudo: acesso remoto, gestão de equipamentos, clientes/lojas, monitoramento, drivers, ferramentas. *(Substituído em 2026-10-15 pela decisão definitiva: Remote congelado + Beta Cube Agent + Beta Cube Painel — ver topo. Item mantido para registro.)*
- [ ] Commit após cada etapa testada.
- [~] Nas máquinas das lojas o Remote roda em segundo plano, como serviço; o funcionário não consegue finalizar.
  - Status (BACKLOG): "Proteção das lojas", pedida 2026-09-24, em andamento. Implementado no commit `2941d1132`: `preset-note` (nome da loja) suprime janela/bandeja; `sc failure` reduzido de 60s/60s/300s para 5s/5s/5s; serviço avisa o bridge no shutdown nativo do Windows (`/api/shutdown_notice`); watchdog de heartbeat do bridge (`evaluate_offline_watchdog`) só alerta se não houver aviso de shutdown mais recente que o último heartbeat.
  - Falta para `[x]`: testar de verdade (a) matar o processo no Gerenciador de Tarefas e confirmar que volta em segundos, (b) confirmar visualmente que não aparece janela/ícone numa máquina com `STORE_NAME`, (c) confirmar que desligamento normal não dispara alerta. Nenhum dos 3 foi testado ainda.

## 1. Estabilidade (prioridade máxima)

- [x] **Máquina fica offline e não volta sozinha** (ex.: após reiniciar, ícone na bandeja mas "computador remoto está offline"). Já voltou depois de correções. Precisa de solução definitiva + teste de reboot na VM.
  - **Entregue e testado em 2026-10-05, commit final `dfbe64e65`.** Bateria na VM `BetaCubeTeste`: 5 reinícios + queda/volta de rede, zero clique, serviço registrou sozinho no hbbs nos 6 checkpoints (`rendezvous_reachable=1` confirmado de fora a cada um). Os 32 instaladores de loja foram regenerados com esse binário (`instaladores/`). Pedido original: 2026-09-24 (caixa01, loja Itaquera, só recuperado via AnyDesk).
  - Causas raiz encontradas (em ordem): retry do serviço não relançava sem sessão de console ativa e falha de lançamento era engolida em silêncio (`0ded43a68`, + watchdog por Tarefa Agendada SYSTEM a cada 1 min); instalador chamava `--install` e esperava clique humano → `--silent-install` (`34618275f`); `sc create/start/stop/delete/failure` sem aspas em `{app_name}` — com o espaço de "Beta Cube Remote", **o serviço nunca foi criado em nenhuma instalação desde o rebrand** (`755fcb214`); config (server/key/preset-note) escrita no perfil de quem roda o instalador, mas o serviço roda como LocalService com perfil próprio → caía no servidor público e nunca registrava no hbbs (`7190de524`); reinstalar por cima não reiniciava o processo, ACL do LocalService, e cache em memória do `Config` (`dfbe64e65`: staging em `C:\ProgramData\Beta Cube Remote\config` + `icacls` + `Config::set_option`).
  - Investigação de rede encerrada (2026-09-26): rede/firewall Oracle (UDP 21116) não era o problema.
  - Próximo passo registrado: Fernando instala loja por loja no dia a dia. Loja já atualizada = aparece **online na aba Equipment com a janela fechada**; loja antiga só aparece online com a janela aberta. Só as 4 lojas Itaquera, Vila-Guilherme, Pinheiro-e-Pinheiro e Isabela-FCO chegaram a mandar heartbeat até 2026-10-02; as outras 29 nunca registraram.
- [~] Tela branca no client.
  - BACKLOG (2026-10-06/07): causa achada, **não era bug de código novo** — a proteção das lojas (`preset-note` não-vazio ⇒ nunca mostra janela, `flutter/lib/main.dart`, commit `2941d1132`) deixava a janela nativa vazia visível porque o Dart fazia só `return` sem esconder a janela. Fix `dea0c43a2` (`windowManager.ensureInitialized()` + `hide()` antes do `return`). O instalador `TesteVM` usado no teste tinha `STORE_NAME` setado, o que contradizia a própria feature. Também corrigidos: `stop-service='Y'` preso que pulava a criação do serviço em reinstalação (`39a89fef8`) e atalho duplicado no Menu Iniciar (`SetShellVarContext all` no NSIS, `34233b89c`).
  - Falta: rebuild (~45 min, inclui Dart), rodar os 7 passos do checklist na VM e no PC do Fernando, e só depois regenerar os 32 instaladores de loja (3ª vez). Não confirmado como `[x]`.

## 2. Branding

- [ ] Whitelabel completo: nome, ícones, splash, textos internos (não só o instalador).
  - Paleta da marca (memória, 2026-09-08): blocos do logo `#A6371A`/`#2E8B2A`/`#E8881F`/`#1E50D2`; acento do site `#22D3EE` sobre `#070B16`; no app `MyTheme.accent`→`#22D3EE` e `ColorScheme.primary`→`#1E50D2` (`flutter/lib/common.dart`). Já feito em jul–set/2026: pubspec, strings de UI/About/título da janela, 50 arquivos `src/lang/*.rs`, ícone gerado de `res/icon-source-1024.png` para todas as plataformas (`logo.svg`/`icon.svg` têm a marca como imagem raster dentro de SVG, não vetor redesenhado; o wordmark do `logo-header.svg` virou `<text>` por instrução do Fernando).
  - Deliberadamente NÃO tocado (2026-09): `MyTheme.button` (`#2C8CFF`), link azul isolado do chat, empacotamento Linux, iOS `AppIcon`, `applicationId com.carriez.flutter_hbb` do Android. Decisão de 2026-10-15: nada de "RustDesk" visível ao cliente (ver topo).
- [ ] Aplicar o ícone oficial (grade de 4 quadrados nas cores da marca + círculo ciano com cursor) em todas as plataformas.
- [ ] Aparência profissional: o cliente deve sentir que é um produto da Beta Cube, "não um programa aleatório".

## 3. Acesso e permissões

- [ ] Várias senhas simultâneas por máquina (~5), cada uma com nível de permissão (controle total, só visualização, admin, RH...).
- [ ] Build Android (.apk) para acessar as lojas pelo celular (prioridade: equipe de 3-4 pessoas em campo).
- [ ] iOS (por último).
  - Divergência registrada: a memória de 2026-09-08 anotava iOS como fora de escopo ("sem distribuição iOS"); este pedido mantém iOS "por último". Fernando confirma qual vale.

## 4. Gestão de equipamentos / clientes

- [ ] Aba de gestão de equipamentos dentro do Remote, puxando do GLPI (via betacube-bridge).
- [ ] Separação visual por cliente/loja (Entidades do GLPI).
- [ ] Instalador por loja: digita o nome da loja uma vez e as máquinas se registram agrupadas (Servidor, Caixa 01, 02...).
  - Estado real: existe instalador por loja gerado via `makensis /DSTORE_NAME=...` (`scripts/gerar-instalador-loja.ps1`; `STORE_NAME` vira `preset-note` usado para criar/associar a Entidade no GLPI); 32 instaladores em `instaladores/` regenerados em 2026-10-06. Mas o nome da loja é fixado na geração do .exe, não digitado no instalador. Não marcado `[x]` por isso e por falta de teste de agrupamento.
- [ ] Fase 2: instalação em cascata (instala no servidor e se espalha pela rede da loja).

## 5. Ferramentas na sessão (Quick Actions)

- [ ] Quick Actions também como **sidebar dentro da janela da sessão remota** (não só na aba Equipment).
  - Estado real: só existe um item de menu "Quick Actions" na toolbar da sessão (`flutter/lib/common/widgets/toolbar.dart`) que abre o mesmo diálogo da aba Equipment. A sidebar em si **não começou**.
  - Especificação do BACKLOG (preservar): painel lateral colapsável estilo PC Manager, embutido na janela da sessão, reaproveitando a lógica/componente das Quick Actions existente (sem duplicar), com trilho de categorias (Visão geral, Sistema, Impressoras e portas, Loja/PDV, Programas, Segurança, Histórico, Ferramentas), cards com progresso/resultado inline, ações de risco com borda/ícone vermelho legível.
  - Grade "Ferramentas": abrir PowerShell/CMD admin, Gerenciador de Tarefas, Gerenciador de Dispositivos, Serviços, Visualizador de Eventos, Impressoras, Regedit, Conexões de Rede, Programas e Recursos, Inicialização, Opções de Energia. Diagnóstico de rede (ipconfig, ping, Test-NetConnection, flushdns, renovar IP, reset winsock com confirmação, scan de rede local). Sistema/loja (sincronia de hora, info de máquina/BIOS/ativação, captura de tela remota). Energia/sessão (reiniciar/desligar/modo de segurança/reinício agendado com confirmação, bloquear, encerrar sessão, enviar mensagem). Produtividade ("Meus scripts", "Favoritos", busca rápida Ctrl+K).
  - Pedido em sessão anterior a 2026-09-24 (4 mensagens seguidas), interrompido pelo bug do "Install driver"; nunca retomado.
- [ ] Organizadas no estilo **Microsoft PC Manager** (categorias + aba Ferramentas). (ver especificação acima)
- [ ] Atalhos de PowerShell/CMD como admin com reparos comuns: `sfc /scannow`, `DISM`, `chkdsk`.
  - Estado real: `sfc_scan`, `dism_restore_health`, `chkdsk_schedule` (agenda para o próximo boot), `clear_temp` existem em `src/quick_actions.rs` e têm botões em `equipment_detail_dialog.dart`. Falta o atalho de PowerShell/CMD admin em si e teste na VM.
- [ ] Destravar impressora: listar os drivers instalados na hora e o técnico escolhe (sem driver fixo; lojas usam HP, Epson, Canon...).
- [ ] Porta COM, Tomcat, SITEF, Defender (já existentes: revisar e manter).
- [~] Dispositivo sem driver (ex.: "CDC ACM Comm"): detectar e resolver rápido.
  - BACKLOG "Catálogo de drivers por VID/PID (v1)", pedido 2026-09-24, em andamento. "Install driver" lista dispositivos com problema (VID/PID), consulta catálogo no bridge, instala com 1 clique se conhecido, oferece driver nativo (usbser) para CDC/ACM genérico e permite cadastrar aparelho desconhecido na hora (nome + .inf/.zip). Implementado: cliente `2941d1132`, bridge `e24a059` (`/internal/driver_catalog`, respondendo HTTP 200). Caso de teste combinado: CDC ACM Comm do caixa01, loja Itaquera.
  - Falta para `[x]`: **nunca testado contra o dispositivo real nem outro dispositivo de verdade** (na VM, só por simulação).
- [ ] Problemas de VPN/monitor de rede nas lojas: quick action específica (detalhar com o Fernando).

### 5.0 Especificação "Pinpad Gertec" vinda do BACKLOG (2026-10-06, "especificação final", não iniciada)

> Esta spec (procedimento real da loja J&L, 2 caixas com pinpad parado) foi pedida antes do caso CAIXA 06 de 5.1. **As duas coexistem — nenhuma foi removida; Fernando decide se/como unificar.**

- [ ] **Botão 1 — "Diagnóstico do caixa"** (100% somente leitura): portas COM (`Get-PnpDevice -Class Ports`) destacando fantasmas (status Unknown) e qual COM é o Gertec PIN Pad PPC; driver Gertec instalado + versão (Driver/WebAPI/DLL/Serial Manager); serviço "WNB Monitor" existe/rodando?; Driver Booster (ou similar) instalado?; Windows Update bloqueado para drivers? (`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\ExcludeWUDriversInQualityUpdate = 1`).
- [ ] **Botão 2 — "Corrigir pinpad"**: (a) instala driver Gertec (Gertec-Full-Installer 2.2.2.0, da biblioteca de arquivos; flag silenciosa se houver, senão abre o instalador); (b) remove portas COM fantasma (`pnputil /remove-device` nas de status Unknown); (c) limpa `ComDB` (mesma chave acima), SEMPRE com backup do valor antes; (d) reinicia serviço "WNB Monitor"; (e) mostra em qual COM o pinpad ficou, com opção de forçar uma COM específica (a que o PDV da loja espera).
- [ ] **Botão 3 — "Blindar caixa"** (pede confirmação): bloqueia Windows Update de atualizar drivers (chave acima); desinstala Driver Booster e similares; registra no inventário que a máquina foi blindada.
- [ ] Regras: Diagnóstico não altera nada. Corrigir e Blindar mostram a lista EXATA do que vão fazer ANTES e só executam passo a passo, com confirmação a cada passo. Todo valor alterado (ComDB, registro) tem backup automático com opção de desfazer. Toda ação gera log; ações que apagam/desinstalam pedem confirmação explícita.
- [ ] Método de teste: Fernando não tem bancada com pinpad físico nem testa em máquina de cliente — simular tudo na VM (portas COM virtuais fantasma, serviço falso "WNB Monitor", Driver Booster instalado de verdade, bloqueio do Windows Update aplicado de verdade). Hardware físico do pinpad fica sem teste real até a loja.
- Estado real do código: existem soltos `list_usb_devices`, `reset_com_ports`, `reinstall_usb_devices`, `install_catalog_driver`, `restart_services` (Tomcat/SITEF/TCServer). Nada de diagnóstico Gertec, ComDB, WNB Monitor, Driver Booster ou Blindar.

### 5.1 Pinpad Doctor (caso real resolvido em 15/10/2026, CAIXA 06)

Cada etapa mostra o resultado; nada destrutivo roda sem confirmação.

- [ ] Listar dispositivos USB presentes, destacar Gertec (`VID_1753`) e itens com Status Error.
- [ ] Listar drivers Gertec no DriverStore (`Get-WindowsDriver -Online`, ProviderName Gertec).
- [ ] Testar abertura das portas COM; se ocupada, mostrar qual processo segura (`handle64.exe -a Serial`).
- [ ] Detectar `EPSON_Port_Communication_Service` (PCSVC.exe) segurando COM e oferecer desativar + finalizar.
- [ ] Achar todos os `CliSiTef.ini` (`dir C:\CliSiTef*.ini /s /b`), mostrar `Porta=` e oferecer trocar para `AUTO_USB` (com backup `.bak`). Caso real: versão nova do caixa veio com `Porta=COM3`, que era a impressora Epson.
- [ ] "Limpeza total Gertec": programas, serviço, dispositivos (`pnputil /remove-device`), drivers (`pnputil /delete-driver /uninstall`), pastas e registro.
- [ ] Monitor de USB ao vivo (mostra conectar/desconectar em tempo real).

## 6. Monitoramento (absorver o BetaCube Monitor, Windows primeiro)

- [ ] Sensores: temperatura CPU/GPU/HD, voltagens, RPM de cooler (base: LibreHardwareMonitor).
- [ ] Saúde do disco (SMART) e da memória RAM.
- [ ] Drivers desatualizados/faltando.
- [ ] Saúde geral do Windows (`windows_health.py` do Monitor): erros críticos do Event Log nas últimas 24 h; serviços críticos parados (wuauserv, WinDefend, Dnscache, BITS, EventLog, RpcSs); atualizações pendentes; uptime; disco com menos de 10% livre.
- [ ] Detecção de problemas elétricos.
- [ ] Antivírus em camadas: Defender → CIRCL → MalwareBazaar → VirusTotal. Só alerta, nunca apaga.
- [ ] Alertas só quando algo precisa de atenção (sem "tudo OK" no Telegram).
- [ ] Log de conexões/transferências em tempo real (estilo "Status de Conexões FTP" do Arius: timestamp, evento, seta de direção).

## 7. Drivers e arquivos

- [ ] **Biblioteca de arquivos própria** ("tipo um FTP"): instaladores/drivers usados sempre (ex.: Gertec PPC930) prontos para enviar à máquina da loja. *Pedido há semanas, ainda não entregue.*
  - Detalhe do BACKLOG (plano aprovado em 2026-09-25, implementação não iniciada; pedido original ~2026-09-11 sem registro em commit): área no bridge para subir instaladores/drivers de uso frequente (Gertec PPC930, D-SAT Device Manager, drivers de impressora, SITEF) com nome/categoria/versão. Dentro da sessão remota: escolher arquivo e "Enviar pra esta máquina" (download direto bridge→loja, sem passar pelo PC do técnico) ou "Enviar e instalar". O catálogo VID/PID passa a usar essa mesma biblioteca, sem duplicar arquivo. Mostra espaço usado; se o disco não comportar, usa Object Storage da Oracle — **sempre avisando antes de trocar de backend, nunca troca silenciosa**.
  - Falta para `[x]`: implementar + testar upload de arquivo real + "Enviar pra esta máquina" em sessão real/VM + confirmar pelo log que o download foi direto para a máquina remota.
- [ ] **Dispositivos protegidos + ponto de restauração + verificação de porta COM** (BACKLOG, plano aprovado 2026-09-25, não iniciado; pedido ~2026-09-11 sem registro): o instalador de drivers nunca atualiza sozinho SAT, impressora fiscal/térmica, pinpad (Gertec etc.), balança ou placa de rede — aparecem como "protegido" e só atualizam com confirmação item a item. Ponto de restauração antes de qualquer instalação (decisão fechada: se falhar, BLOQUEIA a instalação, com botão explícito "Prosseguir sem ponto de restauração"). Depois, confere se a porta COM de cada dispositivo continua a mesma (antes/depois). Objetivo: substituir dependência de ferramentas de terceiro tipo SDI. Falta para `[x]`: implementar + testar em dispositivo protegido (ou placa de rede da VM) + `Get-ComputerRestorePoint` mostrando o ponto.
- [ ] Detector/instalador de drivers próprio (busca online), com cuidados para não instalar driver errado.

## 8. Rede

- [ ] Integração UniFi / Omada / Mikrotik com **controle real**: reiniciar AP/switch, ligar/desligar porta PoE, bloquear cliente, ligar/desligar SSID.
- [ ] Equipamentos Gertec de rede (busca-preço): ver e mudar IP remotamente.

## 9. Assistente de IA (lado técnico apenas)

- [ ] Chat dentro do client com contexto da máquina (sensores, erros de driver, histórico GLPI). Só orienta/sugere, não executa sozinho.

## 10. Itens vindos do BACKLOG.md (não estavam no PEDIDOS original; nada removido)

- [ ] **GLPI automático por sessão** (pedido 2026-10-06, prioridade alta, não iniciado): toda sessão de acesso remoto abre/atualiza um chamado na entidade da loja, com máquina, horário de início/fim e as Ações Rápidas executadas; Fernando só completa descrição/solução no final. Hoje nada vai para o GLPI automaticamente. Motivo da urgência: AnyDesk grátis impõe espera de 100 s por acesso; quanto antes as lojas migrarem, mais rápido o AnyDesk é abandonado.
- [ ] **Reformulação dos alertas de offline** (bridge, pedida 2026-10-06, não iniciada; teste obrigatório com dados simulados, nunca direto em lojas reais). Alertas atuais são inúteis (repetem a cada 4h, uma mensagem por máquina, duplicados). Lógica final (a 2ª mensagem supera as regras de frequência da 1ª):
  1. Agrupa por LOJA (entidade/preset-note), não por máquina.
  2. Uma máquina offline e o resto da loja online = problema real: UM alerta + abre chamado no GLPI da loja daquela máquina.
  3. Loja inteira cai junto (janela de poucos minutos): dentro do horário de fechamento = silêncio; fora = UM alerta "Loja X inteira offline — possível queda de internet/energia".
  4. Aprende o padrão de liga/desliga de cada máquina pelo histórico (2-3 semanas de heartbeat) e só alerta quando foge do padrão (ex.: caiu no meio do expediente); loja que nunca desliga à noite continua vigiada. Sem histórico suficiente, usa só as regras 2, 3 (fechamento padrão 22h–7h) e 5.
  5. Aviso de desligamento normal do Windows nunca gera alerta (já existe, manter).
  6. Servidor da loja (ex.: dtmserver) tem prioridade: cai com o resto da loja ligado ⇒ alerta na hora.
  7. Quando a máquina/loja volta: UM aviso "voltou" (não um por máquina se foi queda da loja inteira).
  - Ações adicionais, independentes: **duplicados** (fatal1ty e dtmserver alertam 2x — reinstalação cria `rustdesk_id` novo e o registro antigo do mesmo hostname/loja fica esquecido: juntar/arquivar e limpar os existentes); **marcação "não monitorar"** por máquina (`betacubeteste` e `fatal1ty_990fx_killer` nunca alertam); **GLPI**: `caixa02`, `caixa06` e `diretoria` aparecem na entidade raiz "Beta Cube Soluções em TI" em vez da loja certa — confirmar a loja e corrigir o vínculo.
- [ ] **Watchdog de heartbeat reabre chamado a cada 4h para dispositivo zumbi** (diagnóstico 2026-09-25, causa confirmada, fix NÃO implementado): o cooldown de 4h (`alert_cooldown_hours`) funciona, mas nunca para para dispositivo que não volta (registros antigos/de teste offline de 16 a 403 h: `fatal1ty_990fx_killer`, duplicatas de caixa01/02/06/dtmserver/diretoria anteriores ao fix de colisão `bddc9aa`). Fix proposto: parar de reabrir após N repetições sem recuperação (1-2x) ou exigir confirmação manual para silenciar/decomissionar; limpar separadamente esses registros do banco (`devices`/`alerts`). Falta decidir com Fernando.
- [ ] **Atualização remota das lojas já instaladas** (pedido 2026-09-25): as lojas antigas rodam em modo portátil, sem serviço. Preparar jeito de rodar o instalador novo **por cima**, via acesso remoto, sem clique, confirmando no final que o serviço fica "Em execução"; testar update-por-cima na VM (não só instalação limpa) antes de qualquer loja real. Aguardava a bateria de instalação limpa (que passou em 2026-10-05) — liberado para começar.
- [ ] **Modo manutenção** (pedido em 2026-09-25, escopo indefinido): avisa na tela do caixa, mostra progresso e bloqueia reinício. Precisa Fernando redescrever antes de virar plano: manual ou automático? overlay ou janela? "bloqueio de reinício" impede o usuário de reiniciar, ou o watchdog/`sc failure` de reiniciar o serviço?
- [x] **Migração IP → nome do servidor** (2026-10-06): `remote.betacube.com.br` (A record, DNS only na Cloudflare; UDP não passa pelo proxy) aponta para o IP atual da VM Oracle (Ephemeral); `installer/betacube-installer.nsi` usa o nome (commit `9cb56871e`); `ops/check-ip-and-update-dns.sh` no cron da VM (a cada 5 min) detecta mudança de IP, atualiza o DNS e avisa no Telegram — testado quebrando o DNS de propósito. Validado na VM `BetaCubeTeste` (registra no hbbs pelo nome) antes de regenerar os 32 instaladores.
- [x] **Cert TLS do helpdesk vencido + 500 na aba Equipment** (incidente 2026-10-01/02): cert renovado via acme.sh com auto-renovação (cron do `opc`, 4x/dia; válido até 2026-11-29); `/internal/equipment` do bridge cai para a lista local se o GLPI falhar (header `X-Glpi-Status: degraded`); alerta de expiração de cert (`ops/check-cert-expiry.sh`, cron diário 08:00, ≤14 dias). kdump desabilitado na VM Oracle (`crashkernel=no` via `grubby`) → RAM utilizável 498 Mi → 945 Mi. **Regra: nunca rodar `dnf` na VM Oracle do GLPI/RustDesk nem na da RH-360** (travou a VM por OOM).
  - `manage.betacube.com.br` (MeshCentral): obsoleto, desativado em 2026-10-02.

## 11. Como tem que funcionar — Agent, Painel, instalador único e troca nas lojas (Fernando, 2026-10-15)

**Requisitos (todos `[ ]`, nenhum removido ou simplificado):**

- [ ] Tudo é `.exe` instalado com instalador Beta Cube, igual AnyDesk. **Nada de Python/script visível** na máquina da loja.
- [ ] **Beta Cube Agent:** linguagem que gere `.exe`/serviço Windows nativo **sem falso positivo de antivírus** (evitar PyInstaller; avaliar C#/.NET ou Rust). **Portar** a lógica do Beta Cube Monitor (`C:\projetos\Beta Cube Monitor`: `hardware_monitor.py`, `disk_health.py`, `power_health.py`, `windows_health.py`, `security_scanner.py`, `windows_defender_scan.py`, `diagnostico.py`, `system_maintenance.py`, `agendador.py`, `telegram_bot.py`) — **não reescrever a regra de negócio do zero**.
- [ ] **UM instalador por loja** (evolução de `scripts/gerar-instalador-loja.ps1`): instala Beta Cube Remote + Agent juntos, com o nome da loja embutido; registra a máquina no GLPI agrupada na loja (Servidor, Caixa 01, Caixa 02...). **Instalação silenciosa, sem perguntar nada ao funcionário.**
- [ ] **Painel (Windows + Android nativos):** lista por loja > máquina mostrando nome da loja, nome da máquina, se é servidor, online/offline e saúde. Ao abrir um acesso, **nome da loja e da máquina ficam visíveis na janela** do acesso.
- [ ] **Plano de troca nas lojas** sem perder acesso a nenhuma máquina no meio do caminho (abaixo).

**Plano de troca (ordem proposta — a aprovar pelo Fernando):**
0. Congelar o Remote no commit confirmado (topo do arquivo) e fechar o branding sem "RustDesk" (§2). Testar tudo na VM Hyper-V, incluindo atualização por cima de uma instalação antiga.
1. **Etapa aditiva (zero risco de perder acesso):** instalar só o Agent ao lado do Remote que já está na loja. Não toca no Remote nem no AnyDesk. Conferir heartbeat/inventário no bridge e no Painel. Se o Agent falhar, o acesso remoto continua como estava.
2. **Piloto:** uma loja pequena, uma máquina por vez, com o AnyDesk de reserva ainda instalado e a máquina vista pelo Painel antes de começar.
3. **Troca do Remote por cima** (instalador novo da loja sobre o antigo), só em máquina que já tem Agent respondendo e acesso de reserva ativo. Ordem dentro da loja: caixas primeiro, **servidor por último**; nunca duas máquinas da mesma loja ao mesmo tempo. Aceite por máquina: online com a janela fechada, reinício, serviço volta sozinho.
4. **Rollback:** o instalador/versão anterior de cada loja fica guardado; se a máquina não voltar online em poucos minutos, o Agent (ou a tarefa de watchdog) reverte, e o AnyDesk de reserva cobre o intervalo.
5. **Só depois** de todas as lojas migradas e validadas: remover AnyDesk de reserva e, por fim, remover as funções Beta Cube do código do Remote (regra do topo: só após a versão nova testada).
6. **29 das 33 lojas nunca receberam o Remote** (Fernando parou de instalar por causa de problemas nas primeiras instalações). Para elas **não há troca: é instalação limpa com o instalador único (Remote + Agent juntos)**. Só as 4 lojas Itaquera, Vila-Guilherme, Pinheiro-e-Pinheiro e Isabela-FCO tiveram o Remote antigo e seguem o plano de troca acima.
7. **Bloqueio antes de qualquer loja nova:** Fernando exige (a) saber qual foi o problema das primeiras instalações e (b) confirmação de que está resolvido **e testado na VM**. Causas registradas no histórico (ver relatório de 2026-10-15): instalador esperando clique (`--install`), serviço nunca criado (`sc` sem aspas), config no perfil errado (nunca registrava no hbbs), reinstalação por cima sem reiniciar, atalho duplicado, `stop-service` preso e janela vazia em máquina de loja. As quatro primeiras estão validadas na VM; as três últimas dependem da bateria do rebuild. **Nenhuma loja nova até Fernando aprovar o relatório.**

## 12. Itens e decisões trazidos da memória do Claude (2026-10-15)

Fonte: `C:\Users\Morttificarum\.claude-antigo\projects\C--Users-mortt\memory\` (project_betacube_remote_rebrand, project_betacube_bridge, project_betacube_monitor_prototype, reference_betacube_vm). Regras de trabalho foram para o `CLAUDE.md`.

- [ ] **Bug "tela remota parece com o Magnifier/zoom ativo"** (reportado 2026-09-17, nunca investigado): ao conectar numa máquina pelo Beta Cube Remote, a tela remota às vezes aparece como se o Magnifier do Windows estivesse ligado, difícil de clicar com precisão. Desconhecido se é DPI/escala, modo de captura errado ou Magnifier realmente ligado na máquina remota.
- [ ] **Quick Action para aplicar o `sc failure` em máquinas já instaladas, sem reinstalar** (backlog não urgente, 2026-09-17): a correção de recuperação automática do serviço (`sc failure reset=86400 actions=restart/...`) só protege máquinas depois de reinstalar; precisa chegar à frota existente remotamente. (Os tempos hoje são 5s/5s/5s desde `2941d1132`.)
- [ ] **Monitorar o próprio bridge** (anotado como "Not yet done" em 2026-09-08): hoje só há `restart: always` no compose; falta monitoramento/alerta do serviço do bridge em si.
- [ ] **Fase 5 do plano original — dashboard (PyQt) no Beta Cube Monitor** consumindo `GET /internal/devices` e `/internal/events` do bridge (já implementados): nunca iniciada; **substituída pela decisão de 2026-10-15** (o Painel nativo Windows + Android faz esse papel). Mantida aqui para registro.
- [ ] **URL base do GLPI com IP antigo** (achado lateral de 2026-09-08, não corrigido, não bloqueante): os `links` das respostas da API do GLPI ainda usam `137.131.223.246`; é a configuração "URL base" (Configurar > Geral), independente do IP real da VM.
- [ ] **Alerta crítico do bridge (`ENABLE_CRITICAL_ALERTS`)** nasceu desligado por padrão (só servidor, cooldown de 4 h, Telegram + chamado GLPI). Decidir quando ligar, junto com a reformulação dos alertas da seção 10.
- [ ] **Chave do VirusTotal** do `betacube_config.ini` do Monitor (hoje sem uso na stack nova): só reaproveitar quando começar a fase do antivírus em camadas (seção 6); nunca versionar.
- **Decisões de arquitetura herdadas (valem para o Agent/Painel):**
  - O **GLPI é a fonte da verdade** de quais máquinas existem e de qual loja são; **sem banco paralelo de dispositivos**. O bridge cria o Computer na entidade padrão no primeiro contato e depois só atualiza o campo `comment` (resumo de sensores + SO/CPU/memória), sem sobrescrever `entities_id`.
  - Os sensores concentram o estado atual num resumo de uma linha no GLPI (temperaturas, vida do disco, ventoinha, com data/hora), não um histórico.
  - Controle de rede (UniFi/Omada/Mikrotik) por **proxy via o agente da própria loja** (o bridge não alcança a LAN); credenciais cifradas em repouso. Estado: implementado nos 3 fabricantes, com inventário NetworkEquipment no GLPI (2026-09-17), ainda sem tela comprovada no Painel.
  - Alvos de plataforma do produto: Windows, macOS e Android (Linux e iOS por último/fora de foco, ver seção 3).
  - A GUI do Remote só é o app que o Fernando opera; MeshCentral/painéis web não são usados por ele (regra no `CLAUDE.md`).