import time
import random
import requests
import os
import uuid
import numpy as np
from collections import deque
from dotenv import load_dotenv
import google.generativeai as genai
from sklearn.ensemble import IsolationForest

load_dotenv()
api_key = os.getenv("GEMINI_API_KEY")
modelo = None

if api_key:
    genai.configure(api_key=api_key)
    modelo = genai.GenerativeModel("gemini-2.5-flash")

class NodoEdge:
    def __init__(self, maquina_id):
        self.maquina_id = maquina_id
        self.headers = {"Authorization": "Bearer " + os.environ["DEVICE_API_KEY"]}
        self.boot_id = uuid.uuid4().hex
        self.sequence = 0
        api_base = os.getenv("API_BASE_URL", "http://127.0.0.1:8000")
        api_base_str = str(api_base)
        api_base_clean = api_base_str.rstrip("/")
        self.url_sensores = f"{api_base_clean}/api/sensores"
        self.url_alertas = f"{api_base_clean}/api/alertas"

        self.temp_alerta = 35.0
        self.temp_peligro = 45.0
        self.vib_alerta = 11.0
        self.vib_peligro = 17.0
        self.hum_alerta = 60.0
        self.hum_peligro = 80.0
        self.api_base = api_base_clean
        self._cargar_limites_desde_api()

        self.VENTANA = 10
        self.buf_temp = deque(maxlen=self.VENTANA)
        self.buf_vib  = deque(maxlen=self.VENTANA)
        self.buf_volt = deque(maxlen=self.VENTANA)
        self.buf_vel  = deque(maxlen=self.VENTANA)
        self.buf_hum  = deque(maxlen=self.VENTANA)
        self.buf_tamb = deque(maxlen=self.VENTANA)

        self.ENTRENAMIENTO_MIN = 15
        self.historial_multivar = []
        self.modelo_if = None
        self.if_entrenado = False

        self.nivel_alerta = 0
        self.temp_actual  = 25.0
        self.temp_amb_actual = 22.0
        self.CICLOS_ALERTA_PREVENTIVA = 12

    def _cargar_limites_desde_api(self):
        try:
            url = f"{self.api_base}/api/maquinas/{self.maquina_id}/config"
            resp = requests.get(url, headers=self.headers, timeout=4)
            resp.raise_for_status()
            if resp.status_code == 200:
                cfg = resp.json()
                self.temp_alerta = float(cfg["temp_alerta"])
                self.temp_peligro = float(cfg["temp_peligro"])
                self.vib_alerta = float(cfg["vib_alerta"])
                self.vib_peligro = float(cfg["vib_peligro"])
                if "hum_alerta" in cfg:
                    self.hum_alerta = float(cfg["hum_alerta"])
                if "hum_peligro" in cfg:
                    self.hum_peligro = float(cfg["hum_peligro"])
                print(f"[Edge] Limites cargados: temp alerta={self.temp_alerta}C, peligro={self.temp_peligro}C")
        except:
            print("[Edge] API no disponible")

    def _ciclos_estimados_hasta_umbral(self, actual, pendiente, umbral):
        if actual >= umbral: return 0
        if pendiente <= 0.02: return 9999
        return max(0, int(np.ceil((umbral - actual) / pendiente)))

    def _proyectar_ciclos_preventivo(self, datos, features):
        if len(self.buf_temp) < 3: return 9999, "temperatura"
        den = max(1, len(self.buf_temp)-1)
        p_t = features["temp_delta"] / den
        p_v = features["vib_delta"] / den
        c_t = self._ciclos_estimados_hasta_umbral(datos["temperatura"], p_t, self.temp_alerta)
        c_v = self._ciclos_estimados_hasta_umbral(datos["vibracion"], p_v, self.vib_alerta)
        return (c_t, "temperatura") if c_t <= c_v else (c_v, "vibracion")

    def leer_sensores(self, ciclo):
        volt = 12.0
        hum = 20.0
        def interpolar(i, f, p, t): return i + (f - i) * (p / t)

        # Simulación de CAMBIO: En el ciclo 15, hay un pico repentino de vibración (desbalance)
        if ciclo == 15:
            print("\n[EVENTO] ¡Simulando cambio brusco: Desbalance repentino!")
            self.temp_actual += 5.0
            vib = 25.0 # Salto brusco a peligro
            vel = 1200
        elif ciclo < 15:
            self.temp_actual = 25.0 + random.uniform(0, 2)
            self.temp_amb_actual = 22.0 + random.uniform(0, 1)
            vib = random.uniform(2.0, 4.0)
            vel = 650
        else:
            # Post-cambio: se mantiene alto o empeora
            self.temp_actual += random.uniform(0.5, 1.5)
            vib = 25.0 + random.uniform(0, 5)
            vel = 1200 + random.uniform(-50, 50)
        
        return {
            "temperatura": round(self.temp_actual, 1),
            "temp_ambiente": round(self.temp_amb_actual, 1),
            "vibracion": round(vib, 2),
            "voltaje": volt,
            "velocidad": int(vel),
            "humedad": hum,
        }

    def _actualizar_buffers(self, datos):
        self.buf_temp.append(datos["temperatura"])
        self.buf_vib.append(datos["vibracion"])
        self.buf_volt.append(datos["voltaje"])
        self.buf_vel.append(datos["velocidad"])
        self.buf_hum.append(datos["humedad"])
        self.buf_tamb.append(datos.get("temp_ambiente", self.temp_amb_actual))

    def _features_ventana(self):
        def stats(buf):
            arr = list(buf)
            if len(arr) < 2: return 0.0, 0.0, 0.0
            return float(np.mean(arr)), float(np.std(arr)), float(arr[-1] - arr[0])
        st_t = stats(self.buf_temp)
        st_v = stats(self.buf_vib)
        st_h = stats(self.buf_hum)
        return {
            "temp_media": st_t[0], "temp_std": st_t[1], "temp_delta": st_t[2],
            "vib_media": st_v[0], "vib_std": st_v[1], "vib_delta": st_v[2],
            "hum_media": st_h[0], "hum_std": st_h[1], "hum_delta": st_h[2],
        }

    def _entrenar_isolation_forest(self):
        X = np.array(self.historial_multivar)
        self.modelo_if = IsolationForest(n_estimators=100, contamination=0.1, random_state=42)
        self.modelo_if.fit(X)
        self.if_entrenado = True
        print(f"[Edge] Isolation Forest entrenado.")

    def _es_anomalia_if(self, datos):
        if not self.if_entrenado: return False, 0.0
        vec = np.array([datos["temperatura"], datos.get("temp_ambiente", self.temp_amb_actual),
                        datos["vibracion"], datos["voltaje"], datos["velocidad"], datos["humedad"]]).reshape(1, -1)
        return self.modelo_if.predict(vec)[0] == -1, self.modelo_if.decision_function(vec)[0]

    def _calcular_score_riesgo(self, datos, features, anomalia_if, score_if):
        score = 0.0
        if datos["temperatura"] >= self.temp_peligro: score += 40.0
        elif datos["temperatura"] >= self.temp_alerta: score += 28.0
        if datos["vibracion"] >= self.vib_peligro: score += 30.0
        elif datos["vibracion"] >= self.vib_alerta: score += 20.0
        if features["temp_delta"] > 8.0: score += 10.0
        elif features["temp_delta"] > 4.0: score += 5.0
        if anomalia_if: score += min(10.0, abs(score_if) * 20)
        return min(100.0, score)

    def procesar_localmente(self, datos):
        self._actualizar_buffers(datos)
        features = self._features_ventana()
        self.historial_multivar.append([datos["temperatura"], datos.get("temp_ambiente", self.temp_amb_actual),
                                        datos["vibracion"], datos["voltaje"], datos["velocidad"], datos["humedad"]])
        if len(self.historial_multivar) >= self.ENTRENAMIENTO_MIN and len(self.historial_multivar) % 5 == 0:
            self._entrenar_isolation_forest()
        
        anomalia_if, score_if = self._es_anomalia_if(datos)
        score_riesgo = self._calcular_score_riesgo(datos, features, anomalia_if, score_if)
        ciclos_alerta, metrica = self._proyectar_ciclos_preventivo(datos, features)

        self.sequence += 1
        payload = {
            "sequence": self.sequence, "boot_id": self.boot_id, "firmware_version": "simulator-change-3",
            "maquina_id": self.maquina_id, "voltaje": datos["voltaje"], "temperatura": datos["temperatura"],
            "temp_ambiente": datos.get("temp_ambiente", self.temp_amb_actual), "vibracion": datos["vibracion"],
            "velocidad": datos["velocidad"], "humedad": datos["humedad"], "temp_media": features["temp_media"],
            "temp_std": features["temp_std"], "temp_delta": features["temp_delta"], "vib_media": features["vib_media"],
            "vib_delta": features["vib_delta"], "score_riesgo_edge": score_riesgo,
        }
        try: requests.post(self.url_sensores, headers=self.headers, json=payload, timeout=5).raise_for_status()
        except requests.exceptions.RequestException as exc: print(f"[Edge] Error de comunicación: {exc}")

        if score_riesgo >= 70.0:
            self.generar_alerta_gemini(datos, features, score_riesgo, "critico")
        elif score_riesgo >= 30.0 or ciclos_alerta <= self.CICLOS_ALERTA_PREVENTIVA:
            self.generar_alerta_gemini(datos, features, score_riesgo, "predictivo", ciclos_alerta, metrica)

        print(f"[Ciclo] T={datos['temperatura']}C V={datos['vibracion']} Score={score_riesgo} => {'ANOMALIA' if anomalia_if else 'OK'}")

    def generar_alerta_gemini(self, datos, features, score_riesgo, tipo, ciclos=9999, metrica=""):
        payload = {"maquina_id": self.maquina_id, "riesgo": score_riesgo, "diagnostico": f"Alerta {tipo}: T={datos['temperatura']} V={datos['vibracion']}"}
        try: requests.post(self.url_alertas, headers=self.headers, json=payload, timeout=5).raise_for_status()
        except requests.exceptions.RequestException as exc: print(f"[Edge] Error de comunicación: {exc}")

if __name__ == "__main__":
    nodo = NodoEdge(maquina_id=os.getenv("MACHINE_ID", "M-01"))
    for i in range(1, 30):
        print(f"--- Ciclo {i} ---")
        lectura = nodo.leer_sensores(i)
        nodo.procesar_localmente(lectura)
        time.sleep(1)
