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
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(item.hostname),
      content: SizedBox(
        width: 480,
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

  @override
  void initState() {
    super.initState();
    _load();
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

  bool _printerPickerLoading = false;

  Future<void> _runAction(String action, {Map<String, dynamic>? params, String? label}) async {
    final id = await gFFI.equipmentModel.enqueueCommand(widget.item.rustdeskId!, action, params);
    if (!mounted) return;
    setState(() {
      _lastActionMessage = id != null
          ? '${label ?? action}: ${translate("enviado, deve executar no próximo contato da máquina")}'
          : '${label ?? action}: ${translate("falha ao enviar comando")}';
    });
  }

  void _runSensitiveAction(String action, String label) {
    deleteConfirmDialog(() async => await _runAction(action, label: label), label);
  }

  /// "Destravar impressora" (parte 2): não existe driver fixo por loja, então
  /// em vez de adivinhar, lista o que está instalado agora e deixa o
  /// técnico escolher a impressora + driver antes de aplicar (set_printer_driver).
  Future<void> _openPrinterDriverPicker() async {
    final rustdeskId = widget.item.rustdeskId!;
    setState(() => _printerPickerLoading = true);
    final commandId = await gFFI.equipmentModel.enqueueCommand(rustdeskId, 'list_printer_drivers');
    if (commandId == null) {
      setState(() {
        _printerPickerLoading = false;
        _lastActionMessage = translate('falha ao enviar comando');
      });
      return;
    }
    final row = await gFFI.equipmentModel.pollCommandResult(rustdeskId, commandId);
    if (!mounted) return;
    setState(() => _printerPickerLoading = false);

    // result_json vem duas vezes serializado: a coluna do bridge guarda o
    // JSON do comando ({"stdout": ..., "stderr": ..., "exit_code": ...})
    // como STRING, e "stdout" por sua vez é a saída do
    // `ConvertTo-Json -Compress` do PowerShell, outra string JSON dentro
    // dessa.
    Map<String, dynamic>? parsed;
    try {
      final resultJson = row?['result_json'] as String?;
      if (resultJson != null && resultJson.trim().isNotEmpty) {
        final resultMap = jsonDecode(resultJson) as Map<String, dynamic>;
        final stdout = resultMap['stdout'] as String?;
        if (stdout != null && stdout.trim().isNotEmpty) {
          parsed = jsonDecode(stdout) as Map<String, dynamic>;
        }
      }
    } catch (_) {}

    if (row == null || row['status'] != 'done' || parsed == null) {
      setState(() => _lastActionMessage = translate('Não foi possível listar os drivers de impressora (sem resposta a tempo, ou a máquina está offline)'));
      return;
    }

    final drivers = (parsed['drivers'] is List ? parsed['drivers'] : [parsed['drivers']])
        .whereType<Map>()
        .map((d) => d['Name']?.toString())
        .whereType<String>()
        .toList();
    final impressoras = (parsed['impressoras'] is List ? parsed['impressoras'] : [parsed['impressoras']])
        .whereType<Map>()
        .toList();

    if (!mounted) return;
    _showPrinterDriverDialog(rustdeskId, impressoras, drivers);
  }

  void _showPrinterDriverDialog(String rustdeskId, List<Map> impressoras, List<String> drivers) {
    if (impressoras.isEmpty) {
      setState(() => _lastActionMessage = translate('Nenhuma impressora encontrada na máquina'));
      return;
    }
    String? selectedPrinter = impressoras.first['Name']?.toString();
    String? selectedDriver = drivers.isNotEmpty ? drivers.first : null;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(translate('Destravar impressora')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('Impressora')),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedPrinter,
                items: impressoras
                    .map((p) => p['Name']?.toString())
                    .whereType<String>()
                    .toSet()
                    .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedPrinter = v),
              ),
              const SizedBox(height: 12),
              Text(translate('Driver')),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedDriver,
                items: drivers
                    .toSet()
                    .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedDriver = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(translate('Cancel'))),
            TextButton(
              onPressed: selectedPrinter == null || selectedDriver == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      _runAction(
                        'set_printer_driver',
                        params: {'printer_name': selectedPrinter, 'driver_name': selectedDriver},
                        label: '${translate("Printer driver")}: $selectedPrinter -> $selectedDriver',
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
      ],
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
        _printerDriverButton(),
        _actionButton('restart_services', 'Tomcat', params: {'name_contains': ['tomcat']}),
        _actionButton('restart_services', 'SITEF', params: {'name_contains': ['WNBMonitor', 'WNBTLSclient']}),
        _sensitiveActionButton('disable_defender', 'Windows Defender'),
        _sensitiveActionButton('disable_firewall', 'Windows Firewall'),
      ],
    );
  }

  Widget _actionButton(String action, String label, {Map<String, dynamic>? params}) {
    return ElevatedButton(
      onPressed: () => _runAction(action, params: params, label: label),
      child: Text(label),
    );
  }

  Widget _printerDriverButton() {
    return ElevatedButton(
      onPressed: _printerPickerLoading ? null : _openPrinterDriverPicker,
      child: _printerPickerLoading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(translate('Choose printer driver')),
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
      child: Text('${translate("Disable")} $label'),
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
