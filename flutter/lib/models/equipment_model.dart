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
  // Sinal DIFERENTE de `online`: heartbeat chegando no bridge não implica
  // que o servidor de ID/rendezvous do RustDesk considere a máquina
  // alcançável pra sessão remota (o que decide se o botão Conectar
  // funciona) -- ver item 3, teste real nas lojas 2026-09-11. null =
  // cliente ainda não reporta isso (versão antiga), não "com problema".
  final bool? reachable;

  EquipmentItem({
    required this.glpiId,
    required this.hostname,
    this.entityId,
    this.comment,
    this.rustdeskId,
    required this.online,
    this.lastSeenAt,
    this.reachable,
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
      reachable: json['reachable'] is bool ? json['reachable'] as bool : null,
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

  /// Sensores/drivers do device (Fase 3) — devolve null se o bridge não
  /// tiver nada ainda (device sem agente, ou ainda não relatou sensores).
  Future<Map<String, dynamic>?> fetchSensors(String rustdeskId) async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) return null;
    try {
      final resp = await http.get(Uri.parse('$api/internal/devices/$rustdeskId/sensors'));
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Lista os instaladores de driver disponíveis no pacote hospedado pelo
  /// bridge (Fase 4) — devolve [] em caso de erro, nunca null (o botão
  /// que chama isso já trata lista vazia como "nada disponível").
  Future<List<Map<String, dynamic>>> listDrivers() async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) return [];
    try {
      final resp = await http.get(Uri.parse('$api/internal/drivers'));
      if (resp.statusCode != 200) return [];
      final List list = jsonDecode(resp.body);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Histórico de Ações Rápidas já enfileiradas pro device (mais recente
  /// primeiro) -- pra saber se um comando realmente rodou e o que
  /// aconteceu, sem precisar confiar cegamente no "enviado" instantâneo.
  Future<List<Map<String, dynamic>>> listCommands(String rustdeskId, {int limit = 20}) async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) return [];
    try {
      final resp = await http.get(Uri.parse('$api/internal/commands?rustdesk_id=$rustdeskId&limit=$limit'));
      if (resp.statusCode != 200) return [];
      final List list = jsonDecode(resp.body);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Log de auditoria de conexão (Fase 4) -- conectar/login/desconectar
  /// (type="conn"), transferência de arquivo com direção (type="file") e
  /// violações de segurança tipo força-bruta/whitelist (type="alarm").
  /// `payload_json` vem como string -- decodificado aqui, não no bridge,
  /// pra manter o endpoint genérico (mesmo dado bruto que fica no banco).
  Future<List<Map<String, dynamic>>> listEvents(String rustdeskId, {int limit = 100}) async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) return [];
    try {
      final resp = await http.get(Uri.parse('$api/internal/events?rustdesk_id=$rustdeskId&limit=$limit'));
      if (resp.statusCode != 200) return [];
      final List list = jsonDecode(resp.body);
      return list.map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        try {
          row['payload'] = jsonDecode(row['payload_json'] as String? ?? '{}');
        } catch (_) {
          row['payload'] = {};
        }
        return row;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Enfileira uma Ação Rápida pro device — executa no próximo contato
  /// (heartbeat) da máquina com o bridge, não é instantâneo. Devolve o id
  /// do comando, ou null se não deu pra enfileirar.
  Future<int?> enqueueCommand(String rustdeskId, String action, [Map<String, dynamic>? params]) async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) return null;
    try {
      final resp = await http.post(
        Uri.parse('$api/internal/commands'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'rustdesk_id': rustdeskId, 'action': action, 'params': params ?? {}}),
      );
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return _asInt(body['id']);
    } catch (_) {
      return null;
    }
  }
}
