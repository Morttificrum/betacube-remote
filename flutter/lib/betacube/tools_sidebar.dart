import 'package:flutter/material.dart';

import '../desktop/pages/equipment_detail_dialog.dart';
import '../models/equipment_model.dart';
import '../common.dart';
import '../models/model.dart';
import 'tools_catalog.dart';
import 'tools_runner.dart';

/// Barra lateral de ferramentas dentro da janela da sessão remota (estilo Microsoft PC Manager: categorias
/// em cartões, ação em um clique, resultado inline). Módulo Beta Cube separado -- exceção aprovada ao
/// congelamento do Remote em 2026-10-16 (ver CLAUDE.md): único ponto de encaixe em `remote_page.dart`,
/// sem tocar em textura, input, rendezvous nem relay. Flutuante sobre a imagem remota (não redimensiona a
/// imagem), recolhível, e só aparece em sessão normal com máquina Windows.
class BetaCubeSessionTools extends StatefulWidget {
  final String rustdeskId;
  final String hostname;
  final bool enabled;
  const BetaCubeSessionTools({
    Key? key,
    required this.rustdeskId,
    required this.hostname,
    required this.enabled,
  }) : super(key: key);

  @override
  State<BetaCubeSessionTools> createState() => _BetaCubeSessionToolsState();
}

enum _RunState { running, done, failed }

class _ToolState {
  _RunState state;
  String message;
  int elapsed;
  _ToolState(this.state, this.message, {this.elapsed = 0});
}

class _BetaCubeSessionToolsState extends State<BetaCubeSessionTools> {
  bool _open = false;
  String? _expanded = kBetaCubeToolCategories.first.title;
  final Map<String, _ToolState> _states = {};

  static const double _panelWidth = 340;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.rustdeskId.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(alignment: Alignment.center, child: _handle(context)),
          if (_open) _panel(context),
        ],
      ),
    );
  }

  Widget _handle(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: color,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
      child: InkWell(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
        onTap: () => setState(() => _open = !_open),
        child: SizedBox(
          width: 26,
          height: 96,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_open ? Icons.chevron_right : Icons.chevron_left, color: Colors.white, size: 20),
              const SizedBox(height: 4),
              const RotatedBox(
                quarterTurns: 3,
                child: Text('Ferramentas', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 10,
      color: scheme.surface,
      child: SizedBox(
        width: _panelWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              color: scheme.primary.withOpacity(0.10),
              child: Row(
                children: [
                  Icon(Icons.handyman_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ferramentas Beta Cube', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(widget.hostname, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recolher',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _open = false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: [for (final c in kBetaCubeToolCategories) _category(context, c)],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Mais opções (painel completo)'),
                onPressed: () => showEquipmentDetailDialog(
                  context,
                  EquipmentItem(glpiId: 0, hostname: widget.hostname, rustdeskId: widget.rustdeskId, online: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _category(BuildContext context, BcCategory c) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _expanded == c.title;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = expanded ? null : c.title),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: scheme.primary.withOpacity(0.12),
                    child: Icon(c.icon, size: 17, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.note != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(c.note!, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                    ),
                  for (final t in c.tools) _tool(context, t),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tool(BuildContext context, BcTool t) {
    final scheme = Theme.of(context).colorScheme;
    final st = _states[t.id];
    final running = st?.state == _RunState.running;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              const SizedBox(width: 6),
              if (running)
                Row(children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 6),
                  Text('${st!.elapsed}s', style: const TextStyle(fontSize: 11)),
                ])
              else
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                    onPressed: () => _start(t),
                    child: const Text('Executar', style: TextStyle(fontSize: 12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(t.description, style: const TextStyle(fontSize: 11)),
          if (t.longRunning && !running && st == null)
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text('Demorado: pode levar vários minutos.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
            ),
          if (st != null && st.message.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (st.state == _RunState.failed ? Colors.red : st.state == _RunState.done ? Colors.green : Colors.blueGrey)
                    .withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: st.state == _RunState.failed ? Colors.red : st.state == _RunState.done ? Colors.green : Colors.blueGrey,
                    width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    st.state == _RunState.failed
                        ? Icons.error_outline
                        : st.state == _RunState.done
                            ? Icons.check_circle_outline
                            : Icons.hourglass_bottom,
                    size: 15,
                    color: st.state == _RunState.failed ? Colors.red : st.state == _RunState.done ? Colors.green : Colors.blueGrey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: SelectableText(st.message, style: const TextStyle(fontSize: 11))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- execução

  void _set(String id, _RunState s, String msg, {int elapsed = 0}) {
    if (!mounted) return;
    setState(() => _states[id] = _ToolState(s, msg, elapsed: elapsed));
  }

  Future<bool> _confirm(String text, {String ok = 'Confirmar'}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar ação'),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _start(BcTool t) async {
    if (t.confirm != null && !await _confirm(t.confirm!)) return;
    switch (t.kind) {
      case BcToolKind.action:
        await _runPlain(t);
        break;
      case BcToolKind.wnbVpn:
        await _runWnb(t);
        break;
      case BcToolKind.printerPicker:
        await _runPrinterPicker(t);
        break;
      case BcToolKind.driverIssues:
        await _runDriverIssues(t);
        break;
    }
  }

  Future<BcCommandResult> _exec(String toolId, String action,
      {Map<String, dynamic>? params, Duration timeout = const Duration(minutes: 4), String label = 'Executando…'}) {
    _set(toolId, _RunState.running, label);
    return bcRunCommand(
      widget.rustdeskId,
      action,
      params: params,
      timeout: timeout,
      onTick: (s) => _set(toolId, _RunState.running, label, elapsed: s),
    );
  }

  Future<void> _runPlain(BcTool t) async {
    final r = await _exec(
      t.id,
      t.action!,
      params: t.params,
      timeout: t.longRunning ? const Duration(minutes: 45) : const Duration(minutes: 4),
      label: 'Enviado à máquina; aguardando o resultado…',
    );
    _set(t.id, r.ok ? _RunState.done : _RunState.failed, bcSummarize(r));
    if (r.ok && t.offerReboot && mounted) {
      if (await _confirm('O chkdsk só roda no próximo boot. Reiniciar a máquina agora?', ok: 'Reiniciar agora')) {
        final rr = await _exec(t.id, 'reboot_now', label: 'Reiniciando…');
        _set(t.id, rr.ok ? _RunState.done : _RunState.failed,
            rr.ok ? 'Reinício enviado. A sessão vai cair e a máquina volta sozinha.' : bcSummarize(rr));
      }
    }
  }

  Future<void> _runWnb(BcTool t) async {
    final r = await _exec(t.id, 'wnb_services',
        params: t.params, timeout: const Duration(minutes: 4), label: 'Consultando os serviços WNB…');
    _set(t.id, r.ok ? _RunState.done : _RunState.failed, bcSummarize(r));
  }

  Future<void> _runPrinterPicker(BcTool t) async {
    final list = await _exec(t.id, 'list_printers', timeout: const Duration(minutes: 3), label: 'Listando impressoras…');
    if (!list.ok) {
      _set(t.id, _RunState.failed, bcSummarize(list));
      return;
    }
    final printers = bcStdoutAsList(list.data);
    if (printers.isEmpty) {
      _set(t.id, _RunState.done, 'Nenhuma impressora encontrada nesta máquina.');
      return;
    }
    if (!mounted) return;
    String? selected = printers.first['Name']?.toString();
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Resetar uma impressora'),
          content: SizedBox(
            width: 420,
            child: DropdownButton<String>(
              isExpanded: true,
              value: selected,
              items: printers
                  .map((p) => DropdownMenuItem<String>(
                        value: p['Name']?.toString(),
                        child: Text('${p['Name']}  —  ${p['DriverName']}  (${p['PortName']})', overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setD(() => selected = v),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
            ElevatedButton(onPressed: selected == null ? null : () => Navigator.of(ctx).pop(selected), child: const Text('Resetar')),
          ],
        ),
      ),
    );
    if (chosen == null) {
      _set(t.id, _RunState.done, 'Cancelado.');
      return;
    }
    if (!await _confirm('Remover a impressora "$chosen" (e o driver dela, se nenhuma outra usar)?')) {
      _set(t.id, _RunState.done, 'Cancelado.');
      return;
    }
    final r = await _exec(t.id, 'reset_printer',
        params: {'printer_name': chosen}, timeout: const Duration(minutes: 4), label: 'Resetando "$chosen"…');
    _set(t.id, r.ok ? _RunState.done : _RunState.failed, bcSummarize(r));
  }

  Future<void> _runDriverIssues(BcTool t) async {
    final r = await _exec(t.id, 'list_driver_issues', timeout: const Duration(minutes: 3), label: 'Procurando dispositivos sem driver…');
    if (!r.ok) {
      _set(t.id, _RunState.failed, bcSummarize(r));
      return;
    }
    final devices = bcStdoutAsList(r.data);
    if (devices.isEmpty) {
      _set(t.id, _RunState.done, 'Nenhum dispositivo com problema de driver encontrado.');
      return;
    }
    _set(t.id, _RunState.running, 'Consultando o catálogo da Beta Cube…');
    final catalog = <int, Map<String, dynamic>?>{};
    for (var i = 0; i < devices.length; i++) {
      final vid = devices[i]['VID']?.toString();
      final pid = devices[i]['PID']?.toString();
      if (vid != null && vid.isNotEmpty && pid != null && pid.isNotEmpty) {
        catalog[i] = await gFFI.equipmentModel.lookupDriverCatalog(vid, pid);
      }
    }
    if (!mounted) return;
    _set(t.id, _RunState.done, '${devices.length} dispositivo(s) sem driver. Escolha o que instalar na janela.');
    final pick = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dispositivos sem driver'),
        content: SizedBox(
          width: 460,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: devices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = devices[i];
              final name = d['FriendlyName']?.toString() ?? 'Dispositivo desconhecido';
              final vid = d['VID']?.toString();
              final pid = d['PID']?.toString();
              final hasIds = vid != null && vid.isNotEmpty && pid != null && pid.isNotEmpty;
              final cat = catalog[i];
              final cdc = name.toUpperCase().contains('CDC') || name.toUpperCase().contains('ACM');
              Widget? action;
              if (cat != null) {
                action = ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop({
                    'action': 'install_catalog_driver',
                    'params': {'filename': cat['driver_filename']},
                    'label': 'Instalar ${cat['device_name']}',
                  }),
                  child: const Text('Instalar'),
                );
              } else if (cdc) {
                action = ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop({'action': 'install_usbser_driver', 'label': 'Driver serial nativo (usbser)'}),
                  child: const Text('Usar nativo'),
                );
              } else if (hasIds) {
                action = OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop({'register': true}),
                  child: const Text('Cadastrar'),
                );
              }
              return ListTile(
                dense: true,
                title: Text(name),
                subtitle: Text(hasIds
                    ? (cat != null ? 'VID_$vid&PID_$pid — catálogo: ${cat['device_name']}' : 'VID_$vid&PID_$pid')
                    : 'VID/PID não identificado'),
                trailing: action,
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fechar'))],
      ),
    );
    if (pick == null) return;
    if (pick['register'] == true) {
      if (!mounted) return;
      showEquipmentDetailDialog(
        context,
        EquipmentItem(glpiId: 0, hostname: widget.hostname, rustdeskId: widget.rustdeskId, online: true),
      );
      return;
    }
    if (!await _confirm('${pick['label']}? O driver será instalado nesta máquina.')) return;
    final ri = await _exec(t.id, pick['action'] as String,
        params: pick['params'] as Map<String, dynamic>?, timeout: const Duration(minutes: 10), label: '${pick['label']}…');
    _set(t.id, ri.ok ? _RunState.done : _RunState.failed, bcSummarize(ri));
  }
}
