import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../models/model.dart';
import '../../models/network_model.dart';

/// Detalhe de um controlador de rede (Fase 6): dispositivos, redes (SSID)
/// e clientes, cada um com Ações Rápidas de controle -- mesmo espírito do
/// diálogo de Equipamento, mas fala com UniFi/Omada/Mikrotik em vez de um
/// PC com o agente instalado.
void showNetworkControllerDetailDialog(BuildContext context, NetworkController controller) {
  final maxWidth = MediaQuery.of(context).size.width * 0.9;
  final dialogWidth = maxWidth < 560 ? maxWidth : 560.0;
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(controller.label?.isNotEmpty == true ? controller.label! : controller.baseUrl),
      content: SizedBox(
        width: dialogWidth,
        child: _NetworkControllerDetailBody(controller: controller),
      ),
      actions: [
        dialogButton(translate('Close'), icon: Icon(Icons.close_rounded), onPressed: close, isOutline: true),
      ],
      onCancel: close,
    );
  });
}

class _NetworkControllerDetailBody extends StatefulWidget {
  final NetworkController controller;
  const _NetworkControllerDetailBody({required this.controller});

  @override
  State<_NetworkControllerDetailBody> createState() => _NetworkControllerDetailBodyState();
}

class _NetworkControllerDetailBodyState extends State<_NetworkControllerDetailBody> {
  bool _loading = true;
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _wlans = [];
  List<Map<String, dynamic>> _clients = [];
  String? _lastActionMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final model = gFFI.networkModel;
    final results = await Future.wait([
      model.listDevices(widget.controller.id),
      model.listWlans(widget.controller.id),
      model.listClients(widget.controller.id),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _devices = results[0];
      _wlans = results[1];
      _clients = results[2];
    });
  }

  Future<void> _runAction(String action, Map<String, dynamic> params, {String? label}) async {
    final result = await gFFI.networkModel.runAction(widget.controller.id, action, params);
    if (!mounted) return;
    setState(() {
      _lastActionMessage = result.success
          ? '${label ?? action}: ${translate("done")}'
          : '${label ?? action}: ${result.error ?? translate("failed")}';
    });
  }

  void _promptPortAndRunPoe(String mac) {
    final portController = TextEditingController();
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(translate('PoE power-cycle')),
        content: TextField(
          controller: portController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: translate('Port number')),
        ),
        actions: [
          dialogButton(translate('Cancel'), onPressed: close, isOutline: true),
          dialogButton(translate('OK'), onPressed: () {
            final port = int.tryParse(portController.text.trim());
            if (port == null) return;
            close();
            _runAction('poe_power_cycle', {'mac': mac, 'port_idx': port},
                label: '${translate("PoE power-cycle")} ($mac:$port)');
          }),
        ],
        onCancel: close,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(translate('Devices'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: translate('Refresh'),
              onPressed: _load,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        if (_devices.isEmpty) Text(translate('Empty')),
        ..._devices.map(_deviceTile),
        const SizedBox(height: 12),
        Text(translate('Networks (SSID)'), style: const TextStyle(fontWeight: FontWeight.bold)),
        if (_wlans.isEmpty) Text(translate('Empty')),
        ..._wlans.map(_wlanTile),
        const SizedBox(height: 12),
        Text(translate('Connected clients'), style: const TextStyle(fontWeight: FontWeight.bold)),
        if (_clients.isEmpty) Text(translate('Empty')),
        ..._clients.map(_clientTile),
        if (_lastActionMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_lastActionMessage!, style: const TextStyle(fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }

  Widget _deviceTile(Map<String, dynamic> d) {
    final mac = d['mac']?.toString() ?? '';
    final name = d['name']?.toString();
    final model = d['model']?.toString();
    final title = (name?.isNotEmpty == true) ? name! : mac;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.router, size: 18),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text('$mac${model != null ? " · $model" : ""}', style: const TextStyle(fontSize: 11)),
      trailing: Wrap(spacing: 4, children: [
        IconButton(
          icon: const Icon(Icons.location_searching, size: 18),
          tooltip: translate('Locate'),
          onPressed: () => _runAction('set_locate', {'mac': mac, 'enabled': true},
              label: '${translate("Locate")} ($title)'),
        ),
        IconButton(
          icon: const Icon(Icons.bolt, size: 18),
          tooltip: translate('PoE power-cycle'),
          onPressed: () => _promptPortAndRunPoe(mac),
        ),
        IconButton(
          icon: const Icon(Icons.restart_alt, size: 18, color: Colors.red),
          tooltip: translate('Restart'),
          onPressed: () => deleteConfirmDialog(
              () async => await _runAction('restart', {'mac': mac}, label: '${translate("Restart")} ($title)'),
              title),
        ),
      ]),
    );
  }

  Widget _wlanTile(Map<String, dynamic> w) {
    final id = w['_id']?.toString() ?? '';
    final name = w['name']?.toString() ?? id;
    final enabled = w['enabled'] == true;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(Icons.wifi, size: 18, color: enabled ? Colors.green : Colors.grey),
      title: Text(name, style: const TextStyle(fontSize: 13)),
      trailing: Switch(
        value: enabled,
        onChanged: id.isEmpty
            ? null
            : (v) => _runAction('toggle_ssid', {'wlan_id': id, 'enabled': v}, label: '$name (SSID)'),
      ),
    );
  }

  Widget _clientTile(Map<String, dynamic> c) {
    final mac = c['mac']?.toString() ?? '';
    final name = c['hostname']?.toString() ?? c['name']?.toString();
    final title = (name?.isNotEmpty == true) ? name! : mac;
    final blocked = c['blocked'] == true;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(Icons.devices, size: 18, color: blocked ? Colors.red : null),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(mac, style: const TextStyle(fontSize: 11)),
      trailing: Wrap(spacing: 4, children: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: translate('Reconnect'),
          onPressed: () => _runAction('kick_client', {'mac': mac}, label: '${translate("Reconnect")} ($title)'),
        ),
        IconButton(
          icon: Icon(blocked ? Icons.lock_open : Icons.block, size: 18, color: blocked ? null : Colors.red),
          tooltip: translate(blocked ? 'Unblock' : 'Block'),
          onPressed: () => _runAction(
              blocked ? 'unblock_client' : 'block_client', {'mac': mac},
              label: '${translate(blocked ? "Unblock" : "Block")} ($title)'),
        ),
      ]),
    );
  }
}
