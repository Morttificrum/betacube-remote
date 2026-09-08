import 'dart:convert';

import 'package:get/get.dart';

import '../common.dart';
import '../utils/http_service.dart' as http;
import 'model.dart';
import 'platform_model.dart';

class EquipmentEntity {
  final int id;
  final String name;

  EquipmentEntity({required this.id, required this.name});

  factory EquipmentEntity.fromJson(Map<String, dynamic> json) {
    return EquipmentEntity(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }
}

class EquipmentItem {
  final int glpiId;
  final String hostname;
  final int? entityId;
  final String? comment;
  final String? rustdeskId;
  final bool online;
  final double? lastSeenAt;

  EquipmentItem({
    required this.glpiId,
    required this.hostname,
    this.entityId,
    this.comment,
    this.rustdeskId,
    required this.online,
    this.lastSeenAt,
  });

  bool get hasAgent => rustdeskId != null && rustdeskId!.isNotEmpty;

  factory EquipmentItem.fromJson(Map<String, dynamic> json) {
    return EquipmentItem(
      glpiId: _asInt(json['glpi_id']) ?? 0,
      hostname: json['hostname']?.toString() ?? '',
      entityId: _asInt(json['entity_id']),
      comment: json['comment']?.toString(),
      rustdeskId: json['rustdesk_id']?.toString(),
      online: json['online'] == true,
      lastSeenAt: (json['last_seen_at'] as num?)?.toDouble(),
    );
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

/// Estado da aba "Equipamentos": inventário do GLPI (por entidade/cliente)
/// cruzado com o status de acesso remoto, servido pelo betacube-bridge
/// (mesmo servidor já configurado em `api-server`, ver Fase 4 do rebrand).
class EquipmentModel {
  final RxList<EquipmentEntity> entities = <EquipmentEntity>[].obs;
  final RxList<EquipmentItem> items = <EquipmentItem>[].obs;
  final Rx<int?> selectedEntityId = Rx<int?>(null);
  final RxBool loading = false.obs;
  final RxString error = ''.obs;
  var pulledOnce = false;

  WeakReference<FFI> parent;

  EquipmentModel(this.parent);

  Future<void> pull() async {
    if (loading.value) return;
    loading.value = true;
    error.value = '';
    try {
      final api = await bind.mainGetApiServer();
      if (api.isEmpty) {
        error.value = translate('Custom server not set');
        return;
      }

      if (entities.isEmpty) {
        final entitiesResp = await http.get(Uri.parse('$api/internal/entities'));
        if (entitiesResp.statusCode == 200) {
          final List list = jsonDecode(entitiesResp.body);
          entities.value = list.map((e) => EquipmentEntity.fromJson(e)).toList();
        }
      }

      final entityId = selectedEntityId.value;
      final query = entityId == null ? '' : '?entity_id=$entityId';
      final itemsResp = await http.get(Uri.parse('$api/internal/equipment$query'));
      if (itemsResp.statusCode == 200) {
        final List list = jsonDecode(itemsResp.body);
        items.value = list.map((e) => EquipmentItem.fromJson(e)).toList();
      } else {
        error.value = 'HTTP ${itemsResp.statusCode}';
      }
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
      pulledOnce = true;
    }
  }

  void selectEntity(int? entityId) {
    selectedEntityId.value = entityId;
    pull();
  }
}
