import 'package:flutter/material.dart';

/// Catálogo das ferramentas da barra lateral da sessão remota (módulo Beta Cube, exceção aprovada ao
/// congelamento do Remote em 2026-10-16 -- ver CLAUDE.md). Dados puros: nenhuma lógica de conexão aqui.
///
/// Cada ferramenta aponta para uma ação que JÁ existe em `src/quick_actions.rs` (executada pelo agente
/// da máquina remota via bridge) ou para um fluxo com escolha (impressora, driver).
enum BcToolKind {
  /// Enfileira a ação, espera o resultado e mostra inline.
  action,

  /// Lista as impressoras, o técnico escolhe uma, confirma e reseta só ela.
  printerPicker,

  /// Detecta dispositivos sem driver e oferece instalar (catálogo VID/PID / driver nativo).
  driverIssues,

  /// Reinicia/lista os serviços `WNB*` mostrando status antes e depois.
  wnbVpn,
}

class BcTool {
  final String id;
  final String label;
  final String description;
  final BcToolKind kind;
  final String? action;
  final Map<String, dynamic>? params;

  /// Texto da confirmação. `null` = não pede confirmação (só leitura ou inofensivo).
  final String? confirm;

  /// Ações demoradas (sfc/DISM): timeout maior e aviso de que leva minutos.
  final bool longRunning;

  /// Depois de concluir, oferece reiniciar a máquina (chkdsk agenda pro próximo boot).
  final bool offerReboot;

  const BcTool({
    required this.id,
    required this.label,
    required this.description,
    this.kind = BcToolKind.action,
    this.action,
    this.params,
    this.confirm,
    this.longRunning = false,
    this.offerReboot = false,
  });
}

class BcCategory {
  final String title;
  final IconData icon;
  final String? note;
  final List<BcTool> tools;
  const BcCategory({required this.title, required this.icon, required this.tools, this.note});
}

const _sitefNames = ['WNBMonitor', 'WNBTLSclient', 'WNB Monitor', 'WNB TLS Client'];

/// Etapa 1: categorias com as ações que já existiam. Etapas 2-4 (Pinpad Doctor completo, liberar espaço,
/// drivers online) entram nas categorias abaixo conforme forem entregues.
const List<BcCategory> kBetaCubeToolCategories = [
  BcCategory(
    title: 'Reparar Windows',
    icon: Icons.build_circle_outlined,
    tools: [
      BcTool(
        id: 'sfc',
        label: 'Verificar arquivos do sistema (sfc /scannow)',
        description: 'Procura e repara arquivos do Windows corrompidos. Leva vários minutos.',
        action: 'sfc_scan',
        longRunning: true,
      ),
      BcTool(
        id: 'dism',
        label: 'Reparar imagem do Windows (DISM)',
        description: 'DISM /Online /Cleanup-Image /RestoreHealth. Leva vários minutos e precisa de internet.',
        action: 'dism_restore_health',
        longRunning: true,
      ),
      BcTool(
        id: 'chkdsk',
        label: 'Verificar disco (chkdsk /r /f)',
        description: 'Agenda a verificação do disco C: para o próximo boot. Só roda depois de reiniciar a máquina.',
        action: 'chkdsk_schedule',
        confirm: 'Agendar chkdsk /r /f /b /x no disco C: para o próximo boot?',
        offerReboot: true,
      ),
    ],
  ),
  BcCategory(
    title: 'Otimizar',
    icon: Icons.speed_outlined,
    tools: [
      BcTool(
        id: 'clear_temp',
        label: 'Limpar temporários e prefetch',
        description: 'Apaga arquivos temporários e o prefetch. Não mexe em documentos.',
        action: 'clear_temp',
        confirm: 'Apagar os arquivos temporários e o prefetch desta máquina?',
      ),
    ],
  ),
  BcCategory(
    title: 'Portas COM',
    icon: Icons.usb_outlined,
    tools: [
      BcTool(
        id: 'reset_com',
        label: 'Resetar portas COM (remover COM fantasma)',
        description: 'Remove portas COM de dispositivos que não estão mais presentes e força o Windows a realocar.',
        action: 'reset_com_ports',
        confirm: 'Remover as portas COM fantasma e reconectar as presentes? Pode interromper o pinpad por instantes.',
      ),
      BcTool(
        id: 'list_usb',
        label: 'Listar dispositivos USB',
        description: 'Somente leitura: mostra os dispositivos USB presentes e o status deles.',
        action: 'list_usb_devices',
      ),
      BcTool(
        id: 'reinstall_usb',
        label: 'Reinstalar dispositivos USB',
        description: 'Desinstala o driver de todo dispositivo USB presente e deixa o Windows reinstalar.',
        action: 'reinstall_usb_devices',
        confirm: 'Reinstalar TODOS os dispositivos USB presentes? Teclado, leitor e pinpad podem sumir por instantes.',
      ),
    ],
  ),
  BcCategory(
    title: 'Rede / VPN',
    icon: Icons.vpn_lock_outlined,
    tools: [
      BcTool(
        id: 'wnb_status',
        label: 'Ver serviços WNB (status)',
        description: 'Somente leitura: lista os serviços WNB* (WNBMonitor, WNBTLSclient...) e o status de cada um.',
        kind: BcToolKind.wnbVpn,
        params: {'restart': false},
      ),
      BcTool(
        id: 'wnb_restart',
        label: 'Reiniciar VPN (WNB)',
        description: 'Reinicia WNBMonitor e WNBTLSclient (e qualquer WNB* encontrado), mostrando o status antes e depois.',
        kind: BcToolKind.wnbVpn,
        params: {'restart': true},
        confirm: 'Reiniciar os serviços da VPN (WNB)? A loja fica sem a VPN por alguns segundos.',
      ),
      BcTool(
        id: 'sitef',
        label: 'Reiniciar SITEF',
        description: 'Mesmo ciclo garantido de parar e iniciar, para os serviços WNB do SITEF.',
        action: 'restart_services',
        params: {'name_contains': _sitefNames},
        confirm: 'Reiniciar o SITEF? Vendas em andamento no caixa podem falhar.',
      ),
      BcTool(
        id: 'tomcat',
        label: 'Reiniciar Tomcat',
        description: 'Reinicia o serviço do Tomcat.',
        action: 'restart_services',
        params: {'name_contains': ['tomcat']},
        confirm: 'Reiniciar o Tomcat desta máquina?',
      ),
    ],
  ),
  BcCategory(
    title: 'Drivers',
    icon: Icons.memory_outlined,
    tools: [
      BcTool(
        id: 'driver_issues',
        label: 'Detectar dispositivos sem driver',
        description: 'Lista dispositivos com problema de driver e oferece instalar pelo catálogo da Beta Cube.',
        kind: BcToolKind.driverIssues,
      ),
    ],
  ),
  BcCategory(
    title: 'Pinpad Doctor',
    icon: Icons.credit_card_outlined,
    note: 'Etapa 1: só as peças que já existiam. O Pinpad Doctor completo vem na etapa 2.',
    tools: [
      BcTool(
        id: 'pp_usb',
        label: 'Listar dispositivos USB (pinpad)',
        description: 'Somente leitura: mostra o que está conectado, incluindo itens com erro.',
        action: 'list_usb_devices',
      ),
      BcTool(
        id: 'pp_com',
        label: 'Resetar portas COM',
        description: 'Remove COM fantasma (mesma ação da categoria Portas COM).',
        action: 'reset_com_ports',
        confirm: 'Remover as portas COM fantasma e reconectar as presentes?',
      ),
    ],
  ),
  BcCategory(
    title: 'Impressoras',
    icon: Icons.print_outlined,
    tools: [
      BcTool(
        id: 'unstick_printer',
        label: 'Destravar fila de impressão',
        description: 'Para o spooler, limpa os trabalhos travados e inicia de novo.',
        action: 'unstick_printer',
        confirm: 'Parar o spooler, limpar a fila de impressão e iniciar de novo? Todos os trabalhos pendentes serão perdidos.',
      ),
      BcTool(
        id: 'reset_printer',
        label: 'Resetar UMA impressora',
        description: 'Escolha a impressora na lista; só ela é removida (e o driver, se ninguém mais usar).',
        kind: BcToolKind.printerPicker,
      ),
      BcTool(
        id: 'reset_printers',
        label: 'Resetar TODAS as impressoras',
        description: 'Apaga spooler, filas e drivers instalados. Agressivo: use só se uma só não resolver.',
        action: 'reset_printers',
        confirm: 'Remover TODAS as impressoras e drivers desta máquina? Pinpads e impressoras da loja precisarão ser reinstalados.',
      ),
    ],
  ),
];
