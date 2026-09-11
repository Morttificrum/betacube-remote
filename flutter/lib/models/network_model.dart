import 'dart:convert';

import 'package:get/get.dart';

import '../utils/http_service.dart' as http;
import 'model.dart';
import 'platform_model.dart';

/// Fase 6: controlador de rede (UniFi/Omada/Mikrotik) cadastrado por
/// loja (Entidade GLPI). Nunca carrega credenciais -- o bridge não as
/// devolve pro cliente (ver /internal/network/controllers no bridge).
class NetworkController {
  final int id;
  final int entityId;
  final String vendor;
  final String? label;
  final String baseUrl;
  final String? controllerType;
  final String? siteId;
  final double? lastSyncedAt;

  NetworkController({
    required this.id,
    required this.entityId,
    required this.vendor,
    this.label,
    required this.baseUrl,
    this.controllerType,
    this.siteId,
    this.lastSyncedAt,
  });

  factory NetworkController.fromJson(Map<String, dynamic> json) {
    return NetworkController(
      id: _asInt(json['id']) ?? 0,
      entityId: _asInt(json['entity_id']) ?? 0,
      vendor: json['vendor']?.toString() ?? '',
      label: json['label']?.toString(),
      baseUrl: json['base_url']?.toString() ?? '',
      controllerType: json['controller_type']?.toString(),
      siteId: json['site_id']?.toString(),
      lastSyncedAt: (json['last_synced_at'] as num?)?.toDouble(),
    );
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

/// Resultado de uma ação de controle (Fase 6) -- `success` reflete o
/// campo `ok`/status HTTP; `error` traz a mensagem do bridge quando falha
/// (parâmetro faltando, agente offline, chamada rejeitada pelo
/// controlador, etc.) pra mostrar direto pro técnico.
class NetworkActionResult {
  final bool success;
  final String? error;
  NetworkActionResult({required this.success, this.error});
}

/// Estado da aba "Rede" (Fase 6): controladores UniFi/Omada/Mikrotik por
/// loja, cada um com seus dispositivos/clientes e Ações Rápidas de
/// controle -- mesmo espírito da aba Equipamentos, servido pelo mesmo
/// betacube-bridge, mas fala com equipamento de rede em vez de PCs.
class NetworkModel {
  final RxList<NetworkController> controllers = <NetworkController>[].obs;
  final RxBool loading = false.obs;
  final RxString error = ''.obs;
  var pulledOnce = false;

  WeakReference<FFI> parent;

  NetworkModel(this.parent);

  Future<void> pullControllers({int? entityId}) async {
    if (loading.value) return;
    loading.value = true;
    error.value = '';
    try {
      final api = await bind.mainGetApiServer();
      if (api.isEmpty) {
        error.value = translate('Custom server not set');
        return;
      }
      final query = entityId != null ? '?entity_id=$entityId' : '';
      final resp = await http.get(Uri.parse('$api/internal/network/controllers$query'));
      if (resp.statusCode != 200) {
        error.value = 'HTTP ${resp.statusCode}';
        return;
      }
      final List list = jsonDecode(resp.body);
      controllers.value = list.map((e) => NetworkController.fromJson(e)).toList();
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
      pulledOnce = true;
    }
  }

  Future<String?> createController({
    required int entityId,
    required String vendor,
    String? label,
    required String baseUrl,
    required Map<String, dynamic> auth,
    String? controllerType,
    String? siteId,
  }) async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) return translate('Custom server not set');
    try {
      final resp = await http.post(
        Uri.parse('$api/internal/network/controllers'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'entity_id': entityId,
          'vendor': vendor,
          'label': label,
          'base_url': baseUrl,
          'auth': auth,
          'controller_type': controllerType,
          'site_id': siteId,
        }),
      );
      if (resp.statusCode != 200) {
        try {
          return jsonDecode(resp.body)['error']?.toString() ?? 'HTTP ${resp.statusCode}';
        } catch (_) {
          return 'HTTP ${resp.statusCode}';
        }
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> deleteController(int id) async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) return;
    try {
      await http.delete(Uri.parse('$api/internal/network/controllers/$id'));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listDevices(int controllerId) async {
    return _listSubresource(controllerId, 'devices');
  }

  Future<List<Map<String, dynamic>>> listClients(int controllerId) async {
    return _listSubresource(controllerId, 'clients');
  }

  Future<List<Map<String, dynamic>>> listWlans(int controllerId) async {
    return _listSubresource(controllerId, 'wlans');
  }

  Future<List<Map<String, dynamic>>> _listSubresource(int controllerId, String sub) async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) return [];
    try {
      final resp = await http.get(Uri.parse('$api/internal/network/controllers/$controllerId/$sub'));
      if (resp.statusCode != 200) return [];
      final List list = jsonDecode(resp.body);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Dispara uma ação de controle (reiniciar, PoE power-cycle, bloquear/
  /// desbloquear/kick de cliente, toggle de SSID, localizar) -- o bridge
  /// resolve o controlador, monta a chamada certa pro fabricante e a
  /// enfileira pro agente da loja executar; essa chamada só retorna
  /// depois que o bridge já sabe o resultado (timeout de 15s do lado de
  /// lá), então dá pra tratar como síncrona aqui.
  Future<NetworkActionResult> runAction(
      int controllerId, String action, Map<String, dynamic> params) async {
    final api = await bind.mainGetApiServer();
    if (api.isEmpty) {
      return NetworkActionResult(success: false, error: translate('Custom server not set'));
    }
    try {
      final resp = await http.post(
        Uri.parse('$api/internal/network/controllers/$controllerId/actions/$action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(params),
      );
      final decoded = jsonDecode(resp.body);
      if (resp.statusCode != 200) {
        return NetworkActionResult(
            success: false, error: decoded['error']?.toString() ?? 'HTTP ${resp.statusCode}');
      }
      return NetworkActionResult(success: decoded['ok'] == true);
    } catch (e) {
      return NetworkActionResult(success: false, error: e.toString());
    }
  }
}
