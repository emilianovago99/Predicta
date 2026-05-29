#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// ═══════════════════════════════════════════════════════════════
// CONFIGURACIÓN DE RED
// ═══════════════════════════════════════════════════════════════
const char* SSID = "nano";
const char* PASSWORD = "nanovago9";
const char* SERVER_NAME = "http://10.213.241.77:8000/api/sensores";
const char* MAQUINA_ID = "M-01";

// ═══════════════════════════════════════════════════════════════
// VARIABLES GLOBALES DE SIMULACIÓN
// ═══════════════════════════════════════════════════════════════
unsigned long ultimoTiempo = 0;
const int INTERVALO_ENVIO = 5000; // 5 segundos

// Variables para simular tendencias realistas
float temperatura_actual = 45.0;
float vibracion_actual = 2.5;
float voltaje_actual = 110.0;
int velocidad_actual = 1200;
float humedad_actual = 55.0;

// ═══════════════════════════════════════════════════════════════
// ESTRUCTURAS DE DATOS
// ═══════════════════════════════════════════════════════════════
struct Sensores {
  float temperatura;
  float humedad;
  float voltaje;
  float vibracion;
  int velocidad;
};

// ═══════════════════════════════════════════════════════════════
// FUNCIONES DE LECTURA SIMULADA
// ═══════════════════════════════════════════════════════════════

float generarTemperatura() {
  // Simular variación pequeña pero realista
  float variacion = random(-20, 20) / 10.0; // -2.0 a +2.0°C
  temperatura_actual += variacion;
  
  // Mantener dentro de rangos realistas
  temperatura_actual = constrain(temperatura_actual, 40.0, 75.0);
  return round(temperatura_actual * 10) / 10.0;
}

float generarHumedad() {
  float variacion = random(-15, 15) / 10.0; // -1.5 a +1.5%
  humedad_actual += variacion;
  humedad_actual = constrain(humedad_actual, 30.0, 80.0);
  return round(humedad_actual * 10) / 10.0;
}

float generarVoltaje() {
  float variacion = random(-30, 30) / 10.0; // -3.0 a +3.0V
  voltaje_actual += variacion;
  voltaje_actual = constrain(voltaje_actual, 90.0, 130.0);
  return round(voltaje_actual * 10) / 10.0;
}

float generarVibracion() {
  float variacion = random(-15, 15) / 100.0; // -0.15 a +0.15 mm/s
  vibracion_actual += variacion;
  vibracion_actual = constrain(vibracion_actual, 0.5, 8.0);
  return round(vibracion_actual * 100) / 100.0;
}

int generarVelocidad() {
  int variacion = random(-100, 100); // -100 a +100 RPM
  velocidad_actual += variacion;
  velocidad_actual = constrain(velocidad_actual, 600, 1800);
  return velocidad_actual;
}

Sensores leerTodosSensores() {
  Sensores datos;
  datos.temperatura = generarTemperatura();
  datos.humedad = generarHumedad();
  datos.voltaje = generarVoltaje();
  datos.vibracion = generarVibracion();
  datos.velocidad = generarVelocidad();
  
  return datos;
}

// ═══════════════════════════════════════════════════════════════
// COMUNICACIÓN CON SERVIDOR
// ═══════════════════════════════════════════════════════════════

void enviarDatosAlServidor(Sensores datos) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WIFI] Desconectado");
    return;
  }

  HTTPClient http;
  http.begin(SERVER_NAME);
  http.addHeader("Content-Type", "application/json");

  // Crear JSON usando ArduinoJson
  StaticJsonDocument<256> doc;
  doc["maquina_id"] = MAQUINA_ID;
  doc["temperatura"] = datos.temperatura;
  doc["humedad"] = datos.humedad;
  doc["voltaje"] = datos.voltaje;
  doc["vibracion"] = datos.vibracion;
  doc["velocidad"] = datos.velocidad;

  String jsonPayload;
  serializeJson(doc, jsonPayload);

  Serial.println("[HTTP] Enviando datos...");
  Serial.println(jsonPayload);

  int httpCode = http.POST(jsonPayload);

  if (httpCode > 0) {
    Serial.print("[HTTP] Código: ");
    Serial.println(httpCode);
    
    if (httpCode == HTTP_CODE_OK) {
      String response = http.getString();
      Serial.println("[HTTP] ✓ Éxito");
    }
  } else {
    Serial.print("[HTTP] Error: ");
    Serial.println(httpCode);
  }

  http.end();
}

// ═══════════════════════════════════════════════════════════════
// SETUP Y LOOP
// ═══════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n╔═══════════════════════════════════════╗");
  Serial.println("║   PREDICTA - ESP32 SIMULADOR          ║");
  Serial.println("╚═══════════════════════════════════════╝");
  Serial.print("Máquina: ");
  Serial.println(MAQUINA_ID);
  Serial.println("[INFO] Modo: SIMULACIÓN DE DATOS\n");

  // Conectar WiFi
  Serial.print("Conectando WiFi: ");
  Serial.println(SSID);
  WiFi.begin(SSID, PASSWORD);

  int intentos = 0;
  while (WiFi.status() != WL_CONNECTED && intentos < 20) {
    delay(500);
    Serial.print(".");
    intentos++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✓ WiFi Conectado");
    Serial.print("   IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n✗ Error conectando WiFi");
  }

  ultimoTiempo = millis();
  randomSeed(analogRead(0)); // Para mejor aleatoriedad
}

void loop() {
  // Leer todos los sensores (simulados)
  Sensores datos = leerTodosSensores();

  // Mostrar en serial
  Serial.println("\n┌─ LECTURA DE SENSORES (SIMULADA) ──────┐");
  Serial.print("│ Temperatura: ");
  Serial.print(datos.temperatura);
  Serial.println(" °C");
  Serial.print("│ Humedad:     ");
  Serial.print(datos.humedad);
  Serial.println(" %");
  Serial.print("│ Voltaje:     ");
  Serial.print(datos.voltaje);
  Serial.println(" V");
  Serial.print("│ Vibración:   ");
  Serial.print(datos.vibracion);
  Serial.println(" mm/s");
  Serial.print("│ Velocidad:   ");
  Serial.print(datos.velocidad);
  Serial.println(" RPM");
  Serial.println("└────────────────────────────────────────┘");

  // Enviar al servidor
  enviarDatosAlServidor(datos);

  // Esperar antes del siguiente ciclo
  delay(INTERVALO_ENVIO);
}