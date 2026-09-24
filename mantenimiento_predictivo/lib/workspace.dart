import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'config/api_config.dart';
import 'services/api.dart';
import 'ui/design.dart';
import 'pantalla_monitoreo.dart';
import 'machine_setup.dart';

const sensorLabels = {
  'temp': 'Temperatura del motor', 'temp_amb': 'Temperatura ambiente',
  'vib': 'Vibración', 'volt': 'Voltaje', 'vel': 'Velocidad', 'hum': 'Humedad',
};

class Workspace extends StatefulWidget {
  final Map<String, dynamic> user;
  const Workspace({super.key, required this.user});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  Map<String, dynamic>? company, area;
  List<dynamic> items = [];
  bool loading = true;
  String? error;
  String query = '';
  final search = TextEditingController();
  int generation = 0;
  Timer? timer;
  bool areasTreeExpanded = true;
  bool treeLoading = false;
  List<dynamic> treeAreas = [];
  final Map<int, List<dynamic>> treeMachines = {};
  final Set<int> expandedTreeAreas = {};
  final Set<String> updatingTreeMachines = {};
  int? alertsAreaId;
  int lastAreaAlertId = 0;
  bool areaAlertsInitialized = false;
  bool pollingAreaAlerts = false;
  String? activeMachineId;
  bool get installer => widget.user['rol'] == 'instalador';
  bool get canEdit => widget.user['rol'] != 'participante';
  int get level => company == null ? 0 : area == null ? 1 : 2;
  String get title => ['Empresas', 'Áreas de trabajo', 'Máquinas'][level];
  String get singular => ['empresa', 'área', 'máquina'][level];

  @override
  void initState() {
    super.initState();
    if (!installer) company = {'id_empresa': widget.user['id_empresa'], 'nombre': widget.user['empresa_nombre']};
    load();
    if (company != null) loadTreeAreas();
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (level == 2 && !loading) {
        load(silent: true);
        pollAreaAlerts();
      }
    });
  }
  @override
  void dispose() { timer?.cancel(); search.dispose(); super.dispose(); }

  Future<void> load({bool silent = false}) async {
    final request = ++generation;
    if (!silent) setState(() { loading = true; error = null; });
    final path = level == 0 ? '/api/empresas' : level == 1 ? '/api/empresas/${company!['id_empresa']}/areas' : '/api/areas/${area!['id_area']}/maquinas';
    try {
      final result = await Api.request(path);
      if (!mounted || request != generation) return;
      setState(() { items = result as List; loading = false; error = null; });
    } catch (e) {
      if (mounted && request == generation) setState(() { error = e.toString(); loading = false; });
    }
  }

  void navigate(int target, [Map<String, dynamic>? value]) {
    setState(() {
      activeMachineId = null;
      if (target == 0) {
        company = null; area = null; treeAreas = []; treeMachines.clear(); expandedTreeAreas.clear();
        resetAreaAlerts();
      }
      if (target == 1) {
        final previousCompany = company?['id_empresa'];
        company = value ?? company; area = null;
        resetAreaAlerts();
        if (previousCompany != company?['id_empresa']) {
          treeAreas = []; treeMachines.clear(); expandedTreeAreas.clear();
        }
      }
      if (target == 2) {
        final nextAreaId = value?['id_area'] as int?;
        if (area?['id_area'] != nextAreaId) resetAreaAlerts(nextAreaId);
        area = value;
      }
      items = []; query = ''; search.clear();
    });
    load();
    if (target == 1 && company != null) loadTreeAreas();
    if (target == 2) pollAreaAlerts();
  }

  void resetAreaAlerts([int? areaId]) {
    alertsAreaId = areaId;
    lastAreaAlertId = 0;
    areaAlertsInitialized = false;
  }

  Future<void> pollAreaAlerts() async {
    final selectedAreaId = area?['id_area'];
    if (selectedAreaId is! int || pollingAreaAlerts) return;
    if (alertsAreaId != selectedAreaId) resetAreaAlerts(selectedAreaId);
    pollingAreaAlerts = true;
    try {
      final result = await Api.request('/api/areas/$selectedAreaId/alertas?after_id=$lastAreaAlertId') as List;
      if (!mounted || area?['id_area'] != selectedAreaId) return;
      if (result.isEmpty) {
        areaAlertsInitialized = true;
        return;
      }
      final alerts = result.map((item) => Map<String, dynamic>.from(item)).toList();
      final newestId = alerts.map((item) => (item['id_alerta'] as num).toInt()).reduce((a, b) => a > b ? a : b);
      if (!areaAlertsInitialized) {
        lastAreaAlertId = newestId;
        areaAlertsInitialized = true;
        return;
      }
      lastAreaAlertId = newestId;
      for (final alert in alerts) {
        showAreaAlert(alert);
      }
    } catch (_) {
      // La actualización general del área ya comunica problemas de conexión.
    } finally {
      pollingAreaAlerts = false;
    }
  }

  void showAreaAlert(Map<String, dynamic> alert) {
    final type = alert['tipo']?.toString() ?? 'predictivo';
    final color = type == 'critico' ? Colors.red.shade800
      : type == 'evento' ? Colors.deepPurple.shade700 : Colors.orange.shade800;
    final machineId = alert['id_maquina'].toString();
    final machineName = alert['maquina_nombre']?.toString() ?? machineId;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      backgroundColor: color, behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      showCloseIcon: true, closeIconColor: Colors.white,
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${type.toUpperCase()} · $machineName ($machineId)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 3),
        Text(alert['diagnostico']?.toString() ?? 'Se detectó una alerta.', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
      ]),
      action: SnackBarAction(
        label: 'VER MÁQUINA', textColor: Colors.white,
        onPressed: () => openTreeMachine({'id_maquina': machineId, 'nombre': machineName}),
      ),
    ));
  }

  Future<void> loadTreeAreas() async {
    final selectedCompany = company?['id_empresa'];
    if (selectedCompany == null || treeLoading) return;
    setState(() => treeLoading = true);
    try {
      final result = await Api.request('/api/empresas/$selectedCompany/areas');
      if (!mounted || company?['id_empresa'] != selectedCompany) return;
      setState(() => treeAreas = result as List);
    } catch (_) {
      // La vista principal muestra los errores de red; el árbol puede reintentarse.
    } finally {
      if (mounted) setState(() => treeLoading = false);
    }
  }

  Future<void> toggleTreeArea(Map<String, dynamic> selectedArea) async {
    final id = (selectedArea['id_area'] as num).toInt();
    final opening = !expandedTreeAreas.contains(id);
    setState(() {
      if (opening) {
        expandedTreeAreas.add(id);
      } else {
        expandedTreeAreas.remove(id);
      }
    });
    navigate(2, selectedArea);
    if (!opening || treeMachines.containsKey(id)) return;
    await loadTreeMachines(id);
  }

  Future<void> loadTreeMachines(int areaId, {bool showError = true}) async {
    try {
      final result = await Api.request('/api/areas/$areaId/maquinas');
      if (mounted && expandedTreeAreas.contains(areaId)) {
        setState(() => treeMachines[areaId] = result as List);
      }
    } catch (e) {
      if (mounted && showError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void openTreeMachine(Map<String, dynamic> machine) {
    setState(() => activeMachineId = machine['id_maquina'].toString());
  }

  Future<void> updateTreeMachine(Map<String, dynamic> machine, {
    String? name, int? targetAreaId,
  }) async {
    final machineId = machine['id_maquina'].toString();
    if (updatingTreeMachines.contains(machineId)) return;
    setState(() => updatingTreeMachines.add(machineId));
    try {
      final config = Map<String, dynamic>.from(
        await Api.request('/api/maquinas/$machineId/config'),
      );
      if (name != null) config['nombre'] = name;
      if (targetAreaId != null) config['id_area'] = targetAreaId;
      await Api.request('/api/maquinas/$machineId/config', body: config, put: true);

      final openAreas = expandedTreeAreas.toList();
      treeMachines.clear();
      await loadTreeAreas();
      for (final areaId in openAreas) {
        await loadTreeMachines(areaId, showError: false);
      }
      await load(silent: true);
      if (mounted) {
        final message = targetAreaId != null ? 'Máquina movida correctamente' : 'Nombre actualizado correctamente';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => updatingTreeMachines.remove(machineId));
    }
  }

  Future<void> renameTreeMachine(Map<String, dynamic> machine) async {
    final controller = TextEditingController(text: machine['nombre'].toString());
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Cambiar nombre de máquina'),
      content: Form(key: formKey, child: TextFormField(
        controller: controller, autofocus: true, maxLength: 100,
        decoration: const InputDecoration(labelText: 'Nombre'),
        validator: (value) => value == null || value.trim().isEmpty ? 'Escribe un nombre' : null,
        onFieldSubmitted: (_) {
          if (formKey.currentState!.validate()) Navigator.pop(context, controller.text.trim());
        },
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          if (formKey.currentState!.validate()) Navigator.pop(context, controller.text.trim());
        }, child: const Text('Guardar')),
      ],
    ));
    controller.dispose();
    if (name != null && name != machine['nombre'] && mounted) {
      await updateTreeMachine(machine, name: name);
    }
  }

  Future<void> moveTreeMachine(Map<String, dynamic> machine, int targetAreaId) async {
    final currentAreaId = (machine['id_area'] as num).toInt();
    if (currentAreaId == targetAreaId) return;
    await updateTreeMachine(machine, targetAreaId: targetAreaId);
  }

  Future<void> deleteMachine(Map<String, dynamic> machine) async {
    final machineId = machine['id_maquina'].toString();
    final machineName = machine['nombre']?.toString() ?? machineId;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('¿Eliminar máquina?'),
      content: Text('Se eliminará “$machineName” ($machineId), junto con su telemetría, alertas y credenciales. Esta acción es permanente.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar definitivamente'),
        ),
      ],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => updatingTreeMachines.add(machineId));
    try {
      await Api.request('/api/maquinas/$machineId', delete: true);
      if (activeMachineId == machineId) activeMachineId = null;
      final areaId = (machine['id_area'] as num?)?.toInt();
      if (areaId != null) {
        treeMachines[areaId]?.removeWhere((item) => item['id_maquina'].toString() == machineId);
      }
      await loadTreeAreas();
      await load(silent: true);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máquina eliminada correctamente')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => updatingTreeMachines.remove(machineId));
    }
  }

  Future<void> renameTreeArea(Map<String, dynamic> selectedArea) async {
    final controller = TextEditingController(text: selectedArea['nombre'].toString());
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Cambiar nombre del área'),
      content: Form(key: formKey, child: TextFormField(
        controller: controller, autofocus: true, maxLength: 100,
        decoration: const InputDecoration(labelText: 'Nombre del área'),
        validator: (value) => value == null || value.trim().isEmpty ? 'Escribe un nombre' : null,
        onFieldSubmitted: (_) {
          if (formKey.currentState!.validate()) Navigator.pop(context, controller.text.trim());
        },
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          if (formKey.currentState!.validate()) Navigator.pop(context, controller.text.trim());
        }, child: const Text('Guardar')),
      ],
    ));
    controller.dispose();
    if (name == null || name == selectedArea['nombre'] || !mounted) return;
    try {
      await Api.request('/api/areas/${selectedArea['id_area']}', body: {'nombre': name}, put: true);
      if (area?['id_area'] == selectedArea['id_area']) {
        setState(() => area = {...area!, 'nombre': name});
      }
      await loadTreeAreas();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Área actualizada correctamente')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> deleteTreeArea(Map<String, dynamic> selectedArea) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('¿Eliminar área?'),
      content: Text('Se eliminará “${selectedArea['nombre']}”. Solo es posible si no contiene máquinas.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar'),
        ),
      ],
    ));
    if (confirmed != true || !mounted) return;
    try {
      final id = (selectedArea['id_area'] as num).toInt();
      await Api.request('/api/areas/$id', delete: true);
      treeMachines.remove(id);
      expandedTreeAreas.remove(id);
      if (area?['id_area'] == id) {
        navigate(1);
      } else {
        await loadTreeAreas();
        if (level == 1) await load(silent: true);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Área eliminada correctamente')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> create({String? userRole, Map<String, dynamic>? machine}) async {
    Map<String, dynamic>? config;
    if (machine != null) {
      try { config = Map<String, dynamic>.from(await Api.request('/api/maquinas/${machine['id_maquina']}/config')); }
      catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); return; }
      if (!mounted) return;
    }
    final result = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => RegistrationDialog(
      kind: machine != null ? 'config' : userRole != null ? 'member' : ['company', 'area', 'machine'][level],
      companyId: company?['id_empresa'], areaId: area?['id_area'], machine: machine, config: config, userRole: userRole,
    ));
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cambios guardados correctamente')));
      await load();
      if (company != null) {
        final openAreas = expandedTreeAreas.toList();
        treeMachines.clear();
        await loadTreeAreas();
        for (final areaId in openAreas) {
          await loadTreeMachines(areaId, showError: false);
        }
      }
    }
  }

  Widget sidebar() => Container(width: 232, color: Colors.white, padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Padding(padding: EdgeInsets.only(top: 14, bottom: 46), child: Brand()),
    const Text('ESPACIO DE TRABAJO', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
    const SizedBox(height: 18),
    Expanded(child: ListView(padding: EdgeInsets.zero, children: [
      if (installer) navItem('Empresas', Icons.business_outlined, level == 0, () => navigate(0)),
      if (company != null) ...[
        treeItem(
          label: 'Áreas', icon: Icons.grid_view_rounded, selected: level == 1,
          expanded: areasTreeExpanded,
          onTap: () {
            setState(() => areasTreeExpanded = !areasTreeExpanded);
            if (areasTreeExpanded) { navigate(1); loadTreeAreas(); }
          },
        ),
        if (areasTreeExpanded) ...[
          if (treeLoading && treeAreas.isEmpty)
            const Padding(padding: EdgeInsets.fromLTRB(44, 10, 0, 14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
          for (final rawArea in treeAreas) ...treeAreaNodes(Map<String, dynamic>.from(rawArea)),
        ],
      ],
    ])),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: canvas, borderRadius: BorderRadius.circular(14)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.sensors_rounded, color: accent), SizedBox(height: 10),
      Text('Conecta tu operación', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      SizedBox(height: 6), Text('Registra una máquina y usa su identificador para enviar lecturas.', style: TextStyle(color: muted, fontSize: 12)),
    ])),
    const SizedBox(height: 24), const Divider(), const SizedBox(height: 12),
    Row(children: [CircleAvatar(radius: 18, backgroundColor: const Color(0xFFE3F3EE), child: Text((widget.user['nombre'] as String).substring(0, 1).toUpperCase(), style: const TextStyle(color: accent))),
      const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.user['nombre'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text(widget.user['rol'], style: const TextStyle(color: muted, fontSize: 11)),
      ])), IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout_rounded, size: 18), onPressed: () async { await Api.logout(); if (mounted) { sessionNavigator.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const PantallaLogin()), (_) => false); } }),
    ]),
  ]));

  Widget navItem(String label, IconData icon, bool selected, VoidCallback? action) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Material(
    color: selected ? const Color(0xFFE8F4F0) : Colors.transparent, borderRadius: BorderRadius.circular(10),
    child: ListTile(dense: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12), onTap: action,
      leading: Icon(icon, size: 20, color: selected ? accent : muted),
      title: Text(label, style: TextStyle(fontSize: 13, color: selected ? accent : muted, fontWeight: selected ? FontWeight.w700 : FontWeight.w400))),
  ));

  Widget treeItem({required String label, required IconData icon, required bool selected,
    required VoidCallback onTap, bool? expanded, double indent = 0, Widget? trailing}) => Padding(
    padding: EdgeInsets.only(left: indent, bottom: 4),
    child: Material(
      color: selected ? const Color(0xFFE8F4F0) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        dense: true, minLeadingWidth: 20, horizontalTitleGap: 8,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10), onTap: onTap,
        leading: Icon(icon, size: 19, color: selected ? accent : muted),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: selected ? accent : muted, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
        trailing: trailing ?? (expanded == null ? null : Icon(expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18, color: muted)),
      ),
    ),
  );

  List<Widget> treeAreaNodes(Map<String, dynamic> treeArea) {
    final id = (treeArea['id_area'] as num).toInt();
    final expanded = expandedTreeAreas.contains(id);
    final machines = treeMachines[id];
    return [
      DragTarget<Map<String, dynamic>>(
        onWillAcceptWithDetails: (details) => canEdit && (details.data['id_area'] as num).toInt() != id,
        onAcceptWithDetails: (details) => moveTreeMachine(details.data, id),
        builder: (context, candidates, rejected) => DecoratedBox(
          decoration: BoxDecoration(
            color: candidates.isEmpty ? Colors.transparent : accent.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: treeItem(
            label: treeArea['nombre'].toString(), icon: Icons.account_tree_outlined,
            selected: area?['id_area'] == id, expanded: expanded, indent: 12,
            onTap: () => toggleTreeArea(treeArea),
            trailing: canEdit ? SizedBox(width: 54, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              SizedBox(width: 28, height: 32, child: PopupMenuButton<String>(
                  tooltip: 'Opciones del área', padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'rename') renameTreeArea(treeArea);
                    if (value == 'delete') deleteTreeArea(treeArea);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Cambiar nombre'), contentPadding: EdgeInsets.zero)),
                    PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar'), contentPadding: EdgeInsets.zero)),
                  ],
                  icon: const Icon(Icons.more_vert_rounded, size: 17),
                ),
              ),
              Icon(expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18, color: muted),
            ])) : null,
          ),
        ),
      ),
      if (expanded && machines == null)
        const Padding(padding: EdgeInsets.fromLTRB(52, 8, 0, 12), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
      if (expanded && machines != null)
        for (final rawMachine in machines)
          Draggable<Map<String, dynamic>>(
            data: Map<String, dynamic>.from(rawMachine),
            maxSimultaneousDrags: canEdit && !updatingTreeMachines.contains(rawMachine['id_maquina'].toString()) ? 1 : 0,
            feedback: Material(
              elevation: 6, borderRadius: BorderRadius.circular(10), color: Colors.white,
              child: Container(width: 190, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.precision_manufacturing_outlined, size: 18, color: accent),
                  const SizedBox(width: 8), Expanded(child: Text(rawMachine['nombre'].toString(), overflow: TextOverflow.ellipsis)),
                ])),
            ),
            childWhenDragging: Opacity(opacity: .35, child: machineTreeItem(Map<String, dynamic>.from(rawMachine))),
            child: machineTreeItem(Map<String, dynamic>.from(rawMachine)),
          ),
    ];
  }

  Widget machineTreeItem(Map<String, dynamic> machine) {
    final machineId = machine['id_maquina'].toString();
    final updating = updatingTreeMachines.contains(machineId);
    return treeItem(
      label: machine['nombre'].toString(), icon: Icons.precision_manufacturing_outlined,
      selected: false, indent: 26,
      onTap: updating ? () {} : () => openTreeMachine(machine),
      trailing: updating
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : canEdit ? SizedBox(width: 28, height: 32, child: PopupMenuButton<String>(
            tooltip: 'Opciones de la máquina', padding: EdgeInsets.zero,
            onSelected: (value) {
              if (value == 'rename') renameTreeMachine(machine);
              if (value == 'delete') deleteMachine(machine);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Cambiar nombre'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar'), contentPadding: EdgeInsets.zero)),
            ],
            icon: const Icon(Icons.more_vert_rounded, size: 17),
          )) : null,
    );
  }

  Widget stat(String value, String label, IconData icon, Color color) => Container(
    constraints: const BoxConstraints(minWidth: 155), padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
    child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
      const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700, color: ink)), Text(label, style: const TextStyle(color: muted, fontSize: 12))])),
    ]),
  );

  String status(Map<String, dynamic> m) {
    if (m['ultima_lectura'] == null) return 'Sin lecturas';
    if ((m['edad_segundos'] as num? ?? 999) > 30) return 'Sin señal reciente';
    return {'optimo': 'Operación normal', 'alerta': 'Atención', 'peligro': 'Peligro'}[m['estado']] ?? 'Sin estado';
  }

  Widget tile(Map<String, dynamic> item) {
    final isMachine = level == 2;
    final label = isMachine ? status(item) : '${item['total_maquinas'] ?? 0} máquinas';
    final stale = item['ultima_lectura'] == null || (item['edad_segundos'] as num? ?? 999) > 30;
    final color = !isMachine ? accent : stale ? muted : item['estado'] == 'peligro' ? const Color(0xFFCE4B51) : item['estado'] == 'alerta' ? const Color(0xFFAE7419) : accent;
    final sensors = sensorLabels.keys.where((k) => item['medir_$k'] == 1 || item['medir_$k'] == true).length;
    void open() {
      if (isMachine) {
        openTreeMachine(item);
      } else { navigate(level + 1, item); }
    }
    return Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: open, hoverColor: accent.withValues(alpha: .025), child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: canvas, borderRadius: BorderRadius.circular(13)),
        child: Icon([Icons.business_outlined, Icons.layers_outlined, Icons.precision_manufacturing_outlined][level], color: ink, size: 24)),
        const Spacer(),
        if (isMachine && canEdit) IconButton(tooltip: 'Telegram e instalación', onPressed: () => showDialog(context: context, builder: (_) => MachineSetup(machineId: item['id_maquina'], installer: installer)), icon: const Icon(Icons.cable_rounded, color: accent, size: 20)),
        if (isMachine && canEdit) IconButton(tooltip: 'Configurar sensores y umbrales', onPressed: () => create(machine: item), icon: const Icon(Icons.tune_rounded, color: muted, size: 20)),
        if (isMachine && canEdit) IconButton(tooltip: 'Eliminar máquina', onPressed: () => deleteMachine(item), icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error, size: 20))
        else if (!isMachine && level == 1 && canEdit) PopupMenuButton<String>(
          tooltip: 'Opciones del área',
          onSelected: (value) {
            if (value == 'rename') renameTreeArea(item);
            if (value == 'delete') deleteTreeArea(item);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Cambiar nombre'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar'), contentPadding: EdgeInsets.zero)),
          ],
          icon: const Icon(Icons.more_vert_rounded, color: muted, size: 20),
        )
        else const Icon(Icons.north_east_rounded, color: muted, size: 19),
      ]),
      const SizedBox(height: 22), Text(item['nombre'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -.3)),
      const SizedBox(height: 5), Text(isMachine ? '${item['id_maquina']} · $sensors sensores habilitados' : level == 0 ? '${item['total_areas'] ?? 0} áreas de trabajo' : 'En ${company!['nombre']}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: muted)),
      const Spacer(), const Divider(height: 28),
      Row(children: [Flexible(child: StatusPill(label, color: color)), const Spacer(), Text(isMachine ? 'Monitorear' : 'Explorar', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent))]),
    ]))));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final visible = items.where((i) => '${i['nombre']} ${i['id_maquina'] ?? ''}'.toLowerCase().contains(query.toLowerCase())).toList();
    final totalMachines = items.fold<int>(0, (sum, i) => sum + ((i['total_maquinas'] ?? 0) as num).toInt());
    final live = items.where((i) => i['ultima_lectura'] != null && (i['edad_segundos'] as num? ?? 999) <= 30).length;
    return Scaffold(
      drawer: wide ? null : Drawer(child: SafeArea(child: sidebar())),
      body: SafeArea(child: Row(children: [
        if (wide) sidebar(),
        Expanded(child: activeMachineId == null ? Column(children: [
          Container(height: 76, padding: EdgeInsets.symmetric(horizontal: wide ? 36 : 16), decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: line))),
            child: Row(children: [if (!wide) Builder(builder: (c) => IconButton(tooltip: 'Abrir navegación', onPressed: () => Scaffold.of(c).openDrawer(), icon: const Icon(Icons.menu_rounded))),
              Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                if (installer) TextButton(onPressed: () => navigate(0), child: const Text('Empresas')),
                if (company != null) ...[const Icon(Icons.chevron_right, size: 16, color: muted), TextButton(onPressed: () => navigate(1), child: Text(company!['nombre']))],
                if (area != null) ...[const Icon(Icons.chevron_right, size: 16, color: muted), Text(area!['nombre'], style: const TextStyle(fontSize: 13))],
              ]))),
              IconButton(tooltip: 'Actualizar', onPressed: loading ? null : () => load(), icon: const Icon(Icons.refresh_rounded, color: muted)),
            ])),
          Expanded(child: RefreshIndicator(onRefresh: load, child: ListView(padding: EdgeInsets.all(wide ? 36 : 20), children: [
            Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 24, runSpacing: 20, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('VISTA GENERAL', style: TextStyle(fontSize: 10, color: accent, letterSpacing: 1.8, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8), Text(title, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8), Text(['El punto de partida de una operación conectada.', 'Organiza los espacios de tu operación.', 'Cada máquina, cada señal, en un solo lugar.'][level], style: const TextStyle(color: muted, fontSize: 13)),
              ]),
              if (canEdit) Wrap(spacing: 10, runSpacing: 10, children: [
                if (level == 1 && installer) OutlinedButton.icon(onPressed: () => create(userRole: 'jefe'), icon: const Icon(Icons.manage_accounts_outlined, size: 17), label: const Text('Añadir jefe')),
                if (level == 1 && !installer) OutlinedButton.icon(onPressed: () => create(userRole: 'participante'), icon: const Icon(Icons.person_add_alt_1, size: 17), label: const Text('Añadir técnico')),
                FilledButton.icon(onPressed: () => create(), icon: const Icon(Icons.add, size: 18), label: Text('Nueva $singular')),
              ]),
            ]),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (context, c) {
              final cards = [
                stat(loading ? '—' : '${items.length}', title, Icons.grid_view_rounded, accent),
                stat(loading ? '—' : '${level == 2 ? live : totalMachines}', level == 2 ? 'Con señal reciente' : 'Máquinas registradas', Icons.sensors_rounded, const Color(0xFF517AB0)),
                stat(loading ? '—' : '${level == 2 ? items.length - live : items.where((i) => (i['total_maquinas'] ?? 0) == 0).length}', level == 2 ? 'Esperando señal' : 'Sin máquinas aún', Icons.schedule_rounded, const Color(0xFFAD803C)),
              ];
              final columns = c.maxWidth < 560 ? 1 : 3;
              return Wrap(spacing: 16, runSpacing: 12, children: cards.map((card) => SizedBox(width: (c.maxWidth - 16 * (columns - 1)) / columns, child: card)).toList());
            }),
            const SizedBox(height: 30),
            Row(children: [Expanded(child: TextField(controller: search, onChanged: (v) => setState(() => query = v), decoration: InputDecoration(hintText: 'Buscar en $title'.toLowerCase(), prefixIcon: const Icon(Icons.search_rounded, size: 21),
              suffixIcon: query.isEmpty ? null : IconButton(tooltip: 'Limpiar búsqueda', onPressed: () { search.clear(); setState(() => query = ''); }, icon: const Icon(Icons.close, size: 18))))),
              if (wide) ...[const SizedBox(width: 20), Text('${visible.length} resultados', style: const TextStyle(color: muted, fontSize: 12))],
            ]),
            const SizedBox(height: 22),
            AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: loading
              ? const SizedBox(key: ValueKey('loading'), height: 240, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : error != null ? EmptyState(key: const ValueKey('error'), title: 'No pudimos actualizar la vista', subtitle: error!, onRetry: () => load(), icon: Icons.cloud_off_rounded)
              : visible.isEmpty ? EmptyState(key: const ValueKey('empty'), title: query.isEmpty ? 'Tu próxima $singular empieza aquí' : 'Sin coincidencias', subtitle: query.isEmpty ? canEdit ? 'Usa el botón “Nueva $singular” para comenzar.' : 'Tu equipo aún no ha registrado elementos.' : 'Prueba con otro nombre o identificador.', icon: Icons.add_business_outlined)
              : LayoutBuilder(key: ValueKey('$level-${company?['id_empresa']}-${area?['id_area']}'), builder: (context, c) {
                final columns = c.maxWidth >= 1100 ? 4 : c.maxWidth >= 780 ? 3 : c.maxWidth >= 520 ? 2 : 1;
                return Wrap(spacing: 18, runSpacing: 18, children: visible.map((i) => SizedBox(width: (c.maxWidth - (columns - 1) * 18) / columns, height: 244, child: tile(Map<String, dynamic>.from(i)))).toList());
              })),
            const SizedBox(height: 28),
            if (level == 2) const Text('La señal se actualiza cada 8 segundos. Después de 30 segundos sin lecturas, la máquina se muestra sin señal reciente.', style: TextStyle(color: muted, fontSize: 12)),
          ]))),
        ]) : PantallaMonitoreo(
          key: ValueKey(activeMachineId),
          idMaquina: activeMachineId!,
          onBack: () => setState(() => activeMachineId = null),
        )),
      ])),
    );
  }
}

class RegistrationDialog extends StatefulWidget {
  final String kind;
  final String? userRole;
  final int? companyId, areaId;
  final Map<String, dynamic>? machine, config;
  const RegistrationDialog({super.key, required this.kind, this.companyId, this.areaId, this.machine, this.config, this.userRole});
  @override
  State<RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<RegistrationDialog> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  final sensors = <String, bool>{};
  bool busy = false;
  String? error;
  bool get config => widget.kind == 'config';
  bool get machine => widget.kind == 'machine' || config;
  bool get creatingManager => widget.kind == 'member' && widget.userRole == 'jefe';
  String get title => widget.kind == 'member'
      ? creatingManager ? 'Añadir jefe' : 'Añadir técnico'
      : {'company': 'Nueva empresa', 'area': 'Nueva área', 'machine': 'Registrar máquina', 'config': 'Sensores y umbrales'}[widget.kind]!;
  @override
  void initState() {
    super.initState();
    for (final key in ['nombre', 'responsable', 'email', 'password', 'id_maquina']) {
      fields[key] = TextEditingController(text: widget.config?[key]?.toString() ?? '');
    }
    for (final key in sensorLabels.keys) {
      sensors[key] = widget.config == null || widget.config!['medir_$key'] == 1 || widget.config!['medir_$key'] == true;
      for (final level in ['alerta', 'peligro']) {
        fields['${key}_$level'] = TextEditingController(text: widget.config?['${key}_$level']?.toString() ?? '');
      }
    }
  }
  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }

  Widget field(String key, String label, {String? hint, bool password = false, bool number = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: TextFormField(
      controller: fields[key], obscureText: password, enabled: !busy,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : key == 'email' ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(labelText: label, helperText: hint, helperMaxLines: 3),
      validator: (raw) {
        final v = raw?.trim() ?? '';
        if (v.isEmpty) return 'Este campo es obligatorio';
        if (key == 'password' && v.length < 8) return 'Usa al menos 8 caracteres';
        if (key == 'email' && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) return 'Ingresa un correo válido';
        if (key == 'id_maquina' && !RegExp(r'^[A-Za-z0-9_-]{1,50}$').hasMatch(v)) return 'Usa letras, números, guion o guion bajo (máximo 50)';
        if (number) {
          final n = num.tryParse(v);
          if (n == null || !n.isFinite) return 'Ingresa un número válido';
          if (key.startsWith('vel_') && n != n.roundToDouble()) return 'Usa un número entero';
          if (key.endsWith('_peligro')) {
            final other = num.tryParse(fields[key.replaceFirst('_peligro', '_alerta')]!.text);
            if (other != null && n <= other) return 'Debe superar la alerta';
          }
        }
        if (key == 'nombre' || key == 'responsable' || key == 'email') { if (v.length > 100) return 'Máximo 100 caracteres'; }
        return null;
      },
    ),
  );

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (machine && !sensors.values.any((v) => v)) { setState(() => error = 'Habilita al menos un sensor.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final body = <String, dynamic>{'nombre': fields['nombre']!.text.trim()};
      String path;
      switch (widget.kind) {
        case 'company':
          path = '/api/empresas';
          for (final k in ['responsable', 'email', 'password']) { body[k] = fields[k]!.text; }
        case 'member':
          path = '/api/usuarios'; body.addAll({'id_empresa': widget.companyId, 'rol': widget.userRole, 'email': fields['email']!.text, 'password': fields['password']!.text});
        case 'area':
          path = '/api/areas'; body['id_empresa'] = widget.companyId;
        default:
          path = config ? '/api/maquinas/${widget.machine!['id_maquina']}/config' : '/api/maquinas';
          body['id_area'] = widget.config?['id_area'] ?? widget.areaId;
          if (!config) body['id_maquina'] = fields['id_maquina']!.text.trim();
          for (final k in sensorLabels.keys) {
            body['medir_$k'] = sensors[k];
            if (config) {
              for (final l in ['alerta', 'peligro']) { body['${k}_$l'] = num.parse(fields['${k}_$l']!.text); }
            }
          }
      }
      await Api.request(path, body: body, put: config);
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: AlertDialog(
    title: Text(title), content: SizedBox(width: 540, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(config ? 'Ajusta qué medir y cuándo necesitas recibir atención.' : machine ? 'Asigna un identificador único. El dispositivo deberá usarlo al enviar sus lecturas.' : widget.kind == 'company' ? 'Crea la empresa y la cuenta de su responsable en un solo paso.' : 'Organiza tu equipo y tu operación.', style: const TextStyle(color: muted, fontSize: 13)),
      const SizedBox(height: 24), field('nombre', widget.kind == 'member' ? creatingManager ? 'Nombre del jefe' : 'Nombre del técnico' : 'Nombre'),
      if (widget.kind == 'company') field('responsable', 'Nombre del responsable'),
      if (widget.kind == 'company' || widget.kind == 'member') ...[field('email', 'Correo electrónico'), field('password', 'Contraseña', password: true, hint: 'Al menos 8 caracteres')],
      if (widget.kind == 'machine') field('id_maquina', 'Identificador del dispositivo', hint: 'Por ejemplo: MOTOR-02. Debe coincidir con el firmware.'),
      if (machine) ...[
        const SizedBox(height: 4), const Text('SENSORES HABILITADOS', style: TextStyle(color: accent, fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        for (final entry in sensorLabels.entries) ...[
          SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: Text(entry.value, style: const TextStyle(fontSize: 14)), value: sensors[entry.key]!, onChanged: busy ? null : (v) => setState(() => sensors[entry.key] = v)),
          if (config) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: field('${entry.key}_alerta', 'Alerta', number: true)), const SizedBox(width: 12), Expanded(child: field('${entry.key}_peligro', 'Peligro', number: true))]),
        ],
      ],
      if (config) ...[
        const Divider(), const SizedBox(height: 12), SelectableText('ID: ${widget.machine!['id_maquina']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8), const Text('Envía las lecturas del dispositivo a este endpoint:', style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 8), SelectableText(ApiConfig.uri('/api/sensores').toString(), style: const TextStyle(fontSize: 12)),
        TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: widget.machine!['id_maquina'])), icon: const Icon(Icons.copy, size: 16), label: const Text('Copiar identificador')),
      ],
      if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ])))),
    actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: busy ? null : save, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar'))],
  ));
}
