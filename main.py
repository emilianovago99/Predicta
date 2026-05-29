from contextlib import asynccontextmanager
from typing import Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import AliasChoices, BaseModel, ConfigDict, Field
import mysql.connector
import requests
import os
import joblib
import numpy as np
from io import BytesIO
from dotenv import load_dotenv
import google.generativeai as genai
from sklearn.linear_model import LinearRegression, LogisticRegression
from sklearn.ensemble import GradientBoostingRegressor, IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
import time
import hashlib

load_dotenv()
TELEGRAM_TOKEN   = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")
GEMINI_API_KEY   = os.getenv("GEMINI_API_KEY")

modelo_gemini = None
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)
    modelo_gemini = genai.GenerativeModel("gemini-2.5-flash")

# Ventana de proyeccion y alerta preventiva (antes de llegar al amarillo)
CICLOS_HORIZONTE_ML = 60
CICLOS_ALERTA_PREVENTIVA = 12   # alertar si faltan <= N ciclos para umbral alerta
MIN_MUESTRAS_RUL = 10
MIN_MUESTRAS_ENTRENAR = 15
RETRAIN_INTERVAL = 8

# Detección de cambios bruscos (parada de motor, frenado, apagado térmico)
UMBRAL_CAIDA_VEL_RPM = 350
UMBRAL_CAIDA_TEMP_MOTOR = 7.0
UMBRAL_CAIDA_TEMP_AMB = 5.0
UMBRAL_CAIDA_VIBRACION = 1.2
UMBRAL_CAIDA_VOLTAGE = 12.0
UMBRAL_CAIDA_PCT = 0.35
MIN_VEL_OPERATIVA = 400

# ─────────────────────────────────────────────────────────────────────────
# ESTADO GLOBAL DE MODELOS ML  (persistidos en memoria, actualizados cada N lecturas)
# ─────────────────────────────────────────────────────────────────────────
class ModelStore:
    """
    Almacena modelos ML en memoria para no re-entrenarlos en cada request.
    Clave: id_maquina  →  dict con modelo RUL y clasificador.
    """
    def __init__(self):
        self.rul_models: dict[str, dict] = {}        # {id_maquina: {modelo, scaler, ultima_actualizacion}}
        self.clf_models: dict[str, Pipeline] = {}    # {id_maquina: Pipeline(scaler + LogReg)}
        self.if_models:  dict[str, IsolationForest] = {}
        self.RETRAIN_INTERVAL = RETRAIN_INTERVAL
        self.ultima_alerta_preventiva: dict[str, int] = {}
        self.chat_cache: dict[str, tuple[str, float]] = {}  # {pregunta: (respuesta, timestamp)}
        self.CACHE_DURATION = 300  # 5 minutos

    def necesita_reentrenar(self, id_maquina: str, n_muestras: int) -> bool:
        if id_maquina not in self.rul_models:
            return True
        return n_muestras % self.RETRAIN_INTERVAL == 0

model_store = ModelStore()


# ─────────────────────────────────────────────────────────────────────────
# LIFESPAN (reemplaza on_event deprecated)
# ─────────────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    print("=== Predicta API iniciada ===")
    yield
    print("=== Predicta API detenida ===")

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─────────────────────────────────────────────────────────────────────────
# BASE DE DATOS
# ─────────────────────────────────────────────────────────────────────────
def conectar_db():
    return mysql.connector.connect(
        host="127.0.0.1",
        port=3307,
        user="api_user",
        password="api_password_seguro",
        database="mecanimales_db",
        autocommit=False,
    )


# ─────────────────────────────────────────────────────────────────────────
# TELEGRAM
# ─────────────────────────────────────────────────────────────────────────
def notificar_telegram(maquina_id: str, riesgo: float, diagnostico: str):
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT_ID:
        return
    icono = "🔴" if riesgo > 90.0 else "🟠"
    texto = (
        f"{icono} *PREDICTA ALERTA*\n\n"
        f"*Máquina:* {maquina_id}\n"
        f"*Riesgo:* {riesgo:.0f}/100\n"
        f"*Diagnóstico:* {diagnostico}"
    )
    try:
        requests.post(
            f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage",
            json={"chat_id": TELEGRAM_CHAT_ID, "text": texto, "parse_mode": "Markdown"},
            timeout=5,
        )
    except Exception:
        pass


# ─────────────────────────────────────────────────────────────────────────
# MODELOS PYDANTIC
# ─────────────────────────────────────────────────────────────────────────
class LoginRequest(BaseModel):
    email: str
    password: str

class Telemetria(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    maquina_id: str = Field(
        ...,
        validation_alias=AliasChoices("maquina_id", "id_maquina"),
    )
    voltaje:    float
    temperatura: float  # temperatura del motor
    temp_ambiente: float = 25.0
    vibracion:  float
    velocidad:  int
    humedad:    float
    # Features de ventana opcionales (las envía el nodo edge mejorado)
    temp_media:  float = 0.0
    temp_std:    float = 0.0
    temp_delta:  float = 0.0
    vib_media:   float = 0.0
    vib_delta:   float = 0.0
    score_riesgo_edge: float = 0.0

class Alerta(BaseModel):
    maquina_id: str
    riesgo:     float
    diagnostico: str
    tipo:       str = "critico"  # por defecto crítico si viene del edge

class MaquinaRegistro(BaseModel):
    id_area:    int
    nombre:     str
    id_maquina: str
    medir_temp: bool
    medir_temp_amb: bool = True
    medir_vib:  bool
    medir_volt: bool
    medir_vel:  bool
    medir_hum:  bool

class AreaRegistro(BaseModel):
    id_empresa: int
    nombre:     str

class ConfiguracionMaquina(BaseModel):
    nombre:      str
    id_area:     int
    temp_alerta: float
    temp_peligro: float
    vib_alerta:  float
    vib_peligro: float
    volt_alerta: float
    volt_peligro: float
    vel_alerta:  int
    vel_peligro: int
    hum_alerta:  float
    hum_peligro: float
    temp_amb_alerta: float = 30.0
    temp_amb_peligro: float = 38.0
    medir_temp:  bool
    medir_temp_amb: bool = True
    medir_vib:   bool
    medir_volt:  bool
    medir_vel:   bool
    medir_hum:   bool

class ChatRequest(BaseModel):
    mensaje:    str
    id_maquina: str

class UsuarioRegistro(BaseModel):
    id_empresa: int
    nombre:     str
    email:      str
    password:   str
    rol:        str


# ─────────────────────────────────────────────────────────────────────────
# HELPERS ML
# ─────────────────────────────────────────────────────────────────────────

def _etiqueta_estado(row: dict, limites: dict) -> str:
    """Genera etiqueta de estado para un registro histórico dado sus límites."""
    temp_amb = float(row.get("temp_ambiente", 25.0))
    if (row["temperatura"] >= limites["temp_peligro"]
            or row["vibracion"] >= limites["vib_peligro"]
            or row["voltaje"] >= limites.get("volt_peligro", 130.0)
            or row["velocidad"] >= limites.get("vel_peligro", 1500)
            or row["humedad"] >= limites.get("hum_peligro", 80.0)
            or temp_amb >= limites.get("temp_amb_peligro", 38.0)):
        return "peligro"
    if (row["temperatura"] >= limites["temp_alerta"]
            or row["vibracion"] >= limites["vib_alerta"]
            or row["voltaje"] >= limites.get("volt_alerta", 100.0)
            or row["velocidad"] >= limites.get("vel_alerta", 800)
            or row["humedad"] >= limites.get("hum_alerta", 60.0)
            or temp_amb >= limites.get("temp_amb_alerta", 30.0)):
        return "alerta"
    return "optimo"


def _caida_relativa(prev_val: float, curr_val: float) -> bool:
    if prev_val <= 0:
        return False
    return (prev_val - curr_val) / prev_val >= UMBRAL_CAIDA_PCT


def _detectar_cambio_brusco(prev: dict, curr: dict) -> Optional[dict]:
    """
    Detecta paradas o frenados abruptos comparando la lectura anterior con la actual.
    Pensado para pruebas de RPM y apagado súbito del motor.
    """
    eventos: list[tuple[str, str, float]] = []

    vel_prev = float(prev["velocidad"])
    vel_curr = float(curr["velocidad"])
    if vel_prev >= MIN_VEL_OPERATIVA and (vel_prev - vel_curr) >= UMBRAL_CAIDA_VEL_RPM:
        eventos.append((
            "velocidad",
            f"Caída brusca de RPM: {vel_prev:.0f} → {vel_curr:.0f} "
            f"(≥{UMBRAL_CAIDA_VEL_RPM} RPM en un ciclo; posible parada o frenado).",
            92.0,
        ))

    temp_prev = float(prev["temperatura"])
    temp_curr = float(curr["temperatura"])
    if (temp_prev - temp_curr) >= UMBRAL_CAIDA_TEMP_MOTOR:
        eventos.append((
            "temperatura_motor",
            f"Caída brusca de temperatura del motor: {temp_prev:.1f}°C → {temp_curr:.1f}°C.",
            85.0,
        ))

    t_amb_prev = float(prev.get("temp_ambiente", 25.0))
    t_amb_curr = float(curr.get("temp_ambiente", 25.0))
    if (t_amb_prev - t_amb_curr) >= UMBRAL_CAIDA_TEMP_AMB:
        eventos.append((
            "temperatura_ambiente",
            f"Caída brusca de temperatura ambiente: {t_amb_prev:.1f}°C → {t_amb_curr:.1f}°C.",
            75.0,
        ))

    vib_prev = float(prev["vibracion"])
    vib_curr = float(curr["vibracion"])
    if (vib_prev - vib_curr) >= UMBRAL_CAIDA_VIBRACION and vib_prev >= 1.5:
        eventos.append((
            "vibracion",
            f"Caída brusca de vibración: {vib_prev:.2f} → {vib_curr:.2f} mm/s "
            f"(motor posiblemente detenido).",
            88.0,
        ))

    volt_prev = float(prev["voltaje"])
    volt_curr = float(curr["voltaje"])
    if (volt_prev - volt_curr) >= UMBRAL_CAIDA_VOLTAGE:
        eventos.append((
            "voltaje",
            f"Caída brusca de voltaje: {volt_prev:.1f}V → {volt_curr:.1f}V.",
            80.0,
        ))

    if vel_prev >= MIN_VEL_OPERATIVA and _caida_relativa(vel_prev, vel_curr):
        if not any(e[0] == "velocidad" for e in eventos):
            eventos.append((
                "velocidad",
                f"Caída relativa de RPM ≥{int(UMBRAL_CAIDA_PCT * 100)}% "
                f"({vel_prev:.0f} → {vel_curr:.0f}).",
                90.0,
            ))

    diff_prev = temp_prev - t_amb_prev
    diff_curr = temp_curr - t_amb_curr
    if diff_prev >= 8.0 and diff_curr <= 3.0 and (temp_prev - temp_curr) >= 5.0:
        eventos.append((
            "termica",
            "El motor se enfrió de forma abrupta respecto al ambiente "
            "(posible apagado con ambiente estable).",
            86.0,
        ))

    if not eventos:
        return None

    metricas = ", ".join(e[0] for e in eventos)
    detalle = " ".join(e[1] for e in eventos)
    riesgo = max(e[2] for e in eventos)
    diagnostico = (
        f"[EVENTO] Cambio abrupto no habitual en: {metricas}. {detalle} "
        "Revise parada de emergencia, frenado o fallo de alimentación."
    )
    return {"metricas": metricas, "diagnostico": diagnostico, "riesgo": riesgo}


def _crear_alerta_evento(cursor, id_maquina: str, evento: dict) -> None:
    cursor.execute(
        """INSERT INTO Alertas (id_maquina, riesgo, diagnostico, tipo)
           VALUES (%s, %s, %s, 'evento')""",
        (id_maquina, evento["riesgo"], evento["diagnostico"]),
    )
    cursor.execute(
        "UPDATE Maquina SET estado = 'alerta' WHERE id_maquina = %s AND estado = 'optimo'",
        (id_maquina,),
    )
    notificar_telegram(id_maquina, evento["riesgo"], evento["diagnostico"])


def _features_desde_row(row: dict, prev: Optional[dict] = None) -> list:
    """Vector enriquecido: valores actuales + variacion respecto a lectura anterior."""
    d_temp = 0.0
    d_vib = 0.0
    d_vel = 0.0
    d_temp_amb = 0.0
    if prev is not None:
        d_temp = row["temperatura"] - prev["temperatura"]
        d_vib = row["vibracion"] - prev["vibracion"]
        d_vel = float(row["velocidad"]) - float(prev["velocidad"])
        d_temp_amb = float(row.get("temp_ambiente", 25.0)) - float(
            prev.get("temp_ambiente", 25.0)
        )
    return [
        row["temperatura"],
        float(row.get("temp_ambiente", 25.0)),
        row["vibracion"],
        row["voltaje"],
        row["velocidad"],
        row["humedad"],
        d_temp,
        d_vib,
        d_vel,
        d_temp_amb,
    ]


def _matriz_features(historial: list) -> np.ndarray:
    filas = []
    for i, row in enumerate(historial):
        prev = historial[i - 1] if i > 0 else None
        filas.append(_features_desde_row(row, prev))
    return np.array(filas)


def _pendiente_y_actual(valores: list, ventana: int = 25) -> tuple[float, float]:
    muestras = valores[-ventana:] if len(valores) > ventana else valores
    if len(muestras) < 3:
        ultimo = float(muestras[-1]) if muestras else 0.0
        return 0.0, ultimo
    x = np.arange(len(muestras)).reshape(-1, 1)
    y = np.array(muestras, dtype=float)
    modelo = LinearRegression().fit(x, y)
    return float(modelo.coef_[0]), float(y[-1])


def _ciclos_hasta_umbral(actual: float, pendiente: float, umbral: float) -> int:
    if actual >= umbral:
        return 0
    if pendiente <= 0.02:
        return 9999
    return max(0, int(np.ceil((umbral - actual) / pendiente)))


def _ciclos_gbr_hasta_umbral(store: dict, clave_gbr: str, umbral: float) -> int:
    gbr = store.get(clave_gbr)
    if gbr is None:
        return 9999
    n = store["n_muestras"]
    futuro = np.arange(n, n + CICLOS_HORIZONTE_ML).reshape(-1, 1)
    pred = gbr.predict(futuro)
    cruces = np.where(pred >= umbral)[0]
    return int(cruces[0]) if len(cruces) else 9999


def _texto_prediccion(rul_alerta: int, rul_peligro: int, metrica: str) -> str:
    if rul_alerta == 0:
        return "Zona preventiva (amarillo) alcanzada o superada"
    if rul_alerta <= 5:
        return f"Mantenimiento preventivo urgente (~{rul_alerta} ciclos a amarillo)"
    if rul_alerta <= CICLOS_ALERTA_PREVENTIVA:
        return f"Alerta temprana: amarillo proyectado en ~{rul_alerta} ciclos ({metrica})"
    if rul_peligro <= CICLOS_ALERTA_PREVENTIVA:
        return f"Tendencia a peligro en ~{rul_peligro} ciclos; revisar {metrica}"
    if rul_alerta < 9999:
        return f"Degradacion controlada: preventivo en ~{rul_alerta} ciclos"
    return "Comportamiento estable en horizonte proyectado"


def calcular_prediccion_mantenimiento(
    id_maquina: str,
    historial: list,
    limites: dict,
) -> dict:
    """
    Calcula ciclos hasta umbral de alerta (amarillo) y de peligro (rojo)
    usando tendencia lineal + proyeccion GBR cuando existe modelo entrenado.
    """
    if len(historial) < MIN_MUESTRAS_RUL:
        return {
            "status": "Insuficientes datos",
            "rul_alerta_ciclos": -1,
            "rul_peligro_ciclos": -1,
            "rul_ciclos": -1,
            "rul_min": -1,
            "rul_max": -1,
            "prediccion": "Recolectando volumen de datos...",
            "modelo": "pendiente",
            "metrica_critica": None,
            "requiere_alerta_preventiva": False,
        }

    metricas = [
        ("temperatura", "temp_alerta", "temp_peligro", "gbr_temp", "gbr_temp_lo", "gbr_temp_hi"),
        ("vibracion", "vib_alerta", "vib_peligro", "gbr_vib", None, None),
    ]

    mejor_alerta = 9999
    mejor_peligro = 9999
    mejor_alerta_lo = 9999
    mejor_alerta_hi = 9999
    metrica_critica = "temperatura"
    store = model_store.rul_models.get(id_maquina)

    for nombre, key_alerta, key_peligro, key_gbr, key_lo, key_hi in metricas:
        serie = [float(r[nombre]) for r in historial]
        pend, actual = _pendiente_y_actual(serie)
        c_alerta = _ciclos_hasta_umbral(actual, pend, float(limites[key_alerta]))
        c_peligro = _ciclos_hasta_umbral(actual, pend, float(limites[key_peligro]))

        if store:
            c_gbr_a = _ciclos_gbr_hasta_umbral(store, key_gbr, float(limites[key_alerta]))
            c_alerta = min(c_alerta, c_gbr_a)
            if key_lo and key_hi:
                c_lo = _ciclos_gbr_hasta_umbral(store, key_lo, float(limites[key_alerta]))
                c_hi = _ciclos_gbr_hasta_umbral(store, key_hi, float(limites[key_alerta]))
                if c_alerta < mejor_alerta:
                    mejor_alerta_lo = c_lo
                    mejor_alerta_hi = c_hi

        if c_alerta < mejor_alerta:
            mejor_alerta = c_alerta
            mejor_alerta_lo = max(0, c_alerta - 3)
            mejor_alerta_hi = c_alerta + 5
            metrica_critica = nombre
        if c_peligro < mejor_peligro:
            mejor_peligro = c_peligro

    # Humedad y voltaje como respaldo con tendencia lineal
    for nombre, key_alerta, key_peligro in [
        ("humedad", "hum_alerta", "hum_peligro"),
        ("voltaje", "volt_alerta", "volt_peligro"),
    ]:
        serie = [float(r.get(nombre, 0)) for r in historial]
        pend, actual = _pendiente_y_actual(serie)
        c_alerta = _ciclos_hasta_umbral(actual, pend, float(limites[key_alerta]))
        if c_alerta < mejor_alerta:
            mejor_alerta = c_alerta
            mejor_alerta_lo = max(0, c_alerta - 3)
            mejor_alerta_hi = c_alerta + 5
            metrica_critica = nombre

    texto = _texto_prediccion(mejor_alerta, mejor_peligro, metrica_critica)
    requiere = (
        0 < mejor_alerta <= CICLOS_ALERTA_PREVENTIVA
        or 0 < mejor_peligro <= CICLOS_ALERTA_PREVENTIVA
    )

    return {
        "status": "Entrenado" if store else "Tendencia lineal",
        "rul_alerta_ciclos": mejor_alerta if mejor_alerta < 9999 else -1,
        "rul_peligro_ciclos": mejor_peligro if mejor_peligro < 9999 else -1,
        "rul_ciclos": mejor_alerta if mejor_alerta < 9999 else -1,
        "rul_min": mejor_alerta_lo if mejor_alerta < 9999 else -1,
        "rul_max": mejor_alerta_hi if mejor_alerta < 9999 else -1,
        "prediccion": texto,
        "modelo": "GradientBoosting+tendencia" if store else "Regresion lineal",
        "metrica_critica": metrica_critica,
        "requiere_alerta_preventiva": requiere,
    }


def _crear_alerta_preventiva_servidor(
    cursor,
    id_maquina: str,
    pred: dict,
    limites: dict,
) -> None:
    """Registra alerta predictiva en BD si aun no se envio recientemente."""
    n_actual = model_store.ultima_alerta_preventiva.get(id_maquina, -999)
    cursor.execute(
        "SELECT COUNT(*) AS total FROM SensorData WHERE id_maquina = %s",
        (id_maquina,),
    )
    n_total = cursor.fetchone()["total"]
    if n_total - n_actual < 5:
        return

    ciclos = pred["rul_alerta_ciclos"]
    metrica = pred.get("metrica_critica", "sensores")
    diagnostico = (
        f"[ML Preventivo] Se proyecta zona AMARILLA (alerta) en aproximadamente "
        f"{ciclos} ciclos. Metrica critica: {metrica}. "
        f"Umbrales configurados: temp alerta {limites['temp_alerta']}C, "
        f"vib alerta {limites['vib_alerta']} mm/s. "
        f"Accion: programar mantenimiento antes de llegar a peligro."
    )
    riesgo = max(45.0, min(75.0, 80.0 - (ciclos * 3)))

    cursor.execute(
        """INSERT INTO Alertas (id_maquina, riesgo, diagnostico, tipo)
           VALUES (%s, %s, %s, 'predictivo')""",
        (id_maquina, riesgo, diagnostico),
    )
    cursor.execute(
        "UPDATE Maquina SET estado = 'alerta' WHERE id_maquina = %s AND estado = 'optimo'",
        (id_maquina,),
    )
    model_store.ultima_alerta_preventiva[id_maquina] = n_total
    notificar_telegram(id_maquina, riesgo, diagnostico)


def entrenar_modelos_maquina(id_maquina: str, historial: list, limites: dict):
    """
    Entrena y guarda en model_store:
      1. Pipeline (StandardScaler + LogisticRegression) como clasificador de estado.
      2. GradientBoostingRegressor para RUL con cuantiles.
      3. IsolationForest para anomalías multivariadas.
    """
    if len(historial) < MIN_MUESTRAS_ENTRENAR:
        return

    X = _matriz_features(historial)

    # ── 1. Clasificador de estado ────────────────────────────────────────
    etiquetas = [_etiqueta_estado(r, limites) for r in historial]
    label_map = {"optimo": 0, "alerta": 1, "peligro": 2}
    y_clf = np.array([label_map[e] for e in etiquetas])

    # Solo entrenar si hay al menos dos clases distintas
    if len(set(y_clf)) >= 2:
        pipe = Pipeline([
            ("scaler", StandardScaler()),
            ("clf",    LogisticRegression(max_iter=500, class_weight="balanced")),
        ])
        pipe.fit(X, y_clf)
        model_store.clf_models[id_maquina] = pipe

    # ── 2. RUL con GradientBoosting (cuantil 0.5 = mediana) ─────────────
    y_temp = np.array([r["temperatura"] for r in historial])
    y_vib  = np.array([r["vibracion"]   for r in historial])
    idx    = np.arange(len(historial)).reshape(-1, 1)

    gbr_temp = GradientBoostingRegressor(loss="quantile", alpha=0.5, n_estimators=100)
    gbr_vib  = GradientBoostingRegressor(loss="quantile", alpha=0.5, n_estimators=100)
    gbr_temp.fit(idx, y_temp)
    gbr_vib.fit(idx,  y_vib)

    # Intervalo de confianza (cuantiles 10 y 90)
    gbr_temp_lo = GradientBoostingRegressor(loss="quantile", alpha=0.10, n_estimators=100)
    gbr_temp_hi = GradientBoostingRegressor(loss="quantile", alpha=0.90, n_estimators=100)
    gbr_temp_lo.fit(idx, y_temp)
    gbr_temp_hi.fit(idx, y_temp)

    model_store.rul_models[id_maquina] = {
        "gbr_temp":    gbr_temp,
        "gbr_vib":     gbr_vib,
        "gbr_temp_lo": gbr_temp_lo,
        "gbr_temp_hi": gbr_temp_hi,
        "n_muestras":  len(historial),
        "limites":     limites,
    }

    # ── 3. Isolation Forest ──────────────────────────────────────────────
    if_model = IsolationForest(n_estimators=100, contamination=0.1, random_state=42)
    if_model.fit(X)
    model_store.if_models[id_maquina] = if_model

    print(f"[ML] Modelos actualizados para {id_maquina} con {len(historial)} muestras.")


# ─────────────────────────────────────────────────────────────────────────
# ENDPOINTS
# ─────────────────────────────────────────────────────────────────────────

@app.post("/api/login")
def iniciar_sesion(credenciales: LoginRequest):
    conexion = conectar_db()
    cursor   = conexion.cursor(dictionary=True)
    try:
        # NOTA: en producción usa bcrypt para el hash. Aquí se mantiene
        # la comparación directa para compatibilidad con el init.sql actual.
        cursor.execute(
            """
            SELECT u.id_usuario, u.id_empresa, u.nombre, u.rol,
                   e.nombre AS empresa_nombre
            FROM Usuario u
            JOIN Empresa e ON u.id_empresa = e.id_empresa
            WHERE u.email = %s AND u.password_hash = %s
            """,
            (credenciales.email, credenciales.password),
        )
        usuario = cursor.fetchone()
        if not usuario:
            raise HTTPException(status_code=401, detail="Credenciales incorrectas")
        return usuario
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.post("/api/usuarios")
def registrar_usuario(datos: UsuarioRegistro):
    conexion = conectar_db()
    cursor   = conexion.cursor()
    try:
        cursor.execute(
            "INSERT INTO Usuario (id_empresa, nombre, email, password_hash, rol) VALUES (%s, %s, %s, %s, %s)",
            (datos.id_empresa, datos.nombre, datos.email, datos.password, datos.rol),
        )
        conexion.commit()
        return {"status": "Usuario registrado exitosamente"}
    except Exception as e:
        conexion.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.post("/api/sensores")
def registrar_telemetria(datos: Telemetria):
    conexion = conectar_db()
    cursor   = conexion.cursor(dictionary=True)
    try:
        # Obtener límites de la máquina
        cursor.execute(
            """SELECT temp_alerta, temp_peligro, vib_alerta, vib_peligro,
                      volt_alerta, volt_peligro, vel_alerta, vel_peligro,
                      hum_alerta, hum_peligro,
                      temp_amb_alerta, temp_amb_peligro
               FROM Maquina WHERE id_maquina = %s""",
            (datos.maquina_id,),
        )
        limites = cursor.fetchone()

        cursor.execute(
            """SELECT temperatura, temp_ambiente, vibracion, voltaje, velocidad, humedad
               FROM SensorData WHERE id_maquina = %s
               ORDER BY id_data DESC LIMIT 1""",
            (datos.maquina_id,),
        )
        lectura_previa = cursor.fetchone()

        fila_actual = {
            "temperatura": datos.temperatura,
            "temp_ambiente": datos.temp_ambiente,
            "vibracion": datos.vibracion,
            "voltaje": datos.voltaje,
            "velocidad": datos.velocidad,
            "humedad": datos.humedad,
        }

        if lectura_previa:
            evento = _detectar_cambio_brusco(lectura_previa, fila_actual)
            if evento:
                _crear_alerta_evento(cursor, datos.maquina_id, evento)

        # Guardar telemetría
        cursor.execute(
            """INSERT INTO SensorData
               (id_maquina, temperatura, temp_ambiente, vibracion, voltaje, velocidad, humedad)
               VALUES (%s, %s, %s, %s, %s, %s, %s)""",
            (datos.maquina_id, datos.temperatura, datos.temp_ambiente,
             datos.vibracion, datos.voltaje, datos.velocidad, datos.humedad),
        )

        # ── Determinar estado usando clasificador ML si está disponible ──
        nuevo_estado = "optimo"

        if datos.maquina_id in model_store.clf_models:
            pipe = model_store.clf_models[datos.maquina_id]
            cursor.execute(
                """SELECT temperatura, temp_ambiente, vibracion, voltaje, velocidad, humedad
                   FROM SensorData WHERE id_maquina = %s
                   ORDER BY id_data DESC LIMIT 1 OFFSET 1""",
                (datos.maquina_id,),
            )
            prev_row = cursor.fetchone()
            X_nuevo = np.array(_features_desde_row(fila_actual, prev_row)).reshape(1, -1)
            pred = int(pipe.predict(X_nuevo)[0])
            nuevo_estado = {0: "optimo", 1: "alerta", 2: "peligro"}.get(pred, "optimo")
        elif limites:
            # Fallback: lógica de umbrales original
            if (datos.temperatura >= limites["temp_peligro"]
                    or datos.vibracion >= limites["vib_peligro"]
                    or datos.voltaje   >= limites["volt_peligro"]
                    or datos.velocidad >= limites["vel_peligro"]
                    or datos.humedad   >= limites["hum_peligro"]
                    or datos.temp_ambiente >= limites.get("temp_amb_peligro", 38.0)):
                nuevo_estado = "peligro"
            elif (datos.temperatura >= limites["temp_alerta"]
                    or datos.vibracion >= limites["vib_alerta"]
                    or datos.voltaje   >= limites["volt_alerta"]
                    or datos.velocidad >= limites["vel_alerta"]
                    or datos.humedad   >= limites["hum_alerta"]
                    or datos.temp_ambiente >= limites.get("temp_amb_alerta", 30.0)):
                nuevo_estado = "alerta"

        cursor.execute(
            """SELECT temperatura, temp_ambiente, vibracion, voltaje, velocidad, humedad
               FROM SensorData WHERE id_maquina = %s
               ORDER BY id_data ASC""",
            (datos.maquina_id,),
        )
        historial = cursor.fetchall()

        prediccion_ml = {}
        if limites:
            prediccion_ml = calcular_prediccion_mantenimiento(
                datos.maquina_id, historial, limites
            )

        if nuevo_estado == "peligro" and limites:
            # Crear alerta crítica cuando se detecta estado de peligro
            metrica_critica = prediccion_ml.get("metrica_critica", "sensores")
            diagnostico = (
                f"[CRÍTICO] Se ha detectado condición de peligro inmediato. "
                f"Temperatura motor: {datos.temperatura}°C (peligro > {limites['temp_peligro']}°C), "
                f"Ambiente: {datos.temp_ambiente}°C, "
                f"Vibración: {datos.vibracion} mm/s (peligro > {limites['vib_peligro']} mm/s), "
                f"Humedad: {datos.humedad}% (peligro > {limites.get('hum_peligro', 80.0)}%). "
                f"ACCIÓN INMEDIATA: Detener máquina y revisar sistema."
            )
            riesgo = 95.0
            cursor.execute(
                """INSERT INTO Alertas (id_maquina, riesgo, diagnostico, tipo)
                   VALUES (%s, %s, %s, 'critico')""",
                (datos.maquina_id, riesgo, diagnostico),
            )
            notificar_telegram(datos.maquina_id, riesgo, diagnostico)
        elif (
            nuevo_estado == "optimo"
            and prediccion_ml.get("requiere_alerta_preventiva")
            and limites
        ):
            nuevo_estado = "alerta"
            _crear_alerta_preventiva_servidor(cursor, datos.maquina_id, prediccion_ml, limites)

        cursor.execute(
            "UPDATE Maquina SET estado = %s WHERE id_maquina = %s",
            (nuevo_estado, datos.maquina_id),
        )

        cursor.execute(
            "SELECT COUNT(*) AS total FROM SensorData WHERE id_maquina = %s",
            (datos.maquina_id,),
        )
        n_total = cursor.fetchone()["total"]

        if model_store.necesita_reentrenar(datos.maquina_id, n_total) and limites:
            entrenar_modelos_maquina(datos.maquina_id, historial, limites)

        conexion.commit()

        return {
            "status": "Datos guardados",
            "estado_calculado": nuevo_estado,
            "prediccion": prediccion_ml,
        }

    except Exception as e:
        conexion.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.post("/api/alertas")
def registrar_alerta(alerta: Alerta):
    conexion = conectar_db()
    cursor   = conexion.cursor()
    try:
        cursor.execute(
            "SELECT id_maquina FROM Maquina WHERE id_maquina = %s",
            (alerta.maquina_id,),
        )
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="Maquina no registrada")

        cursor.execute(
            "INSERT INTO Alertas (id_maquina, riesgo, diagnostico, tipo) VALUES (%s, %s, %s, %s)",
            (alerta.maquina_id, alerta.riesgo, alerta.diagnostico, alerta.tipo),
        )

        estado_nuevo = "peligro" if alerta.riesgo > 90.0 else "alerta"
        cursor.execute(
            "UPDATE Maquina SET estado = %s WHERE id_maquina = %s",
            (estado_nuevo, alerta.maquina_id),
        )
        conexion.commit()

        notificar_telegram(alerta.maquina_id, alerta.riesgo, alerta.diagnostico)
        return {"status": "Alerta registrada y estado actualizado"}

    except HTTPException:
        raise
    except Exception as e:
        conexion.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.get("/api/maquinas/{id_maquina}/datos")
def obtener_datos_maquina(id_maquina: str):
    conexion = conectar_db()
    cursor   = conexion.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT nombre, estado,
                      temp_alerta, temp_peligro, vib_alerta, vib_peligro,
                      volt_alerta, volt_peligro, vel_alerta, vel_peligro,
                      hum_alerta, hum_peligro,
                      temp_amb_alerta, temp_amb_peligro,
                      medir_temp, medir_temp_amb, medir_vib, medir_volt, medir_vel, medir_hum
               FROM Maquina WHERE id_maquina = %s""",
            (id_maquina,),
        )
        maquina = cursor.fetchone()
        if not maquina:
            raise HTTPException(status_code=404, detail="Maquina no encontrada")

        cursor.execute(
            """SELECT temperatura, temp_ambiente, vibracion, voltaje, velocidad, humedad
               FROM SensorData WHERE id_maquina = %s
               ORDER BY fecha DESC LIMIT 50""",
            (id_maquina,),
        )
        historial = cursor.fetchall()

        cursor.execute(
            """SELECT diagnostico, fecha, tipo FROM Alertas
               WHERE id_maquina = %s ORDER BY fecha DESC LIMIT 1""",
            (id_maquina,),
        )
        ultima_alerta = cursor.fetchone()

        # ── Anomalía con Isolation Forest del servidor ───────────────────
        anomalia_info = None
        if id_maquina in model_store.if_models and historial:
            ultimo = historial[0]
            X = np.array(_features_desde_row(ultimo)).reshape(1, -1)
            pred   = model_store.if_models[id_maquina].predict(X)[0]
            score  = model_store.if_models[id_maquina].decision_function(X)[0]
            anomalia_info = {
                "es_anomalia": bool(pred == -1),
                "score_if":    round(float(score), 4),
            }

        return {
            "maquina":      maquina,
            "historial":    historial,
            "ultima_alerta": ultima_alerta,
            "anomalia_if":  anomalia_info,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.get("/api/maquinas/{id_maquina}/prediccion")
def obtener_prediccion(id_maquina: str):
    """
    RUL preventivo: ciclos estimados hasta umbral de alerta (amarillo)
    y hasta umbral de peligro (rojo), con intervalo de confianza.
    """
    conexion = conectar_db()
    cursor   = conexion.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT temp_alerta, temp_peligro, vib_alerta, vib_peligro,
                      volt_alerta, volt_peligro, vel_alerta, vel_peligro,
                      hum_alerta, hum_peligro,
                      temp_amb_alerta, temp_amb_peligro
               FROM Maquina WHERE id_maquina = %s""",
            (id_maquina,),
        )
        limites = cursor.fetchone()
        if not limites:
            raise HTTPException(status_code=404, detail="Maquina no encontrada")

        cursor.execute(
            """SELECT temperatura, temp_ambiente, vibracion, voltaje, velocidad, humedad
               FROM SensorData WHERE id_maquina = %s ORDER BY id_data ASC""",
            (id_maquina,),
        )
        historial = cursor.fetchall()

        return calcular_prediccion_mantenimiento(id_maquina, historial, limites)

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.get("/api/maquinas/{id_maquina}/config")
def obtener_configuracion_maquina(id_maquina: str):
    conexion = conectar_db()
    cursor   = conexion.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT nombre, id_area,
                      temp_alerta, temp_peligro, vib_alerta, vib_peligro,
                      volt_alerta, volt_peligro, vel_alerta, vel_peligro,
                      hum_alerta, hum_peligro,
                      temp_amb_alerta, temp_amb_peligro,
                      medir_temp, medir_temp_amb, medir_vib, medir_volt, medir_vel, medir_hum
               FROM Maquina WHERE id_maquina = %s""",
            (id_maquina,),
        )
        config = cursor.fetchone()
        if not config:
            raise HTTPException(status_code=404, detail="Maquina no encontrada")
        return config
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.put("/api/maquinas/{id_maquina}/config")
def actualizar_configuracion_maquina(id_maquina: str, config: ConfiguracionMaquina):
    conexion = conectar_db()
    cursor   = conexion.cursor()
    try:
        cursor.execute(
            """UPDATE Maquina SET
               nombre = %s, id_area = %s,
               temp_alerta = %s, temp_peligro = %s,
               vib_alerta = %s,  vib_peligro = %s,
               volt_alerta = %s, volt_peligro = %s,
               vel_alerta = %s,  vel_peligro = %s,
               hum_alerta = %s,  hum_peligro = %s,
               temp_amb_alerta = %s, temp_amb_peligro = %s,
               medir_temp = %s, medir_temp_amb = %s,
               medir_vib = %s, medir_volt = %s,
               medir_vel = %s,  medir_hum = %s
               WHERE id_maquina = %s""",
            (config.nombre, config.id_area,
             config.temp_alerta, config.temp_peligro,
             config.vib_alerta,  config.vib_peligro,
             config.volt_alerta, config.volt_peligro,
             config.vel_alerta,  config.vel_peligro,
             config.hum_alerta,  config.hum_peligro,
             config.temp_amb_alerta, config.temp_amb_peligro,
             config.medir_temp, config.medir_temp_amb,
             config.medir_vib, config.medir_volt,
             config.medir_vel,  config.medir_hum,
             id_maquina),
        )
        conexion.commit()
        # Invalidar modelos para que se re-entrenen con los nuevos límites
        model_store.rul_models.pop(id_maquina, None)
        model_store.clf_models.pop(id_maquina, None)
        return {"status": "Configuracion actualizada exitosamente"}
    except Exception as e:
        conexion.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.get("/api/empresas")
def obtener_empresas():
    conexion = conectar_db()
    cursor   = conexion.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id_empresa, nombre FROM Empresa")
        return cursor.fetchall()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.get("/api/empresas/{id_empresa}/areas")
def obtener_areas(id_empresa: int):
    conexion = conectar_db()
    cursor   = conexion.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT id_area, nombre FROM Area WHERE id_empresa = %s",
            (id_empresa,),
        )
        return cursor.fetchall()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.get("/api/areas/{id_area}/maquinas")
def obtener_maquinas_area(id_area: int):
    conexion = conectar_db()
    cursor   = conexion.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT id_maquina, nombre, estado FROM Maquina WHERE id_area = %s",
            (id_area,),
        )
        return cursor.fetchall()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.post("/api/empresas_rapido")
def crear_empresa(nombre: str):
    conexion = conectar_db()
    cursor   = conexion.cursor()
    try:
        cursor.execute("INSERT INTO Empresa (nombre) VALUES (%s)", (nombre,))
        id_empresa = cursor.lastrowid
        conexion.commit()
        return {"id_empresa": id_empresa, "status": "Empresa creada exitosamente"}
    except Exception as e:
        conexion.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.post("/api/areas")
def crear_area(datos: AreaRegistro):
    conexion = conectar_db()
    cursor   = conexion.cursor()
    try:
        cursor.execute(
            "INSERT INTO Area (id_empresa, nombre) VALUES (%s, %s)",
            (datos.id_empresa, datos.nombre),
        )
        id_area = cursor.lastrowid
        conexion.commit()
        return {"id_area": id_area, "status": "Área creada exitosamente"}
    except Exception as e:
        conexion.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.post("/api/maquinas")
def registrar_maquina(datos: MaquinaRegistro):
    conexion = conectar_db()
    cursor   = conexion.cursor()
    try:
        cursor.execute(
            """INSERT INTO Maquina
               (id_maquina, id_area, nombre, estado,
                medir_temp, medir_temp_amb, medir_vib, medir_volt, medir_vel, medir_hum)
               VALUES (%s, %s, %s, 'optimo', %s, %s, %s, %s, %s, %s)""",
            (datos.id_maquina, datos.id_area, datos.nombre,
             datos.medir_temp, datos.medir_temp_amb, datos.medir_vib, datos.medir_volt,
             datos.medir_vel, datos.medir_hum),
        )
        conexion.commit()
        return {"id_maquina": datos.id_maquina, "status": "Maquina registrada exitosamente"}
    except Exception as e:
        conexion.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()


@app.post("/api/chat")
def asistente_mecanimal(request: ChatRequest):
    """
    Chatbot Mecanimal con contexto enriquecido: incluye historial reciente,
    tendencias, predicción RUL y alertas en el prompt de Gemini.
    Con caché para optimizar uso de Gemini API.
    """
    conexion = conectar_db()
    cursor   = conexion.cursor(dictionary=True)
    try:
        # Crear clave de caché
        cache_key = hashlib.md5(f"{request.id_maquina}:{request.mensaje}".encode()).hexdigest()
        
        # Verificar caché
        if cache_key in model_store.chat_cache:
            cached_response, cached_time = model_store.chat_cache[cache_key]
            if time.time() - cached_time < model_store.CACHE_DURATION:
                print(f"[Chat] Respondiendo desde caché para {request.id_maquina}")
                return {"respuesta": cached_response, "fuente": "cache"}
        
        # Validar que la máquina exista
        cursor.execute(
            "SELECT nombre, estado FROM Maquina WHERE id_maquina = %s",
            (request.id_maquina,),
        )
        maquina = cursor.fetchone()
        if not maquina:
            raise HTTPException(status_code=404, detail="Máquina no encontrada")

        # Obtener últimas 5 lecturas
        cursor.execute(
            """SELECT temperatura, temp_ambiente, vibracion, voltaje, velocidad, humedad
               FROM SensorData WHERE id_maquina = %s
               ORDER BY fecha DESC LIMIT 5""",
            (request.id_maquina,),
        )
        datos_recientes = cursor.fetchall()
        
        # Invertir para obtener orden cronológico (antiguo a reciente)
        datos_recientes = list(reversed(datos_recientes)) if datos_recientes else []

        contexto = "No hay datos de sensores registrados."
        if datos_recientes:
            ultimo = datos_recientes[-1]  # El más reciente
            
            temp_vals = [float(r["temperatura"]) for r in datos_recientes]
            vib_vals = [float(r["vibracion"]) for r in datos_recientes]
            
            delta_temp = temp_vals[-1] - temp_vals[0]  # positivo = subiendo
            delta_vib = vib_vals[-1] - vib_vals[0]
            tendencia_temp = "subiendo" if delta_temp > 0 else "bajando"
            tendencia_vib = "aumentando" if delta_vib > 0 else "disminuyendo"

            contexto = (
                f"🔍 Máquina {maquina['nombre']} - Estado: {maquina['estado'].upper()}\n"
                f"📊 Última lectura:\n"
                f"  • Temp. motor: {ultimo['temperatura']:.1f}°C (Δ{delta_temp:+.1f}°C, {tendencia_temp})\n"
                f"  • Temp. ambiente: {float(ultimo.get('temp_ambiente', 25)):.1f}°C\n"
                f"  • Vibración: {ultimo['vibracion']:.2f} mm/s (Δ{delta_vib:+.2f}, {tendencia_vib})\n"
                f"  • Voltaje: {ultimo['voltaje']:.1f}V | Velocidad: {ultimo['velocidad']} RPM | Humedad: {ultimo['humedad']:.1f}%"
            )

        # Obtener últimas alertas
        cursor.execute(
            """SELECT tipo, riesgo, diagnostico FROM Alertas
               WHERE id_maquina = %s
               ORDER BY fecha DESC LIMIT 3""",
            (request.id_maquina,),
        )
        alertas_recientes = cursor.fetchall()
        
        alertas_ctx = ""
        if alertas_recientes:
            alertas_txt = "; ".join(
                f"{a['tipo']} (riesgo {a['riesgo']:.0f}%): {a['diagnostico'][:60]}..."
                for a in alertas_recientes
            )
            alertas_ctx = f"\n⚠️ Alertas recientes: {alertas_txt}"

        # Incluir RUL si está disponible
        rul_ctx = ""
        if request.id_maquina in model_store.rul_models and datos_recientes:
            store = model_store.rul_models[request.id_maquina]
            rul_ctx = f"\n📈 Modelo ML: {store['n_muestras']} muestras entrenadas."

        prompt = (
            "Eres Mecanimal, un asistente técnico amigable para ingenieros de fábrica. "
            "Habla de forma natural, clara y comprensible. Evita jerga técnica. "
            "Usa emojis cuando sea apropiado. Responde máximo 2 oraciones.\n\n"
            f"Contexto actual de la máquina:\n{contexto}{alertas_ctx}{rul_ctx}\n\n"
            f"Pregunta del usuario: {request.mensaje}\n\n"
            "Responde de manera útil, directa y fácil de entender. "
            "Si hablas de ciclos o tiempos, explícalos claramente. "
            "Si el estado es crítico, avisa de forma clara."
        )

        try:
            if modelo_gemini is None:
                raise RuntimeError("Gemini no configurado")
            respuesta = modelo_gemini.generate_content(prompt)
            respuesta_texto = respuesta.text.strip() if respuesta.text else "Sin respuesta"
        except Exception as e:
            print(f"[Chat] Error Gemini: {e}")
            # Fallback inteligente basado en la pregunta y estado actual
            respuesta_texto = ""
            pregunta_lower = request.mensaje.lower()
            
            # Intentar responder según tipo de pregunta
            if "ciclo" in pregunta_lower or "falla" in pregunta_lower or "cuantos" in pregunta_lower:
                # Pregunta sobre ciclos hasta falla
                if request.id_maquina in model_store.rul_models and datos_recientes:
                    store = model_store.rul_models[request.id_maquina]
                    respuesta_texto = f"🔮 Según nuestro análisis, la máquina tiene aproximadamente {store['n_muestras']} ciclos de historial. " \
                                    f"El modelo estima que aún quedan ciclos antes de problemas serios."
                else:
                    respuesta_texto = "📊 Aún no tenemos suficientes datos para proyectar fallas. Seguimos recolectando información."
            
            elif "temperatura" in pregunta_lower or "temp" in pregunta_lower:
                if datos_recientes:
                    ultimo = datos_recientes[-1]
                    temp = ultimo['temperatura']
                    respuesta_texto = f"🌡️ La temperatura actual es {temp:.1f}°C. "
                    if maquina['estado'].upper() == "PELIGRO":
                        respuesta_texto += "¡ALERTA! Está muy alta, detén la máquina ya."
                    elif maquina['estado'].upper() == "ALERTA":
                        respuesta_texto += "Está elevada, mantén control."
                    else:
                        respuesta_texto += "Está normal."
                else:
                    respuesta_texto = "❌ Sin datos de temperatura disponibles."
            
            elif "vibracion" in pregunta_lower or "vibración" in pregunta_lower:
                if datos_recientes:
                    ultimo = datos_recientes[-1]
                    vib = ultimo['vibracion']
                    respuesta_texto = f"📳 La vibración es {vib:.1f} mm/s. "
                    if vib > 6:
                        respuesta_texto += "Está alta, revisa el sistema."
                    else:
                        respuesta_texto += "Normal."
                else:
                    respuesta_texto = "❌ Sin datos de vibración."
            
            elif "estado" in pregunta_lower or "como esta" in pregunta_lower:
                estado = maquina['estado'].upper()
                if estado == "PELIGRO":
                    respuesta_texto = f"🚨 La máquina está en PELIGRO. Requiere atención inmediata."
                elif estado == "ALERTA":
                    respuesta_texto = f"⚠️ La máquina está en ALERTA. Programa mantenimiento pronto."
                else:
                    respuesta_texto = f"✅ La máquina está OPTIMA. Todo normal."
            
            else:
                # Respuesta genérica
                estado = maquina['estado'].upper()
                if estado == "PELIGRO":
                    respuesta_texto = "🚨 ¡ALERTA CRÍTICA! Máquina en estado peligro. Detener inmediatamente."
                elif estado == "ALERTA":
                    respuesta_texto = "⚠️ Máquina en alerta. Programa mantenimiento pronto."
                else:
                    respuesta_texto = "✅ Máquina funcionando normalmente."
                
                if datos_recientes:
                    ultimo = datos_recientes[-1]
                    respuesta_texto += f" Última lectura: {ultimo['temperatura']:.1f}°C, vibración {ultimo['vibracion']:.1f}mm/s."

        # Guardar en caché
        model_store.chat_cache[cache_key] = (respuesta_texto, time.time())
        
        return {"respuesta": respuesta_texto, "fuente": "gemini"}

    except HTTPException:
        raise
    except Exception as e:
        print(f"[Chat] Error general: {e}")
        raise HTTPException(status_code=500, detail=f"Error en chatbot: {str(e)}")
    finally:
        cursor.close()
        conexion.close()


# ─────────────────────────────────────────────────────────────────────────
# ENDPOINT EXTRA: estado de modelos en memoria (útil para debug)
# ─────────────────────────────────────────────────────────────────────────
@app.get("/api/ml/estado")
def estado_modelos():
    return {
        "rul_models":  list(model_store.rul_models.keys()),
        "clf_models":  list(model_store.clf_models.keys()),
        "if_models":   list(model_store.if_models.keys()),
        "retrain_interval": model_store.RETRAIN_INTERVAL,
    }