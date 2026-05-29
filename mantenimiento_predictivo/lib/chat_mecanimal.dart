import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config/api_config.dart';

class ChatMecanimal extends StatefulWidget {
  final String idMaquina;

  const ChatMecanimal({super.key, required this.idMaquina});

  @override
  State<ChatMecanimal> createState() => _ChatMecanimalState();
}

class _ChatMecanimalState extends State<ChatMecanimal> {
  TextEditingController controlador = TextEditingController();
  List<Map<String, String>> mensajes = [];
  bool escribiendo = false;

  @override
  void initState() {
    super.initState();
    mensajes.add({
      'rol': 'bot',
      'texto':
          '¡Hola humano! Soy tu Asistente Mecanimal 🐾🤖\n¿Qué quieres saber sobre el estado de la máquina ${widget.idMaquina}?',
    });
  }

  Future<void> enviarMensaje() async {
    String texto = controlador.text.trim();
    if (texto.isEmpty) {
      return;
    }

    setState(() {
      mensajes.add({'rol': 'user', 'texto': texto});
      controlador.clear();
      escribiendo = true;
    });

    final url = ApiConfig.uri('/api/chat');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'mensaje': texto, 'id_maquina': widget.idMaquina}),
      );

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          final respuesta = data['respuesta'] ?? 'Sin respuesta';
          setState(() {
            mensajes.add({'rol': 'bot', 'texto': respuesta});
            escribiendo = false;
          });
        } catch (parseError) {
          setState(() {
            mensajes.add({
              'rol': 'bot',
              'texto': 'Error procesando respuesta del servidor. 🤔',
            });
            escribiendo = false;
          });
        }
      } else {
        setState(() {
          mensajes.add({
            'rol': 'bot',
            'texto':
                'Error ${response.statusCode}: Mecanimal con falla en servidor. 🔧',
          });
          escribiendo = false;
        });
      }
    } catch (e) {
      setState(() {
        mensajes.add({
          'rol': 'bot',
          'texto': 'Mecanimal desconectado. Revisa la conexión de red 🔌',
        });
        escribiendo = false;
      });
    }
  }

  Widget construirBurbuja(Map<String, String> mensaje) {
    bool esUsuario = false;
    if (mensaje['rol'] == 'user') {
      esUsuario = true;
    }

    Alignment alineacion = Alignment.centerLeft;
    Color colorBurbuja = Colors.white;
    Color colorTexto = Colors.black87;
    EdgeInsets margenes = const EdgeInsets.only(
      top: 8,
      bottom: 8,
      right: 60,
      left: 16,
    );

    if (esUsuario) {
      alineacion = Alignment.centerRight;
      colorBurbuja = Colors.teal.shade700;
      colorTexto = Colors.white;
      margenes = const EdgeInsets.only(top: 8, bottom: 8, right: 16, left: 60);
    }

    return Container(
      alignment: alineacion,
      margin: margenes,
      child: Container(
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: colorBurbuja,
          borderRadius: BorderRadius.circular(16.0),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4.0,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          mensaje['texto']!,
          style: TextStyle(color: colorTexto, fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      appBar: AppBar(
        title: const Text('Mecanimal 🐾🤖'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: mensajes.length,
              itemBuilder: (context, index) {
                return construirBurbuja(mensajes[index]);
              },
            ),
          ),
          if (escribiendo)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controlador,
                    decoration: InputDecoration(
                      hintText: 'Pregúntale al Mecanimal...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                FloatingActionButton(
                  onPressed: enviarMensaje,
                  backgroundColor: Colors.teal.shade800,
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
