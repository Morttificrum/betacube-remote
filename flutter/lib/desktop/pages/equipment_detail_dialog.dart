import 'dart:convert';

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../models/equipment_model.dart';
import '../../models/model.dart';

/// Painel de sensores + Ações Rápidas de um equipamento (Fase 3). Aberto a
/// partir de um clique na aba Equipamentos — dados vêm do betacube-bridge,
/// não do core Rust local (o device é remoto, quase nunca é a própria
/// máquina rodando este Flutter).
void showEquipmentDetailDialog(BuildContext context, EquipmentItem item) {
  // Largura responsiva -- esse diálogo agora também abre a partir da aba
  // Equipamentos no mobile (tela estreita), não só no desktop. 480 fixo
  // quebrava em celular; usa até 480 ou 90% da tela, o que for menor.
  final maxWidth = MediaQuery.of(context).size.width * 0.9;
  final dialogWidth = maxWidth < 480 ? maxWidth : 480.0;
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(item.hostname),
      content: SizedBox(
        width: dialogWidth,
        child: _EquipmentDetailBody(item: item),
      ),
      actions: [
        dialogButton(translate('Close'), icon: Icon(Icons.close_rounded), onPressed: close, isOutline: true),
      ],
      onCancel: close,
    );
  });
}

class _EquipmentDetailBody extends StatefulWidget {
  final EquipmentItem item;
  const _EquipmentDetailBody({required this.item});

  @override
  State<_EquipmentDetailBody> createState() => _EquipmentDetailBodyState();
}

class _EquipmentDetailBodyState extends State<_EquipmentDetailBody> {
  bool _loading = true;
  List<dynamic> _sensors = [];
  List<dynamic> _driverIssues = [];
  String? _lastActionMessage;

  bool _historyLoading = false;
  List<Map<String, dynamic>> _commandHistory = [];

  bool _eventsLoading = false;
  List<Map<String, dynamic>> _events = [];

  // Fase 5: placa-mãe/monitor(es)/áudio/rede via WMI, estilo AIDA64 --
  // vem no mesmo tick estendido de disk/power/windows_health.
  Map<String, dynamic>? _systemInfo;

  @override
  void initState() {
    super.initState();
    _load();
    _loadHistory();
    _loadEvents();
  }

  Future<void> _load() async {
    final data = await gFFI.equipmentModel.fetchSensors(widget.item.rustdeskId ?? '');
    if (!mounted) return;
    setState(() {
      _loading = false;
      final sensors = data?['sensors'];
      _sensors = sensors is List ? sensors : [];
      final issues = data?['driver_issues'];
      _driverIssues = issues is List ? issues : (issues == null ? [] : [issues]);
      final sysinfo = data?['system_info'];
      _systemInfo = sysinfo is Map ? Map<String, dynamic>.from(sysinfo) : null;
    });
  }

  /// Histórico de comandos (Ações Rápidas) já enviados pra essa máquina --
  /// sem isso não tinha como saber se um comando rodou de verdade sem
  /// confiar cegamente no "enviado" instantâneo.
  Future<void> _loadHistory() async {
    final rustdeskId = widget.item.rustdeskId;
    if (rustdeskId == null || rustdeskId.isEmpty) return;
    setState(() => _historyLoading = true);
    final history = await gFFI.equipmentModel.listCommands(rustdeskId);
    if (!mounted) return;
    setState(() {
      _historyLoading = false;
      _commandHistory = history;
    });
  }

  /// Log de auditoria (Fase 4): conectar/login/desconectar, transferência
  /// de arquivo com direção, e alarmes de segurança (força-bruta,
  /// whitelist de IP) -- os dados já fluíam pro bridge desde a Fase 3, só
  /// não tinha tela nenhuma usando isso ainda.
  Future<void> _loadEvents() async {
    final rustdeskId = widget.item.rustdeskId;
    if (rustdeskId == null || rustdeskId.isEmpty) return;
    setState(() => _eventsLoading = true);
    final events = await gFFI.equipmentModel.listEvents(rustdeskId);
    if (!mounted) return;
    setState(() {
      _eventsLoading = false;
      _events = events;
    });
  }

  Future<void> _runAction(String action, {Map<String, dynamic>? params, String? label}) async {
    final id = await gFFI.equipmentModel.enqueueCommand(widget.item.rustdeskId!, action, params);
    if (!mounted) return;
    setState(() {
      _lastActionMessage = id != null
          ? '${label ?? action}: ${translate("enviado, deve executar no próximo contato da máquina")}'
          : '${label ?? action}: ${translate("falha ao enviar comando")}';
    });
    // O comando novo já aparece no histórico como "pending" -- o técnico
    // pode abrir o histórico de novo depois (botão de atualizar) pra ver
    // quando virar "done"/"failed", sem precisar fechar e reabrir o painel.
    _loadHistory();
  }

  void _runSensitiveAction(String action, String label) {
    deleteConfirmDialog(() async => await _runAction(action, label: label), label);
  }

  bool _driverPickerLoading = false;

  /// "Instalar driver" (Fase 4): busca o que tem no pacote hospedado pelo
  /// bridge e deixa o técnico escolher -- ao contrário da impressora, aqui
  /// a escolha é necessária mesmo (são arquivos nomeados/distintos, não dá
  /// pra "resetar tudo" já que instalar é sempre um arquivo específico).
  Future<void> _openDriverPicker() async {
    setState(() => _driverPickerLoading = true);
    final drivers = await gFFI.equipmentModel.listDrivers();
    if (!mounted) return;
    setState(() => _driverPickerLoading = false);

    if (drivers.isEmpty) {
      setState(() => _lastActionMessage = translate('Nenhum driver disponível no pacote'));
      return;
    }

    String? selected = drivers.first['filename']?.toString();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(translate('Install driver')),
          content: DropdownButton<String>(
            isExpanded: true,
            value: selected,
            items: drivers
                .map((d) => d['filename']?.toString())
                .whereType<String>()
                .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                .toList(),
            onChanged: (v) => setDialogState(() => selected = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(translate('Cancel'))),
            TextButton(
              onPressed: selected == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      _runAction(
                        'install_driver',
                        params: {'filename': selected},
                        label: '${translate("Install driver")}: $selected',
                      );
                    },
              child: Text(translate('Apply')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.item.hasAgent) {
      return Text(translate('No Beta Cube Remote installed'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (!_loading) _buildSensors(),
        const SizedBox(height: 12),
        if (_driverIssues.isNotEmpty) _buildDriverIssues(),
        const SizedBox(height: 12),
        if (_systemInfo != null) _buildSystemInfo(),
        if (_systemInfo != null) const SizedBox(height: 12),
        Text(translate('Quick Actions'), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildActions(),
        if (_lastActionMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_lastActionMessage!, style: const TextStyle(fontStyle: FontStyle.italic)),
          ),
        const SizedBox(height: 12),
        _buildCommandHistory(),
        const SizedBox(height: 12),
        _buildEventLog(),
      ],
    );
  }

  Widget _buildCommandHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(translate('Command history'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: translate('Refresh'),
              onPressed: _historyLoading ? null : _loadHistory,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_historyLoading) const LinearProgressIndicator(),
        if (!_historyLoading && _commandHistory.isEmpty) Text(translate('Empty')),
        if (_commandHistory.isNotEmpty)
          SizedBox(
            height: 180,
            child: ListView.separated(
              itemCount: _commandHistory.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) => _commandHistoryTile(_commandHistory[i]),
            ),
          ),
      ],
    );
  }

  Widget _commandHistoryTile(Map<String, dynamic> cmd) {
    final status = cmd['status']?.toString() ?? '';
    final action = cmd['action']?.toString() ?? '';
    final createdAt = (cmd['created_at'] as num?)?.toDouble();
    Color color;
    switch (status) {
      case 'done':
        color = Colors.green;
        break;
      case 'failed':
        color = Colors.red;
        break;
      case 'sent':
        color = Colors.blue;
        break;
      default:
        color = Colors.grey;
    }
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(Icons.circle, size: 10, color: color),
      title: Text(action, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        createdAt != null ? '$status · ${_relativeTime(createdAt)}' : status,
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => _showCommandResult(cmd),
    );
  }

  String _relativeTime(double epochSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch((epochSeconds * 1000).round());
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  void _showCommandResult(Map<String, dynamic> cmd) {
    String body = translate('No result yet');
    final resultJson = cmd['result_json'] as String?;
    if (resultJson != null && resultJson.trim().isNotEmpty && resultJson.trim() != '{}') {
      try {
        final parsed = jsonDecode(resultJson) as Map<String, dynamic>;
        final buffer = StringBuffer();
        final stdout = parsed['stdout']?.toString() ?? '';
        final stderr = parsed['stderr']?.toString() ?? '';
        final error = parsed['error']?.toString() ?? '';
        if (stdout.isNotEmpty) buffer.writeln(stdout);
        if (stderr.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln('--- stderr ---');
          buffer.writeln(stderr);
        }
        if (error.isNotEmpty) buffer.writeln('Erro: $error');
        body = buffer.isEmpty ? jsonEncode(parsed) : buffer.toString();
      } catch (_) {
        body = resultJson;
      }
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${cmd['action']} (${cmd['status']})'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: SelectableText(body)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(translate('Close'))),
        ],
      ),
    );
  }

  Widget _buildEventLog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(translate('Connection log'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: translate('Refresh'),
              onPressed: _eventsLoading ? null : _loadEvents,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_eventsLoading) const LinearProgressIndicator(),
        if (!_eventsLoading && _events.isEmpty) Text(translate('Empty')),
        if (_events.isNotEmpty)
          SizedBox(
            height: 220,
            child: ListView.separated(
              itemCount: _events.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) => _eventTile(_events[i]),
            ),
          ),
      ],
    );
  }

  Widget _eventTile(Map<String, dynamic> row) {
    final type = row['type']?.toString() ?? '';
    final payload = row['payload'] is Map
        ? Map<String, dynamic>.from(row['payload'] as Map)
        : <String, dynamic>{};
    final createdAt = (row['created_at'] as num?)?.toDouble();

    IconData icon;
    Color color;
    String summary;

    switch (type) {
      case 'conn':
        final action = payload['action']?.toString();
        if (action == 'new') {
          icon = Icons.link;
          color = Colors.blue;
          final ip = payload['ip']?.toString() ?? '';
          summary = '${translate("New connection")} ($ip)';
        } else if (action == 'close') {
          icon = Icons.link_off;
          color = Colors.grey;
          summary = translate('Connection closed');
        } else {
          // Sem "action" == evento de login (ver connection.rs, ~linha 1657):
          // tem "peer" ([my_id, my_name]) em vez disso.
          icon = Icons.login;
          color = Colors.green;
          final peer = payload['peer'];
          final peerName = (peer is List && peer.length > 1) ? peer[1]?.toString() : null;
          summary = '${translate("Login")}${peerName != null && peerName.isNotEmpty ? ": $peerName" : ""}';
        }
        break;
      case 'file':
        // RemoteSend (0) = o equipamento enviou pro técnico (download);
        // RemoteReceive (1) = o técnico enviou pro equipamento (upload).
        // Ver FileAuditType/post_file_audit em connection.rs.
        final fileType = (payload['type'] as num?)?.toInt();
        final isSend = fileType == 0;
        icon = isSend ? Icons.arrow_upward : Icons.arrow_downward;
        color = isSend ? Colors.teal : Colors.indigo;
        final info = payload['info'];
        Map<String, dynamic> infoMap = {};
        if (info is String) {
          try {
            infoMap = Map<String, dynamic>.from(jsonDecode(info) as Map);
          } catch (_) {}
        } else if (info is Map) {
          infoMap = Map<String, dynamic>.from(info);
        }
        final num_ = infoMap['num']?.toString();
        summary = isSend
            ? translate('File sent to technician')
            : translate('File received from technician');
        if (num_ != null && num_ != '1') summary += ' ($num_)';
        break;
      case 'alarm':
        icon = Icons.warning_amber;
        color = Colors.red;
        final typ = (payload['typ'] as num?)?.toInt();
        const labels = {
          0: 'IP not in whitelist',
          1: 'Too many login attempts',
          2: '6 attempts within one minute',
          6: 'Too many IPv6-prefix attempts',
          7: 'Terminal OS login backoff',
        };
        summary = translate(labels[typ] ?? 'Security alarm');
        break;
      default:
        icon = Icons.circle;
        color = Colors.grey;
        summary = type;
    }

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 16, color: color),
      title: Text(summary, style: const TextStyle(fontSize: 13)),
      subtitle: createdAt != null
          ? Text(_relativeTime(createdAt), style: const TextStyle(fontSize: 11))
          : null,
    );
  }

  Widget _buildSensors() {
    if (_sensors.isEmpty) {
      return Text(translate('Empty'));
    }
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: _sensors.map((s) {
        final name = '${s['hardware']} — ${s['sensor']}';
        final type = s['sensor_type'] as String? ?? '';
        final value = s['value'];
        final unit = _unitFor(type);
        return Chip(label: Text('$name: ${_fmt(value)}$unit'));
      }).toList(),
    );
  }

  Widget _buildDriverIssues() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(translate('Driver issues'), style: const TextStyle(fontWeight: FontWeight.bold)),
        ..._driverIssues.map((d) => Text('• ${d['FriendlyName'] ?? d.toString()}')),
      ],
    );
  }

  /// Fase 5: tela de informações do sistema estilo AIDA64 (própria, via
  /// WMI -- não dá pra embutir o AIDA64 real). Completa o que já vem por
  /// outros meios (CPU/RAM/GPU/disco, já mostrados em `_buildSensors`).
  Widget _buildSystemInfo() {
    final info = _systemInfo!;
    final lines = <String>[];

    final board = info['placa_mae'];
    final boardMap = board is List && board.isNotEmpty
        ? Map<String, dynamic>.from(board.first as Map)
        : (board is Map ? Map<String, dynamic>.from(board) : null);
    if (boardMap != null) {
      final manufacturer = boardMap['Manufacturer']?.toString() ?? '';
      final product = boardMap['Product']?.toString() ?? '';
      if (manufacturer.isNotEmpty || product.isNotEmpty) {
        lines.add('${translate("Motherboard")}: $manufacturer $product'.trim());
      }
    }

    final monitors = info['monitores'];
    final monitorList = monitors is List ? monitors : (monitors is Map ? [monitors] : []);
    for (final m in monitorList) {
      final mm = Map<String, dynamic>.from(m as Map);
      final name = mm['Name']?.toString() ?? '';
      final w = mm['ScreenWidth'];
      final h = mm['ScreenHeight'];
      if (name.isNotEmpty) {
        lines.add('${translate("Monitor")}: $name${w != null && h != null ? " (${w}x$h)" : ""}');
      }
    }

    final audio = info['audio'];
    final audioList = audio is List ? audio : (audio is Map ? [audio] : []);
    for (final a in audioList) {
      final am = Map<String, dynamic>.from(a as Map);
      final name = am['Name']?.toString() ?? '';
      if (name.isNotEmpty) lines.add('${translate("Audio")}: $name');
    }

    final network = info['rede'];
    final networkList = network is List ? network : (network is Map ? [network] : []);
    for (final n in networkList) {
      final nm = Map<String, dynamic>.from(n as Map);
      final name = nm['Name']?.toString() ?? '';
      final mac = nm['MACAddress']?.toString();
      if (name.isNotEmpty) {
        lines.add('${translate("Network")}: $name${mac != null && mac.isNotEmpty ? " ($mac)" : ""}');
      }
    }

    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(translate('System information'), style: const TextStyle(fontWeight: FontWeight.bold)),
        ...lines.map((l) => Text(l, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  Widget _buildActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _actionButton('sfc_scan', 'sfc /scannow'),
        _actionButton('dism_restore_health', 'DISM RestoreHealth'),
        _actionButton('clear_temp', translate('Clear temp/prefetch')),
        _chkdskButton(),
        _actionButton('unstick_printer', translate('Unstick printer')),
        _sensitiveActionButton('reset_printers', translate('Reset printers')),
        _actionButton('reset_com_ports', translate('Reset COM ports')),
        _sensitiveActionButton('reinstall_usb_devices', translate('Reinstall USB devices')),
        _driverPickerButton(),
        _actionButton('restart_services', 'Tomcat', params: {'name_contains': ['tomcat']}),
        // Nome interno do serviço Windows nunca foi confirmado -- só o
        // Display Name (o que aparece em services.msc). Cobre os dois
        // formatos (com e sem espaço/maiúsculas) já que quick_actions.rs
        // agora casa contra Name E DisplayName.
        _actionButton('restart_services', 'SITEF',
            params: {
              'name_contains': [
                'WNBMonitor',
                'WNBTLSclient',
                'WNB Monitor',
                'WNB TLS Client'
              ]
            }),
        _actionButton('scan_processos', translate('Scan running processes')),
        _actionButton('defender_full_scan', translate('Defender full scan')),
        _sensitiveActionButton('disable_defender', '${translate("Disable")} Windows Defender'),
        _sensitiveActionButton('disable_firewall', '${translate("Disable")} Windows Firewall'),
      ],
    );
  }

  Widget _actionButton(String action, String label, {Map<String, dynamic>? params}) {
    return ElevatedButton(
      onPressed: () => _runAction(action, params: params, label: label),
      child: Text(label),
    );
  }

  Widget _driverPickerButton() {
    return ElevatedButton(
      onPressed: _driverPickerLoading ? null : _openDriverPicker,
      child: _driverPickerLoading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(translate('Install driver')),
    );
  }

  Widget _chkdskButton() {
    return ElevatedButton(
      onPressed: () async {
        await _runAction('chkdsk_schedule', label: 'chkdsk /r /f /b /x');
        if (!mounted) return;
        final reboot = await _confirmReboot();
        if (reboot == true) {
          await _runAction('reboot_now', label: translate('Restart'));
        }
      },
      child: const Text('chkdsk /r /f /b /x'),
    );
  }

  Future<bool?> _confirmReboot() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(translate('chkdsk agendado pro próximo boot')),
        content: Text(translate('Reiniciar a máquina agora, ou só deixar agendado pro próximo boot natural?')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(translate('Só agendar'))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(translate('Reiniciar agora'))),
        ],
      ),
    );
  }

  Widget _sensitiveActionButton(String action, String label) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
      onPressed: () => _runSensitiveAction(action, label),
      child: Text(label),
    );
  }

  String _unitFor(String sensorType) {
    switch (sensorType) {
      case 'Temperature':
        return '°C';
      case 'Voltage':
        return 'V';
      case 'Fan':
        return ' RPM';
      case 'Load':
        return '%';
      default:
        return '';
    }
  }

  String _fmt(dynamic value) {
    if (value is num) return value.toStringAsFixed(1);
    return value?.toString() ?? '';
  }
}
