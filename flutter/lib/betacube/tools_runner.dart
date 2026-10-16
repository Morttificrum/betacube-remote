import 'dart:convert';

import '../common.dart';
import '../models/model.dart';

/// Executor das ferramentas da barra lateral: enfileira a Ação Rápida no bridge (mesmo caminho que o
/// diálogo de Equipment já usa: `EquipmentModel.enqueueCommand`) e espera o resultado fazendo polling do
/// histórico de comandos. Só usa a API HTTP do bridge -- não toca em nada do motor de conexão.
class BcCommandResult {
  final String status; // done | failed | timeout | enqueue_failed
  final Map<String, dynamic> data;
  final String? error;
  const BcCommandResult(this.status, this.data, {this.error});

  bool get ok => status == 'done';
}

Future<BcCommandResult> bcRunCommand(
  String rustdeskId,
  String action, {
  Map<String, dynamic>? params,
  Duration timeout = const Duration(minutes: 3),
  void Function(int elapsedSeconds)? onTick,
}) async {
  final (id, enqueueError) = await gFFI.equipmentModel.enqueueCommand(rustdeskId, action, params);
  if (id == null) {
    return BcCommandResult('enqueue_failed', const {}, error: enqueueError ?? 'erro desconhecido ao enviar o comando');
  }
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    await Future.delayed(const Duration(seconds: 2));
    onTick?.call(sw.elapsed.inSeconds);
    final history = await gFFI.equipmentModel.listCommands(rustdeskId, limit: 30);
    for (final c in history) {
      if (c['id'] == id) {
        final status = c['status']?.toString();
        if (status == 'done' || status == 'failed') {
          return BcCommandResult(status!, _decode(c['result_json']));
        }
        break;
      }
    }
  }
  return BcCommandResult('timeout', const {},
      error: 'A máquina não respondeu em ${timeout.inMinutes} min -- confira o histórico de comandos (o comando continua na fila).');
}

Map<String, dynamic> _decode(dynamic raw) {
  try {
    final s = raw?.toString() ?? '';
    final v = jsonDecode(s.isEmpty ? '{}' : s);
    return v is Map ? Map<String, dynamic>.from(v) : {'stdout': v.toString()};
  } catch (_) {
    return {'stdout': raw?.toString() ?? ''};
  }
}

/// Tenta ler o `stdout` de um resultado como JSON (listas de impressoras, dispositivos etc.).
List<Map<String, dynamic>> bcStdoutAsList(Map<String, dynamic> data) {
  try {
    final stdout = data['stdout']?.toString() ?? '';
    final v = jsonDecode(stdout.isEmpty ? '[]' : stdout);
    if (v is List) return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (v is Map) return [Map<String, dynamic>.from(v)];
  } catch (_) {}
  return [];
}

String _clip(String s, [int max = 1200]) => s.length <= max ? s : '${s.substring(0, max)}…';

/// Texto curto e legível do resultado, para o cartão da ferramenta.
String bcSummarize(BcCommandResult r) {
  if (r.status == 'enqueue_failed' || r.status == 'timeout') return r.error ?? r.status;
  final d = r.data;
  if (!r.ok) {
    final err = d['error'] ?? d['stderr'] ?? d['stdout'];
    return _clip('Falhou: ${err ?? "sem detalhes"}');
  }
  if (d.containsKey('before') && d.containsKey('after')) return _summarizeServices(d);
  final lines = <String>[];
  if (d['note'] != null) lines.add(d['note'].toString());
  final stdout = (d['stdout']?.toString() ?? '').trim();
  if (stdout.isNotEmpty) lines.add(stdout);
  if (d['matched'] is List && (d['matched'] as List).isNotEmpty) {
    lines.add('Serviços: ${(d['matched'] as List).join(", ")}');
    for (final r in (d['results'] as List? ?? [])) {
      final res = r is Map ? r['result'] : null;
      final inner = res is Map ? res['stdout']?.toString() : null;
      try {
        final j = jsonDecode(inner ?? '{}');
        lines.add('${r['service']}: ${j['final_status']}${j['force_killed'] == true ? " (processo estava preso e foi encerrado)" : ""}');
      } catch (_) {}
    }
  }
  if (lines.isEmpty) lines.add('Concluído.');
  return _clip(lines.join('\n'));
}

String _summarizeServices(Map<String, dynamic> d) {
  String fmt(dynamic list) {
    if (list is! List || list.isEmpty) return '  (nenhum)';
    return list.map((s) => '  ${s['Name']}  [${s['DisplayName']}]  ${s['Status']}').join('\n');
  }

  final restart = d['restart'] == true;
  final b = StringBuffer(restart ? 'ANTES:\n' : 'Serviços WNB* encontrados:\n');
  b.write(fmt(d['before']));
  if (restart) {
    b.write('\nDEPOIS:\n${fmt(d['after'])}');
    final after = d['after'];
    if (after is List && after.isNotEmpty && after.every((s) => s['Status'] == 'Running')) {
      b.write('\nTodos em execução.');
    } else {
      b.write('\nAtenção: algum serviço NÃO está em execução.');
    }
  }
  return b.toString();
}
