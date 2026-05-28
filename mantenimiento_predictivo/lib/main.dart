import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'pantalla_monitoreo.dart';

void main() {
  runApp(const AppMantenimiento());
}

class AppMantenimiento extends StatelessWidget {
  const AppMantenimiento({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mecanimales Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    iniciarApp();
  }

  Future<void> iniciarApp() async {
    await Future.delayed(const Duration(milliseconds: 3500));

    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const PantallaLogin()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade900,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.precision_manufacturing,
                size: 120,
                color: Colors.teal,
              ),
              const SizedBox(height: 30),
              const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'MECANIMALES',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'SaaS Industrial 4.0',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 100),
              const CircularProgressIndicator(color: Colors.teal),
            ],
          ),
        ),
      ),
    );
  }
}

class PantallaLogin extends StatefulWidget {
  const PantallaLogin({super.key});

  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  TextEditingController correoControlador = TextEditingController();
  TextEditingController passwordControlador = TextEditingController();
  bool cargando = false;

  Future<void> procesarLogin() async {
    setState(() {
      cargando = true;
    });

    final url = Uri.parse('http://10.10.7.161:8000/api/login');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': correoControlador.text,
          'password': passwordControlador.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['rol'] == 'instalador') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PantallaInstalador()),
          );
        }

        if (data['rol'] != 'instalador') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PantallaAreas(
                idEmpresa: data['id_empresa'],
                rol: data['rol'],
                nombreEmpresa: data['empresa_nombre'],
              ),
            ),
          );
        }
      }

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Credenciales incorrectas'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          cargando = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error de conexión con el servidor'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade900,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10.0,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.precision_manufacturing,
                  size: 80,
                  color: Colors.teal,
                ),
                const SizedBox(height: 16),
                const Text(
                  'MECANIMALES',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const Text(
                  'SaaS Industrial 4.0',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: correoControlador,
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: passwordControlador,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: procesarLogin,
                    child: const Text(
                      'INICIAR SESIÓN',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (cargando)
                  const Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PantallaInstalador extends StatefulWidget {
  const PantallaInstalador({super.key});

  @override
  State<PantallaInstalador> createState() => _PantallaInstaladorState();
}

class _PantallaInstaladorState extends State<PantallaInstalador> {
  List<dynamic> empresas = [];

  @override
  void initState() {
    super.initState();
    cargarEmpresas();
  }

  Future<void> cargarEmpresas() async {
    final url = Uri.parse('http://10.10.7.161:8000/api/empresas');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          empresas = json.decode(response.body);
        });
      }
    } catch (e) {
      empresas = [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Directorio de Empresas (Instalador)'),
        backgroundColor: Colors.teal.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const PantallaLogin()),
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: empresas.length,
        itemBuilder: (context, index) {
          return Card(
            elevation: 4,
            child: ListTile(
              leading: const Icon(Icons.business, size: 40, color: Colors.teal),
              title: Text(
                empresas[index]['nombre'],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('Gestionar áreas y maquinaria'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PantallaAreas(
                      idEmpresa: empresas[index]['id_empresa'],
                      rol: 'instalador',
                      nombreEmpresa: empresas[index]['nombre'],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PantallaCrearEmpresa(),
            ),
          ).then((_) => cargarEmpresas());
        },
        icon: const Icon(Icons.add_business),
        label: const Text('Nueva Empresa'),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class PantallaCrearEmpresa extends StatefulWidget {
  const PantallaCrearEmpresa({super.key});

  @override
  State<PantallaCrearEmpresa> createState() => _PantallaCrearEmpresaState();
}

class _PantallaCrearEmpresaState extends State<PantallaCrearEmpresa> {
  TextEditingController nombreEmpresaCtrl = TextEditingController();
  TextEditingController jefeNombreCtrl = TextEditingController();
  TextEditingController jefeEmailCtrl = TextEditingController();
  TextEditingController jefePassCtrl = TextEditingController();

  Future<void> guardarEmpresaYJefe() async {
    if (nombreEmpresaCtrl.text.isEmpty) {
      return;
    }
    if (jefeEmailCtrl.text.isEmpty) {
      return;
    }

    final urlEmpresa = Uri.parse(
      'http://10.10.7.161:8000/api/empresas_rapido?nombre=${nombreEmpresaCtrl.text}',
    );

    try {
      final responseEmpresa = await http.post(urlEmpresa);

      if (responseEmpresa.statusCode == 200) {
        final dataEmpresa = json.decode(responseEmpresa.body);
        final idEmpresaGenerada = dataEmpresa['id_empresa'];

        final urlUsuario = Uri.parse('http://10.10.7.161:8000/api/usuarios');
        final responseUsuario = await http.post(
          urlUsuario,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'id_empresa': idEmpresaGenerada,
            'nombre': jefeNombreCtrl.text,
            'email': jefeEmailCtrl.text,
            'password': jefePassCtrl.text,
            'rol': 'jefe',
          }),
        );

        if (responseUsuario.statusCode == 200) {
          if (mounted) {
            Navigator.pop(context);
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al crear empresa y asignar jefe'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Empresa y Jefe'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Datos de la Empresa',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nombreEmpresaCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre Comercial',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Asignar Jefe de Mantenimiento',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: jefeNombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre Completo del Jefe',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: jefeEmailCtrl,
              decoration: const InputDecoration(
                labelText: 'Correo Electrónico',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: jefePassCtrl,
              decoration: const InputDecoration(
                labelText: 'Contraseña Asignada',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: guardarEmpresaYJefe,
                child: const Text('GUARDAR EMPRESA Y CREAR CUENTA DE JEFE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PantallaAreas extends StatefulWidget {
  final int idEmpresa;
  final String rol;
  final String nombreEmpresa;

  const PantallaAreas({
    super.key,
    required this.idEmpresa,
    required this.rol,
    required this.nombreEmpresa,
  });

  @override
  State<PantallaAreas> createState() => _PantallaAreasState();
}

class _PantallaAreasState extends State<PantallaAreas> {
  List<dynamic> areas = [];

  @override
  void initState() {
    super.initState();
    cargarAreas();
  }

  Future<void> cargarAreas() async {
    final url = Uri.parse(
      'http://10.10.7.161:8000/api/empresas/${widget.idEmpresa}/areas',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          areas = json.decode(response.body);
        });
      }
    } catch (e) {
      areas = [];
    }
  }

  Widget? construirBotonAgregar(BuildContext context) {
    if (widget.rol == 'jefe') {
      return FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  PantallaCrearArea(idEmpresa: widget.idEmpresa),
            ),
          ).then((_) => cargarAreas());
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva Área'),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      );
    }
    if (widget.rol == 'instalador') {
      return FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  PantallaCrearArea(idEmpresa: widget.idEmpresa),
            ),
          ).then((_) => cargarAreas());
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva Área'),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Color colorBarra = Colors.blueGrey.shade900;
    if (widget.rol == 'instalador') {
      colorBarra = Colors.teal.shade900;
    }

    List<Widget> accionesBarra = [];

    if (widget.rol == 'jefe') {
      accionesBarra.add(
        IconButton(
          icon: const Icon(Icons.person_add),
          tooltip: 'Registrar Participante',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    PantallaCrearParticipante(idEmpresa: widget.idEmpresa),
              ),
            );
          },
        ),
      );
    }

    if (widget.rol != 'instalador') {
      accionesBarra.add(
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const PantallaLogin()),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('Áreas - ${widget.nombreEmpresa}'),
        backgroundColor: colorBarra,
        foregroundColor: Colors.white,
        actions: accionesBarra,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: areas.length,
        itemBuilder: (context, index) {
          return Card(
            elevation: 4,
            child: ListTile(
              leading: const Icon(
                Icons.factory,
                size: 40,
                color: Colors.blueGrey,
              ),
              title: Text(
                areas[index]['nombre'],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('Ver máquinas asignadas'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PantallaMaquinas(
                      idArea: areas[index]['id_area'],
                      rol: widget.rol,
                      idEmpresa: widget.idEmpresa,
                      nombreArea: areas[index]['nombre'],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: construirBotonAgregar(context),
    );
  }
}

class PantallaCrearParticipante extends StatelessWidget {
  final int idEmpresa;

  final TextEditingController nombreCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController passCtrl = TextEditingController();

  PantallaCrearParticipante({super.key, required this.idEmpresa});

  Future<void> registrarEnBaseDeDatos(BuildContext context) async {
    if (emailCtrl.text.isEmpty) {
      return;
    }
    final url = Uri.parse('http://10.10.7.161:8000/api/usuarios');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id_empresa': idEmpresa,
          'nombre': nombreCtrl.text,
          'email': emailCtrl.text,
          'password': passCtrl.text,
          'rol': 'participante',
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Participante registrado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al crear cuenta'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Añadir Participante al Proyecto'),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre Completo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Correo Electrónico',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passCtrl,
              decoration: const InputDecoration(
                labelText: 'Contraseña Provisional',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => registrarEnBaseDeDatos(context),
                child: const Text('CREAR CUENTA DE PARTICIPANTE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PantallaCrearArea extends StatelessWidget {
  final int idEmpresa;
  final TextEditingController nombreAreaCtrl = TextEditingController();

  PantallaCrearArea({super.key, required this.idEmpresa});

  Future<void> guardarArea(BuildContext context) async {
    final url = Uri.parse('http://10.10.7.161:8000/api/areas');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id_empresa': idEmpresa,
          'nombre': nombreAreaCtrl.text,
        }),
      );
      if (response.statusCode == 200) {
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al crear área'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Añadir Nueva Área'),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: nombreAreaCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del Área (ej. Línea de Empaque)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => guardarArea(context),
                child: const Text('GUARDAR ÁREA'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PantallaMaquinas extends StatefulWidget {
  final int idArea;
  final String rol;
  final int idEmpresa;
  final String nombreArea;

  const PantallaMaquinas({
    super.key,
    required this.idArea,
    required this.rol,
    required this.idEmpresa,
    required this.nombreArea,
  });

  @override
  State<PantallaMaquinas> createState() => _PantallaMaquinasState();
}

class _PantallaMaquinasState extends State<PantallaMaquinas> {
  List<dynamic> maquinas = [];

  @override
  void initState() {
    super.initState();
    cargarMaquinas();
  }

  Future<void> cargarMaquinas() async {
    final url = Uri.parse(
      'http://10.10.7.161:8000/api/areas/${widget.idArea}/maquinas',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          maquinas = json.decode(response.body);
        });
      }
    } catch (e) {
      maquinas = [];
    }
  }

  Widget? construirBotonEdicion(BuildContext context, String idMaquina) {
    if (widget.rol == 'jefe') {
      return IconButton(
        icon: const Icon(Icons.settings, color: Colors.teal),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PantallaConfiguracion(
                idMaquina: idMaquina,
                idEmpresa: widget.idEmpresa,
              ),
            ),
          ).then((_) => cargarMaquinas());
        },
      );
    }
    if (widget.rol == 'instalador') {
      return IconButton(
        icon: const Icon(Icons.settings, color: Colors.teal),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PantallaConfiguracion(
                idMaquina: idMaquina,
                idEmpresa: widget.idEmpresa,
              ),
            ),
          ).then((_) => cargarMaquinas());
        },
      );
    }
    return const Icon(Icons.speed, color: Colors.blueAccent);
  }

  Widget? construirBotonAgregarMaquina(BuildContext context) {
    if (widget.rol == 'instalador') {
      return FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  PantallaVincularMaquina(idArea: widget.idArea),
            ),
          ).then((_) => cargarMaquinas());
        },
        icon: const Icon(Icons.precision_manufacturing),
        label: const Text('Vincular Hardware'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Color colorBarra = Colors.blueGrey.shade800;
    if (widget.rol == 'instalador') {
      colorBarra = Colors.teal.shade800;
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('Máquinas - ${widget.nombreArea}'),
        backgroundColor: colorBarra,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: maquinas.length,
        itemBuilder: (context, index) {
          return Card(
            elevation: 4,
            child: ListTile(
              leading: const Icon(
                Icons.precision_manufacturing,
                size: 40,
                color: Colors.blueGrey,
              ),
              title: Text(
                maquinas[index]['nombre'],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'ID Físico: ${maquinas[index]['id_maquina']} | Estado: ${maquinas[index]['estado']}',
              ),
              trailing: construirBotonEdicion(
                context,
                maquinas[index]['id_maquina'],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PantallaMonitoreo(
                      idMaquina: maquinas[index]['id_maquina'],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: construirBotonAgregarMaquina(context),
    );
  }
}

class PantallaVincularMaquina extends StatefulWidget {
  final int idArea;

  const PantallaVincularMaquina({super.key, required this.idArea});

  @override
  State<PantallaVincularMaquina> createState() =>
      _PantallaVincularMaquinaState();
}

class _PantallaVincularMaquinaState extends State<PantallaVincularMaquina> {
  final TextEditingController idMaquinaCtrl = TextEditingController();
  final TextEditingController nombreCtrl = TextEditingController();

  bool medirTemp = true;
  bool medirVib = true;
  bool medirVolt = true;
  bool medirVel = true;
  bool medirHum = true;

  Future<void> guardarMaquina(BuildContext context) async {
    final url = Uri.parse('http://10.10.7.161:8000/api/maquinas');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id_area': widget.idArea,
          'id_maquina': idMaquinaCtrl.text,
          'nombre': nombreCtrl.text,
          'medir_temp': medirTemp,
          'medir_vib': medirVib,
          'medir_volt': medirVolt,
          'medir_vel': medirVel,
          'medir_hum': medirHum,
        }),
      );
      if (response.statusCode == 200) {
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al vincular máquina'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vincular Nuevo Hardware'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: idMaquinaCtrl,
              decoration: const InputDecoration(
                labelText: 'MAC / ID del Hardware Físico (ej. M-05)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre Descriptivo (ej. Banda Transportadora)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Sensores Activos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            SwitchListTile(
              title: const Text('Temperatura'),
              value: medirTemp,
              onChanged: (bool valor) {
                setState(() {
                  medirTemp = valor;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Vibración'),
              value: medirVib,
              onChanged: (bool valor) {
                setState(() {
                  medirVib = valor;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Voltaje'),
              value: medirVolt,
              onChanged: (bool valor) {
                setState(() {
                  medirVolt = valor;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Velocidad'),
              value: medirVel,
              onChanged: (bool valor) {
                setState(() {
                  medirVel = valor;
                });
              },
            ),
            SwitchListTile(
              title: const Text('Humedad'),
              value: medirHum,
              onChanged: (bool valor) {
                setState(() {
                  medirHum = valor;
                });
              },
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => guardarMaquina(context),
                child: const Text('GUARDAR Y VINCULAR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PantallaConfiguracion extends StatefulWidget {
  final String idMaquina;
  final int idEmpresa;

  const PantallaConfiguracion({
    super.key,
    required this.idMaquina,
    required this.idEmpresa,
  });

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  TextEditingController nombreControlador = TextEditingController();
  TextEditingController tAlertaCtrl = TextEditingController();
  TextEditingController tPeligroCtrl = TextEditingController();
  TextEditingController vibAlertaCtrl = TextEditingController();
  TextEditingController vibPeligroCtrl = TextEditingController();
  TextEditingController voltAlertaCtrl = TextEditingController();
  TextEditingController voltPeligroCtrl = TextEditingController();
  TextEditingController velAlertaCtrl = TextEditingController();
  TextEditingController velPeligroCtrl = TextEditingController();
  TextEditingController humAlertaCtrl = TextEditingController();
  TextEditingController humPeligroCtrl = TextEditingController();

  int? idAreaActual;
  List<dynamic> areasDisponibles = [];

  bool medirTemp = true;
  bool medirVib = true;
  bool medirVolt = true;
  bool medirVel = true;
  bool medirHum = true;

  @override
  void initState() {
    super.initState();
    cargarAreas().then((_) => cargarConfiguracion());
  }

  Future<void> cargarAreas() async {
    final url = Uri.parse(
      'http://10.10.7.161:8000/api/empresas/${widget.idEmpresa}/areas',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          areasDisponibles = json.decode(response.body);
        });
      }
    } catch (e) {
      areasDisponibles = [];
    }
  }

  Future<void> cargarConfiguracion() async {
    final url = Uri.parse(
      'http://10.10.7.161:8000/api/maquinas/${widget.idMaquina}/config',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          nombreControlador.text = data['nombre'];
          idAreaActual = data['id_area'];
          tAlertaCtrl.text = data['temp_alerta'].toString();
          tPeligroCtrl.text = data['temp_peligro'].toString();
          vibAlertaCtrl.text = data['vib_alerta'].toString();
          vibPeligroCtrl.text = data['vib_peligro'].toString();
          voltAlertaCtrl.text = data['volt_alerta'].toString();
          voltPeligroCtrl.text = data['volt_peligro'].toString();
          velAlertaCtrl.text = data['vel_alerta'].toString();
          velPeligroCtrl.text = data['vel_peligro'].toString();
          humAlertaCtrl.text = data['hum_alerta'].toString();
          humPeligroCtrl.text = data['hum_peligro'].toString();

          if (data['medir_temp'] == 1) {
            medirTemp = true;
          }
          if (data['medir_temp'] == 0) {
            medirTemp = false;
          }
          if (data['medir_vib'] == 1) {
            medirVib = true;
          }
          if (data['medir_vib'] == 0) {
            medirVib = false;
          }
          if (data['medir_volt'] == 1) {
            medirVolt = true;
          }
          if (data['medir_volt'] == 0) {
            medirVolt = false;
          }
          if (data['medir_vel'] == 1) {
            medirVel = true;
          }
          if (data['medir_vel'] == 0) {
            medirVel = false;
          }
          if (data['medir_hum'] == 1) {
            medirHum = true;
          }
          if (data['medir_hum'] == 0) {
            medirHum = false;
          }
        });
      }
    } catch (e) {
      nombreControlador.text = 'Error de carga';
    }
  }

  Future<void> guardarConfiguracion() async {
    if (idAreaActual == null) {
      return;
    }
    final url = Uri.parse(
      'http://10.10.7.161:8000/api/maquinas/${widget.idMaquina}/config',
    );
    try {
      await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'nombre': nombreControlador.text,
          'id_area': idAreaActual,
          'temp_alerta': double.parse(tAlertaCtrl.text),
          'temp_peligro': double.parse(tPeligroCtrl.text),
          'vib_alerta': double.parse(vibAlertaCtrl.text),
          'vib_peligro': double.parse(vibPeligroCtrl.text),
          'volt_alerta': double.parse(voltAlertaCtrl.text),
          'volt_peligro': double.parse(voltPeligroCtrl.text),
          'vel_alerta': int.parse(velAlertaCtrl.text),
          'vel_peligro': int.parse(velPeligroCtrl.text),
          'hum_alerta': double.parse(humAlertaCtrl.text),
          'hum_peligro': double.parse(humPeligroCtrl.text),
          'medir_temp': medirTemp,
          'medir_vib': medirVib,
          'medir_volt': medirVolt,
          'medir_vel': medirVel,
          'medir_hum': medirHum,
        }),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al guardar configuración')),
      );
    }
  }

  List<DropdownMenuItem<int>> obtenerItemsAreas() {
    List<DropdownMenuItem<int>> items = [];
    for (var area in areasDisponibles) {
      items.add(
        DropdownMenuItem(value: area['id_area'], child: Text(area['nombre'])),
      );
    }
    return items;
  }

  Widget construirSeccionLimite(
    String titulo,
    TextEditingController ctrlAlerta,
    TextEditingController ctrlPeligro,
    bool activo,
    ValueChanged<bool> onChangeSwitch,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            Switch(value: activo, onChanged: onChangeSwitch),
          ],
        ),
        if (activo)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrlAlerta,
                  decoration: const InputDecoration(labelText: 'Alerta'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: ctrlPeligro,
                  decoration: const InputDecoration(labelText: 'Peligro'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Activo y Límites'),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text(
              'Ubicación e Identidad',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nombreControlador,
              decoration: const InputDecoration(
                labelText: 'Nombre de la Máquina',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (areasDisponibles.isNotEmpty)
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Área Asignada',
                  border: OutlineInputBorder(),
                ),
                value: idAreaActual,
                items: obtenerItemsAreas(),
                onChanged: (int? valor) {
                  if (valor != null) {
                    setState(() {
                      idAreaActual = valor;
                    });
                  }
                },
              ),
            const SizedBox(height: 32),
            construirSeccionLimite(
              'Límites de Temperatura (°C)',
              tAlertaCtrl,
              tPeligroCtrl,
              medirTemp,
              (bool val) {
                setState(() {
                  medirTemp = val;
                });
              },
            ),
            construirSeccionLimite(
              'Límites de Vibración (mm/s)',
              vibAlertaCtrl,
              vibPeligroCtrl,
              medirVib,
              (bool val) {
                setState(() {
                  medirVib = val;
                });
              },
            ),
            construirSeccionLimite(
              'Límites de Voltaje (V)',
              voltAlertaCtrl,
              voltPeligroCtrl,
              medirVolt,
              (bool val) {
                setState(() {
                  medirVolt = val;
                });
              },
            ),
            construirSeccionLimite(
              'Límites de Velocidad (RPM)',
              velAlertaCtrl,
              velPeligroCtrl,
              medirVel,
              (bool val) {
                setState(() {
                  medirVel = val;
                });
              },
            ),
            construirSeccionLimite(
              'Límites de Humedad (%)',
              humAlertaCtrl,
              humPeligroCtrl,
              medirHum,
              (bool val) {
                setState(() {
                  medirHum = val;
                });
              },
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: guardarConfiguracion,
                child: const Text('GUARDAR CAMBIOS EN LA NUBE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
