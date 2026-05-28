import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
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
  double vibracion = 0.0;
  int velocidad = 0;
  double voltaje = 0.0;
  double humedad = 0.0;

  double tAlerta = 50.0;
  double tPeligro = 60.0;
  double vibAlerta = 4.0;
  double vibPeligro = 7.0;
  double voltAlerta = 100.0;
  double voltPeligro = 130.0;
  int velAlerta = 800;
  int velPeligro = 1500;
  double humAlerta = 60.0;
  double humPeligro = 80.0;

  bool medirTemp = true;
  bool medirVib = true;
  bool medirVolt = true;
  bool medirVel = true;
  bool medirHum = true;

  String metricaActiva = 'Temperatura';
  String ultimaAlertaProcesada = '';

  List<PuntoGrafica> histTemp = [];
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
    temporizador = Timer.periodic(const Duration(seconds: 2), (timer) {
      obtenerDatosMaquina();
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

  Future<void> obtenerDatosMaquina() async {
    final url = Uri.parse(
      'http://10.10.7.161:8000/api/maquinas/${widget.idMaquina}/datos',
    );

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

          if (data['maquina']['medir_temp'] == 1) {
            medirTemp = true;
          }
          if (data['maquina']['medir_temp'] == 0) {
            medirTemp = false;
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
            if (ultimaAlertaProcesada != diagnostico) {
              ultimaAlertaProcesada = diagnostico;
              lanzarNotificacionPantalla(diagnostico, estado);
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
              vibracion = listaRaw[0]['vibracion'].toDouble();
              velocidad = listaRaw[0]['velocidad'].toInt();
              voltaje = listaRaw[0]['voltaje'].toDouble();
              humedad = listaRaw[0]['humedad'].toDouble();

              histTemp.clear();
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
    if (metricaActiva == 'Temperatura') {
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

  Color obtenerColorGrafica() {
    if (metricaActiva == 'Temperatura') {
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
    if (metricaActiva == 'Temperatura') {
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
    if (metricaActiva == 'Temperatura') {
      return tPeligro;
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

  List<Widget> construirBotonesMetricas() {
    List<Widget> chips = [];
    if (medirTemp) {
      chips.add(crearChoiceChip('Temperatura'));
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

    double maxVel = 2000.0;
    if (velPeligro > 1800) {
      maxVel = velPeligro + 500.0;
    }

    double maxVolt = 250.0;
    if (voltPeligro > 200) {
      maxVolt = voltPeligro + 50.0;
    }

    double maxTemp = 120.0;
    if (tPeligro > 100) {
      maxTemp = tPeligro + 30.0;
    }

    double maxVib = 10.0;
    if (vibPeligro > 8) {
      maxVib = vibPeligro + 5.0;
    }

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
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            const Text(
                              'Velocidad (RPM)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: SfRadialGauge(
                                axes: <RadialAxis>[
                                  RadialAxis(
                                    minimum: 0,
                                    maximum: maxVel,
                                    ranges: <GaugeRange>[
                                      GaugeRange(
                                        startValue: 0,
                                        endValue: velAlerta.toDouble(),
                                        color: Colors.green,
                                      ),
                                      GaugeRange(
                                        startValue: velAlerta.toDouble(),
                                        endValue: velPeligro.toDouble(),
                                        color: Colors.orange,
                                      ),
                                      GaugeRange(
                                        startValue: velPeligro.toDouble(),
                                        endValue: maxVel,
                                        color: Colors.red,
                                      ),
                                    ],
                                    pointers: <GaugePointer>[
                                      NeedlePointer(
                                        value: velocidad.toDouble(),
                                        enableAnimation: true,
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
                                        positionFactor: 0.5,
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
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            const Text(
                              'Voltaje (V)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                                      ),
                                    ],
                                    ranges: <GaugeRange>[
                                      GaugeRange(
                                        startValue: 0,
                                        endValue: voltAlerta,
                                        color: Colors.green,
                                      ),
                                      GaugeRange(
                                        startValue: voltAlerta,
                                        endValue: voltPeligro,
                                        color: Colors.orange,
                                      ),
                                      GaugeRange(
                                        startValue: voltPeligro,
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
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            const Text(
                              'Temperatura (°C)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: SfLinearGauge(
                                minimum: 0,
                                maximum: maxTemp,
                                orientation: LinearGaugeOrientation.vertical,
                                ranges: [
                                  LinearGaugeRange(
                                    startValue: 0,
                                    endValue: tAlerta,
                                    color: Colors.green,
                                  ),
                                  LinearGaugeRange(
                                    startValue: tAlerta,
                                    endValue: tPeligro,
                                    color: Colors.orange,
                                  ),
                                  LinearGaugeRange(
                                    startValue: tPeligro,
                                    endValue: maxTemp,
                                    color: Colors.red,
                                  ),
                                ],
                                barPointers: [
                                  LinearBarPointer(
                                    value: temperatura,
                                    color: obtenerColorIndicador(
                                      temperatura,
                                      tAlerta,
                                      tPeligro,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                if (medirVib)
                  SizedBox(
                    width: anchoTarjeta,
                    height: 250,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
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
                              child: SfRadialGauge(
                                axes: <RadialAxis>[
                                  RadialAxis(
                                    minimum: 0,
                                    maximum: maxVib,
                                    startAngle: 180,
                                    endAngle: 0,
                                    canScaleToFit: true,
                                    pointers: <GaugePointer>[
                                      NeedlePointer(
                                        value: vibracion,
                                        enableAnimation: true,
                                      ),
                                    ],
                                    ranges: <GaugeRange>[
                                      GaugeRange(
                                        startValue: 0,
                                        endValue: vibAlerta,
                                        color: Colors.green,
                                      ),
                                      GaugeRange(
                                        startValue: vibAlerta,
                                        endValue: vibPeligro,
                                        color: Colors.orange,
                                      ),
                                      GaugeRange(
                                        startValue: vibPeligro,
                                        endValue: maxVib,
                                        color: Colors.red,
                                      ),
                                    ],
                                  ),
                                ],
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
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            const Text(
                              'Humedad (%)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: SfRadialGauge(
                                axes: <RadialAxis>[
                                  RadialAxis(
                                    minimum: 0,
                                    maximum: 100,
                                    ranges: <GaugeRange>[
                                      GaugeRange(
                                        startValue: 0,
                                        endValue: humAlerta,
                                        color: Colors.green,
                                      ),
                                      GaugeRange(
                                        startValue: humAlerta,
                                        endValue: humPeligro,
                                        color: Colors.orange,
                                      ),
                                      GaugeRange(
                                        startValue: humPeligro,
                                        endValue: 100,
                                        color: Colors.red,
                                      ),
                                    ],
                                    pointers: <GaugePointer>[
                                      NeedlePointer(
                                        value: humedad,
                                        enableAnimation: true,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${humedad.toStringAsFixed(1)} %',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
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
                            title: AxisTitle(text: obtenerUnidadGrafica()),
                            plotBands: <PlotBand>[
                              PlotBand(
                                isVisible: true,
                                start: obtenerLimiteGrafica(),
                                end: obtenerLimiteGrafica() + 0.5,
                                color: Colors.red,
                                text: 'Crítico',
                                textStyle: const TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                          tooltipBehavior: TooltipBehavior(enable: true),
                          series: <CartesianSeries<PuntoGrafica, int>>[
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
