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

if not api_key:
    print("[Edge] GEMINI_API_KEY no configurada")

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
        except requests.exceptions.RequestException:
            print("[Edge] API no disponible")

    def _ciclos_estimados_hasta_umbral(self, actual, pendiente, umbral):
        if actual >= umbral:
            return 0
        if pendiente <= 0.02:
            return 9999
        calculo = (umbral - actual) / pendiente
        return max(0, int(np.ceil(calculo)))

    def _proyectar_ciclos_preventivo(self, datos, features):
        if len(self.buf_temp) < 3:
            return 9999, "temperatura"

        denominador = len(self.buf_temp) - 1
        if denominador < 1:
            denominador = 1

        pend_temp = features["temp_delta"] / denominador
        pend_vib = features["vib_delta"] / denominador

        c_temp = self._ciclos_estimados_hasta_umbral(datos["temperatura"], pend_temp, self.temp_alerta)
        c_vib = self._ciclos_estimados_hasta_umbral(datos["vibracion"], pend_vib, self.vib_alerta)

        if c_temp <= c_vib:
            return c_temp, "temperatura"
        return c_vib, "vibracion"

    def leer_sensores(self, ciclo):
        volt = 12.0
        hum = 20.0

        def interpolar(inicio, fin, paso, total_pasos):
            progreso = paso / total_pasos
            return inicio + (fin - inicio) * progreso

        if ciclo <= 10:
            self.temp_actual = random.uniform(25.0, 28.0)
            self.temp_amb_actual = random.uniform(22.0, 24.0)
            vib = random.uniform(2.0, 5.0)
            vel = int(random.uniform(600, 700))

        elif ciclo <= 20:
            paso = ciclo - 10
            self.temp_actual = interpolar(28.0, 38.0, paso, 10) + random.uniform(-0.5, 0.5)
            self.temp_amb_actual = interpolar(24.0, 30.0, paso, 10) + random.uniform(-0.5, 0.5)
            vib = interpolar(5.0, 13.0, paso, 10) + random.uniform(-0.5, 0.5)
            vel = int(interpolar(700, 1000, paso, 10))

        elif ciclo <= 28:
            paso = ciclo - 20
            self.temp_actual = interpolar(38.0, 48.0, paso, 8) + random.uniform(-0.5, 0.5)
            self.temp_amb_actual = interpolar(30.0, 40.0, paso, 8) + random.uniform(-0.5, 0.5)
            vib = interpolar(13.0, 19.0, paso, 8) + random.uniform(-0.5, 0.5)
            vel = int(interpolar(1000, 1600, paso, 8))

        else:
            paso = ciclo - 28
            self.temp_actual = interpolar(48.0, 26.0, paso, 12) + random.uniform(-0.5, 0.5)
            self.temp_amb_actual = interpolar(40.0, 23.0, paso, 12) + random.uniform(-0.5, 0.5)
            vib = interpolar(19.0, 3.0, paso, 12) + random.uniform(-0.5, 0.5)
            vel = int(interpolar(1600, 650, paso, 12))

        return {
            "temperatura": round(self.temp_actual, 1),
            "temp_ambiente": round(self.temp_amb_actual, 1),
            "vibracion": round(vib, 2),
            "voltaje": volt,
            "velocidad": vel,
            "humedad": hum,
        }

    def _actualizar_buffers(self, datos):
        self.buf_temp.append(datos["temperatura"])
        self.buf_vib.append(datos["vibracion"])
        self.buf_volt.append(datos["voltaje"])
        self.buf_vel.append(datos["velocidad"])
        self.buf_hum.append(datos["humedad"])

        if "temp_ambiente" in datos:
            self.buf_tamb.append(datos["temp_ambiente"])
        if "temp_ambiente" not in datos:
            self.buf_tamb.append(self.temp_amb_actual)

    def _features_ventana(self):
        def stats(buf):
            arr = list(buf)
            if len(arr) < 2:
                return 0.0, 0.0, 0.0
            return float(np.mean(arr)), float(np.std(arr)), float(arr[-1] - arr[0])

        t_mean, t_std, t_delta = stats(self.buf_temp)
        v_mean, v_std, v_delta = stats(self.buf_vib)
        h_mean, h_std, h_delta = stats(self.buf_hum)

        return {
            "temp_media":   t_mean,
            "temp_std":     t_std,
            "temp_delta":   t_delta,
            "vib_media":    v_mean,
            "vib_std":      v_std,
            "vib_delta":    v_delta,
            "hum_media":    h_mean,
            "hum_std":      h_std,
            "hum_delta":    h_delta,
        }

    def _vector_multivar(self, datos):
        t_amb = self.temp_amb_actual
        if "temp_ambiente" in datos:
            t_amb = datos["temp_ambiente"]

        return [
            datos["temperatura"],
            t_amb,
            datos["vibracion"],
            datos["voltaje"],
            datos["velocidad"],
            datos["humedad"],
        ]

    def _entrenar_isolation_forest(self):
        X = np.array(self.historial_multivar)
        self.modelo_if = IsolationForest(
            n_estimators=100,
            contamination=0.1,
            random_state=42,
        )
        self.modelo_if.fit(X)
        self.if_entrenado = True
        print(f"[Edge] Isolation Forest re-entrenado con {len(X)} muestras.")

    def _es_anomalia_if(self, datos):
        if not self.if_entrenado:
            return False, 0.0
        vec = np.array(self._vector_multivar(datos)).reshape(1, -1)
        prediccion = self.modelo_if.predict(vec)
        score = self.modelo_if.decision_function(vec)[0]
        if prediccion[0] == -1:
            return True, score
        return False, score

    def _calcular_score_riesgo(self, datos, features, anomalia_if, score_if):
        score = 0.0

        if datos["temperatura"] >= self.temp_peligro:
            score += 40.0
        if datos["temperatura"] < self.temp_peligro:
            if datos["temperatura"] >= self.temp_alerta:
                score += 28.0

        if datos["vibracion"] >= self.vib_peligro:
            score += 30.0
        if datos["vibracion"] < self.vib_peligro:
            if datos["vibracion"] >= self.vib_alerta:
                score += 20.0

        if datos["humedad"] >= self.hum_peligro:
            score += 15.0
        if datos["humedad"] < self.hum_peligro:
            if datos["humedad"] >= self.hum_alerta:
                score += 8.0

        if features["temp_delta"] > 8.0:
            score += 10.0
        if features["temp_delta"] <= 8.0:
            if features["temp_delta"] > 4.0:
                score += 5.0

        if features["vib_delta"] > 3.0:
            score += 5.0

        if anomalia_if:
            penalizacion = abs(score_if) * 20
            if penalizacion > 10.0:
                penalizacion = 10.0
            score += penalizacion

        if score > 100.0:
            return 100.0
        return score

    def procesar_localmente(self, datos):
        self._actualizar_buffers(datos)
        features = self._features_ventana()

        self.historial_multivar.append(self._vector_multivar(datos))

        n = len(self.historial_multivar)
        modulo = n % 5
        if n >= self.ENTRENAMIENTO_MIN:
            if modulo == 0:
                self._entrenar_isolation_forest()

        anomalia_if = False
        score_if    = 0.0
        if self.if_entrenado:
            resultado_if = self._es_anomalia_if(datos)
            anomalia_if = resultado_if[0]
            score_if = resultado_if[1]

        score_riesgo = self._calcular_score_riesgo(datos, features, anomalia_if, score_if)

        resultado_preventivo = self._proyectar_ciclos_preventivo(datos, features)
        ciclos_alerta = resultado_preventivo[0]
        metrica_critica = resultado_preventivo[1]

        es_peligro = False
        if score_riesgo >= 70.0:
            es_peligro = True

        es_preventivo_temprano = False
        if not es_peligro:
            if ciclos_alerta <= self.CICLOS_ALERTA_PREVENTIVA:
                if ciclos_alerta < 9999:
                    es_preventivo_temprano = True

        es_prediccion = False
        if not es_peligro:
            if es_preventivo_temprano:
                es_prediccion = True
            if score_riesgo >= 30.0:
                es_prediccion = True
            if features["temp_delta"] > 3.0:
                es_prediccion = True
            if anomalia_if:
                es_prediccion = True

        t_amb = self.temp_amb_actual
        if "temp_ambiente" in datos:
            t_amb = datos["temp_ambiente"]

        self.sequence += 1
        payload_telemetria = {
            "sequence": self.sequence, "boot_id": self.boot_id, "firmware_version": "simulator-3",
            "maquina_id": self.maquina_id,
            "voltaje":     datos["voltaje"],
            "temperatura": datos["temperatura"],
            "temp_ambiente": t_amb,
            "vibracion":   datos["vibracion"],
            "velocidad":   datos["velocidad"],
            "humedad":     datos["humedad"],
            "temp_media":  features["temp_media"],
            "temp_std":    features["temp_std"],
            "temp_delta":  features["temp_delta"],
            "vib_media":   features["vib_media"],
            "vib_delta":   features["vib_delta"],
            "score_riesgo_edge": score_riesgo,
        }

        try:
            requests.post(self.url_sensores, headers=self.headers, json=payload_telemetria, timeout=10).raise_for_status()
        except requests.exceptions.RequestException as e:
            print(f"[Edge] Error enviando telemetría: {e}")

        if not es_peligro:
            if not es_prediccion:
                self.nivel_alerta = 0

        if es_peligro:
            if self.nivel_alerta < 2:
                self.generar_alerta_gemini(datos, features, score_riesgo, "critico")
                self.nivel_alerta = 2

        if es_prediccion:
            if self.nivel_alerta < 1:
                if es_preventivo_temprano:
                    if score_riesgo < 55.0:
                        score_riesgo = 55.0
                self.generar_alerta_gemini(
                    datos, features, score_riesgo, "predictivo", ciclos_alerta, metrica_critica
                )
                self.nivel_alerta = 1

        estado_str = "OK"
        if es_prediccion:
            estado_str = "ALERTA"
        if es_peligro:
            estado_str = "PELIGRO"

        if_tag = ""
        if anomalia_if:
            if_tag = " [IF-ANOMALIA]"

        prev_tag = ""
        if ciclos_alerta < 9999:
            prev_tag = f"  RUL-alerta~{ciclos_alerta}c({metrica_critica})"

        print(
            f"[Ciclo] T_motor={datos['temperatura']:.1f}C  "
            f"V={datos['vibracion']:.1f}mm/s  "
            f"dT={features['temp_delta']:+.1f}  "
            f"Score={score_riesgo:.0f}  "
            f"=> {estado_str}{if_tag}{prev_tag}"
        )

    def generar_alerta_gemini(
        self, datos, features, score_riesgo, tipo, ciclos_alerta=9999, metrica="sensores"
    ):
        contexto_historial = (
            f"Tendencia temperatura: media={features['temp_media']:.1f}C, "
            f"std={features['temp_std']:.2f}, delta={features['temp_delta']:+.1f}C. "
            f"Tendencia vibracion: media={features['vib_media']:.2f}mm/s, "
            f"delta={features['vib_delta']:+.2f}mm/s. "
            f"Humedad media={features['hum_media']:.1f}%."
        )

        prompt = ""
        riesgo = 0.0

        if tipo == "critico":
            prompt = (
                f"Valores actuales: Temperatura {datos['temperatura']:.1f}C, "
                f"Vibracion {datos['vibracion']:.1f}mm/s, "
                f"Voltaje {datos['voltaje']:.1f}V, "
                f"Velocidad {datos['velocidad']}RPM, "
                f"Humedad {datos['humedad']:.1f}%. "
                f"Score de riesgo: {score_riesgo:.0f}/100. "
                f"{contexto_historial} "
                f"Da un diagnostico tecnico conciso indicando la causa."
            )
            riesgo = score_riesgo
            if riesgo > 95.0:
                riesgo = 95.0

        if tipo != "critico":
            prompt = (
                f"Tendencia preocupante hacia zona AMARILLA. "
                f"Temperatura actual {datos['temperatura']:.1f}C (alerta en {self.temp_alerta}C), "
                f"delta {features['temp_delta']:+.1f}C. "
                f"Proyeccion ML: umbral de alerta en ~{ciclos_alerta} ciclos ({metrica}). "
                f"Score: {score_riesgo:.0f}/100. "
                f"Indica accion preventiva."
            )
            riesgo = score_riesgo
            if riesgo < 50.0:
                riesgo = 50.0
            if riesgo > 72.0:
                riesgo = 72.0

        diagnostico = ""
        try:
            if modelo is None:
                raise RuntimeError("Gemini no configurado")
            respuesta = modelo.generate_content(prompt)
            diagnostico = respuesta.text.strip()
        except Exception as e:
            print(f"[Edge] Gemini no disponible: {e}")
            if tipo == "critico":
                diagnostico = (
                    f"Fallo critico detectado: T={datos['temperatura']:.1f}C, "
                    f"Vib={datos['vibracion']:.1f}mm/s. Score={score_riesgo:.0f}. "
                    "Detener maquina."
                )
            if tipo != "critico":
                diagnostico = (
                    f"[Preventivo] Zona amarilla en ~{ciclos_alerta} ciclos "
                    f"({metrica}). T={datos['temperatura']:.1f}C, "
                    f"dT={features['temp_delta']:+.1f}C. "
                    "Programar mantenimiento."
                )

        payload_alerta = {
            "maquina_id": self.maquina_id,
            "riesgo":      riesgo,
            "diagnostico": diagnostico,
            "tipo": tipo,
        }

        try:
            requests.post(self.url_alertas, headers=self.headers, json=payload_alerta, timeout=5).raise_for_status()
        except requests.exceptions.RequestException as e:
            print(f"[Edge] Error enviando alerta: {e}")

if __name__ == "__main__":
    nodo = NodoEdge(maquina_id=os.getenv("MACHINE_ID", "M-01"))
    print("=== Simulador Edge Predicta ===")

    for i in range(1, 41):
        print(f"\n--- Ciclo {i}/40 ---")
        lectura = nodo.leer_sensores(i)
        nodo.procesar_localmente(lectura)
        time.sleep(2)