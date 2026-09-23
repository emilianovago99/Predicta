import statistics
import time
import requests
import google.generativeai as genai

import os
from dotenv import load_dotenv
load_dotenv()
genai.configure(api_key=os.environ['GEMINI_API_KEY'])
modelo_gemini = genai.GenerativeModel('gemini-2.5-flash')

class MotorEdgeAI:
    def __init__(self):
        self.en_calibracion = True
        self.datos_vibracion = []
        self.datos_temperatura = []
        self.limite_vib_sup = 0.0
        self.limite_temp_sup = 0.0

    def ingerir_datos(self, vibracion, temperatura):
        if self.en_calibracion:
            self.datos_vibracion.append(vibracion)
            self.datos_temperatura.append(temperatura)
            
            if len(self.datos_vibracion) == 50:
                self.finalizar_calibracion()
        
        if self.en_calibracion == False:
            self.evaluar_anomalia(vibracion, temperatura)

    def finalizar_calibracion(self):
        promedio_vib = statistics.mean(self.datos_vibracion)
        desviacion_vib = statistics.stdev(self.datos_vibracion)
        self.limite_vib_sup = promedio_vib + (3 * desviacion_vib)

        promedio_temp = statistics.mean(self.datos_temperatura)
        desviacion_temp = statistics.stdev(self.datos_temperatura)
        self.limite_temp_sup = promedio_temp + (3 * desviacion_temp)

        self.en_calibracion = False
        print("Calibración exitosa. Iniciando protección activa.")

    def evaluar_anomalia(self, vibracion, temperatura):
        anomalia_vibracion = vibracion > self.limite_vib_sup
        anomalia_temperatura = temperatura > self.limite_temp_sup

        if anomalia_vibracion or anomalia_temperatura:
            self.detonar_alerta(vibracion, temperatura)

    def detonar_alerta(self, vibracion, temperatura):
        prompt = f"Actúa como un experto en mantenimiento industrial. Detectamos una anomalía. Vibración: {vibracion}, Temperatura: {temperatura}. Genera un diagnóstico de causa raíz de máximo 2 líneas."
        respuesta = modelo_gemini.generate_content(prompt)
        diagnostico = respuesta.text

        payload = {
            "maquina_id": os.getenv("MACHINE_ID", "M-01"),
            "riesgo": 85.0,
            "diagnostico": diagnostico
        }
        
        try:
            requests.post(os.getenv("API_BASE_URL", "http://127.0.0.1:8000").rstrip("/") + "/api/alertas", json=payload, headers={"Authorization": "Bearer " + os.environ["DEVICE_API_KEY"]}, timeout=10).raise_for_status()
            print("Alerta verificada y subida al servidor con éxito.")
        except Exception as e:
            print("Error de conexión con el servidor principal.")

motor = MotorEdgeAI()

datos_simulados = [
    (2.1, 45.0), (2.2, 45.2), (2.1, 45.1), (2.3, 45.3), (2.2, 45.1),
    (2.1, 45.0), (2.4, 45.4), (2.2, 45.2), (2.1, 45.1), (2.2, 45.0),
    (2.1, 45.0), (2.2, 45.2), (2.1, 45.1), (2.3, 45.3), (2.2, 45.1),
    (2.1, 45.0), (2.4, 45.4), (2.2, 45.2), (2.1, 45.1), (2.2, 45.0),
    (2.1, 45.0), (2.2, 45.2), (2.1, 45.1), (2.3, 45.3), (2.2, 45.1),
    (2.1, 45.0), (2.4, 45.4), (2.2, 45.2), (2.1, 45.1), (2.2, 45.0),
    (2.1, 45.0), (2.2, 45.2), (2.1, 45.1), (2.3, 45.3), (2.2, 45.1),
    (2.1, 45.0), (2.4, 45.4), (2.2, 45.2), (2.1, 45.1), (2.2, 45.0),
    (2.1, 45.0), (2.2, 45.2), (2.1, 45.1), (2.3, 45.3), (2.2, 45.1),
    (2.1, 45.0), (2.4, 45.4), (2.2, 45.2), (2.1, 45.1), (2.2, 45.0),
    (2.2, 45.1), (2.3, 45.2), 
    (8.5, 95.0) 
]

for vib, temp in datos_simulados:
    motor.ingerir_datos(vib, temp)
    time.sleep(0.1)