import 'package:flutter/material.dart';

import '../../common.dart';
import '../../desktop/pages/equipment_page.dart' as desktop;
import 'home_page.dart';

/// Wrapper mobile da aba Equipamentos -- a implementação real
/// (`desktop.EquipmentPage`) já é widgets Material puros sobre um model
/// (`EquipmentModel`) multiplataforma, sem nada desktop-only; só faltava
/// o registro na navegação do celular (ver home_page.dart::initPages).
class MobileEquipmentPage extends StatelessWidget implements PageShape {
  MobileEquipmentPage({Key? key}) : super(key: key);

  @override
  final title = translate("Equipment");

  @override
  final icon = const Icon(Icons.dns_outlined);

  @override
  final appBarActions = <Widget>[];

  @override
  Widget build(BuildContext context) => const desktop.EquipmentPage();
}
