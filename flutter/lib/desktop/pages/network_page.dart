import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../models/equipment_model.dart';
import '../../models/model.dart';
import '../../models/network_model.dart';
import 'network_controller_detail_dialog.dart';

/// Aba "Rede" (Fase 6): controle direto de UniFi/Omada/Mikrotik das lojas
/// -- reiniciar AP, bloquear cliente, ligar/desligar SSID, sem precisar
/// abrir o app do fabricante. Ver plano da Fase 6 em
/// C:\Users\mortt\.claude\plans\transient-waddling-sparkle.md.
class NetworkPage extends StatefulWidget {
  const NetworkPage({Key? key}) : super(key: key);

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  NetworkModel get model => gFFI.networkModel;
  EquipmentModel get equipmentModel => gFFI.equipmentModel;
  int? _selectedEntityId;

  @override
  void initState() {
    super.initState();
    if (!equipmentModel.pulledOnce) {
      // Reaproveita a lista de Entidades GLPI já usada na aba
      // Equipamentos -- é o mesmo agrupamento por loja, não faz sentido
      // buscar de novo com outro código.
      equipmentModel.pull();
    }
    if (!model.pulledOnce) {
      model.pullControllers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          _buildEntityFilter(context),
          const SizedBox(height: 8),
          Obx(() => model.error.value.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    model.error.value,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                )),
          Expanded(child: _buildList(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Text(
          translate('Network'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 12),
        Obx(() => model.loading.value
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const SizedBox.shrink()),
        const Spacer(),
        IconButton(
          tooltip: translate('New controller'),
          icon: const Icon(Icons.add),
          onPressed: () => _showAddControllerDialog(context),
        ),
        IconButton(
          tooltip: translate('Refresh'),
          icon: const Icon(Icons.refresh),
          onPressed: () => model.pullControllers(entityId: _selectedEntityId),
        ),
      ],
    );
  }

  Widget _buildEntityFilter(BuildContext context) {
    return Obx(() {
      final entities = equipmentModel.entities;
      if (entities.isEmpty) return const SizedBox.shrink();
      return Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(translate('All')),
            selected: _selectedEntityId == null,
            onSelected: (_) {
              setState(() => _selectedEntityId = null);
              model.pullControllers();
            },
          ),
          ...entities.map((e) => ChoiceChip(
                label: Text(e.name),
                selected: _selectedEntityId == e.id,
                onSelected: (_) {
                  setState(() => _selectedEntityId = e.id);
                  model.pullControllers(entityId: e.id);
                },
              )),
        ],
      );
    });
  }

  Widget _buildList(BuildContext context) {
    return Obx(() {
      final items = model.controllers;
      if (!model.loading.value && items.isEmpty) {
        return Center(child: Text(translate('Empty')));
      }
      return ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final c = items[index];
          final entityName = equipmentModel.entities
              .firstWhereOrNull((e) => e.id == c.entityId)
              ?.name;
          return ListTile(
            leading: const Icon(Icons.router),
            title: Text(c.label?.isNotEmpty == true ? c.label! : c.baseUrl),
            subtitle: Text(
                '${c.vendor.toUpperCase()}${entityName != null ? " · $entityName" : ""} · ${c.baseUrl}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: translate('Remove'),
              onPressed: () => deleteConfirmDialog(() async {
                await model.deleteController(c.id);
                model.pullControllers(entityId: _selectedEntityId);
              }, c.label ?? c.baseUrl),
            ),
            onTap: () => showNetworkControllerDetailDialog(context, c),
          );
        },
      );
    });
  }

  // Tipo de controller por vendor -- Omada usa OAuth2 (Client ID/Secret +
  // Omadac ID, gerados uma vez em Global View > Settings > Platform
  // Integration > Open API dentro do próprio controller), UniFi/Mikrotik
  // usam usuário/senha comuns. Ver plano da Fase 6 pra detalhe completo.
  static const Map<String, List<MapEntry<String, String>>> _controllerTypesByVendor = {
    'unifi': [
      MapEntry('self-hosted', 'Self-hosted (Network Application)'),
      MapEntry('unifi-os', 'UniFi OS (UDM/UDM-Pro/Cloud Key)'),
    ],
    'omada': [
      MapEntry('omada-local', 'Local/hardware controller'),
      MapEntry('omada-cloud', 'Cloud-Based Controller (tier Standard)'),
    ],
    'mikrotik': [
      MapEntry('mikrotik', 'RouterOS (REST, v7.1+)'),
    ],
  };

  void _showAddControllerDialog(BuildContext context) {
    final entities = equipmentModel.entities;
    int? entityId = _selectedEntityId ?? (entities.isNotEmpty ? entities.first.id : null);
    String vendor = 'unifi';
    String controllerType = _controllerTypesByVendor[vendor]!.first.key;
    final labelController = TextEditingController();
    final baseUrlController = TextEditingController();
    final siteController = TextEditingController(text: 'default');
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final clientIdController = TextEditingController();
    final clientSecretController = TextEditingController();
    final omadacIdController = TextEditingController();
    String? errorText;

    gFFI.dialogManager.show((setState, close, context) {
      final isOmada = vendor == 'omada';
      return CustomAlertDialog(
        title: Text(translate('New network controller')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: entityId,
                  decoration: InputDecoration(labelText: translate('Store (GLPI Entity)')),
                  items: entities
                      .map((e) => DropdownMenuItem(value: e.id, child: Text(e.name)))
                      .toList(),
                  onChanged: (v) => setState(() => entityId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: vendor,
                  decoration: InputDecoration(labelText: translate('Vendor')),
                  items: const [
                    DropdownMenuItem(value: 'unifi', child: Text('UniFi')),
                    DropdownMenuItem(value: 'omada', child: Text('Omada')),
                    DropdownMenuItem(value: 'mikrotik', child: Text('Mikrotik')),
                  ],
                  onChanged: (v) => setState(() {
                    vendor = v ?? 'unifi';
                    controllerType = _controllerTypesByVendor[vendor]!.first.key;
                  }),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: controllerType,
                  decoration: InputDecoration(labelText: translate('Controller type')),
                  items: _controllerTypesByVendor[vendor]!
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => controllerType = v ?? controllerType),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: labelController,
                  decoration: InputDecoration(labelText: translate('Label (optional)')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: baseUrlController,
                  decoration: const InputDecoration(
                      labelText: 'Base URL', hintText: 'https://192.168.1.10:8443'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: siteController,
                  decoration: InputDecoration(labelText: translate('Site ID')),
                ),
                const SizedBox(height: 8),
                // Omada: OAuth2 Client Credentials (gerado dentro do
                // próprio controller). UniFi/Mikrotik: usuário/senha.
                if (isOmada) ...[
                  TextField(
                    controller: clientIdController,
                    decoration: const InputDecoration(labelText: 'Client ID'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: clientSecretController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Client Secret'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: omadacIdController,
                    decoration: const InputDecoration(labelText: 'Omadac ID'),
                  ),
                ] else ...[
                  TextField(
                    controller: usernameController,
                    decoration: InputDecoration(labelText: translate('Username')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(labelText: translate('Password')),
                  ),
                ],
                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(errorText!, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          dialogButton(translate('Cancel'), onPressed: close, isOutline: true),
          dialogButton(translate('OK'), onPressed: () async {
            final Map<String, dynamic> auth = isOmada
                ? {
                    'client_id': clientIdController.text.trim(),
                    'client_secret': clientSecretController.text.trim(),
                    'omadac_id': omadacIdController.text.trim(),
                  }
                : {
                    'username': usernameController.text.trim(),
                    'password': passwordController.text,
                  };
            final authIncomplete = auth.values.any((v) => (v as String).isEmpty);
            if (entityId == null || baseUrlController.text.trim().isEmpty || authIncomplete) {
              setState(() => errorText = translate('Preencha todos os campos obrigatórios'));
              return;
            }
            final err = await model.createController(
              entityId: entityId!,
              vendor: vendor,
              label: labelController.text.trim().isEmpty ? null : labelController.text.trim(),
              baseUrl: baseUrlController.text.trim(),
              auth: auth,
              controllerType: controllerType,
              siteId: siteController.text.trim().isEmpty ? null : siteController.text.trim(),
            );
            if (err != null) {
              setState(() => errorText = err);
              return;
            }
            close();
            await model.pullControllers(entityId: _selectedEntityId);
          }),
        ],
        onCancel: close,
      );
    });
  }
}
