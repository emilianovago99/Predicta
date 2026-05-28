# 🐾🤖 Mecanimales - SaaS Industrial 4.0 de Mantenimiento Predictivo

Plataforma integral de Mantenimiento Predictivo (SaaS B2B) diseñada para monitorear maquinaria industrial en tiempo real, anticipar fallas catastróficas mediante Edge Computing e Inteligencia Artificial, y notificar a los equipos de ingeniería antes de que ocurran los paros de línea.

Desarrollado para el **Hackatec**.

---

## 🚀 Características Principales

- **Edge AI Predictivo:** Procesamiento de telemetría (temperatura, vibración, voltaje, velocidad) de forma local. El algoritmo detecta aceleraciones anómalas en la fricción y temperatura antes de rebasar los límites estructurales.
- **Asistente Mecanimal (IA):** Chatbot integrado en la aplicación móvil impulsado por **Gemini 2.5 Flash**. Analiza el estado en vivo de los sensores y brinda diagnósticos en lenguaje natural. Incluye un sistema de respaldo (Fallback) si la IA pierde conexión.
- **Arquitectura Multi-Inquilino (SaaS B2B):** Seguridad perimetral basada en tres roles estrictos:
  - **Instaladores (Mecanimales):** Dan de alta nuevas empresas y vinculan el hardware físico (IoT) a la nube.
  - **Jefes de Mantenimiento:** Tienen control remoto sobre el hardware, modifican límites de alerta/peligro y gestionan áreas de la fábrica.
  - **Participantes (Técnicos):** Visualización en tiempo real e interacción con la IA, sin permisos de modificación de red.
- **Alertas Multicanal:** Sistema de escalamiento de alertas (Nivel 1: Predictivo Naranja, Nivel 2: Crítico Rojo) con notificaciones Push integradas en la app y despachos automáticos vía **Telegram**.
- **Dashboard Dinámico:** Gráficas de comportamiento de sensores que mutan de color según los umbrales personalizados de cada cliente industrial.

---

## 🛠️ Arquitectura del Sistema

El ecosistema está compuesto por tres capas:

1. **La Máquina (Edge Computing):** Script en Python (`simulador_edge.py`) que simula la lectura de sensores de hardware y procesa la información localmente.
2. **La Nube (Backend & BD):** Servidor construido con **FastAPI** en Python y base de datos relacional en **MariaDB**.
3. **El Control (Frontend Móvil):** Aplicación desarrollada en **Flutter**, diseñada para dispositivos Android/iOS con renderizado de alto rendimiento.

---

## ⚙️ Requisitos Previos

Antes de levantar el proyecto, asegúrate de tener instalado:

- Python 3.9+
- Flutter SDK (Versión estable más reciente)
- MariaDB o MySQL Server (Puerto 3307 o ajustado en `main.py`)
- Una API Key de [Google Gemini](https://aistudio.google.com/)
- Un Token de Bot de Telegram y el Chat ID de destino.

---

## 📦 Guía de Instalación y Ejecución

Sigue estos pasos en orden para levantar todo el ecosistema en un entorno de red local.

### 1. Base de Datos

1. Abre tu gestor de base de datos (ej. DBeaver, phpMyAdmin o terminal de MariaDB).
2. Ejecuta el script completo proporcionado en `esquema.sql`. Esto creará la base de datos `mecanimales_db`, las tablas y los usuarios iniciales de demostración.

### 2. Configuración del Entorno (Variables)

Crea un archivo llamado `.env` en la raíz de tu carpeta del servidor (donde está `main.py`) y agrega tus credenciales:

```env
GEMINI_API_KEY=tu_api_key_de_gemini_aqui
TELEGRAM_BOT_TOKEN=tu_token_del_bot_aqui
TELEGRAM_CHAT_ID=tu_chat_id_aqui
```
