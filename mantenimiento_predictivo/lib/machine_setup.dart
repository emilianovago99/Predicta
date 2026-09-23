import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api.dart';
import 'ui/design.dart';

class MachineSetup extends StatefulWidget {
  final String machineId;
  final bool installer;
  const MachineSetup({super.key, required this.machineId, required this.installer});
  @override
  State<MachineSetup> createState() => _MachineSetupState();
}

class _MachineSetupState extends State<MachineSetup> {
  Map<String, dynamic>? notifications, installation, enrollment;
  final server = TextEditingController();
  final name = TextEditingController(), token = TextEditingController(), chat = TextEditingController();
  int? channelId;
  int? editingId;
  int cooldown = 15;
  bool busy = false, adding = false;
  String? error, notice;
  String get base => '/api/maquinas/${widget.machineId}';
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { for (final c in [server, name, token, chat]) { c.dispose(); } super.dispose(); }
  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    setState(() { busy = true; error = null; notice = null; });
    try { await work(); } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> load() => run(() async {
    final n = Map<String, dynamic>.from(await Api.request('$base/notifications'));
    Map<String, dynamic>? i;
    if (widget.installer) { i = Map<String, dynamic>.from(await Api.request('$base/installation')); }
    if (!mounted) return;
    setState(() {
      notifications = n; installation = i; channelId = n['channel_id'];
      cooldown = ((n['cooldown_seconds'] as num) / 60).round();
      if (server.text.isEmpty) server.text = i?['server_url'] ?? '';
    });
  });
  Future<void> save() => run(() async {
    await Api.request('$base/notifications', put: true, body: {'channel_id': channelId, 'cooldown_seconds': cooldown * 60});
    if (mounted) setState(() => notice = 'Destino y frecuencia guardados.');
  });
  Future<void> addChannel() => run(() async {
    final created = await Api.request(editingId == null ? '/api/telegram/channels' : '/api/telegram/channels/$editingId', put: editingId != null, body: {
      'id_empresa': notifications!['id_empresa'], 'nombre': name.text.trim(),
      'bot_token': token.text.trim(), 'chat_id': chat.text.trim(),
    });
    token.clear();
    final n = Map<String, dynamic>.from(await Api.request('$base/notifications'));
    if (mounted) setState(() { notifications = n; channelId = created['id']; adding = false; editingId = null; notice = 'Destino guardado. Guarda la asignación a esta máquina.'; });
  });
  Future<void> generate() async {
    if (installation?['provisioned'] == true) {
      final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('¿Reinstalar el sensor?'),
        content: const Text('Cuando el nuevo sensor use el código, la clave anterior dejará de funcionar. Las mediciones guardadas se conservan.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar'))]));
      if (yes != true) return;
    }
    await run(() async {
      final result = Map<String, dynamic>.from(await Api.request('$base/installation', body: {'server_url': server.text.trim()}));
      if (mounted) setState(() => enrollment = result);
    });
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Conexiones · ${widget.machineId}'),
    content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (notifications == null && busy) const LinearProgressIndicator(),
      if (notifications != null) ...[
        const Text('TELEGRAM', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Comparte un destino entre varias máquinas de esta empresa. Recibirás resúmenes breves, sin diagnósticos largos de IA.'),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(key: ValueKey('channel-$channelId-${notifications!['channels'].length}'), initialValue: channelId ?? 0,
          isExpanded: true, decoration: const InputDecoration(labelText: 'Destino de alertas'),
          items: [const DropdownMenuItem(value: 0, child: Text('Sin Telegram')),
            for (final c in notifications!['channels']) DropdownMenuItem(value: c['id'] as int, child: Text(c['nombre'], overflow: TextOverflow.ellipsis))],
          onChanged: busy ? null : (v) => setState(() => channelId = v == 0 ? null : v)),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(key: ValueKey('cooldown-$cooldown'), initialValue: cooldown,
          decoration: const InputDecoration(labelText: 'Recordar si el problema continúa'),
          items: ({5, 15, 30, 60, cooldown}.toList()..sort()).map((v) => DropdownMenuItem(value: v, child: Text('Cada $v minutos'))).toList(),
          onChanged: busy ? null : (v) => setState(() => cooldown = v!)),
        const SizedBox(height: 8),
        const Text('Se agrupan hasta 5 máquinas por mensaje, con un máximo de un envío por minuto por destino. Los avisos no críticos llegan sin sonido.', style: TextStyle(color: muted, fontSize: 12)),
        for (final c in notifications!['channels']) if (c['id'] == channelId && c['last_status'] != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('Último envío: ${c['last_status']}', style: const TextStyle(fontSize: 12))),
        TextButton.icon(onPressed: busy ? null : () => setState(() { adding = !adding; editingId = null; name.clear(); token.clear(); chat.clear(); }), icon: const Icon(Icons.add), label: const Text('Nuevo destino de Telegram')),
        if (channelId != null) TextButton(onPressed: busy ? null : () => setState(() {
          final c = (notifications!['channels'] as List).firstWhere((c) => c['id'] == channelId);
          editingId = channelId; adding = true; name.text = c['nombre']; chat.text = c['chat_id']; token.clear();
        }), child: const Text('Editar credenciales del destino')),
        if (adding) ...[
          if (editingId != null) const Text('Este cambio se aplica a todas las máquinas que usan el destino. Ingresa de nuevo el token del bot.', style: TextStyle(fontWeight: FontWeight.w600)),
          const Text('Crea el bot con @BotFather. Agrégalo al grupo o abre su chat con /start; indica el ID numérico de ese chat.', style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del destino (ej. Mantenimiento planta)')),
          const SizedBox(height: 12), TextField(controller: token, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: const InputDecoration(labelText: 'Token de BotFather')),
          const SizedBox(height: 12), TextField(controller: chat, decoration: const InputDecoration(labelText: 'Chat ID (ej. -1001234567890)')),
          const SizedBox(height: 12), OutlinedButton(onPressed: busy ? null : addChannel, child: Text(editingId == null ? 'Crear destino' : 'Actualizar destino')),
        ],
        FilledButton(onPressed: busy ? null : save, child: const Text('Guardar Telegram')),
      ],
      if (widget.installer && installation != null) ...[
        const SizedBox(height: 24), const Divider(), const SizedBox(height: 16),
        const Text('INSTALAR SENSOR', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        StatusPill(installation!['connected'] == true ? 'Recibiendo mediciones' : 'Esperando señal', color: installation!['connected'] == true ? accent : muted),
        if (installation!['last_reading'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Última recepción: ${installation!['last_reading']['received_at']} UTC\nFirmware: ${installation!['last_reading']['firmware_version'] ?? 'No informado'}', style: const TextStyle(fontSize: 12))),
        const SizedBox(height: 16),
        const Text('1. Conecta el sensor a la red de la planta.\n2. Indica el nombre del servidor de Predicta.\n3. Genera y carga el paquete de instalación en el sensor.\n4. Actualiza aquí para comprobar la primera medición.'),
        const SizedBox(height: 12),
        TextField(controller: server, decoration: const InputDecoration(labelText: 'Dirección del servidor', hintText: 'http://predicta.planta:8088', helperText: 'El nombre debe resolver en la red del sensor. No uses localhost.', helperMaxLines: 2)),
        const SizedBox(height: 12), const Text('El sensor usa DHCP. Su identidad es el ID de máquina y su clave, no su IP.', style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: busy ? null : generate, icon: const Icon(Icons.link), label: const Text('Generar código de instalación')),
        if (enrollment != null) ...[
          const SizedBox(height: 12), const Text('Código privado · un solo uso · vence en 10 minutos', style: TextStyle(fontWeight: FontWeight.w600)),
          SelectableText(enrollment!['enrollment_code']),
          TextButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(enrollment))); if (mounted) setState(() => notice = 'Paquete copiado. Compártelo solo con el instalador.'); }, icon: const Icon(Icons.copy), label: const Text('Copiar paquete para el sensor')),
        ],
      ],
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
      if (notice != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(notice!, style: const TextStyle(color: accent))),
    ]))),
    actions: [TextButton(onPressed: busy ? null : load, child: const Text('Actualizar estado')),
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cerrar'))],
  );
}
