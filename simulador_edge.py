import time
import random
import requests
import os
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
else:
    print("[Edge] GEMINI_API_KEY no configurada: alertas usaran diagnostico local.")


class NodoEdge:
    def __init__(self, maquina_id):
        self.maquina_id = maquina_id
        api_base = os.getenv("API_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
        self.url_sensores = f"{api_base}/api/sensores"
        self.url_alertas = f"{api_base}/api/alertas"

        # Umbrales: alerta (amarillo) y peligro (rojo) — se cargan desde la API
        self.temp_alerta = 50.0
        self.temp_peligro = 60.0
        self.vib_alerta = 4.0
        self.vib_peligro = 7.0
        self.hum_alerta = 60.0
        self.hum_peligro = 80.0
        self.api_base = api_base
        self._cargar_limites_desde_api()

        # ── Ventana deslizante para cada variable (últimas N lecturas) ───
        self.VENTANA = 10
        self.buf_temp = deque(maxlen=self.VENTANA)
        self.buf_vib  = deque(maxlen=self.VENTANA)
        self.buf_volt = deque(maxlen=self.VENTANA)
        self.buf_vel  = deque(maxlen=self.VENTANA)
        self.buf_hum  = deque(maxlen=self.VENTANA)
        self.buf_tamb = deque(maxlen=self.VENTANA)

        # ── Historial multivariado para Isolation Forest ─────────────────
        self.ENTRENAMIENTO_MIN = 15          # muestras mínimas para entrenar
        self.historial_multivar = []         # lista de vectores [5 features]
        self.modelo_if = None                # IsolationForest entrenado
        self.if_entrenado = False

        # ── Control de alertas (evita spam) ──────────────────────────────
        self.nivel_alerta = 0                # 0=ok  1=predictivo  2=crítico
        self.temp_actual  = 42.0
        self.temp_amb_actual = 24.0
        self.CICLOS_ALERTA_PREVENTIVA = 12

    def _cargar_limites_desde_api(self):
        try:
            url = f"{self.api_base}/api/maquinas/{self.maquina_id}/config"
            resp = requests.get(url, timeout=4)
            if resp.status_code == 200:
                cfg = resp.json()
                self.temp_alerta = float(cfg["temp_alerta"])
                self.temp_peligro = float(cfg["temp_peligro"])
                self.vib_alerta = float(cfg["vib_alerta"])
                self.vib_peligro = float(cfg["vib_peligro"])
                self.hum_alerta = float(cfg.get("hum_alerta", 60.0))
                self.hum_peligro = float(cfg.get("hum_peligro", 80.0))
                print(
                    f"[Edge] Limites cargados: temp alerta={self.temp_alerta}C, "
                    f"peligro={self.temp_peligro}C"
                )
        except requests.exceptions.RequestException:
            print("[Edge] API no disponible: usando limites por defecto.")

    def _ciclos_estimados_hasta_umbral(self, actual, pendiente, umbral):
        if actual >= umbral:
            return 0
        if pendiente <= 0.02:
            return 9999
        return max(0, int(np.ceil((umbral - actual) / pendiente)))

    def _proyectar_ciclos_preventivo(self, datos, features):
        """Estima ciclos hasta cruzar umbral de alerta (amarillo)."""
        if len(self.buf_temp) < 3:
            return 9999, "temperatura"

        pend_temp = features["temp_delta"] / max(1, len(self.buf_temp) - 1)
        pend_vib = features["vib_delta"] / max(1, len(self.buf_temp) - 1)

        c_temp = self._ciclos_estimados_hasta_umbral(
            datos["temperatura"], pend_temp, self.temp_alerta
        )
        c_vib = self._ciclos_estimados_hasta_umbral(
            datos["vibracion"], pend_vib, self.vib_alerta
        )

        if c_temp <= c_vib:
            return c_temp, "temperatura"
        return c_vib, "vibracion"

    # ─────────────────────────────────────────────────────────────────────
    # LECTURA DE SENSORES
    # ─────────────────────────────────────────────────────────────────────
    def leer_sensores(self, ciclo):
        vib  = random.uniform(1.0, 3.5)
        volt = random.uniform(85.0, 95.0)
        vel  = int(random.uniform(600, 750))
        hum  = random.uniform(40.0, 50.0)
        self.temp_amb_actual += random.uniform(-0.4, 0.4)
        self.temp_amb_actual = max(20.0, min(32.0, self.temp_amb_actual))

        def interpolar_rango(inicio, fin, progreso):
            """Interpolacion lineal para volver gradualmente a la normalidad."""
            return inicio + (fin - inicio) * progreso

        def valor_en_rango(minimo, maximo):
            bajo = min(minimo, maximo)
            alto = max(minimo, maximo)
            return random.uniform(bajo, alto)

        if ciclo <= 10:
            self.temp_actual = random.uniform(40.0, 48.0)

        elif ciclo <= 18:
            self.temp_actual = random.uniform(52.0, 58.0)
            vib = random.uniform(4.5, 6.5)
            volt = random.uniform(105.0, 125.0)
            vel = int(random.uniform(900, 1400))
            hum = random.uniform(62.0, 75.0)

        elif ciclo <= 28:
            self.temp_actual = random.uniform(62.0, 70.0)
            vib = random.uniform(7.5, 9.0)
            volt = random.uniform(135.0, 150.0)
            vel = int(random.uniform(1600, 1800))
            hum = random.uniform(82.0, 95.0)

        elif ciclo <= 36:
            # Recuperacion progresiva: ciclo 29 -> 0.0, ciclo 36 -> 1.0
            progreso = (ciclo - 29) / 7.0

            self.temp_actual = valor_en_rango(
                interpolar_rango(62.0, 40.0, progreso),
                interpolar_rango(70.0, 48.0, progreso),
            )
            vib = valor_en_rango(
                interpolar_rango(7.5, 1.0, progreso),
                interpolar_rango(9.0, 3.5, progreso),
            )
            volt = valor_en_rango(
                interpolar_rango(135.0, 85.0, progreso),
                interpolar_rango(150.0, 95.0, progreso),
            )
            vel = int(
                valor_en_rango(
                    interpolar_rango(1600.0, 600.0, progreso),
                    interpolar_rango(1800.0, 750.0, progreso),
                )
            )
            hum = valor_en_rango(
                interpolar_rango(82.0, 40.0, progreso),
                interpolar_rango(95.0, 50.0, progreso),
            )

        else:
            self.temp_actual = random.uniform(40.0, 48.0)
            vib = random.uniform(1.0, 3.5)
            volt = random.uniform(85.0, 95.0)
            vel = int(random.uniform(600, 750))
            hum = random.uniform(40.0, 50.0)

        # Ciclos 38-40: simular parada brusca del motor (prueba de frenado/RPM)
        if 38 <= ciclo <= 40:
            vel = int(random.uniform(80, 200))
            vib = random.uniform(0.4, 1.0)
            self.temp_actual = max(35.0, self.temp_actual - random.uniform(6.0, 12.0))
            volt = random.uniform(82.0, 90.0)

        return {
            "temperatura": self.temp_actual,
            "temp_ambiente": round(self.temp_amb_actual, 1),
            "vibracion":   vib,
            "voltaje":     volt,
            "velocidad":   vel,
            "humedad":     hum,
        }

    # ─────────────────────────────────────────────────────────────────────
    # FEATURES DE VENTANA DESLIZANTE
    # ─────────────────────────────────────────────────────────────────────
    def _actualizar_buffers(self, datos):
        self.buf_temp.append(datos["temperatura"])
        self.buf_vib.append(datos["vibracion"])
        self.buf_volt.append(datos["voltaje"])
        self.buf_vel.append(datos["velocidad"])
        self.buf_hum.append(datos["humedad"])
        self.buf_tamb.append(datos.get("temp_ambiente", self.temp_amb_actual))

    def _features_ventana(self):
        """
        Devuelve estadísticas de los últimos N valores para cada sensor.
        Estas features son las que realmente predicen fallas, no el valor puntual.
        """
        def stats(buf):
            arr = list(buf)
            if len(arr) < 2:
                return 0.0, 0.0, 0.0          # media, std, delta
            return float(np.mean(arr)), float(np.std(arr)), float(arr[-1] - arr[0])

        t_mean, t_std, t_delta = stats(self.buf_temp)
        v_mean, v_std, v_delta = stats(self.buf_vib)
        h_mean, h_std, h_delta = stats(self.buf_hum)

        return {
            "temp_media":   t_mean,
            "temp_std":     t_std,
            "temp_delta":   t_delta,   # cuánto subió/bajó en la ventana
            "vib_media":    v_mean,
            "vib_std":      v_std,
            "vib_delta":    v_delta,
            "hum_media":    h_mean,
            "hum_std":      h_std,
            "hum_delta":    h_delta,
        }

    # ─────────────────────────────────────────────────────────────────────
    # ISOLATION FOREST  ─  detección de anomalías multivariadas
    # ─────────────────────────────────────────────────────────────────────
    def _vector_multivar(self, datos):
        """Vector de 5 variables para Isolation Forest."""
        return [
            datos["temperatura"],
            datos.get("temp_ambiente", self.temp_amb_actual),
            datos["vibracion"],
            datos["voltaje"],
            datos["velocidad"],
            datos["humedad"],
        ]

    def _entrenar_isolation_forest(self):
        """
        Entrena con el historial acumulado. contamination=0.1 significa
        que esperamos ~10 % de anomalías en los datos vistos.
        Se re-entrena cada 5 lecturas nuevas para adaptarse.
        """
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
        """Devuelve True si el punto actual es anomalía según IF."""
        if not self.if_entrenado:
            return False
        vec = np.array(self._vector_multivar(datos)).reshape(1, -1)
        prediccion = self.modelo_if.predict(vec)   # -1 = anomalía, 1 = normal
        score = self.modelo_if.decision_function(vec)[0]
        return prediccion[0] == -1, score

    # ─────────────────────────────────────────────────────────────────────
    # SCORE DINÁMICO DE RIESGO
    # ─────────────────────────────────────────────────────────────────────
    def _calcular_score_riesgo(self, datos, features, anomalia_if, score_if):
        """
        Ponderación aprendida empíricamente para industria manufacturera.
        Devuelve un float 0-100.
        """
        score = 0.0

        # Componente 1: umbrales de alerta (amarillo) y peligro (rojo)
        if datos["temperatura"] >= self.temp_peligro:
            score += 40.0
        elif datos["temperatura"] >= self.temp_alerta:
            score += 28.0
        elif datos["temperatura"] >= self.temp_alerta * 0.88:
            score += 14.0

        if datos["vibracion"] >= self.vib_peligro:
            score += 30.0
        elif datos["vibracion"] >= self.vib_alerta:
            score += 20.0
        elif datos["vibracion"] >= self.vib_alerta * 0.88:
            score += 10.0

        if datos["humedad"] >= self.hum_peligro:
            score += 15.0
        elif datos["humedad"] >= self.hum_alerta:
            score += 8.0

        # Componente 2: tendencia (delta de la ventana)
        if features["temp_delta"] > 8.0:
            score += 10.0
        elif features["temp_delta"] > 4.0:
            score += 5.0

        if features["vib_delta"] > 3.0:
            score += 5.0

        # Componente 3: Isolation Forest (penaliza anomalías combinadas)
        if anomalia_if:
            # score_if negativo → más anómalo; escalamos a 0-10
            penalizacion = min(10.0, abs(score_if) * 20)
            score += penalizacion

        return min(score, 100.0)

    # ─────────────────────────────────────────────────────────────────────
    # PROCESAMIENTO PRINCIPAL
    # ─────────────────────────────────────────────────────────────────────
    def procesar_localmente(self, datos):
        # 1. Actualizar buffers y calcular features de ventana
        self._actualizar_buffers(datos)
        features = self._features_ventana()

        # 2. Acumular historial multivariado
        self.historial_multivar.append(self._vector_multivar(datos))

        # 3. Entrenar / re-entrenar Isolation Forest
        n = len(self.historial_multivar)
        if n >= self.ENTRENAMIENTO_MIN and n % 5 == 0:
            self._entrenar_isolation_forest()

        # 4. Detectar anomalía con IF
        anomalia_if = False
        score_if    = 0.0
        if self.if_entrenado:
            anomalia_if, score_if = self._es_anomalia_if(datos)

        # 5. Score dinámico de riesgo
        score_riesgo = self._calcular_score_riesgo(datos, features, anomalia_if, score_if)

        # 6. Clasificar situacion + alerta preventiva antes del amarillo
        ciclos_alerta, metrica_critica = self._proyectar_ciclos_preventivo(datos, features)

        es_peligro = score_riesgo >= 70.0
        es_preventivo_temprano = (
            not es_peligro
            and ciclos_alerta <= self.CICLOS_ALERTA_PREVENTIVA
            and ciclos_alerta < 9999
        )
        es_prediccion = (not es_peligro) and (
            es_preventivo_temprano
            or score_riesgo >= 30.0
            or features["temp_delta"] > 3.0
            or anomalia_if
        )

        # 7. Enviar telemetría al servidor (con features extras)
        payload_telemetria = {
            "maquina_id": self.maquina_id,
            "voltaje":     datos["voltaje"],
            "temperatura": datos["temperatura"],
            "temp_ambiente": datos.get("temp_ambiente", self.temp_amb_actual),
            "vibracion":   datos["vibracion"],
            "velocidad":   datos["velocidad"],
            "humedad":     datos["humedad"],
            # Features de ventana (el servidor las usará en el RUL mejorado)
            "temp_media":  features["temp_media"],
            "temp_std":    features["temp_std"],
            "temp_delta":  features["temp_delta"],
            "vib_media":   features["vib_media"],
            "vib_delta":   features["vib_delta"],
            "score_riesgo_edge": score_riesgo,
        }

        try:
            requests.post(self.url_sensores, json=payload_telemetria, timeout=5)
        except requests.exceptions.RequestException as e:
            print(f"[Edge] Error enviando telemetría: {e}")

        # 8. Resetear nivel si todo está bien
        if not es_peligro and not es_prediccion:
            self.nivel_alerta = 0

        # 9. Disparar alerta (con anti-spam por nivel)
        if es_peligro and self.nivel_alerta < 2:
            self.generar_alerta_gemini(datos, features, score_riesgo, "critico")
            self.nivel_alerta = 2
        elif es_prediccion and self.nivel_alerta < 1:
            if es_preventivo_temprano:
                score_riesgo = max(score_riesgo, 55.0)
            self.generar_alerta_gemini(
                datos, features, score_riesgo, "predictivo", ciclos_alerta, metrica_critica
            )
            self.nivel_alerta = 1

        # Log local
        estado = "PELIGRO" if es_peligro else ("ALERTA" if es_prediccion else "OK")
        if_tag = " [IF-ANOMALIA]" if anomalia_if else ""
        prev_tag = ""
        if ciclos_alerta < 9999:
            prev_tag = f"  RUL-alerta~{ciclos_alerta}c({metrica_critica})"
        print(
            f"[Ciclo] T_motor={datos['temperatura']:.1f}C  "
            f"T_amb={datos.get('temp_ambiente', self.temp_amb_actual):.1f}C  "
            f"V={datos['vibracion']:.1f}mm/s  "
            f"dT={features['temp_delta']:+.1f}  "
            f"Score={score_riesgo:.0f}  "
            f"=> {estado}{if_tag}{prev_tag}"
        )

    # ─────────────────────────────────────────────────────────────────────
    # GENERACIÓN DE ALERTA CON GEMINI  ─  prompt enriquecido
    # ─────────────────────────────────────────────────────────────────────
    def generar_alerta_gemini(
        self, datos, features, score_riesgo, tipo, ciclos_alerta=9999, metrica="sensores"
    ):
        # Contexto histórico para que Gemini genere un diagnóstico útil
        contexto_historial = (
            f"Tendencia temperatura últimas {len(self.buf_temp)} lecturas: "
            f"media={features['temp_media']:.1f}°C, "
            f"std={features['temp_std']:.2f}, "
            f"delta={features['temp_delta']:+.1f}°C. "
            f"Tendencia vibración: media={features['vib_media']:.2f}mm/s, "
            f"delta={features['vib_delta']:+.2f}mm/s. "
            f"Humedad media={features['hum_media']:.1f}%."
        )

        if tipo == "critico":
            prompt = (
                f"Eres un sistema de diagnóstico industrial. "
                f"Valores actuales: Temperatura {datos['temperatura']:.1f}°C, "
                f"Vibración {datos['vibracion']:.1f}mm/s, "
                f"Voltaje {datos['voltaje']:.1f}V, "
                f"Velocidad {datos['velocidad']}RPM, "
                f"Humedad {datos['humedad']:.1f}%. "
                f"Score de riesgo: {score_riesgo:.0f}/100. "
                f"{contexto_historial} "
                f"Da un diagnóstico técnico conciso (máx 2 oraciones) "
                f"indicando la causa probable y la acción inmediata recomendada."
            )
            riesgo = min(95.0, score_riesgo)

        else:  # predictivo
            prompt = (
                f"Eres un sistema de mantenimiento predictivo industrial. "
                f"Los sensores muestran tendencia preocupante hacia zona AMARILLA (alerta). "
                f"Temperatura actual {datos['temperatura']:.1f}C (alerta en {self.temp_alerta}C), "
                f"delta {features['temp_delta']:+.1f}C en {len(self.buf_temp)} lecturas. "
                f"Proyeccion ML: umbral de alerta en ~{ciclos_alerta} ciclos ({metrica}). "
                f"Score: {score_riesgo:.0f}/100. "
                f"En max 2 oraciones indica accion preventiva antes de llegar a peligro."
            )
            riesgo = min(72.0, max(50.0, score_riesgo))

        try:
            if modelo is None:
                raise RuntimeError("Gemini no configurado")
            respuesta = modelo.generate_content(prompt)
            diagnostico = respuesta.text.strip()
        except Exception as e:
            print(f"[Edge] Gemini no disponible: {e}")
            if tipo == "critico":
                diagnostico = (
                    f"Fallo crítico detectado: T={datos['temperatura']:.1f}°C, "
                    f"Vib={datos['vibracion']:.1f}mm/s. Score={score_riesgo:.0f}. "
                    "Detener máquina y revisar sistema de enfriamiento."
                )
            else:
                diagnostico = (
                    f"[Preventivo] Zona amarilla proyectada en ~{ciclos_alerta} ciclos "
                    f"({metrica}). T={datos['temperatura']:.1f}C, "
                    f"dT={features['temp_delta']:+.1f}C. "
                    "Programar mantenimiento antes del umbral de alerta."
                )

        payload_alerta = {
            "maquina_id": self.maquina_id,
            "riesgo":      riesgo,
            "diagnostico": diagnostico,
        }

        try:
            requests.post(self.url_alertas, json=payload_alerta, timeout=5)
        except requests.exceptions.RequestException as e:
            print(f"[Edge] Error enviando alerta: {e}")


# ─────────────────────────────────────────────────────────────────────────
# EJECUCIÓN
# ─────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    nodo = NodoEdge(maquina_id="M-01")
    print("=== Simulador Edge Predicta ===")
    print(f"Isolation Forest se activará a partir de {nodo.ENTRENAMIENTO_MIN} muestras.\n")

    for i in range(1, 41):
        print(f"\n--- Ciclo {i}/40 ---")
        lectura = nodo.leer_sensores(i)
        nodo.procesar_localmente(lectura)
        time.sleep(2)