// Predicta ESP32 v3: sensor safety and network transport run independently.
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include "DHT.h"
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Wire.h>
#include <time.h>
#include <esp_system.h>
#include "secrets.h"

#define PIN_TEMP_MOTOR 15
#define PIN_RELE 18
#define PIN_DHT 4
#define PIN_FLAMA_ANALOG 34
#define UMBRAL_TEMP_MOTOR 45.0
#define UMBRAL_TEMP_AMBIENTE 27.0
#define UMBRAL_VIBRACION 15.0
#define UMBRAL_FUEGO 1200
const float VELOCIDAD_FIJA = 60.0;
const float VOLTAJE_FIJO = 12.0;
const char* FIRMWARE_VERSION = "3.0.0";
OneWire oneWire(PIN_TEMP_MOTOR);
DallasTemperature sensorsMotor(&oneWire);
DHT dht(PIN_DHT, DHT11);
Adafruit_MPU6050 mpu;

struct Measurement {
  float motor, ambient, vibration, humidity;
  uint32_t sequence;
};
QueueHandle_t pending;
char bootId[33];
volatile bool communicationOk = false;
volatile uint32_t lastSuccess = 0;
bool mpuReady = false;

// Only this task owns HTTP/TLS. Blocking DNS, handshake and retries never stop loop().
void networkTask(void*) {
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  uint32_t lastReconnect = millis();
  Measurement sample;
  for (;;) {
    if (WiFi.status() != WL_CONNECTED || time(nullptr) < 1700000000) {
      communicationOk = false;
      if (millis() - lastReconnect >= 10000) {
        if (WiFi.status() != WL_CONNECTED) WiFi.reconnect();
        else configTime(0, 0, "pool.ntp.org", "time.google.com");
        lastReconnect = millis();
      }
      vTaskDelay(pdMS_TO_TICKS(250));
      continue;
    }
    if (xQueueReceive(pending, &sample, pdMS_TO_TICKS(250)) != pdTRUE) continue;
    char payload[600];
    snprintf(payload, sizeof(payload),
      "{\"maquina_id\":\"%s\",\"temperatura\":%.2f,\"temp_ambiente\":%.2f,"
      "\"vibracion\":%.2f,\"voltaje\":%.2f,\"velocidad\":%d,\"humedad\":%.2f,"
      "\"sequence\":%lu,\"boot_id\":\"%s\",\"firmware_version\":\"%s\"}",
      MACHINE_ID, sample.motor, sample.ambient, sample.vibration, VOLTAJE_FIJO,
      (int)VELOCIDAD_FIJA, sample.humidity, (unsigned long)sample.sequence, bootId, FIRMWARE_VERSION);
    bool delivered = false;
    for (int attempt = 0; attempt < 3; ++attempt) {
      WiFiClientSecure tls;
      WiFiClient plain;
      HTTPClient http;
      tls.setCACert(API_ROOT_CA);  // PEM root CA supplied in secrets.h. Never setInsecure().
      tls.setHandshakeTimeout(8);
      http.setConnectTimeout(5000);
      http.setTimeout(5000);
      http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
      bool started = false;
      if (String(API_URL).startsWith("https://")) started = http.begin(tls, API_URL);
      else if (ALLOW_LOCAL_HTTP && String(API_URL).startsWith("http://")) started = http.begin(plain, API_URL);
      if (!started) { Serial.println("[COMUNICACION] URL/TLS sin configurar"); break; }
      http.addHeader("Content-Type", "application/json");
      http.addHeader("Authorization", String("Bearer ") + DEVICE_API_KEY);
      int code = http.POST((uint8_t*)payload, strlen(payload));
      http.end();
      if (code >= 200 && code < 300) {
        delivered = true;
        lastSuccess = millis();
        break;
      }
      Serial.printf("[COMUNICACION] HTTP %d, intento %d/3\n", code, attempt + 1);
      if (code >= 400 && code < 500 && code != 408 && code != 429) break;
      if (attempt < 2) vTaskDelay(pdMS_TO_TICKS((1000UL << attempt) + (esp_random() % 250)));
    }
    communicationOk = delivered;
    if (!delivered) Serial.println("[COMUNICACION] Medicion descartada tras reintentos limitados");
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_RELE, OUTPUT);
  digitalWrite(PIN_RELE, LOW);  // Existing relay polarity retained.
  sensorsMotor.begin();
  sensorsMotor.setWaitForConversion(false);
  sensorsMotor.requestTemperatures();
  dht.begin();
  mpuReady = mpu.begin();
  snprintf(bootId, sizeof(bootId), "%08lx%08lx%08lx%08lx",
    (unsigned long)esp_random(), (unsigned long)esp_random(),
    (unsigned long)esp_random(), (unsigned long)esp_random());
  pending = xQueueCreate(16, sizeof(Measurement));
  if (!pending || xTaskCreate(networkTask, "predicta-network", 12288, nullptr, 1, nullptr) != pdPASS) {
    Serial.println("[COMUNICACION] No se pudo iniciar transporte; seguridad local activa");
  }
}

void loop() {
  static uint32_t lastMotor = millis(), lastDht = 0, lastMpu = 0, lastSend = 0, lastStatus = 0;
  static uint32_t sequence = 0;
  static float motor = 0, ambient = 0, humidity = 0, vibration = 0;
  const uint32_t now = millis();
  if (now - lastMotor >= 800) {
    motor = sensorsMotor.getTempCByIndex(0);
    sensorsMotor.requestTemperatures();
    lastMotor = now;
  }
  if (now - lastDht >= 2000) {
    ambient = dht.readTemperature(); humidity = dht.readHumidity();
    // Retain legacy DHT fallback; report invalid sensors independently below.
    if (isnan(ambient)) ambient = 0;
    if (isnan(humidity)) humidity = 0;
    lastDht = now;
  }
  if (mpuReady && now - lastMpu >= 100) {
    sensors_event_t a, g, t;
    mpu.getEvent(&a, &g, &t);
    vibration = sqrt(a.acceleration.x*a.acceleration.x + a.acceleration.y*a.acceleration.y + a.acceleration.z*a.acceleration.z);
    lastMpu = now;
  }
  const bool machineRisk = motor > UMBRAL_TEMP_MOTOR || ambient > UMBRAL_TEMP_AMBIENTE ||
    vibration > UMBRAL_VIBRACION || analogRead(PIN_FLAMA_ANALOG) < UMBRAL_FUEGO;
  digitalWrite(PIN_RELE, machineRisk ? HIGH : LOW);
  if (now - lastSend >= 2000) {
    lastSend = now;
    Measurement sample{motor, ambient, vibration, humidity, sequence++};
    // Bounded memory: keep pending order and drop new samples when full.
    if (pending && xQueueSend(pending, &sample, 0) != pdTRUE)
      Serial.println("[COMUNICACION] Buffer lleno; nueva medicion descartada");
  }
  if (now - lastStatus >= 2000) {
    Serial.printf("[MAQUINA] %s | [COMUNICACION] %s\n", machineRisk ? "RIESGO" : "NORMAL",
      communicationOk && now-lastSuccess < 30000 ? "OK" : "SIN COMUNICACION");
    if (!mpuReady || motor == DEVICE_DISCONNECTED_C) Serial.println("[SENSOR] Revisar MPU6050/DS18B20");
    lastStatus = now;
  }
  delay(1); // Yield to FreeRTOS, no network waits in this loop.
}
