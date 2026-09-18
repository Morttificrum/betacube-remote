import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/equipment_model.dart';
import '../../models/model.dart';
import 'equipment_detail_dialog.dart';

/// Sentinela pro "balde" de máquinas sem loja reconhecida (entidade não
/// atribuída, ou atribuída fora da árvore Clientes/BCTI) -- nenhuma
/// entidade real do GLPI usa id negativo.
const int _kOtherGroupId = -1;

/// Aba "Equipamentos": inventário do GLPI por entidade/cliente, cruzado com
/// o status de acesso remoto (quais máquinas já têm o Beta Cube Remote
/// rodando). Fase 1 do roadmap "app único" — ver
/// C:\Users\mortt\.claude\plans\transient-waddling-sparkle.md.
///
/// Navegação em 2 camadas (pedido de teste real, 2026-09-19): lista
/// única com todas as lojas misturadas não escala pra 28-29 lojas (150+
/// máquinas). Camada 1 mostra um botão por loja (+ qualquer entidade de
/// primeiro nível sem sub-lojas, ex. "Beta Cube Soluções em Ti" -- essa
/// continua funcionando igual, só que chegando por um clique em vez de
/// aparecer solta na lista); camada 2 é a lista filtrada de uma loja só.
class EquipmentPage extends StatefulWidget {
  const EquipmentPage({Key? key}) : super(key: key);

  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<EquipmentPage> {
  EquipmentModel get model => gFFI.equipmentModel;

  // null = mostrando a grade de lojas (camada 1).
  int? _viewingGroupId;

  @override
  void initState() {
    super.initState();
    if (!model.pulledOnce) {
      model.pull();
    }
  }

  /// "Loja" (ou qualquer entidade de 1º nível sem filhos, ex. BCTI) --
  /// exclui a raiz e qualquer entidade "passthrough" (tem filhos e é
  /// filha direta da raiz, ex. "Clientes"): essa nunca aparece como
  /// botão, seus FILHOS que aparecem.
  List<EquipmentEntity> _groups(List<EquipmentEntity> entities) {
    if (entities.isEmpty) return [];
    final root = entities.firstWhereOrNull((e) => e.parentId == null);
    final hasChildren = <int>{
      for (final e in entities)
        if (e.parentId != null) e.parentId!,
    };
    final groups = entities.where((e) {
      if (root != null && e.id == root.id) return false;
      if (root != null && e.parentId == root.id && hasChildren.contains(e.id)) {
        return false;
      }
      return true;
    }).toList();
    groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return groups;
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
          Obx(() => model.error.value.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    model.error.value,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                )),
          Expanded(
            child: Obx(() {
              final groupId = _viewingGroupId;
              if (groupId == null) {
                return _buildGroupGrid(context);
              }
              return _buildGroupList(context, groupId);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        if (_viewingGroupId != null)
          IconButton(
            tooltip: translate('Back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _viewingGroupId = null),
          ),
        Text(
          _headerTitle(),
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

  String _headerTitle() {
    final groupId = _viewingGroupId;
    if (groupId == null) return translate('Equipment');
    if (groupId == _kOtherGroupId) return translate('Other');
    final name = model.entities.firstWhereOrNull((e) => e.id == groupId)?.name;
    return name ?? translate('Equipment');
  }

  Widget _buildGroupGrid(BuildContext context) {
    final groups = _groups(model.entities);
    final groupIds = groups.map((g) => g.id).toSet();
    final counts = <int, int>{};
    var otherCount = 0;
    for (final item in model.items) {
      final eid = item.entityId;
      if (eid != null && groupIds.contains(eid)) {
        counts[eid] = (counts[eid] ?? 0) + 1;
      } else {
        otherCount++;
      }
    }
    // Nenhuma loja cadastrada ainda E nenhuma máquina sem loja -- não
    // some com a tela (senão máquina nenhuma some junto), só quando tem
    // mesmo nada pra mostrar.
    if (groups.isEmpty && otherCount == 0) {
      if (!model.loading.value) {
        return Center(child: Text(translate('Empty')));
      }
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final g in groups)
            _groupCard(
              icon: Icons.store,
              label: g.name,
              count: counts[g.id] ?? 0,
              onTap: () => setState(() => _viewingGroupId = g.id),
            ),
          if (otherCount > 0)
            _groupCard(
              icon: Icons.device_unknown,
              label: translate('Other'),
              count: otherCount,
              onTap: () => setState(() => _viewingGroupId = _kOtherGroupId),
            ),
        ],
      ),
    );
  }

  Widget _groupCard({
    required IconData icon,
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2),
              const SizedBox(height: 4),
              Text(
                count == 1 ? '1 máquina' : '$count máquinas',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupList(BuildContext context, int groupId) {
    final groups = _groups(model.entities);
    final groupIds = groups.map((g) => g.id).toSet();
    final items = model.items.where((item) {
      if (groupId == _kOtherGroupId) {
        return item.entityId == null || !groupIds.contains(item.entityId);
      }
      return item.entityId == groupId;
    }).toList();
    if (!model.loading.value && items.isEmpty) {
      return Center(child: Text(translate('Empty')));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _EquipmentRow(item: items[index]),
    );
  }
}

class _EquipmentRow extends StatelessWidget {
  final EquipmentItem item;

  const _EquipmentRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final hasAgent = item.hasAgent;
    // Não usa ListTile(onTap: ..., trailing: ElevatedButton(...)) -- os dois
    // entram na mesma arena de gestos do Flutter e o toque na linha acaba
    // sempre resolvendo pro botão do trailing, mesmo clicando fora dele.
    // Estrutura explícita (InkWell só na parte não-botão + botão separado
    // fora dele) evita essa ambiguidade.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasAgent ? () => showEquipmentDetailDialog(context, item) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.computer,
                color: !hasAgent
                    ? Theme.of(context).disabledColor
                    : (item.online ? Colors.green : Colors.grey),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.hostname),
                    Text(
                      hasAgent
                          ? (item.online ? translate('Online') : translate('Offline'))
                          : translate('No Beta Cube Remote installed'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    // "Online" só diz que o heartbeat chegou -- não que dá
                    // pra abrir sessão remota de fato. Mostra o segundo
                    // sinal só quando é conhecido E discorda do primeiro,
                    // pra não duplicar informação na linha toda vez.
                    if (hasAgent && item.reachable == false)
                      Text(
                        translate('Not reachable for remote session'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.orange),
                      ),
                  ],
                ),
              ),
              if (hasAgent)
                ElevatedButton(
                  onPressed: () => connect(context, item.rustdeskId!),
                  child: Text(translate('Connect')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
