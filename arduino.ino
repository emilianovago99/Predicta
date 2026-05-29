// =============================================================
//  Mecanimales — ESP32 Unified Firmware v2.0
//  Arquitectura: Lectura de sensores + Seguridad local + HTTP POST
//  Tabla destino: SensorData (id_maquina, temperatura, temp_ambiente,
//                              vibracion, voltaje, velocidad, humedad)
// =============================================================

// ── Librerías ────────────────────────────────────────────────
#include <WiFi.h>
#include <HTTPClient.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include "DHT.h"
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Wire.h>

// ── Credenciales de Red ───────────────────────────────────────
const char* ssid        = "S24B";
const char* password    = "12gracias";
const char* serverName  = "http://10.170.192.77:8000/api/sensores";

// ── Identificador de Máquina ──────────────────────────────────
const char* ID_MAQUINA  = "M-01";

// ── Pines ─────────────────────────────────────────────────────
#define PIN_TEMP_MOTOR   15   // DS18B20 — temperatura del motor
#define PIN_RELE         18   // Relevador — paro de emergencia
#define PIN_DHT           4   // DHT11    — temp. ambiente + humedad
#define PIN_FLAMA_ANALOG 34   // Sensor analógico de flama

// ── Tipo DHT ──────────────────────────────────────────────────
#define DHTTYPE DHT11

// ── Valores Estáticos (sin sensor físico disponible) ─────────
//    RPM equivalente a 1 rev/s → 60 RPM
//    Voltaje nominal de línea DC
const float VELOCIDAD_FIJA = 60.0;   // RPM
const float VOLTAJE_FIJO   = 12.0;   // Voltios

// ── Umbrales de Seguridad Local ───────────────────────────────
#define UMBRAL_TEMP_MOTOR    45.0   // °C — motor caliente
#define UMBRAL_TEMP_AMBIENTE 27.0   // °C — ambiente crítico
#define UMBRAL_VIBRACION     15.0   // m/s² — vibración alta
#define UMBRAL_FUEGO        1200    // ADC  — valor bajo = fuego

// ── Temporización ─────────────────────────────────────────────
#define INTERVALO_HTTP_MS  2000UL   // 2 s entre transmisiones HTTP

// ── Objetos de sensores ───────────────────────────────────────
OneWire          oneWire(PIN_TEMP_MOTOR);
DallasTemperature sensorsMotor(&oneWire);
DHT              dht(PIN_DHT, DHTTYPE);
Adafruit_MPU6050 mpu;

// ── Variable de temporización ─────────────────────────────────
unsigned long ultimoEnvioHTTP = 0;


// =============================================================
//  SETUP
// =============================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  // ── Relevador apagado al inicio (estado seguro) ───────────
  pinMode(PIN_RELE, OUTPUT);
  digitalWrite(PIN_RELE, LOW);

  // ── Inicialización de sensores ────────────────────────────
  sensorsMotor.begin();
  dht.begin();

  if (!mpu.begin()) {
    Serial.println("[WARN] MPU6050 no detectado. Vibracion reportara 0.");
  } else {
    Serial.println("[OK] MPU6050 inicializado.");
  }

  // ── Conexión WiFi ─────────────────────────────────────────
  Serial.print("[WiFi] Conectando a: ");
  Serial.println(ssid);
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.println("[WiFi] Conexion establecida.");
  Serial.print("[WiFi] IP del ESP32: ");
  Serial.println(WiFi.localIP());
  Serial.println("[INFO] Firmware Mecanimales v2.0 listo.\n");
}


// =============================================================
//  LOOP
// =============================================================
void loop() {

  // ── 1. LECTURA DE SENSORES ──────────────────────────────────

  // DS18B20: temperatura del motor (°C)
  sensorsMotor.requestTemperatures();
  float tempMotor = sensorsMotor.getTempCByIndex(0);

  // DHT11: temperatura ambiente (°C) y humedad relativa (%)
  float tempAmbiente = dht.readTemperature();
  float humedad      = dht.readHumidity();

  // Valores NaN → 0.0 para evitar JSON inválido
  if (isnan(tempAmbiente)) tempAmbiente = 0.0;
  if (isnan(humedad))      humedad      = 0.0;

  // MPU6050: magnitud del vector de aceleración (m/s²)
  float vibracion = 0.0;
  sensors_event_t a, g, temp_mpu;
  mpu.getEvent(&a, &g, &temp_mpu);
  vibracion = sqrt(
    pow(a.acceleration.x, 2) +
    pow(a.acceleration.y, 2) +
    pow(a.acceleration.z, 2)
  );

  // Sensor analógico de flama (valor ADC)
  int valorFuego = analogRead(PIN_FLAMA_ANALOG);

  // ── 2. MATRIZ DE SEGURIDAD LOCAL (se evalúa SIEMPRE) ────────
  bool   emergencia = false;
  String motivo     = "";

  if (tempMotor    > UMBRAL_TEMP_MOTOR)    { emergencia = true; motivo += "[MOTOR CALIENTE] ";    }
  if (tempAmbiente > UMBRAL_TEMP_AMBIENTE) { emergencia = true; motivo += "[AMBIENTE CRITICO] ";  }
  if (vibracion    > UMBRAL_VIBRACION)     { emergencia = true; motivo += "[VIBRACION ALTA] ";    }
  if (valorFuego   < UMBRAL_FUEGO)         { emergencia = true; motivo += "[FUEGO DETECTADO] ";   }

  if (emergencia) {
    digitalWrite(PIN_RELE, HIGH);   // Activa el paro de emergencia
    Serial.print("[EMERGENCIA] PARO ACTIVO — ");
    Serial.println(motivo);
  } else {
    digitalWrite(PIN_RELE, LOW);    // Sistema en condiciones normales
  }

  // ── 3. TRANSMISIÓN HTTP (no bloqueante, cada 2 s) ───────────
  unsigned long ahora = millis();
  if (ahora - ultimoEnvioHTTP >= INTERVALO_HTTP_MS) {
    ultimoEnvioHTTP = ahora;

    if (WiFi.status() == WL_CONNECTED) {
      enviarDatos(tempMotor, tempAmbiente, vibracion, humedad);
    } else {
      Serial.println("[WiFi] Desconectado. Reintentando reconexion...");
      WiFi.reconnect();
    }
  }

  // Sin delay bloqueante — el loop() vuelve inmediatamente
  // para que la seguridad local se reevalúe sin demoras.
}


// =============================================================
//  FUNCIÓN: Construir JSON y ejecutar HTTP POST
//  Mapeo directo a columnas de SensorData:
//    id_maquina   → ID_MAQUINA  (constante)
//    temperatura  → tempMotor   (DS18B20)
//    temp_ambiente→ tempAmbiente(DHT11)
//    vibracion    → vibracion   (MPU6050)
//    voltaje      → VOLTAJE_FIJO(estático 12.0 V)
//    velocidad    → VELOCIDAD_FIJA (estático 60.0 RPM)
//    humedad      → humedad     (DHT11)
// =============================================================
void enviarDatos(float temperatura, float temp_ambiente,
                 float vibracion,   float humedad) {

  HTTPClient http;
  http.begin(serverName);
  http.addHeader("Content-Type", "application/json");

  // Construcción del payload — valores con 2 decimales
  String jsonPayload = "{";
  jsonPayload += "\"maquina_id\":"    + String("\"") + ID_MAQUINA + "\",";
  jsonPayload += "\"temperatura\":"   + String(temperatura,    2) + ",";
  jsonPayload += "\"temp_ambiente\":" + String(temp_ambiente,  2) + ",";
  jsonPayload += "\"vibracion\":"     + String(vibracion,      2) + ",";
  jsonPayload += "\"voltaje\":"       + String(VOLTAJE_FIJO,   2) + ",";
  jsonPayload += "\"velocidad\":"     + String((int)VELOCIDAD_FIJA) + ",";
  jsonPayload += "\"humedad\":"       + String(humedad,        2);
  jsonPayload += "}";

  Serial.println("[HTTP] Enviando POST...");
  Serial.println("[HTTP] Payload: " + jsonPayload);

  int httpResponseCode = http.POST(jsonPayload);

  if (httpResponseCode > 0) {
    Serial.print("[HTTP] Respuesta del servidor — Codigo: ");
    Serial.println(httpResponseCode);
  } else {
    Serial.print("[HTTP] Error en el envio — Codigo interno: ");
    Serial.println(httpResponseCode);
  }

  http.end();
}