import 'package:flutter/material.dart';
import 'services/api.dart';
import 'ui/design.dart';

class ChatMecanimal extends StatefulWidget {
  final String idMaquina;
  const ChatMecanimal({super.key, required this.idMaquina});
  @override
  State<ChatMecanimal> createState() => _ChatMecanimalState();
}

class _ChatMecanimalState extends State<ChatMecanimal> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <Map<String, String>>[];
  bool busy = false;
  String? error;
  String? failedQuestion;

  @override
  void dispose() { input.dispose(); scroll.dispose(); super.dispose(); }

  void scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) {
      scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  });

  Future<void> send([String? suggestion]) async {
    final question = (suggestion ?? input.text).trim();
    if (busy || question.isEmpty) return;
    setState(() {
      if (question != failedQuestion) messages.add({'role': 'user', 'text': question});
      busy = true; error = null; input.clear();
    });
    scrollDown();
    try {
      final response = await Api.request('/api/chat', body: {'mensaje': question, 'id_maquina': widget.idMaquina});
      if (!mounted) return;
      setState(() { messages.add({'role': 'assistant', 'text': response['respuesta'] ?? 'No hay una respuesta disponible.'}); failedQuestion = null; });
    } catch (e) {
      if (mounted) setState(() { error = '$e'; failedQuestion = question; });
    } finally {
      if (mounted) { setState(() => busy = false); scrollDown(); }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mecanimal'), actions: [Padding(padding: const EdgeInsets.only(right: 20), child: StatusPill(widget.idMaquina))]),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: Column(children: [
      Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.all(24), children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Column(children: [
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: accent.withValues(alpha: .08), borderRadius: BorderRadius.circular(22)), child: const Icon(Icons.auto_awesome_rounded, size: 30, color: accent)),
          const SizedBox(height: 20), Text('Comprende lo que dice tu máquina', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10), const Text('Consulta sus lecturas, alertas y tendencias de mantenimiento.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
          const SizedBox(height: 24), Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
            for (final question in ['¿Cuál es el estado actual?', '¿Hay alguna alerta?', '¿Cuándo necesita mantenimiento?'])
              ActionChip(onPressed: busy ? null : () => send(question), label: Text(question), avatar: const Icon(Icons.north_east, size: 15)),
          ]),
        ])),
        for (final message in messages) Align(alignment: message['role'] == 'user' ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(constraints: const BoxConstraints(maxWidth: 640), margin: const EdgeInsets.only(bottom: 18), padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: message['role'] == 'user' ? ink : Colors.white, border: Border.all(color: message['role'] == 'user' ? ink : line), borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message['role'] == 'user' ? 'TÚ' : 'MECANIMAL', style: TextStyle(color: message['role'] == 'user' ? Colors.white60 : accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 9), SelectableText(message['text']!, style: TextStyle(color: message['role'] == 'user' ? Colors.white : ink, height: 1.65)),
            ]))),
        if (busy) const Padding(padding: EdgeInsets.all(12), child: Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Analizando la información...', style: TextStyle(color: muted))])),
        if (error != null) Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(error!), TextButton.icon(onPressed: busy ? null : () => send(failedQuestion), icon: const Icon(Icons.refresh), label: const Text('Reintentar'))]))),
      ])),
      SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(20, 16, 20, 12), decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: line))), child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, maxLength: 2000, textInputAction: TextInputAction.send, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Pregunta sobre esta máquina...', counterText: ''))),
          const SizedBox(width: 12), IconButton.filled(tooltip: 'Enviar mensaje', onPressed: busy ? null : () => send(), icon: const Icon(Icons.arrow_upward_rounded), padding: const EdgeInsets.all(16)),
        ]),
        const SizedBox(height: 10), const Text('Contrasta las recomendaciones con las lecturas y los procedimientos de tu planta.', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: muted)),
      ]))),
    ]))),
  );
}
