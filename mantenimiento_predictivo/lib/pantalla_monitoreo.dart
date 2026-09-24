import 'package:flutter/material.dart';
import 'dart:async';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'services/api.dart';
import 'ui/design.dart';
import 'chat_mecanimal.dart';

class PuntoGrafica {
  PuntoGrafica(this.tiempo, this.valor);
  final int tiempo;
  final double valor;
}

class PantallaMonitoreo extends StatefulWidget {
  final String idMaquina;
  final VoidCallback? onBack;

  const PantallaMonitoreo({super.key, required this.idMaquina, this.onBack});

  @override
  State<PantallaMonitoreo> createState() => _PantallaMonitoreoState();
}

class _PantallaMonitoreoState extends State<PantallaMonitoreo> {
  String estado = 'optimo';
  String nombre = 'Cargando datos...';
  Map<String, dynamic>? incident;
  String resumenAlerta = 'Sin alertas recientes.';

  double temperatura = 0.0;
  double tempAmbiente = 0.0;
  double vibracion = 0.0;
  int velocidad = 0;
  double voltaje = 0.0;
  double humedad = 0.0;

  double tAlerta = 50.0;
  double tPeligro = 60.0;
  double tAmbAlerta = 30.0;
  double tAmbPeligro = 38.0;
  double vibAlerta = 4.0;
  double vibPeligro = 7.0;
  double voltAlerta = 125.0;
  double voltPeligro = 135.0;
  int velAlerta = 1800;
  int velPeligro = 1900;
  double humAlerta = 60.0;
  double humPeligro = 80.0;

  bool medirTemp = true;
  bool medirTempAmb = true;
  bool medirVib = true;
  bool medirVolt = true;
  bool medirVel = true;
  bool medirHum = true;

  String metricaActiva = 'Temp. motor';

  String estadoPrediccion = 'Evaluando métricas...';
  int rulCiclos = -1;
  int rulPeligroCiclos = -1;

  List<PuntoGrafica> histTemp = [];
  List<PuntoGrafica> histTempAmb = [];
  List<PuntoGrafica> histVib = [];
  List<PuntoGrafica> histVel = [];
  List<PuntoGrafica> histVolt = [];
  List<PuntoGrafica> histHum = [];

  List<PuntoGrafica> datosGraficaActual = [];

  Timer? temporizador;
  bool _fetching = false, _predicting = false, _loaded = false;
  String? _error;
  bool _stale = false;
  late final TrackballBehavior _trackballBehavior = TrackballBehavior(
    enable: true,
    activationMode: ActivationMode.singleTap,
    lineType: TrackballLineType.vertical,
    tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
    markerSettings: const TrackballMarkerSettings(
      markerVisibility: TrackballVisibilityMode.visible,
      height: 8,
      width: 8,
    ),
  );

  double _asDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  int _asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  Map<String, dynamic>? _lecturaMasReciente(List<dynamic> historial) {
    if (historial.isEmpty) return null;

    Map<String, dynamic>? reciente;
    double menorEdad = double.infinity;

    for (final row in historial) {
      if (row is! Map) continue;
      final lectura = Map<String, dynamic>.from(row);
      final edad = _asDouble(lectura['edad_segundos'], double.infinity);
      if (edad < menorEdad) {
        menorEdad = edad;
        reciente = lectura;
      }
    }

    return reciente ?? Map<String, dynamic>.from(historial.first as Map);
  }

  List<Map<String, dynamic>> _historialCronologico(List<dynamic> historial) {
    final filas = historial
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    filas.sort((a, b) {
      final edadA = _asDouble(a['edad_segundos'], double.infinity);
      final edadB = _asDouble(b['edad_segundos'], double.infinity);
      return edadB.compareTo(edadA);
    });

    return filas;
  }

  @override
  void initState() {
    super.initState();
    obtenerDatosMaquina();
    obtenerPrediccionML();
    temporizador = Timer.periodic(const Duration(seconds: 2), (timer) {
      obtenerDatosMaquina();
      obtenerPrediccionML();
    });
  }

  @override
  void dispose() {
    if (temporizador != null) {
      temporizador!.cancel();
    }
    super.dispose();
  }

  Future<void> obtenerPrediccionML() async {
    if (_predicting) return;
    _predicting = true;
    try {
      final data = await Api.request('/api/maquinas/${widget.idMaquina}/prediccion');
      if (mounted) {
        setState(() {
          estadoPrediccion = data['prediccion'];
          rulCiclos = data['rul_ciclos'];
          final peligro = data['rul_peligro_ciclos'];
          if (peligro is int) {
            rulPeligroCiclos = peligro;
          } else if (peligro is num) {
            rulPeligroCiclos = peligro.toInt();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => estadoPrediccion = 'Predicción no disponible');
    } finally {
      _predicting = false;
    }
  }

  Future<void> obtenerDatosMaquina() async {
    if (_fetching) return;
    _fetching = true;

    try {
      final data = await Api.request('/api/maquinas/${widget.idMaquina}/datos');
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = null;
            final history = (data['historial'] as List?) ?? const [];
            final lecturaReciente = _lecturaMasReciente(history);
            _stale = lecturaReciente != null &&
              _asDouble(lecturaReciente['edad_segundos'], 999) > 30;
          nombre = data['maquina']['nombre'];
          estado = data['maquina']['estado'];

          tAlerta = data['maquina']['temp_alerta'].toDouble();
          tPeligro = data['maquina']['temp_peligro'].toDouble();
          vibAlerta = data['maquina']['vib_alerta'].toDouble();
          vibPeligro = data['maquina']['vib_peligro'].toDouble();
          voltAlerta = data['maquina']['volt_alerta'].toDouble();
          voltPeligro = data['maquina']['volt_peligro'].toDouble();
          velAlerta = data['maquina']['vel_alerta'].toInt();
          velPeligro = data['maquina']['vel_peligro'].toInt();
          humAlerta = data['maquina']['hum_alerta'].toDouble();
          humPeligro = data['maquina']['hum_peligro'].toDouble();
          if (data['maquina']['temp_amb_alerta'] != null) {
            tAmbAlerta = data['maquina']['temp_amb_alerta'].toDouble();
          }
          if (data['maquina']['temp_amb_peligro'] != null) {
            tAmbPeligro = data['maquina']['temp_amb_peligro'].toDouble();
          }

          if (data['maquina']['medir_temp'] == 1) {
            medirTemp = true;
          }
          if (data['maquina']['medir_temp'] == 0) {
            medirTemp = false;
          }
          if (data['maquina']['medir_temp_amb'] == 1) {
            medirTempAmb = true;
          }
          if (data['maquina']['medir_temp_amb'] == 0) {
            medirTempAmb = false;
          }
          if (data['maquina']['medir_vib'] == 1) {
            medirVib = true;
          }
          if (data['maquina']['medir_vib'] == 0) {
            medirVib = false;
          }
          if (data['maquina']['medir_volt'] == 1) {
            medirVolt = true;
          }
          if (data['maquina']['medir_volt'] == 0) {
            medirVolt = false;
          }
          if (data['maquina']['medir_vel'] == 1) {
            medirVel = true;
          }
          if (data['maquina']['medir_vel'] == 0) {
            medirVel = false;
          }
          if (data['maquina']['medir_hum'] == 1) {
            medirHum = true;
          }
          if (data['maquina']['medir_hum'] == 0) {
            medirHum = false;
          }

          incident = data['ultima_alerta'] == null ? null : Map<String, dynamic>.from(data['ultima_alerta']);
          resumenAlerta = incident?['action'] ?? 'Sin alertas recientes.';

          if (history.isNotEmpty && lecturaReciente != null) {
              temperatura = _asDouble(lecturaReciente['temperatura']);
              tempAmbiente = _asDouble(lecturaReciente['temp_ambiente']);
              vibracion = _asDouble(lecturaReciente['vibracion']);
              velocidad = _asInt(lecturaReciente['velocidad']);
              voltaje = _asDouble(lecturaReciente['voltaje']);
              humedad = _asDouble(lecturaReciente['humedad']);

              histTemp.clear();
              histTempAmb.clear();
              histVib.clear();
              histVel.clear();
              histVolt.clear();
              histHum.clear();

              final listaCronologica = _historialCronologico(history);
              int contador = 0;

              for (var lectura in listaCronologica) {
                histTemp.add(
                  PuntoGrafica(contador, _asDouble(lectura['temperatura'])),
                );
                if (lectura['temp_ambiente'] != null) {
                  histTempAmb.add(
                    PuntoGrafica(contador, _asDouble(lectura['temp_ambiente'])),
                  );
                }
                histVib.add(
                  PuntoGrafica(contador, _asDouble(lectura['vibracion'])),
                );
                histVel.add(
                  PuntoGrafica(contador, _asDouble(lectura['velocidad'])),
                );
                histVolt.add(
                  PuntoGrafica(contador, _asDouble(lectura['voltaje'])),
                );
                histHum.add(
                  PuntoGrafica(contador, _asDouble(lectura['humedad'])),
                );
                contador++;
              }

              actualizarDatosGrafica();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loaded = true; });
    } finally {
      _fetching = false;
    }
  }

  void actualizarDatosGrafica() {
    if (metricaActiva == 'Temp. motor') {
      datosGraficaActual = histTemp;
    }
    if (metricaActiva == 'Temp. ambiente') {
      datosGraficaActual = histTempAmb;
    }
    if (metricaActiva == 'Comparar temps') {
      datosGraficaActual = histTemp;
    }
    if (metricaActiva == 'Vibración') {
      datosGraficaActual = histVib;
    }
    if (metricaActiva == 'Velocidad') {
      datosGraficaActual = histVel;
    }
    if (metricaActiva == 'Voltaje') {
      datosGraficaActual = histVolt;
    }
    if (metricaActiva == 'Humedad') {
      datosGraficaActual = histHum;
    }
  }

  Color obtenerColorTarjeta() {
    if (estado == 'optimo') {
      return Colors.green.shade700;
    }
    if (estado == 'alerta') {
      return Colors.orange.shade700;
    }
    return Colors.red.shade700;
  }

  Color obtenerColorIndicador(
    double valorActual,
    double limiteAlerta,
    double limitePeligro,
  ) {
    if (valorActual >= limitePeligro) {
      return Colors.red;
    }
    if (valorActual >= limiteAlerta) {
      return Colors.orange;
    }
    return Colors.green;
  }

  String _estadoMetrica(double valorActual, double limiteAlerta, double limitePeligro) {
    if (valorActual >= limitePeligro) return 'Fuera de rango';
    if (valorActual >= limiteAlerta) return 'En alerta';
    final referencia = limiteAlerta * 0.9;
    if (valorActual >= referencia) return 'Cercano a alerta';
    return 'Dentro de rango';
  }

  Color _colorEstadoMetrica(double valorActual, double limiteAlerta, double limitePeligro) {
    if (valorActual >= limitePeligro) return const Color(0xFFCE4B51);
    if (valorActual >= limiteAlerta) return const Color(0xFFAE7419);
    final referencia = limiteAlerta * 0.9;
    if (valorActual >= referencia) return const Color(0xFFB48A3E);
    return accent;
  }

  double _deltaUltimaLectura(List<PuntoGrafica> serie) {
    if (serie.length < 2) return 0;
    final ultimo = serie[serie.length - 1].valor;
    final anterior = serie[serie.length - 2].valor;
    return ultimo - anterior;
  }

  String _textoDelta(double delta, String unidad, {int decimales = 1}) {
    if (delta == 0) return 'Sin cambio';
    final prefijo = delta > 0 ? '↑' : '↓';
    final signo = delta > 0 ? '+' : '';
    return '$prefijo $signo${delta.toStringAsFixed(decimales)} $unidad vs lectura anterior';
  }

  String _resumenDelta(
    List<PuntoGrafica> serie,
    String unidad, {
    int decimales = 1,
  }) {
    if (serie.length < 2) return 'Esperando más lecturas';
    return _textoDelta(_deltaUltimaLectura(serie), unidad, decimales: decimales);
  }

  PuntoGrafica? _ultimoPunto(List<PuntoGrafica> serie) {
    if (serie.isEmpty) return null;
    return serie[serie.length - 1];
  }

  Color obtenerColorPrediccion() {
    if (rulCiclos >= 0) {
      if (rulCiclos < 20) {
        return Colors.red;
      }
      if (rulCiclos < 50) {
        return Colors.orange.shade800;
      }
    }
    return Colors.green.shade700;
  }

  Color obtenerColorGrafica() {
    if (metricaActiva == 'Temp. motor') {
      return Colors.red;
    }
    if (metricaActiva == 'Temp. ambiente') {
      return Colors.lightBlue;
    }
    if (metricaActiva == 'Comparar temps') {
      return Colors.red;
    }
    if (metricaActiva == 'Vibración') {
      return Colors.deepOrange;
    }
    if (metricaActiva == 'Velocidad') {
      return Colors.green;
    }
    if (metricaActiva == 'Humedad') {
      return Colors.blue;
    }
    return Colors.purple;
  }

  String obtenerUnidadGrafica() {
    if (metricaActiva == 'Temp. motor' ||
        metricaActiva == 'Temp. ambiente' ||
        metricaActiva == 'Comparar temps') {
      return '°C';
    }
    if (metricaActiva == 'Vibración') {
      return 'mm/s';
    }
    if (metricaActiva == 'Velocidad') {
      return 'RPM';
    }
    if (metricaActiva == 'Humedad') {
      return '%';
    }
    return 'V';
  }

  double obtenerLimiteGrafica() {
    if (metricaActiva == 'Temp. motor' || metricaActiva == 'Comparar temps') {
      return tPeligro;
    }
    if (metricaActiva == 'Temp. ambiente') {
      return tAmbPeligro;
    }
    if (metricaActiva == 'Vibración') {
      return vibPeligro;
    }
    if (metricaActiva == 'Velocidad') {
      return velPeligro.toDouble();
    }
    if (metricaActiva == 'Humedad') {
      return humPeligro;
    }
    return voltPeligro;
  }

  double obtenerAlertaGrafica() {
    if (metricaActiva == 'Temp. motor' || metricaActiva == 'Comparar temps') {
      return tAlerta;
    }
    if (metricaActiva == 'Temp. ambiente') {
      return tAmbAlerta;
    }
    if (metricaActiva == 'Vibración') {
      return vibAlerta;
    }
    if (metricaActiva == 'Velocidad') {
      return velAlerta.toDouble();
    }
    if (metricaActiva == 'Humedad') {
      return humAlerta;
    }
    return voltAlerta;
  }

  double _umbralBajo(double alerta, double peligro) {
    return alerta < peligro ? alerta : peligro;
  }

  double _umbralAlto(double alerta, double peligro) {
    return alerta < peligro ? peligro : alerta;
  }

  /// Escala máxima del eje/medidor: ajustada a alerta, crítico y valor actual.
  double maxEscala(
    double alerta,
    double peligro,
    List<double> valoresActuales, {
    double minimoEje = 0,
  }) {
    double max = peligro;
    if (alerta > max) {
      max = alerta;
    }
    for (final v in valoresActuales) {
      if (v > max) {
        max = v;
      }
    }
    final base = max - minimoEje;
    final margen = base * 0.12;
    final extra = margen < 1.0 ? 1.0 : margen;
    return max + extra;
  }

  List<double> valoresParaEscalaGrafica() {
    if (metricaActiva == 'Comparar temps') {
      return [
        ...histTemp.map((p) => p.valor),
        ...histTempAmb.map((p) => p.valor),
      ];
    }
    return datosGraficaActual.map((p) => p.valor).toList();
  }

  double obtenerMaxEjeGrafica() {
    if (metricaActiva == 'Comparar temps') {
      final peligro = tPeligro > tAmbPeligro ? tPeligro : tAmbPeligro;
      final alerta = tAlerta < tAmbAlerta ? tAlerta : tAmbAlerta;
      final vals = valoresParaEscalaGrafica();
      return maxEscala(alerta, peligro, vals.isEmpty ? [peligro] : vals);
    }
    final vals = valoresParaEscalaGrafica();
    return maxEscala(
      obtenerAlertaGrafica(),
      obtenerLimiteGrafica(),
      vals.isEmpty ? [obtenerLimiteGrafica()] : vals,
    );
  }

  List<PlotBand> plotBandsGrafica() {
    if (metricaActiva == 'Comparar temps') {
      return [
        PlotBand(
          isVisible: true,
          start: tAlerta,
          end: tAlerta + 0.01,
          color: Colors.orange.withValues(alpha: 0.35),
          text: 'Alerta motor',
          textStyle: const TextStyle(color: Colors.orange, fontSize: 10),
        ),
        PlotBand(
          isVisible: true,
          start: tPeligro,
          end: tPeligro + 0.01,
          color: Colors.red.withValues(alpha: 0.4),
          text: 'Crítico motor',
          textStyle: const TextStyle(color: Colors.red, fontSize: 10),
        ),
        PlotBand(
          isVisible: true,
          start: tAmbAlerta,
          end: tAmbAlerta + 0.01,
          color: Colors.lightBlue.withValues(alpha: 0.35),
          text: 'Alerta amb.',
          textStyle: const TextStyle(color: Colors.blue, fontSize: 10),
        ),
        PlotBand(
          isVisible: true,
          start: tAmbPeligro,
          end: tAmbPeligro + 0.01,
          color: Colors.red.shade300.withValues(alpha: 0.4),
          text: 'Crítico amb.',
          textStyle: TextStyle(color: Colors.red.shade700, fontSize: 10),
        ),
      ];
    }
    final alerta = obtenerAlertaGrafica();
    final peligro = obtenerLimiteGrafica();
    return [
      PlotBand(
        isVisible: true,
        start: alerta,
        end: alerta + 0.01,
        color: Colors.orange.withValues(alpha: 0.35),
        text: 'Alerta',
        textStyle: const TextStyle(color: Colors.orange, fontSize: 11),
      ),
      PlotBand(
        isVisible: true,
        start: peligro,
        end: peligro + 0.01,
        color: Colors.red.withValues(alpha: 0.45),
        text: 'Crítico',
        textStyle: const TextStyle(color: Colors.red, fontSize: 11),
      ),
    ];
  }

  List<Widget> construirBotonesMetricas() {
    List<Widget> chips = [];
    if (medirTemp) {
      chips.add(crearChoiceChip('Temp. motor'));
    }
    if (medirTempAmb) {
      chips.add(crearChoiceChip('Temp. ambiente'));
    }
    if (medirTemp && medirTempAmb) {
      chips.add(crearChoiceChip('Comparar temps'));
    }
    if (medirVib) {
      chips.add(crearChoiceChip('Vibración'));
    }
    if (medirVel) {
      chips.add(crearChoiceChip('Velocidad'));
    }
    if (medirVolt) {
      chips.add(crearChoiceChip('Voltaje'));
    }
    if (medirHum) {
      chips.add(crearChoiceChip('Humedad'));
    }
    return chips;
  }

  Widget crearChoiceChip(String opcion) {
    final seleccionado = metricaActiva == opcion;
    return ChoiceChip(
      label: Text(opcion),
      selected: seleccionado,
      labelStyle: TextStyle(
        color: seleccionado ? Colors.white : ink,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: Colors.white,
      selectedColor: accent,
      side: BorderSide(color: seleccionado ? accent : line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (bool valor) {
        if (valor == true) {
          setState(() {
            metricaActiva = opcion;
            actualizarDatosGrafica();
          });
        }
      },
    );
  }

  int get _sensoresActivos {
    var total = 0;
    if (medirTemp) total++;
    if (medirTempAmb) total++;
    if (medirVib) total++;
    if (medirVolt) total++;
    if (medirVel) total++;
    if (medirHum) total++;
    return total;
  }

  Color _colorEstadoPantalla() {
    if (_error != null) return const Color(0xFF9A6A1D);
    if (_stale) return muted;
    if (estado == 'peligro') return const Color(0xFFCE4B51);
    if (estado == 'alerta') return const Color(0xFFAE7419);
    return accent;
  }

  String _textoEstadoPantalla() {
    if (_error != null) return 'Sin conexión';
    if (_stale) return 'Sin señal reciente';
    return {
          'optimo': 'Operación normal',
          'alerta': 'Atención requerida',
          'peligro': 'Riesgo alto',
        }[estado] ??
        'Operación normal';
  }

  Widget _encabezadoVista() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 20,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MONITOREO EN VIVO',
              style: TextStyle(
                fontSize: 10,
                color: accent,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(nombre, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'ID ${widget.idMaquina} · $_sensoresActivos sensores habilitados',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            StatusPill(_textoEstadoPantalla(), color: _colorEstadoPantalla()),
            OutlinedButton.icon(
              onPressed: _fetching ? null : obtenerDatosMaquina,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Actualizar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tarjetaResumen(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                Text(label, style: const TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetasResumen() {
    final cards = [
      _tarjetaResumen('$_sensoresActivos', 'Sensores activos', Icons.tune_rounded, accent),
      _tarjetaResumen(
        _stale || _error != null ? '0' : '1',
        _stale || _error != null ? 'Con señal reciente' : 'Máquina transmitiendo',
        Icons.sensors_rounded,
        const Color(0xFF517AB0),
      ),
      _tarjetaResumen(
        rulCiclos >= 0 && rulCiclos < 9999 ? '$rulCiclos' : '—',
        'Ciclos a zona preventiva',
        Icons.auto_graph_rounded,
        const Color(0xFFAD803C),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth < 560 ? 1 : 3;
        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: cards
              .map((card) => SizedBox(
                    width: (c.maxWidth - 16 * (columns - 1)) / columns,
                    child: card,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _avisoEstado() {
    if (_error == null && !_stale) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1D6A0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFF9A6A1D)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error ??
                  'Sin lecturas en los últimos 30 segundos. Se muestran los últimos datos recibidos.',
              style: const TextStyle(color: Color(0xFF885D18), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelPrediccion() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 20,
          runSpacing: 20,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF5F2),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.psychology_alt_rounded, color: accent, size: 34),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Análisis Predictivo ML',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    estadoPrediccion,
                    style: TextStyle(
                      fontSize: 30,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8,
                      color: obtenerColorPrediccion(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (rulCiclos >= 0 && rulCiclos < 9999)
                        StatusPill('Preventivo en $rulCiclos ciclos', color: const Color(0xFFAD803C)),
                      if (rulPeligroCiclos >= 0 && rulPeligroCiclos < 9999)
                        StatusPill('Peligro en $rulPeligroCiclos ciclos', color: const Color(0xFFCE4B51)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelAlerta() {
    if (incident == null) return const SizedBox.shrink();

    final isDanger = incident!['severity'] == 2;
    final resolved = incident!['active'] == false;
    final color = resolved ? accent : isDanger ? const Color(0xFFCE4B51) : const Color(0xFFAE7419);
    final background = resolved ? const Color(0xFFE8F4F0) : isDanger ? const Color(0xFFFFF1F3) : const Color(0xFFFFF6E7);
    final icon = resolved ? Icons.check_circle_outline : isDanger ? Icons.warning_rounded : Icons.warning_amber_rounded;
    final title = incident!['title'] as String;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .3,
                    color: color,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final metric in (incident!['metrics'] as List? ?? []))
                    StatusPill("${metric['label']}: ${metric['value']} ${metric['unit']} · límite ${metric['limit']}", color: color),
                ]),
                const SizedBox(height: 8),
                Text(
                  resumenAlerta,
                  style: const TextStyle(fontSize: 14, color: ink, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaMetrica({
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required Color color,
    required String valor,
    required String resumenTendencia,
    required String estadoMetrica,
    required Color colorEstado,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icono, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitulo, style: const TextStyle(color: muted, fontSize: 12)),
                    ],
                  ),
                ),
                StatusPill('En vivo', color: color),
              ],
            ),
            const SizedBox(height: 22),
            Expanded(child: child),
            const SizedBox(height: 14),
            Text(
              valor,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(estadoMetrica, color: colorEstado),
                const SizedBox(height: 8),
                Text(
                  resumenTendencia,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _historialMonitoreo() {
    if (datosGraficaActual.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HISTORIAL',
              style: TextStyle(
                fontSize: 10,
                color: accent,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Historial de monitoreo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -.7),
            ),
            const SizedBox(height: 6),
            Text(
              'Explora tendencias, compara umbrales y revisa la métrica activa sin salir del tablero.',
              style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            Wrap(spacing: 8, runSpacing: 10, children: construirBotonesMetricas()),
            const SizedBox(height: 24),
            SizedBox(
              height: 380,
              child: SfCartesianChart(
                plotAreaBorderWidth: 0,
                trackballBehavior: _trackballBehavior,
                primaryXAxis: const NumericAxis(isVisible: false),
                primaryYAxis: NumericAxis(
                  minimum: 0,
                  maximum: obtenerMaxEjeGrafica(),
                  title: AxisTitle(text: obtenerUnidadGrafica()),
                  majorGridLines: MajorGridLines(
                    width: 1,
                    color: line.withValues(alpha: .7),
                  ),
                  axisLine: const AxisLine(width: 0),
                  plotBands: plotBandsGrafica(),
                ),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  canShowMarker: true,
                  header: 'Muestra',
                  format: 'point.y ${obtenerUnidadGrafica()}',
                ),
                legend: const Legend(isVisible: true, position: LegendPosition.bottom),
                series: <CartesianSeries<PuntoGrafica, int>>[
                  if (metricaActiva != 'Comparar temps')
                    SplineAreaSeries<PuntoGrafica, int>(
                      animationDuration: 0,
                      dataSource: datosGraficaActual,
                      xValueMapper: (PuntoGrafica datos, _) => datos.tiempo,
                      yValueMapper: (PuntoGrafica datos, _) => datos.valor,
                      color: obtenerColorGrafica().withValues(alpha: 0.18),
                      borderColor: obtenerColorGrafica(),
                      borderWidth: 3,
                      markerSettings: const MarkerSettings(isVisible: false),
                      name: metricaActiva,
                    ),
                  if (metricaActiva != 'Comparar temps' && _ultimoPunto(datosGraficaActual) != null)
                    ScatterSeries<PuntoGrafica, int>(
                      dataSource: [_ultimoPunto(datosGraficaActual)!],
                      xValueMapper: (PuntoGrafica datos, _) => datos.tiempo,
                      yValueMapper: (PuntoGrafica datos, _) => datos.valor,
                      color: obtenerColorGrafica(),
                      markerSettings: const MarkerSettings(
                        isVisible: true,
                        width: 11,
                        height: 11,
                        borderWidth: 2,
                        borderColor: Colors.white,
                      ),
                      name: 'Último valor',
                    ),
                  if (metricaActiva == 'Comparar temps') ...[
                    SplineAreaSeries<PuntoGrafica, int>(
                      animationDuration: 0,
                      dataSource: histTemp,
                      xValueMapper: (PuntoGrafica datos, _) => datos.tiempo,
                      yValueMapper: (PuntoGrafica datos, _) => datos.valor,
                      color: Colors.red.withValues(alpha: 0.18),
                      borderColor: Colors.red,
                      borderWidth: 2.5,
                      markerSettings: const MarkerSettings(isVisible: false),
                      name: 'Motor',
                    ),
                    SplineAreaSeries<PuntoGrafica, int>(
                      animationDuration: 0,
                      dataSource: histTempAmb,
                      xValueMapper: (PuntoGrafica datos, _) => datos.tiempo,
                      yValueMapper: (PuntoGrafica datos, _) => datos.valor,
                      color: const Color(0xFF6EB7E7).withValues(alpha: 0.18),
                      borderColor: const Color(0xFF5AA7DA),
                      borderWidth: 2.5,
                      markerSettings: const MarkerSettings(isVisible: false),
                      name: 'Ambiente',
                    ),
                    if (_ultimoPunto(histTemp) != null)
                      ScatterSeries<PuntoGrafica, int>(
                        dataSource: [_ultimoPunto(histTemp)!],
                        xValueMapper: (PuntoGrafica datos, _) => datos.tiempo,
                        yValueMapper: (PuntoGrafica datos, _) => datos.valor,
                        color: Colors.red,
                        markerSettings: const MarkerSettings(
                          isVisible: true,
                          width: 10,
                          height: 10,
                          borderWidth: 2,
                          borderColor: Colors.white,
                        ),
                        name: 'Último motor',
                      ),
                    if (_ultimoPunto(histTempAmb) != null)
                      ScatterSeries<PuntoGrafica, int>(
                        dataSource: [_ultimoPunto(histTempAmb)!],
                        xValueMapper: (PuntoGrafica datos, _) => datos.tiempo,
                        yValueMapper: (PuntoGrafica datos, _) => datos.valor,
                        color: const Color(0xFF5AA7DA),
                        markerSettings: const MarkerSettings(
                          isVisible: true,
                          width: 10,
                          height: 10,
                          borderWidth: 2,
                          borderColor: Colors.white,
                        ),
                        name: 'Último ambiente',
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || histTemp.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: widget.onBack == null ? null : IconButton(
            tooltip: 'Volver al área', icon: const Icon(Icons.arrow_back_rounded), onPressed: widget.onBack,
          ),
          title: Text('Monitoreo · ${widget.idMaquina}'),
        ),
        body: !_loaded ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : EmptyState(title: _error != null ? 'No pudimos cargar las lecturas' : 'Esperando la primera señal',
              subtitle: _error ?? 'La máquina está registrada. Conecta el dispositivo y envía sus lecturas con el ID ${widget.idMaquina}.',
              onRetry: obtenerDatosMaquina),
      );
    }
    final velLo = _umbralBajo(velAlerta.toDouble(), velPeligro.toDouble());
    final velHi = _umbralAlto(velAlerta.toDouble(), velPeligro.toDouble());
    final voltLo = _umbralBajo(voltAlerta, voltPeligro);
    final voltHi = _umbralAlto(voltAlerta, voltPeligro);
    final tempLo = _umbralBajo(tAlerta, tPeligro);
    final tempHi = _umbralAlto(tAlerta, tPeligro);
    final tempAmbLo = _umbralBajo(tAmbAlerta, tAmbPeligro);
    final tempAmbHi = _umbralAlto(tAmbAlerta, tAmbPeligro);
    final vibLo = _umbralBajo(vibAlerta, vibPeligro);
    final vibHi = _umbralAlto(vibAlerta, vibPeligro);
    final humLo = _umbralBajo(humAlerta, humPeligro);
    final humHi = _umbralAlto(humAlerta, humPeligro);

    final maxVel = maxEscala(velLo, velHi, [velocidad.toDouble()]);
    final maxVolt = maxEscala(voltLo, voltHi, [voltaje]);
    final maxTemp = maxEscala(tempLo, tempHi, [temperatura]);
    final maxTempAmb = maxEscala(tempAmbLo, tempAmbHi, [tempAmbiente]);
    final maxVib = maxEscala(vibLo, vibHi, [vibracion]);
    final maxHum = maxEscala(humLo, humHi, [humedad]);
    final maxHumEje = maxHum > 100 ? maxHum : 100.0;

    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        leading: widget.onBack == null ? null : IconButton(
          tooltip: 'Volver al área', icon: const Icon(Icons.arrow_back_rounded), onPressed: widget.onBack,
        ),
        title: Text(nombre),
        actions: [Padding(padding: const EdgeInsets.only(right: 18), child: StatusPill(
          _error != null ? 'Sin conexión' : _stale ? 'Sin señal reciente' : 'Señal reciente',
          color: _error != null || _stale ? muted : accent))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _encabezadoVista(),
                const SizedBox(height: 28),
                _tarjetasResumen(),
                const SizedBox(height: 20),
                _avisoEstado(),
                _panelPrediccion(),
                if (estado == 'peligro' || estado == 'alerta') ...[
                  const SizedBox(height: 18),
                  _panelAlerta(),
                ],
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, c) {
                    final columns = c.maxWidth >= 1180
                        ? 3
                        : c.maxWidth >= 720
                            ? 2
                            : 1;
                    final width = (c.maxWidth - (columns - 1) * 18) / columns;
                    final metricCardHeight = columns == 1 ? 390.0 : 370.0;
                    return Wrap(
                      spacing: 18,
                      runSpacing: 18,
                      children: [
                        if (medirVel)
                          SizedBox(
                            width: width,
                            height: metricCardHeight,
                            child: _tarjetaMetrica(
                              titulo: 'Velocidad',
                              subtitulo: 'Revoluciones por minuto',
                              icono: Icons.speed_rounded,
                              color: const Color(0xFF2D9D78),
                              valor: '$velocidad RPM',
                              resumenTendencia: _resumenDelta(histVel, 'RPM', decimales: 0),
                              estadoMetrica: _estadoMetrica(velocidad.toDouble(), velLo, velHi),
                              colorEstado: _colorEstadoMetrica(velocidad.toDouble(), velLo, velHi),
                              child: Center(
                                child: SizedBox(
                                  width: 240,
                                  height: 190,
                                  child: SfRadialGauge(
                                    axes: <RadialAxis>[
                                      RadialAxis(
                                        minimum: 0,
                                        maximum: maxVel,
                                        startAngle: 135,
                                        endAngle: 45,
                                        canScaleToFit: true,
                                        radiusFactor: 0.96,
                                        ranges: <GaugeRange>[
                                          GaugeRange(startValue: 0, endValue: velLo, color: const Color(0xFF4CAF50)),
                                          GaugeRange(startValue: velLo, endValue: velHi, color: const Color(0xFFED9B2E)),
                                          GaugeRange(startValue: velHi, endValue: maxVel, color: const Color(0xFFDA5A5A)),
                                        ],
                                        pointers: <GaugePointer>[
                                          NeedlePointer(
                                            value: velocidad.toDouble(),
                                            enableAnimation: true,
                                            needleEndWidth: 5,
                                            knobStyle: const KnobStyle(knobRadius: 0.08),
                                          ),
                                        ],
                                        annotations: <GaugeAnnotation>[
                                          GaugeAnnotation(
                                            widget: Text(
                                              velocidad.toString(),
                                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                            ),
                                            angle: 90,
                                            positionFactor: 0.8,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (medirVolt)
                          SizedBox(
                            width: width,
                            height: metricCardHeight,
                            child: _tarjetaMetrica(
                              titulo: 'Voltaje',
                              subtitulo: 'Estabilidad eléctrica',
                              icono: Icons.electric_bolt_rounded,
                              color: const Color(0xFF517AB0),
                              valor: '${voltaje.toStringAsFixed(1)} V',
                              resumenTendencia: _resumenDelta(histVolt, 'V'),
                              estadoMetrica: _estadoMetrica(voltaje, voltLo, voltHi),
                              colorEstado: _colorEstadoMetrica(voltaje, voltLo, voltHi),
                              child: Center(
                                child: SizedBox(
                                  width: 250,
                                  height: 190,
                                  child: SfRadialGauge(
                                    axes: <RadialAxis>[
                                      RadialAxis(
                                        minimum: 0,
                                        maximum: maxVolt,
                                        startAngle: 180,
                                        endAngle: 0,
                                        canScaleToFit: true,
                                        radiusFactor: 0.96,
                                        pointers: <GaugePointer>[
                                          NeedlePointer(
                                            value: voltaje,
                                            enableAnimation: true,
                                            needleLength: 0.7,
                                            needleStartWidth: 2,
                                            needleEndWidth: 4,
                                          ),
                                        ],
                                        ranges: <GaugeRange>[
                                          GaugeRange(startValue: 0, endValue: voltLo, color: const Color(0xFF4CAF50)),
                                          GaugeRange(startValue: voltLo, endValue: voltHi, color: const Color(0xFFED9B2E)),
                                          GaugeRange(startValue: voltHi, endValue: maxVolt, color: const Color(0xFFDA5A5A)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (medirTemp)
                          SizedBox(
                            width: width,
                            height: metricCardHeight,
                            child: _tarjetaMetrica(
                              titulo: 'Temperatura del motor',
                              subtitulo: 'Calor sobre el umbral operativo',
                              icono: Icons.device_thermostat_rounded,
                              color: const Color(0xFFDA5A5A),
                              valor: '${temperatura.toStringAsFixed(1)} °C',
                              resumenTendencia: _resumenDelta(histTemp, '°C'),
                              estadoMetrica: _estadoMetrica(temperatura, tempLo, tempHi),
                              colorEstado: _colorEstadoMetrica(temperatura, tempLo, tempHi),
                              child: Center(
                                child: SizedBox(
                                  width: 180,
                                  child: Column(
                                children: [
                                  Expanded(
                                    child: SfLinearGauge(
                                      minimum: 0,
                                      maximum: maxTemp,
                                      orientation: LinearGaugeOrientation.vertical,
                                      axisTrackStyle: const LinearAxisTrackStyle(
                                        thickness: 19,
                                        edgeStyle: LinearEdgeStyle.endCurve,
                                      ),
                                      ranges: [
                                        LinearGaugeRange(startValue: 0, endValue: tempLo, color: const Color(0xFF4CAF50)),
                                        LinearGaugeRange(startValue: tempLo, endValue: tempHi, color: const Color(0xFFED9B2E)),
                                        LinearGaugeRange(startValue: tempHi, endValue: maxTemp, color: const Color(0xFFDA5A5A)),
                                      ],
                                      barPointers: [
                                        LinearBarPointer(
                                          value: temperatura,
                                          thickness: 19,
                                          edgeStyle: LinearEdgeStyle.endCurve,
                                          color: obtenerColorIndicador(temperatura, tempLo, tempHi),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: obtenerColorIndicador(temperatura, tempLo, tempHi),
                                    ),
                                  ),
                                ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (medirTempAmb)
                          SizedBox(
                            width: width,
                            height: metricCardHeight,
                            child: _tarjetaMetrica(
                              titulo: 'Temperatura ambiente',
                              subtitulo: 'Contexto térmico del área',
                              icono: Icons.thermostat_auto_rounded,
                              color: const Color(0xFF5AA7DA),
                              valor: '${tempAmbiente.toStringAsFixed(1)} °C',
                              resumenTendencia: _resumenDelta(histTempAmb, '°C'),
                              estadoMetrica: _estadoMetrica(tempAmbiente, tempAmbLo, tempAmbHi),
                              colorEstado: _colorEstadoMetrica(tempAmbiente, tempAmbLo, tempAmbHi),
                              child: Center(
                                child: SizedBox(
                                  width: 180,
                                  child: Column(
                                children: [
                                  Expanded(
                                    child: SfLinearGauge(
                                      minimum: 0,
                                      maximum: maxTempAmb,
                                      orientation: LinearGaugeOrientation.vertical,
                                      axisTrackStyle: const LinearAxisTrackStyle(
                                        thickness: 19,
                                        edgeStyle: LinearEdgeStyle.endCurve,
                                      ),
                                      ranges: [
                                        LinearGaugeRange(startValue: 0, endValue: tempAmbLo, color: const Color(0xFF4CAF50)),
                                        LinearGaugeRange(startValue: tempAmbLo, endValue: tempAmbHi, color: const Color(0xFFED9B2E)),
                                        LinearGaugeRange(startValue: tempAmbHi, endValue: maxTempAmb, color: const Color(0xFFDA5A5A)),
                                      ],
                                      barPointers: [
                                        LinearBarPointer(
                                          value: tempAmbiente,
                                          thickness: 19,
                                          edgeStyle: LinearEdgeStyle.endCurve,
                                          color: obtenerColorIndicador(tempAmbiente, tempAmbLo, tempAmbHi),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: obtenerColorIndicador(tempAmbiente, tempAmbLo, tempAmbHi),
                                    ),
                                  ),
                                ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (medirVib)
                          SizedBox(
                            width: width,
                            height: metricCardHeight,
                            child: _tarjetaMetrica(
                              titulo: 'Vibración',
                              subtitulo: 'Movimiento fuera de tolerancia',
                              icono: Icons.vibration_rounded,
                              color: const Color(0xFFAE7419),
                              valor: '${vibracion.toStringAsFixed(1)} mm/s',
                              resumenTendencia: _resumenDelta(histVib, 'mm/s'),
                              estadoMetrica: _estadoMetrica(vibracion, vibLo, vibHi),
                              colorEstado: _colorEstadoMetrica(vibracion, vibLo, vibHi),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
                                child: SfLinearGauge(
                                  minimum: 0,
                                  maximum: maxVib,
                                  orientation: LinearGaugeOrientation.horizontal,
                                  axisTrackStyle: const LinearAxisTrackStyle(
                                    thickness: 14,
                                    edgeStyle: LinearEdgeStyle.bothCurve,
                                  ),
                                  ranges: [
                                    LinearGaugeRange(
                                      startValue: 0,
                                      endValue: vibLo,
                                      color: const Color(0xFF4CAF50),
                                      startWidth: 14,
                                      endWidth: 14,
                                    ),
                                    LinearGaugeRange(
                                      startValue: vibLo,
                                      endValue: vibHi,
                                      color: const Color(0xFFED9B2E),
                                      startWidth: 14,
                                      endWidth: 14,
                                    ),
                                    LinearGaugeRange(
                                      startValue: vibHi,
                                      endValue: maxVib,
                                      color: const Color(0xFFDA5A5A),
                                      startWidth: 14,
                                      endWidth: 14,
                                    ),
                                  ],
                                  markerPointers: [
                                    LinearShapePointer(
                                      value: vibracion,
                                      shapeType: LinearShapePointerType.invertedTriangle,
                                      color: obtenerColorIndicador(vibracion, vibLo, vibHi),
                                      position: LinearElementPosition.cross,
                                    ),
                                  ],
                                  barPointers: [
                                    LinearBarPointer(
                                      value: vibracion,
                                      thickness: 14,
                                      color: obtenerColorIndicador(vibracion, vibLo, vibHi),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (medirHum)
                          SizedBox(
                            width: width,
                            height: metricCardHeight,
                            child: _tarjetaMetrica(
                              titulo: 'Humedad',
                              subtitulo: 'Condiciones del entorno',
                              icono: Icons.water_drop_rounded,
                              color: const Color(0xFF4CAF50),
                              valor: '${humedad.toStringAsFixed(1)} %',
                              resumenTendencia: _resumenDelta(histHum, '%'),
                              estadoMetrica: _estadoMetrica(humedad, humLo, humHi),
                              colorEstado: _colorEstadoMetrica(humedad, humLo, humHi),
                              child: Center(
                                child: SizedBox(
                                  width: 230,
                                  height: 190,
                                  child: SfRadialGauge(
                                    axes: <RadialAxis>[
                                      RadialAxis(
                                        minimum: 0,
                                        maximum: maxHumEje,
                                        showLabels: false,
                                        showTicks: false,
                                        startAngle: 270,
                                        endAngle: 270,
                                        radiusFactor: 0.95,
                                        axisLineStyle: const AxisLineStyle(
                                          thickness: 0.18,
                                          thicknessUnit: GaugeSizeUnit.factor,
                                        ),
                                        ranges: <GaugeRange>[
                                          GaugeRange(startValue: 0, endValue: humLo, color: const Color(0xFF4CAF50).withValues(alpha: 0.22)),
                                          GaugeRange(startValue: humLo, endValue: humHi, color: const Color(0xFFED9B2E).withValues(alpha: 0.28)),
                                          GaugeRange(startValue: humHi, endValue: maxHumEje, color: const Color(0xFFDA5A5A).withValues(alpha: 0.28)),
                                        ],
                                        pointers: <GaugePointer>[
                                          RangePointer(
                                            value: humedad,
                                            width: 0.18,
                                            sizeUnit: GaugeSizeUnit.factor,
                                            color: obtenerColorIndicador(humedad, humLo, humHi),
                                            enableAnimation: true,
                                          ),
                                        ],
                                        annotations: <GaugeAnnotation>[
                                          GaugeAnnotation(
                                            widget: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.water_drop,
                                                  color: obtenerColorIndicador(humedad, humLo, humHi),
                                                  size: 36,
                                                ),
                                              ],
                                            ),
                                            positionFactor: 0.1,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                _historialMonitoreo(),
                const SizedBox(height: 28),
                const Text(
                  'La señal se actualiza cada 8 segundos. Después de 30 segundos sin lecturas, la máquina se muestra sin señal reciente.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatMecanimal(idMaquina: widget.idMaquina),
            ),
          );
        },
        icon: const Icon(Icons.smart_toy, size: 28),
        label: const Text(
          'Consultar IA',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
    );
  }
}
