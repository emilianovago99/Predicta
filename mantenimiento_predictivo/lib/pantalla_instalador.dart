import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PantallaInstalador extends StatefulWidget {
  const PantallaInstalador({super.key});

  @override
  State<PantallaInstalador> createState() => _PantallaInstaladorState();
}

class _PantallaInstaladorState extends State<PantallaInstalador> {
  final TextEditingController nombreController = TextEditingController();
  String mensaje = '';
  bool cargando = false;

  List<dynamic> empresas = [];
  List<dynamic> areas = [];

  int? empresaSeleccionada;
  int? areaSeleccionada;

  @override
  void initState() {
    super.initState();
    cargarEmpresas();
  }

  Future<void> cargarEmpresas() async {
    final url = Uri.parse('http://192.168.1.10:8000/api/empresas');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          empresas = json.decode(response.body);
        });
      }
    } catch (e) {
      setState(() {
        mensaje = 'Error al cargar empresas';
      });
    }
  }

  Future<void> cargarAreas(int idEmpresa) async {
    final url = Uri.parse(
      'http://192.168.1.10:8000/api/empresas/$idEmpresa/areas',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          areas = json.decode(response.body);
          areaSeleccionada = null;
        });
      }
    } catch (e) {
      setState(() {
        mensaje = 'Error al cargar áreas';
      });
    }
  }

  Future<void> crearEmpresa(String nombreEmpresa) async {
    final url = Uri.parse(
      'http://192.168.1.10:8000/api/empresas_rapido?nombre=$nombreEmpresa',
    );
    try {
      final response = await http.post(url);
      if (response.statusCode == 200) {
        await cargarEmpresas();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Empresa creada')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error al crear empresa')));
      }
    }
  }

  Future<void> crearArea(String nombreArea) async {
    if (empresaSeleccionada == null) return;

    final url = Uri.parse('http://192.168.1.10:8000/api/areas');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id_empresa': empresaSeleccionada,
          'nombre': nombreArea,
        }),
      );
      if (response.statusCode == 200) {
        await cargarAreas(empresaSeleccionada!);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Área creada')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error al crear área')));
      }
    }
  }

  void mostrarDialogoCreacion(String tipo) {
    TextEditingController nuevoNombreController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Crear nueva $tipo'),
          content: TextField(
            controller: nuevoNombreController,
            decoration: InputDecoration(hintText: 'Nombre de la $tipo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nuevoNombreController.text.isNotEmpty) {
                  if (tipo == 'Empresa') {
                    crearEmpresa(nuevoNombreController.text);
                  } else {
                    crearArea(nuevoNombreController.text);
                  }
                  Navigator.pop(context);
                }
              },
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );
  }

  Future<void> registrarMaquina() async {
    if (areaSeleccionada == null) {
      setState(() {
        mensaje = 'Por favor selecciona un área';
      });
      return;
    }

    if (nombreController.text.isEmpty) {
      setState(() {
        mensaje = 'Por favor ingresa un nombre';
      });
      return;
    }

    setState(() {
      cargando = true;
      mensaje = '';
    });

    final url = Uri.parse('http://192.168.1.10:8000/api/maquinas');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id_area': areaSeleccionada,
          'nombre': nombreController.text,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          mensaje = 'Hardware enlazado exitosamente';
          nombreController.clear();
        });
      } else {
        setState(() {
          mensaje = 'Error al registrar la máquina';
        });
      }
    } catch (e) {
      setState(() {
        mensaje = 'Error de conexión con el servidor';
      });
    } finally {
      setState(() {
        cargando = false;
      });
    }
  }

  Widget construirSelectorEmpresa() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            decoration: const InputDecoration(
              labelText: 'Seleccionar Empresa Cliente',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business),
            ),
            value: empresaSeleccionada,
            items: empresas.map<DropdownMenuItem<int>>((dynamic empresa) {
              return DropdownMenuItem<int>(
                value: empresa['id_empresa'],
                child: Text(empresa['nombre']),
              );
            }).toList(),
            onChanged: (int? valor) {
              setState(() {
                empresaSeleccionada = valor;
              });
              if (valor != null) {
                cargarAreas(valor);
              }
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle, color: Colors.teal, size: 30),
          onPressed: () => mostrarDialogoCreacion('Empresa'),
        ),
      ],
    );
  }

  Widget construirSelectorArea() {
    if (empresaSeleccionada == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20.0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Seleccionar Área',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.domain),
              ),
              value: areaSeleccionada,
              items: areas.map<DropdownMenuItem<int>>((dynamic area) {
                return DropdownMenuItem<int>(
                  value: area['id_area'],
                  child: Text(area['nombre']),
                );
              }).toList(),
              onChanged: (int? valor) {
                setState(() {
                  areaSeleccionada = valor;
                });
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.teal, size: 30),
            onPressed: () => mostrarDialogoCreacion('Área'),
          ),
        ],
      ),
    );
  }

  Widget construirBoton() {
    if (cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    return ElevatedButton(
      onPressed: registrarMaquina,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text(
        'Vincular y Guardar',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Mecanimales - Admin'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.engineering, size: 60, color: Colors.teal),
                  const SizedBox(height: 16),
                  const Text(
                    'Gestión de Hardware',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  if (empresas.isEmpty)
                    const Center(child: CircularProgressIndicator()),
                  if (empresas.isNotEmpty) construirSelectorEmpresa(),
                  construirSelectorArea(),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre o Tag de la Máquina',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.precision_manufacturing),
                    ),
                  ),
                  const SizedBox(height: 32),
                  construirBoton(),
                  const SizedBox(height: 20),
                  Text(
                    mensaje,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
