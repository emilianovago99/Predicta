from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import mysql.connector
import requests
import os
from dotenv import load_dotenv
import google.generativeai as genai

load_dotenv()
TELEGRAM_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

genai.configure(api_key=GEMINI_API_KEY)
modelo = genai.GenerativeModel('gemini-2.5-flash')

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

def conectar_db():
    return mysql.connector.connect(
        host="127.0.0.1",
        port=3307,
        user="api_user",
        password="api_password_seguro",
        database="mecanimales_db"
    )

def notificar_telegram(maquina_id, riesgo, diagnostico):
    if not TELEGRAM_TOKEN:
        return
    if not TELEGRAM_CHAT_ID:
        return
        
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    
    icono = "🟠"
    if riesgo > 90.0:
        icono = "🔴"
        
    texto = f"{icono} *MECANIMALES ALERTA*\n\n*Máquina:* {maquina_id}\n*Diagnóstico:* {diagnostico}"
    
    payload = {
        "chat_id": TELEGRAM_CHAT_ID, 
        "text": texto, 
        "parse_mode": "Markdown"
    }
    
    try:
        requests.post(url, json=payload)
    except Exception:
        pass

class LoginRequest(BaseModel):
    email: str
    password: str

class Telemetria(BaseModel):
    maquina_id: str
    voltaje: float
    temperatura: float
    vibracion: float
    velocidad: int

class Alerta(BaseModel):
    maquina_id: str
    riesgo: float
    diagnostico: str

class MaquinaRegistro(BaseModel):
    id_area: int
    nombre: str
    id_maquina: str

class AreaRegistro(BaseModel):
    id_empresa: int
    nombre: str

class ConfiguracionMaquina(BaseModel):
    nombre: str
    id_area: int
    temp_alerta: float
    temp_peligro: float
    vib_alerta: float
    vib_peligro: float
    volt_alerta: float
    volt_peligro: float
    vel_alerta: int
    vel_peligro: int

class ChatRequest(BaseModel):
    mensaje: str
    id_maquina: str

class UsuarioRegistro(BaseModel):
    id_empresa: int
    nombre: str
    email: str
    password: str
    rol: str

@app.post("/api/login")
def iniciar_sesion(credenciales: LoginRequest):
    conexion = conectar_db()
    cursor = conexion.cursor(dictionary=True)
    try:
        consulta = """
            SELECT u.id_usuario, u.id_empresa, u.nombre, u.rol, e.nombre AS empresa_nombre 
            FROM Usuario u 
            JOIN Empresa e ON u.id_empresa = e.id_empresa 
            WHERE u.email = %s AND u.password_hash = %s
        """
        cursor.execute(consulta, (credenciales.email, credenciales.password))
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
    cursor = conexion.cursor()
    try:
        cursor.execute(
            "INSERT INTO Usuario (id_empresa, nombre, email, password_hash, rol) VALUES (%s, %s, %s, %s, %s)",
            (datos.id_empresa, datos.nombre, datos.email, datos.password, datos.rol)
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
    cursor = conexion.cursor(dictionary=True)
    try:
        cursor.execute("SELECT temp_alerta, vib_alerta FROM Maquina WHERE id_maquina = %s", (datos.maquina_id,))
        limites = cursor.fetchone()
        
        t_limite = 50.0
        v_limite = 4.0
        
        if limites:
            t_limite = limites['temp_alerta']
            v_limite = limites['vib_alerta']
            
        cursor.execute(
            "INSERT INTO SensorData (id_maquina, temperatura, vibracion, voltaje, velocidad) VALUES (%s, %s, %s, %s, %s)",
            (datos.maquina_id, datos.temperatura, datos.vibracion, datos.voltaje, datos.velocidad)
        )
        
        if datos.temperatura < t_limite:
            if datos.vibracion < v_limite:
                cursor.execute("UPDATE Maquina SET estado = 'optimo' WHERE id_maquina = %s", (datos.maquina_id,))
                
        conexion.commit()
        return {"status": "Datos guardados"}
    except Exception as e:
        conexion.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()

@app.post("/api/alertas")
def registrar_alerta(alerta: Alerta):
    conexion = conectar_db()
    cursor = conexion.cursor()
    try:
        cursor.execute("SELECT id_maquina FROM Maquina WHERE id_maquina = %s", (alerta.maquina_id,))
        maquina = cursor.fetchone()
        
        if not maquina:
            raise HTTPException(status_code=404, detail="Maquina no registrada")
            
        cursor.execute(
            "INSERT INTO Alertas (id_maquina, riesgo, diagnostico) VALUES (%s, %s, %s)",
            (alerta.maquina_id, alerta.riesgo, alerta.diagnostico)
        )
        
        estado_nuevo = 'alerta'
        if alerta.riesgo > 90.0:
            estado_nuevo = 'peligro'
            
        cursor.execute("UPDATE Maquina SET estado = %s WHERE id_maquina = %s", (estado_nuevo, alerta.maquina_id))
        
        conexion.commit()
        
        notificar_telegram(alerta.maquina_id, alerta.riesgo, alerta.diagnostico)
        
        return {"status": "Alerta registrada y estado actualizado"}
    except Exception as e:
        conexion.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()

@app.get("/api/maquinas/{id_maquina}/datos")
def obtener_datos_maquina(id_maquina: str):
    conexion = conectar_db()
    cursor = conexion.cursor(dictionary=True)
    try:
        cursor.execute("SELECT nombre, estado, temp_alerta, temp_peligro, vib_alerta, vib_peligro, volt_alerta, volt_peligro, vel_alerta, vel_peligro FROM Maquina WHERE id_maquina = %s", (id_maquina,))
        maquina = cursor.fetchone()
        
        if not maquina:
            raise HTTPException(status_code=404, detail="Maquina no encontrada")
            
        cursor.execute("SELECT temperatura, vibracion, voltaje, velocidad FROM SensorData WHERE id_maquina = %s ORDER BY fecha DESC LIMIT 50", (id_maquina,))
        historial = cursor.fetchall()
        
        cursor.execute("SELECT diagnostico, fecha FROM Alertas WHERE id_maquina = %s ORDER BY fecha DESC LIMIT 1", (id_maquina,))
        ultima_alerta = cursor.fetchone()
        
        return {
            "maquina": maquina,
            "historial": historial,
            "ultima_alerta": ultima_alerta
        }
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
    cursor = conexion.cursor(dictionary=True)
    try:
        cursor.execute("SELECT nombre, id_area, temp_alerta, temp_peligro, vib_alerta, vib_peligro, volt_alerta, volt_peligro, vel_alerta, vel_peligro FROM Maquina WHERE id_maquina = %s", (id_maquina,))
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
    cursor = conexion.cursor()
    try:
        cursor.execute(
            "UPDATE Maquina SET nombre = %s, id_area = %s, temp_alerta = %s, temp_peligro = %s, vib_alerta = %s, vib_peligro = %s, volt_alerta = %s, volt_peligro = %s, vel_alerta = %s, vel_peligro = %s WHERE id_maquina = %s",
            (config.nombre, config.id_area, config.temp_alerta, config.temp_peligro, config.vib_alerta, config.vib_peligro, config.volt_alerta, config.volt_peligro, config.vel_alerta, config.vel_peligro, id_maquina)
        )
        conexion.commit()
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
    cursor = conexion.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id_empresa, nombre FROM Empresa")
        empresas = cursor.fetchall()
        return empresas
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()

@app.get("/api/empresas/{id_empresa}/areas")
def obtener_areas(id_empresa: int):
    conexion = conectar_db()
    cursor = conexion.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id_area, nombre FROM Area WHERE id_empresa = %s", (id_empresa,))
        areas = cursor.fetchall()
        return areas
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()

@app.get("/api/areas/{id_area}/maquinas")
def obtener_maquinas_area(id_area: int):
    conexion = conectar_db()
    cursor = conexion.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id_maquina, nombre, estado FROM Maquina WHERE id_area = %s", (id_area,))
        maquinas = cursor.fetchall()
        return maquinas
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()

@app.post("/api/empresas_rapido")
def crear_empresa(nombre: str):
    conexion = conectar_db()
    cursor = conexion.cursor()
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
    cursor = conexion.cursor()
    try:
        cursor.execute(
            "INSERT INTO Area (id_empresa, nombre) VALUES (%s, %s)",
            (datos.id_empresa, datos.nombre)
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
    cursor = conexion.cursor()
    try:
        cursor.execute(
            "INSERT INTO Maquina (id_maquina, id_area, nombre, estado) VALUES (%s, %s, %s, 'optimo')",
            (datos.id_maquina, datos.id_area, datos.nombre)
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
    conexion = conectar_db()
    cursor = conexion.cursor(dictionary=True)
    try:
        cursor.execute("SELECT estado FROM Maquina WHERE id_maquina = %s", (request.id_maquina,))
        maquina = cursor.fetchone()
        
        if not maquina:
            raise HTTPException(status_code=404, detail="Maquina no encontrada")
            
        cursor.execute("SELECT temperatura, vibracion, voltaje, velocidad FROM SensorData WHERE id_maquina = %s ORDER BY fecha DESC LIMIT 1", (request.id_maquina,))
        datos = cursor.fetchone()
        
        contexto = "No hay datos recientes de los sensores."
        if datos:
            contexto = f"Temperatura: {datos['temperatura']:.1f}C, Vibracion: {datos['vibracion']:.1f}mm/s, Voltaje: {datos['voltaje']:.1f}V, Velocidad: {datos['velocidad']}RPM. Estado general de la maquina: {maquina['estado']}."
            
        prompt = f"Eres un 'Mecanimal', una mascota robotica super inteligente que asiste a los ingenieros de la fabrica. Eres amigable, directo y usas emojis de animales mecanicos o herramientas. El usuario te pregunta: '{request.mensaje}'. Responde usando estos datos en tiempo real de la maquina: {contexto}. Da una respuesta util y de maximo dos oraciones breves."
        
        respuesta_texto = ""
        try:
            respuesta = modelo.generate_content(prompt)
            respuesta_texto = respuesta.text
        except Exception:
            if datos:
                respuesta_texto = f"🐾🤖 ¡Bzzz! Mis circuitos de IA están tomando un respiro (Modo Respaldo). Te informo rápido: el motor está en estado '{maquina['estado']}' con una temperatura de {datos['temperatura']:.1f}°C."
            if not datos:
                respuesta_texto = "🐾🤖 ¡Bzzz! Mis circuitos de IA están tomando un respiro (Modo Respaldo). No tengo lecturas de sensores disponibles."
        
        return {"respuesta": respuesta_texto}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conexion.close()