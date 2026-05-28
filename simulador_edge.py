import time
import random
import requests
import os
from dotenv import load_dotenv
import google.generativeai as genai

load_dotenv()
api_key = os.getenv("GEMINI_API_KEY")
genai.configure(api_key=api_key)
modelo = genai.GenerativeModel('gemini-2.5-flash')

class NodoEdge:
    def __init__(self, maquina_id):
        self.maquina_id = maquina_id
        self.limite_temperatura = 60.0
        self.limite_vibracion = 7.0
        self.url_sensores = "http://127.0.0.1:8000/api/sensores"
        self.url_alertas = "http://127.0.0.1:8000/api/alertas"
        self.url_config = f"http://127.0.0.1:8000/api/maquinas/{maquina_id}/config"
        self.buffer_temperatura = []
        self.nivel_alerta = 0
        self.temp_actual = 42.0

    def sincronizar_limites_nube(self):
        try:
            respuesta = requests.get(self.url_config)
            if respuesta.status_code == 200:
                config = respuesta.json()
                self.limite_temperatura = config['temp_peligro']
                self.limite_vibracion = config['vib_peligro']
        except Exception:
            pass

    def leer_sensores(self, ciclo):
        vib = random.uniform(1.0, 1.5)
        volt = random.uniform(119.5, 120.5)
        vel = int(random.uniform(1745, 1755))

        if ciclo <= 10:
            self.temp_actual = 42.0 + random.uniform(-0.5, 0.5)

        if ciclo > 10:
            if ciclo <= 18:
                self.temp_actual = self.temp_actual + random.uniform(2.1, 2.5)
                vib = random.uniform(1.8, 3.5)
                volt = random.uniform(118.0, 119.5)
                vel = int(random.uniform(1720, 1740))

        if ciclo > 18:
            if ciclo <= 28:
                self.temp_actual = self.temp_actual + random.uniform(1.0, 2.0)
                vib = random.uniform(6.0, 8.5)
                volt = random.uniform(95.0, 105.0)
                vel = int(random.uniform(800, 950))

        if ciclo > 28:
            self.temp_actual = self.temp_actual - random.uniform(4.0, 6.0)
            if self.temp_actual < 42.0:
                self.temp_actual = 42.0 + random.uniform(-0.5, 0.5)
                
            vib = random.uniform(1.0, 1.5)
            volt = random.uniform(119.5, 120.5)
            vel = int(random.uniform(1745, 1755))

        return {"temperatura": self.temp_actual, "vibracion": vib, "voltaje": volt, "velocidad": vel}

    def procesar_localmente(self, datos):
        self.buffer_temperatura.append(datos["temperatura"])
        if len(self.buffer_temperatura) > 3:
            self.buffer_temperatura.pop(0)

        es_peligro = False
        es_prediccion = False

        if datos["temperatura"] >= self.limite_temperatura:
            es_peligro = True
        if datos["vibracion"] >= self.limite_vibracion:
            es_peligro = True

        if len(self.buffer_temperatura) == 3:
            if not es_peligro:
                delta1 = self.buffer_temperatura[1] - self.buffer_temperatura[0]
                delta2 = self.buffer_temperatura[2] - self.buffer_temperatura[1]
                
                if delta1 > 2.0:
                    if delta2 > 2.0:
                        es_prediccion = True

        if not es_peligro:
            if not es_prediccion:
                self.nivel_alerta = 0

        payload_telemetria = {
            "maquina_id": self.maquina_id,
            "voltaje": datos["voltaje"],
            "temperatura": datos["temperatura"],
            "vibracion": datos["vibracion"],
            "velocidad": datos["velocidad"]
        }
        
        requests.post(self.url_sensores, json=payload_telemetria)
        print(f"Telemetria: Temp {datos['temperatura']:.1f}C | Limite Actual: {self.limite_temperatura}°C")

        if es_peligro:
            if self.nivel_alerta < 2:
                self.generar_alerta_gemini(datos, "critico")
                self.nivel_alerta = 2
        if es_prediccion:
            if self.nivel_alerta < 1:
                self.generar_alerta_gemini(datos, "predictivo")
                self.nivel_alerta = 1

    def generar_alerta_gemini(self, datos, tipo):
        prompt = ""
        riesgo = 0.0

        if tipo == "critico":
            prompt = f"Temperatura actual {datos['temperatura']:.1f}C supera el limite critico. Da diagnostico de falla en una frase corta."
            riesgo = 95.0
        if tipo == "predictivo":
            prompt = f"La temperatura esta subiendo anormalmente rapido (actual: {datos['temperatura']:.1f}C). Predice que componente va a fallar en los proximos minutos si esto sigue asi. Responde en una sola frase corta empezando con 'Prediccion:'."
            riesgo = 60.0

        try:
            respuesta = modelo.generate_content(prompt)
            diagnostico = respuesta.text
        except Exception:
            if tipo == "critico":
                diagnostico = "**Falla en el sistema de enfriamiento (Modo Respaldo Activado).**"
            if tipo == "predictivo":
                diagnostico = "Prediccion: Desgaste inminente por friccion acelerada (Modo Respaldo Activado)."

        payload_alerta = {
            "maquina_id": self.maquina_id,
            "riesgo": riesgo,
            "diagnostico": diagnostico
        }
        
        requests.post(self.url_alertas, json=payload_alerta)
        print(f"\n--- ALERTA ({tipo.upper()}) ENVIADA: {diagnostico} ---\n")

nodo = NodoEdge(maquina_id="M-01")

print("Iniciando monitoreo realista de ciclo de vida (40 ciclos)...")

for i in range(1, 41):
    if i == 1:
        print("\n[FASE 1] Operacion normal. Motor estable.")
    if i == 11:
        print("\n[FASE 2] Friccion detectada. Calentamiento gradual iniciado...")
    if i == 19:
        print("\n[FASE 3] Falla inminente. Limite estructural comprometido...")
    if i == 29:
        print("\n[FASE 4] Protocolo de enfriamiento. Disipando calor...")
        
    nodo.sincronizar_limites_nube()
    lectura = nodo.leer_sensores(i)
    nodo.procesar_localmente(lectura)
    time.sleep(2)