import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'config/api_config.dart';
import 'services/api.dart';
import 'ui/design.dart';
import 'pantalla_monitoreo.dart';

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
    timer = Timer.periodic(const Duration(seconds: 8), (_) { if (level == 2 && !loading) load(silent: true); });
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
      if (target == 0) { company = null; area = null; }
      if (target == 1) { company = value ?? company; area = null; }
      if (target == 2) area = value;
      items = []; query = ''; search.clear();
    });
    load();
  }

  Future<void> create({bool member = false, Map<String, dynamic>? machine}) async {
    Map<String, dynamic>? config;
    if (machine != null) {
      try { config = Map<String, dynamic>.from(await Api.request('/api/maquinas/${machine['id_maquina']}/config')); }
      catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); return; }
      if (!mounted) return;
    }
    final result = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => RegistrationDialog(
      kind: machine != null ? 'config' : member ? 'member' : ['company', 'area', 'machine'][level],
      companyId: company?['id_empresa'], areaId: area?['id_area'], machine: machine, config: config,
    ));
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cambios guardados correctamente')));
      await load();
    }
  }

  Widget sidebar() => Container(width: 232, color: Colors.white, padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Padding(padding: EdgeInsets.only(top: 14, bottom: 46), child: Brand()),
    const Text('ESPACIO DE TRABAJO', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
    const SizedBox(height: 18),
    if (installer) navItem('Empresas', Icons.business_outlined, level == 0, () => navigate(0)),
    navItem('Áreas', Icons.grid_view_rounded, level == 1, company == null ? null : () => navigate(1)),
    navItem('Máquinas', Icons.precision_manufacturing_outlined, level == 2, null),
    const Spacer(),
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
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaMonitoreo(idMaquina: item['id_maquina']))).then((_) { if (mounted) load(silent: true); });
      } else { navigate(level + 1, item); }
    }
    return Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: open, hoverColor: accent.withValues(alpha: .025), child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: canvas, borderRadius: BorderRadius.circular(13)),
        child: Icon([Icons.business_outlined, Icons.layers_outlined, Icons.precision_manufacturing_outlined][level], color: ink, size: 24)),
        const Spacer(), if (isMachine && canEdit) IconButton(tooltip: 'Configurar sensores y umbrales', onPressed: () => create(machine: item), icon: const Icon(Icons.tune_rounded, color: muted, size: 20))
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
        Expanded(child: Column(children: [
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
                if (level == 1) OutlinedButton.icon(onPressed: () => create(member: true), icon: const Icon(Icons.person_add_alt_1, size: 17), label: const Text('Añadir técnico')),
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
        ])),
      ])),
    );
  }
}

class RegistrationDialog extends StatefulWidget {
  final String kind;
  final int? companyId, areaId;
  final Map<String, dynamic>? machine, config;
  const RegistrationDialog({super.key, required this.kind, this.companyId, this.areaId, this.machine, this.config});
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
  String get title => {'company': 'Nueva empresa', 'area': 'Nueva área', 'machine': 'Registrar máquina', 'member': 'Añadir técnico', 'config': 'Sensores y umbrales'}[widget.kind]!;
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
          path = '/api/usuarios'; body.addAll({'id_empresa': widget.companyId, 'rol': 'participante', 'email': fields['email']!.text, 'password': fields['password']!.text});
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
      const SizedBox(height: 24), field('nombre', widget.kind == 'member' ? 'Nombre del técnico' : 'Nombre'),
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
