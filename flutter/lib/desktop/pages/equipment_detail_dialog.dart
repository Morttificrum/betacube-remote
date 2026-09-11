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

  @override
  void initState() {
    super.initState();
    _load();
    _loadHistory();
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
        _driverPickerButton(),
        _actionButton('restart_services', 'Tomcat', params: {'name_contains': ['tomcat']}),
        _actionButton('restart_services', 'SITEF', params: {'name_contains': ['WNBMonitor', 'WNBTLSclient']}),
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
