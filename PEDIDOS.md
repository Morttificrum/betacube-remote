# PEDIDOS — Beta Cube Remote

> **Regra para o Claude Code:** leia este arquivo INTEIRO no início de toda sessão neste repositório.
> Nada aqui pode ser esquecido, reinterpretado ou trocado por "versão simplificada" sem o Fernando aprovar.
> Ao concluir um item: marque `[x]`, anote a data e o commit. Ao começar: marque `[~]`.
> Item só é `[x]` depois de testado na VM Hyper-V (nunca em máquina de cliente).

Legenda: `[ ]` pendente · `[~]` em andamento · `[x]` entregue e testado

---

## 0. Regras de arquitetura (valem para tudo)

- [ ] Núcleo do RustDesk **congelado** na última release estável. Proibido mexer no motor (Rust/Flutter), exceto branding e servidor.
- [ ] Toda funcionalidade Beta Cube fica em módulo/agente separado (`betacube-agent`). Se o agente falhar, o acesso remoto continua funcionando.
- [ ] Tudo nativo (.exe / .apk). **Nada via navegador.** Referência de qualidade: AnyDesk / TeamViewer.
- [ ] Um único app reúne tudo: acesso remoto, gestão de equipamentos, clientes/lojas, monitoramento, drivers, ferramentas.
- [ ] Commit após cada etapa testada.
- [ ] Nas máquinas das lojas o Remote roda em segundo plano, como serviço; o funcionário não consegue finalizar.

## 1. Estabilidade (prioridade máxima)

- [ ] **Máquina fica offline e não volta sozinha** (ex.: após reiniciar, ícone na bandeja mas "computador remoto está offline"). Já voltou depois de correções. Precisa de solução definitiva + teste de reboot na VM.
- [ ] Tela branca no client.

## 2. Branding

- [ ] Whitelabel completo: nome, ícones, splash, textos internos (não só o instalador).
- [ ] Aplicar o ícone oficial (grade de 4 quadrados nas cores da marca + círculo ciano com cursor) em todas as plataformas.
- [ ] Aparência profissional: o cliente deve sentir que é um produto da Beta Cube, "não um programa aleatório".

## 3. Acesso e permissões

- [ ] Várias senhas simultâneas por máquina (~5), cada uma com nível de permissão (controle total, só visualização, admin, RH...).
- [ ] Build Android (.apk) para acessar as lojas pelo celular (prioridade: equipe de 3-4 pessoas em campo).
- [ ] iOS (por último).

## 4. Gestão de equipamentos / clientes

- [ ] Aba de gestão de equipamentos dentro do Remote, puxando do GLPI (via betacube-bridge).
- [ ] Separação visual por cliente/loja (Entidades do GLPI).
- [ ] Instalador por loja: digita o nome da loja uma vez e as máquinas se registram agrupadas (Servidor, Caixa 01, 02...).
- [ ] Fase 2: instalação em cascata (instala no servidor e se espalha pela rede da loja).

## 5. Ferramentas na sessão (Quick Actions)

- [ ] Quick Actions também como **sidebar dentro da janela da sessão remota** (não só na aba Equipment).
- [ ] Organizadas no estilo **Microsoft PC Manager** (categorias + aba Ferramentas).
- [ ] Atalhos de PowerShell/CMD como admin com reparos comuns: `sfc /scannow`, `DISM`, `chkdsk`.
- [ ] Destravar impressora: listar os drivers instalados na hora e o técnico escolhe (sem driver fixo; lojas usam HP, Epson, Canon...).
- [ ] Porta COM, Tomcat, SITEF, Defender (já existentes: revisar e manter).
- [ ] Dispositivo sem driver (ex.: "CDC ACM Comm"): detectar e resolver rápido.
- [ ] Problemas de VPN/monitor de rede nas lojas: quick action específica (detalhar com o Fernando).

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
- [ ] Detecção de problemas elétricos.
- [ ] Antivírus em camadas: Defender → CIRCL → MalwareBazaar → VirusTotal. Só alerta, nunca apaga.
- [ ] Alertas só quando algo precisa de atenção (sem "tudo OK" no Telegram).
- [ ] Log de conexões/transferências em tempo real (estilo "Status de Conexões FTP" do Arius: timestamp, evento, seta de direção).

## 7. Drivers e arquivos

- [ ] **Biblioteca de arquivos própria** ("tipo um FTP"): instaladores/drivers usados sempre (ex.: Gertec PPC930) prontos para enviar à máquina da loja. *Pedido há semanas, ainda não entregue.*
- [ ] Detector/instalador de drivers próprio (busca online), com cuidados para não instalar driver errado.

## 8. Rede

- [ ] Integração UniFi / Omada / Mikrotik com **controle real**: reiniciar AP/switch, ligar/desligar porta PoE, bloquear cliente, ligar/desligar SSID.
- [ ] Equipamentos Gertec de rede (busca-preço): ver e mudar IP remotamente.

## 9. Assistente de IA (lado técnico apenas)

- [ ] Chat dentro do client com contexto da máquina (sensores, erros de driver, histórico GLPI). Só orienta/sugere, não executa sozinho.
