import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/equipment_model.dart';
import '../../models/model.dart';
import 'equipment_detail_dialog.dart';

/// Aba "Equipamentos": inventário do GLPI por entidade/cliente, cruzado com
/// o status de acesso remoto (quais máquinas já têm o Beta Cube Remote
/// rodando). Fase 1 do roadmap "app único" — ver
/// C:\Users\mortt\.claude\plans\transient-waddling-sparkle.md.
class EquipmentPage extends StatefulWidget {
  const EquipmentPage({Key? key}) : super(key: key);

  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<EquipmentPage> {
  EquipmentModel get model => gFFI.equipmentModel;

  @override
  void initState() {
    super.initState();
    if (!model.pulledOnce) {
      model.pull();
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
          translate('Equipment'),
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
          tooltip: translate('Refresh'),
          icon: const Icon(Icons.refresh),
          onPressed: () => model.pull(),
        ),
      ],
    );
  }

  Widget _buildEntityFilter(BuildContext context) {
    return Obx(() {
      final entities = model.entities;
      if (entities.isEmpty) return const SizedBox.shrink();
      return Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(translate('All')),
            selected: model.selectedEntityId.value == null,
            onSelected: (_) => model.selectEntity(null),
          ),
          ...entities.map((e) => ChoiceChip(
                label: Text(e.name),
                selected: model.selectedEntityId.value == e.id,
                onSelected: (_) => model.selectEntity(e.id),
              )),
        ],
      );
    });
  }

  Widget _buildList(BuildContext context) {
    return Obx(() {
      final items = model.items;
      if (!model.loading.value && items.isEmpty) {
        return Center(child: Text(translate('Empty')));
      }
      return ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _EquipmentRow(item: items[index]),
      );
    });
  }
}

class _EquipmentRow extends StatelessWidget {
  final EquipmentItem item;

  const _EquipmentRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final hasAgent = item.hasAgent;
    return ListTile(
      leading: Icon(
        Icons.computer,
        color: !hasAgent
            ? Theme.of(context).disabledColor
            : (item.online ? Colors.green : Colors.grey),
      ),
      title: Text(item.hostname),
      subtitle: Text(
        hasAgent
            ? (item.online ? translate('Online') : translate('Offline'))
            : translate('No Beta Cube Remote installed'),
      ),
      trailing: hasAgent
          ? ElevatedButton(
              onPressed: () => connect(context, item.rustdeskId!),
              child: Text(translate('Connect')),
            )
          : null,
      onTap: hasAgent ? () => showEquipmentDetailDialog(context, item) : null,
    );
  }
}
