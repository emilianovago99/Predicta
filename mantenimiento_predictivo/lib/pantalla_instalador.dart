import 'package:flutter/material.dart';
import 'workspace.dart';

// Compatibility entry for integrations that import the old installer screen.
class PantallaInstalador extends StatelessWidget {
  const PantallaInstalador({super.key});
  @override
  Widget build(BuildContext context) => const Workspace(user: {
    'nombre': 'Instalador', 'rol': 'instalador', 'id_empresa': 1,
  });
}
