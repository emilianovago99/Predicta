import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'config/api_config.dart';
import 'chat_mecanimal.dart';

class PuntoGrafica {
  PuntoGrafica(this.tiempo, this.valor);
  final int tiempo;
  final double valor;
}

class PantallaMonitoreo extends StatefulWidget {
  final String idMaquina;

  const PantallaMonitoreo({super.key, required this.idMaquina});

  @override
  State<PantallaMonitoreo> createState() => _PantallaMonitoreoState();
}

class _PantallaMonitoreoState extends State<PantallaMonitoreo> {
  String estado = 'optimo';
  String nombre = 'Cargando datos...';
  String diagnostico = 'Sin alertas recientes.';

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
  String ultimaAlertaProcesada = '';

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

  void lanzarNotificacionPantalla(String mensajeAlerta, String tipoAlerta) {
    Color colorBanner = Colors.orange.shade800;
    IconData iconoBanner = Icons.analytics_outlined;

    if (tipoAlerta == 'peligro') {
      colorBanner = Colors.red.shade800;
      iconoBanner = Icons.report_problem_rounded;
    }
    if (tipoAlerta == 'evento') {
      colorBanner = Colors.deepPurple.shade700;
      iconoBanner = Icons.bolt_rounded;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(iconoBanner, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tipoAlerta.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    mensajeAlerta,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: colorBanner,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> obtenerPrediccionML() async {
    final url = ApiConfig.uri('/api/maquinas/${widget.idMaquina}/prediccion');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
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
      estadoPrediccion = 'Error de conectividad ML';
    }
  }

  Future<void> obtenerDatosMaquina() async {
    final url = ApiConfig.uri('/api/maquinas/${widget.idMaquina}/datos');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
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

          if (data['ultima_alerta'] != null) {
            diagnostico = data['ultima_alerta']['diagnostico'];
            String tipoAlertaUi = estado;
            if (data['ultima_alerta']['tipo'] != null) {
              tipoAlertaUi = data['ultima_alerta']['tipo'].toString();
            }
            if (ultimaAlertaProcesada != diagnostico) {
              ultimaAlertaProcesada = diagnostico;
              lanzarNotificacionPantalla(diagnostico, tipoAlertaUi);
            }
          }

          if (data['ultima_alerta'] == null) {
            diagnostico = 'Sin alertas recientes.';
            ultimaAlertaProcesada = '';
          }

          if (data['historial'] != null) {
            List<dynamic> listaRaw = data['historial'];
            if (listaRaw.isNotEmpty) {
              temperatura = listaRaw[0]['temperatura'].toDouble();
              if (listaRaw[0]['temp_ambiente'] != null) {
                tempAmbiente = listaRaw[0]['temp_ambiente'].toDouble();
              }
              vibracion = listaRaw[0]['vibracion'].toDouble();
              velocidad = listaRaw[0]['velocidad'].toInt();
              voltaje = listaRaw[0]['voltaje'].toDouble();
              humedad = listaRaw[0]['humedad'].toDouble();

              histTemp.clear();
              histTempAmb.clear();
              histVib.clear();
              histVel.clear();
              histVolt.clear();
              histHum.clear();

              List<dynamic> listaCronologica = listaRaw.reversed.toList();
              int contador = 0;

              for (var lectura in listaCronologica) {
                histTemp.add(
                  PuntoGrafica(contador, lectura['temperatura'].toDouble()),
                );
                if (lectura['temp_ambiente'] != null) {
                  histTempAmb.add(
                    PuntoGrafica(contador, lectura['temp_ambiente'].toDouble()),
                  );
                }
                histVib.add(
                  PuntoGrafica(contador, lectura['vibracion'].toDouble()),
                );
                histVel.add(
                  PuntoGrafica(contador, lectura['velocidad'].toDouble()),
                );
                histVolt.add(
                  PuntoGrafica(contador, lectura['voltaje'].toDouble()),
                );
                histHum.add(
                  PuntoGrafica(contador, lectura['humedad'].toDouble()),
                );
                contador++;
              }

              actualizarDatosGrafica();
            }
          }
        });
      }
    } catch (e) {
      setState(() {
        nombre = 'Error de conexión';
      });
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
      return maxEscala(
        alerta,
        peligro,
        vals.isEmpty ? [peligro] : vals,
      );
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
          color: Colors.orange.withOpacity(0.35),
          text: 'Alerta motor',
          textStyle: const TextStyle(color: Colors.orange, fontSize: 10),
        ),
        PlotBand(
          isVisible: true,
          start: tPeligro,
          end: tPeligro + 0.01,
          color: Colors.red.withOpacity(0.4),
          text: 'Crítico motor',
          textStyle: const TextStyle(color: Colors.red, fontSize: 10),
        ),
        PlotBand(
          isVisible: true,
          start: tAmbAlerta,
          end: tAmbAlerta + 0.01,
          color: Colors.lightBlue.withOpacity(0.35),
          text: 'Alerta amb.',
          textStyle: const TextStyle(color: Colors.blue, fontSize: 10),
        ),
        PlotBand(
          isVisible: true,
          start: tAmbPeligro,
          end: tAmbPeligro + 0.01,
          color: Colors.red.shade300.withOpacity(0.4),
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
        color: Colors.orange.withOpacity(0.35),
        text: 'Alerta',
        textStyle: const TextStyle(color: Colors.orange, fontSize: 11),
      ),
      PlotBand(
        isVisible: true,
        start: peligro,
        end: peligro + 0.01,
        color: Colors.red.withOpacity(0.45),
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
    bool seleccionado = false;
    if (metricaActiva == opcion) {
      seleccionado = true;
    }
    return ChoiceChip(
      label: Text(opcion),
      selected: seleccionado,
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

  @override
  Widget build(BuildContext context) {
    double anchoPantalla = MediaQuery.of(context).size.width;
    double anchoTarjeta = anchoPantalla;

    if (anchoPantalla > 600) {
      anchoTarjeta = (anchoPantalla / 2) - 24;
    }
    if (anchoPantalla > 900) {
      anchoTarjeta = (anchoPantalla / 3) - 24;
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
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(nombre),
        backgroundColor: obtenerColorTarjeta(),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.psychology,
                        color: Colors.blueGrey.shade700,
                        size: 40,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Análisis Predictivo ML',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            estadoPrediccion,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: obtenerColorPrediccion(),
                            ),
                          ),
                          if (rulCiclos >= 0 && rulCiclos < 9999)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Ciclos hasta zona preventiva (amarillo): $rulCiclos',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (rulPeligroCiclos >= 0 && rulPeligroCiclos < 9999)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                'Ciclos hasta zona de peligro (rojo): $rulPeligroCiclos',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (estado == 'peligro')
              Card(
                color: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.red.shade700, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning,
                            color: Colors.red.shade700,
                            size: 30,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'ALERTA DETECTADA',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        diagnostico,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (estado == 'alerta')
              Card(
                color: Colors.orange.shade50,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.orange.shade700, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                            size: 30,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'PRECAUCIÓN',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        diagnostico,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16.0,
              runSpacing: 16.0,
              alignment: WrapAlignment.center,
              children: [
                if (medirVel)
                  SizedBox(
                    width: anchoTarjeta,
                    height: 250,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'Velocidad (RPM)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: SfRadialGauge(
                                axes: <RadialAxis>[
                                  RadialAxis(
                                    minimum: 0,
                                    maximum: maxVel,
                                    startAngle: 135,
                                    endAngle: 45,
                                    ranges: <GaugeRange>[
                                      GaugeRange(
                                        startValue: 0,
                                        endValue: velLo,
                                        color: Colors.green,
                                      ),
                                      GaugeRange(
                                        startValue: velLo,
                                        endValue: velHi,
                                        color: Colors.orange,
                                      ),
                                      GaugeRange(
                                        startValue: velHi,
                                        endValue: maxVel,
                                        color: Colors.red,
                                      ),
                                    ],
                                    pointers: <GaugePointer>[
                                      NeedlePointer(
                                        value: velocidad.toDouble(),
                                        enableAnimation: true,
                                        needleEndWidth: 5,
                                        knobStyle: const KnobStyle(
                                          knobRadius: 0.08,
                                        ),
                                      ),
                                    ],
                                    annotations: <GaugeAnnotation>[
                                      GaugeAnnotation(
                                        widget: Text(
                                          velocidad.toString(),
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        angle: 90,
                                        positionFactor: 0.8,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (medirVolt)
                  SizedBox(
                    width: anchoTarjeta,
                    height: 250,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'Voltaje (V)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: SfRadialGauge(
                                axes: <RadialAxis>[
                                  RadialAxis(
                                    minimum: 0,
                                    maximum: maxVolt,
                                    startAngle: 180,
                                    endAngle: 0,
                                    canScaleToFit: true,
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
                                      GaugeRange(
                                        startValue: 0,
                                        endValue: voltLo,
                                        color: Colors.green,
                                      ),
                                      GaugeRange(
                                        startValue: voltLo,
                                        endValue: voltHi,
                                        color: Colors.orange,
                                      ),
                                      GaugeRange(
                                        startValue: voltHi,
                                        endValue: maxVolt,
                                        color: Colors.red,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${voltaje.toStringAsFixed(1)} V',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (medirTemp)
                  SizedBox(
                    width: anchoTarjeta,
                    height: 250,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'Temp. motor (°C)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: SfLinearGauge(
                                      minimum: 0,
                                      maximum: maxTemp,
                                      orientation:
                                          LinearGaugeOrientation.vertical,
                                      axisTrackStyle:
                                          const LinearAxisTrackStyle(
                                            thickness: 15,
                                            edgeStyle: LinearEdgeStyle.endCurve,
                                          ),
                                      ranges: [
                                        LinearGaugeRange(
                                          startValue: 0,
                                          endValue: tempLo,
                                          color: Colors.green,
                                        ),
                                        LinearGaugeRange(
                                          startValue: tempLo,
                                          endValue: tempHi,
                                          color: Colors.orange,
                                        ),
                                        LinearGaugeRange(
                                          startValue: tempHi,
                                          endValue: maxTemp,
                                          color: Colors.red,
                                        ),
                                      ],
                                      barPointers: [
                                        LinearBarPointer(
                                          value: temperatura,
                                          thickness: 15,
                                          edgeStyle: LinearEdgeStyle.endCurve,
                                          color: obtenerColorIndicador(
                                            temperatura,
                                            tempLo,
                                            tempHi,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: obtenerColorIndicador(
                                        temperatura,
                                        tempLo,
                                        tempHi,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${temperatura.toStringAsFixed(1)} °C',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (medirTempAmb)
                  SizedBox(
                    width: anchoTarjeta,
                    height: 250,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'Temp. ambiente (°C)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: SfLinearGauge(
                                      minimum: 0,
                                      maximum: maxTempAmb,
                                      orientation:
                                          LinearGaugeOrientation.vertical,
                                      axisTrackStyle:
                                          const LinearAxisTrackStyle(
                                            thickness: 15,
                                            edgeStyle: LinearEdgeStyle.endCurve,
                                          ),
                                      ranges: [
                                        LinearGaugeRange(
                                          startValue: 0,
                                          endValue: tempAmbLo,
                                          color: Colors.green,
                                        ),
                                        LinearGaugeRange(
                                          startValue: tempAmbLo,
                                          endValue: tempAmbHi,
                                          color: Colors.orange,
                                        ),
                                        LinearGaugeRange(
                                          startValue: tempAmbHi,
                                          endValue: maxTempAmb,
                                          color: Colors.red,
                                        ),
                                      ],
                                      barPointers: [
                                        LinearBarPointer(
                                          value: tempAmbiente,
                                          thickness: 15,
                                          edgeStyle: LinearEdgeStyle.endCurve,
                                          color: obtenerColorIndicador(
                                            tempAmbiente,
                                            tempAmbLo,
                                            tempAmbHi,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: obtenerColorIndicador(
                                        tempAmbiente,
                                        tempAmbLo,
                                        tempAmbHi,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${tempAmbiente.toStringAsFixed(1)} °C',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (medirVib)
                  SizedBox(
                    width: anchoTarjeta,
                    height: 250,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'Vibración (mm/s)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 40.0,
                                  horizontal: 10.0,
                                ),
                                child: SfLinearGauge(
                                  minimum: 0,
                                  maximum: maxVib,
                                  orientation:
                                      LinearGaugeOrientation.horizontal,
                                  ranges: [
                                    LinearGaugeRange(
                                      startValue: 0,
                                      endValue: vibLo,
                                      color: Colors.green,
                                    ),
                                    LinearGaugeRange(
                                      startValue: vibLo,
                                      endValue: vibHi,
                                      color: Colors.orange,
                                    ),
                                    LinearGaugeRange(
                                      startValue: vibHi,
                                      endValue: maxVib,
                                      color: Colors.red,
                                    ),
                                  ],
                                  markerPointers: [
                                    LinearShapePointer(
                                      value: vibracion,
                                      shapeType: LinearShapePointerType
                                          .invertedTriangle,
                                      color: obtenerColorIndicador(
                                        vibracion,
                                        vibLo,
                                        vibHi,
                                      ),
                                      position: LinearElementPosition.cross,
                                    ),
                                  ],
                                  barPointers: [
                                    LinearBarPointer(
                                      value: vibracion,
                                      color: obtenerColorIndicador(
                                        vibracion,
                                        vibLo,
                                        vibHi,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Text(
                              '${vibracion.toStringAsFixed(1)} mm/s',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (medirHum)
                  SizedBox(
                    width: anchoTarjeta,
                    height: 250,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'Humedad (%)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: SfRadialGauge(
                                axes: <RadialAxis>[
                                  RadialAxis(
                                    minimum: 0,
                                    maximum: maxHumEje,
                                    showLabels: false,
                                    showTicks: false,
                                    startAngle: 270,
                                    endAngle: 270,
                                    axisLineStyle: const AxisLineStyle(
                                      thickness: 0.15,
                                      thicknessUnit: GaugeSizeUnit.factor,
                                    ),
                                    ranges: <GaugeRange>[
                                      GaugeRange(
                                        startValue: 0,
                                        endValue: humLo,
                                        color: Colors.green.withOpacity(0.25),
                                      ),
                                      GaugeRange(
                                        startValue: humLo,
                                        endValue: humHi,
                                        color: Colors.orange.withOpacity(0.35),
                                      ),
                                      GaugeRange(
                                        startValue: humHi,
                                        endValue: maxHumEje,
                                        color: Colors.red.withOpacity(0.35),
                                      ),
                                    ],
                                    pointers: <GaugePointer>[
                                      RangePointer(
                                        value: humedad,
                                        width: 0.15,
                                        sizeUnit: GaugeSizeUnit.factor,
                                        color: obtenerColorIndicador(
                                          humedad,
                                          humLo,
                                          humHi,
                                        ),
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
                                              color: obtenerColorIndicador(
                                                humedad,
                                                humLo,
                                                humHi,
                                              ),
                                              size: 40,
                                            ),
                                            Text(
                                              '${humedad.toStringAsFixed(1)} %',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
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
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 30),
            if (datosGraficaActual.isNotEmpty)
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Historial de Monitoreo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8.0,
                        alignment: WrapAlignment.center,
                        children: construirBotonesMetricas(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 300,
                        child: SfCartesianChart(
                          primaryXAxis: const NumericAxis(isVisible: false),
                          primaryYAxis: NumericAxis(
                            minimum: 0,
                            maximum: obtenerMaxEjeGrafica(),
                            title: AxisTitle(text: obtenerUnidadGrafica()),
                            plotBands: plotBandsGrafica(),
                          ),
                          tooltipBehavior: TooltipBehavior(enable: true),
                          series: <CartesianSeries<PuntoGrafica, int>>[
                            if (metricaActiva != 'Comparar temps')
                              SplineAreaSeries<PuntoGrafica, int>(
                                dataSource: datosGraficaActual,
                                xValueMapper: (PuntoGrafica datos, _) =>
                                    datos.tiempo,
                                yValueMapper: (PuntoGrafica datos, _) =>
                                    datos.valor,
                                color: obtenerColorGrafica().withOpacity(0.3),
                                borderColor: obtenerColorGrafica(),
                                borderWidth: 3,
                                name: metricaActiva,
                              ),
                            if (metricaActiva == 'Comparar temps') ...[
                              SplineAreaSeries<PuntoGrafica, int>(
                                dataSource: histTemp,
                                xValueMapper: (PuntoGrafica datos, _) =>
                                    datos.tiempo,
                                yValueMapper: (PuntoGrafica datos, _) =>
                                    datos.valor,
                                color: Colors.red.withOpacity(0.25),
                                borderColor: Colors.red,
                                borderWidth: 2,
                                name: 'Motor',
                              ),
                              SplineAreaSeries<PuntoGrafica, int>(
                                dataSource: histTempAmb,
                                xValueMapper: (PuntoGrafica datos, _) =>
                                    datos.tiempo,
                                yValueMapper: (PuntoGrafica datos, _) =>
                                    datos.valor,
                                color: Colors.lightBlue.withOpacity(0.25),
                                borderColor: Colors.lightBlue,
                                borderWidth: 2,
                                name: 'Ambiente',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
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
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
    );
  }
}
