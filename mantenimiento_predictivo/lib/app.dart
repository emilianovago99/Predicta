import 'package:flutter/material.dart';
import 'services/api.dart';
import 'ui/design.dart';
import 'workspace.dart';

final sessionNavigator = GlobalKey<NavigatorState>();

class AppMantenimiento extends StatelessWidget {
  const AppMantenimiento({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Predicta · Inteligencia industrial', debugShowCheckedModeBanner: false,
    navigatorKey: sessionNavigator, theme: predictaTheme(), home: const PantallaLogin(),
  );
}

class PantallaLogin extends StatefulWidget {
  const PantallaLogin({super.key});
  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _hide = true;
  @override
  void initState() {
    super.initState();
    _busy = true;
    Api.client.onUnauthorized = () {
      sessionNavigator.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PantallaLogin()), (_) => false);
    };
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      await Api.initialize();
      if (Api.client.token == null) return;
      final user = await Api.request('/api/me');
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => Workspace(user: Map<String, dynamic>.from(user))));
      }
    } catch (_) { await Api.logout(); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  String? _error;
  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final user = await Api.request('/api/login', body: {'email': _email.text.trim(), 'password': _password.text});
      await Api.saveToken(user['access_token'] as String);
      _password.clear();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => Workspace(user: Map<String, dynamic>.from(user))));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _story() => Container(
    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF112C35), Color(0xFF0A4848)])),
    padding: const EdgeInsets.all(56),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      const Brand(light: true), const SizedBox(height: 76),
      const StatusPill('INTELIGENCIA INDUSTRIAL', color: Color(0xFF6EE7C0)),
      const SizedBox(height: 24),
      const Text('Cada señal cuenta.\nAnticípate al\nsiguiente fallo.', style: TextStyle(fontSize: 48, height: 1.12, letterSpacing: -2, fontWeight: FontWeight.w600, color: Colors.white)),
      const SizedBox(height: 24),
      const Text('Conecta tu operación. Comprende tus máquinas.\nToma decisiones con datos reales.', style: TextStyle(color: Color(0xFFB2CECE), fontSize: 17, height: 1.7)),
      const SizedBox(height: 48),
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06),
        border: Border.all(color: Colors.white.withValues(alpha: .12)), borderRadius: BorderRadius.circular(20)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('UNA VISIÓN COMPLETA DE TU OPERACIÓN', style: TextStyle(color: Color(0xFF83B8B2), fontSize: 10, letterSpacing: 1.5)),
          SizedBox(height: 20),
          Row(children: [Icon(Icons.business_outlined, color: Colors.white), SizedBox(width: 12), Expanded(child: Text('Empresas  →  Áreas  →  Máquinas', style: TextStyle(color: Colors.white, fontSize: 15)))]),
          SizedBox(height: 18),
          Text('Sensores conectados. Información en un solo lugar.', style: TextStyle(color: Color(0xFFB2CECE), fontSize: 12)),
        ])),
    ]),
  );

  Widget _loginForm() => Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 380),
    child: AutofillGroup(child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (MediaQuery.sizeOf(context).width < 960) const Padding(padding: EdgeInsets.only(bottom: 48), child: Brand()),
      const Text('TU ESPACIO DE TRABAJO', style: TextStyle(fontSize: 11, color: accent, letterSpacing: 2, fontWeight: FontWeight.w700)),
      const SizedBox(height: 14), Text('Bienvenido de nuevo', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 10), const Text('Tu operación, bajo una nueva perspectiva.', style: TextStyle(color: muted)),
      const SizedBox(height: 36),
      TextFormField(controller: _email, autofillHints: const [AutofillHints.username], keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline_rounded)),
        validator: (v) => v == null || !v.contains('@') ? 'Ingresa un correo válido' : null),
      const SizedBox(height: 18),
      TextFormField(controller: _password, autofillHints: const [AutofillHints.password], obscureText: _hide,
        onFieldSubmitted: (_) => _login(), decoration: InputDecoration(labelText: 'Contraseña', prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(tooltip: _hide ? 'Mostrar contraseña' : 'Ocultar contraseña', onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
        validator: (v) => v == null || v.isEmpty ? 'Ingresa tu contraseña' : null),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 26),
      FilledButton(onPressed: _busy ? null : _login, child: _busy
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('Entrar al espacio'), SizedBox(width: 12), Icon(Icons.arrow_forward_rounded, size: 18)])),

    ]))),
  )));

  @override
  Widget build(BuildContext context) => Scaffold(body: LayoutBuilder(builder: (context, constraints) => Row(children: [
    if (constraints.maxWidth >= 960) Expanded(child: SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints(minHeight: constraints.maxHeight), child: _story()))),
    Expanded(child: _loginForm()),
  ])));
}
