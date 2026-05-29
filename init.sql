-- =========================================================
--  Predicta  ─  Schema v2
--  Mejoras respecto a v1:
--    · Índice compuesto (id_maquina, fecha) en SensorData
--      → consultas de historial hasta 10x más rápidas
--    · Columnas de features de ventana en SensorData
--      → el servidor puede re-entrenar ML sin recalcular
--    · score_riesgo_edge almacenado para auditoría y análisis
--    · Columna tipo en Alertas (critico / predictivo)
--    · Índice en Alertas para consultas rápidas del dashboard
-- =========================================================

DROP TABLE IF EXISTS Alertas;
DROP TABLE IF EXISTS SensorData;
DROP TABLE IF EXISTS Maquina;
DROP TABLE IF EXISTS Area;
DROP TABLE IF EXISTS Usuario;
DROP TABLE IF EXISTS Empresa;

-- ─────────────────────────────────────────────────────────
-- EMPRESA
-- ─────────────────────────────────────────────────────────
CREATE TABLE Empresa (
    id_empresa     INT AUTO_INCREMENT PRIMARY KEY,
    nombre         VARCHAR(100) NOT NULL,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─────────────────────────────────────────────────────────
-- USUARIO
-- ─────────────────────────────────────────────────────────
CREATE TABLE Usuario (
    id_usuario    INT AUTO_INCREMENT PRIMARY KEY,
    id_empresa    INT NOT NULL,
    nombre        VARCHAR(100) NOT NULL,
    email         VARCHAR(100) UNIQUE NOT NULL,
    -- En producción: almacenar aquí el hash bcrypt, nunca texto plano
    password_hash VARCHAR(255) NOT NULL,
    rol           ENUM('instalador', 'jefe', 'participante') NOT NULL,
    FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa) ON DELETE CASCADE
);

-- ─────────────────────────────────────────────────────────
-- ÁREA
-- ─────────────────────────────────────────────────────────
CREATE TABLE Area (
    id_area    INT AUTO_INCREMENT PRIMARY KEY,
    id_empresa INT NOT NULL,
    nombre     VARCHAR(100) NOT NULL,
    FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa) ON DELETE CASCADE
);

-- ─────────────────────────────────────────────────────────
-- MÁQUINA
-- ─────────────────────────────────────────────────────────
CREATE TABLE Maquina (
    id_maquina   VARCHAR(50) PRIMARY KEY,
    id_area      INT NOT NULL,
    nombre       VARCHAR(100) NOT NULL,
    estado       ENUM('optimo', 'alerta', 'peligro') DEFAULT 'optimo',

    -- Umbrales configurables por máquina
    temp_alerta  FLOAT DEFAULT 50.0,
    temp_peligro FLOAT DEFAULT 60.0,
    vib_alerta   FLOAT DEFAULT 4.0,
    vib_peligro  FLOAT DEFAULT 7.0,
    volt_alerta  FLOAT DEFAULT 100.0,
    volt_peligro FLOAT DEFAULT 130.0,
    vel_alerta   INT   DEFAULT 800,
    vel_peligro  INT   DEFAULT 1500,
    hum_alerta   FLOAT DEFAULT 60.0,
    hum_peligro  FLOAT DEFAULT 80.0,
    temp_amb_alerta  FLOAT DEFAULT 30.0,
    temp_amb_peligro FLOAT DEFAULT 38.0,

    -- Flags de sensores activos
    medir_temp   BOOLEAN DEFAULT TRUE,
    medir_temp_amb BOOLEAN DEFAULT TRUE,
    medir_vib    BOOLEAN DEFAULT TRUE,
    medir_volt   BOOLEAN DEFAULT TRUE,
    medir_vel    BOOLEAN DEFAULT TRUE,
    medir_hum    BOOLEAN DEFAULT TRUE,

    FOREIGN KEY (id_area) REFERENCES Area(id_area) ON DELETE CASCADE
);

-- ─────────────────────────────────────────────────────────
-- SENSOR DATA  (tabla de mayor volumen → índices críticos)
-- ─────────────────────────────────────────────────────────
CREATE TABLE SensorData (
    id_data    BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_maquina VARCHAR(50) NOT NULL,

    -- Valores crudos del sensor (temperatura = motor; temp_ambiente = ambiente)
    temperatura FLOAT NOT NULL,
    temp_ambiente FLOAT NOT NULL DEFAULT 25.0,
    vibracion   FLOAT NOT NULL,
    voltaje     FLOAT NOT NULL,
    velocidad   FLOAT NOT NULL,
    humedad     FLOAT NOT NULL,

    -- Features de ventana deslizante calculadas en el nodo edge
    -- (NULL si el nodo no las envía, e.g. nodo legacy)
    temp_media  FLOAT    DEFAULT NULL,
    temp_std    FLOAT    DEFAULT NULL,
    temp_delta  FLOAT    DEFAULT NULL,
    vib_media   FLOAT    DEFAULT NULL,
    vib_delta   FLOAT    DEFAULT NULL,

    -- Score de riesgo calculado en el edge (0-100)
    score_riesgo_edge FLOAT DEFAULT NULL,

    fecha      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (id_maquina) REFERENCES Maquina(id_maquina) ON DELETE CASCADE
);

-- Índice compuesto: clave para consultas de historial y re-entrenamiento ML
-- Cubre: WHERE id_maquina = X ORDER BY fecha DESC
CREATE INDEX idx_sensor_maquina_fecha ON SensorData (id_maquina, fecha);

-- Índice extra para COUNT rápido por máquina (usado en trigger de re-entrenamiento)
CREATE INDEX idx_sensor_maquina      ON SensorData (id_maquina);

-- ─────────────────────────────────────────────────────────
-- ALERTAS
-- ─────────────────────────────────────────────────────────
CREATE TABLE Alertas (
    id_alerta  INT AUTO_INCREMENT PRIMARY KEY,
    id_maquina VARCHAR(50) NOT NULL,
    riesgo     FLOAT NOT NULL,
    diagnostico TEXT NOT NULL,
    -- Tipo de alerta para filtrar en el dashboard
    tipo       ENUM('critico', 'predictivo', 'evento') DEFAULT 'critico',
    fecha      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (id_maquina) REFERENCES Maquina(id_maquina) ON DELETE CASCADE
);

-- Índice para el dashboard: alertas recientes por máquina
CREATE INDEX idx_alertas_maquina_fecha ON Alertas (id_maquina, fecha);

-- ─────────────────────────────────────────────────────────
-- DATOS INICIALES
-- ─────────────────────────────────────────────────────────
INSERT INTO Empresa (nombre) VALUES ('Predicta Core');
INSERT INTO Empresa (nombre) VALUES ('Planta Ensambladora Alpha');

INSERT INTO Area (id_empresa, nombre) VALUES (2, 'Linea de Motores');

INSERT INTO Maquina (id_maquina, id_area, nombre, estado)
    VALUES ('M-01', 1, 'Motor Principal', 'optimo');

-- ADVERTENCIA: passwords en texto plano solo para desarrollo local.
-- En producción reemplazar por hashes bcrypt antes del primer deploy.
INSERT INTO Usuario (id_empresa, nombre, email, password_hash, rol)
    VALUES (1, 'Equipo Predicta',  'admin@predicta.com',  'root',          'instalador');
INSERT INTO Usuario (id_empresa, nombre, email, password_hash, rol)
    VALUES (2, 'Emiliano Valdez',     'jefe@predicta.com',   'hackatec2026',  'jefe');
INSERT INTO Usuario (id_empresa, nombre, email, password_hash, rol)
    VALUES (2, 'Técnico de Planta',   'tecnico@predicta.com','1234',          'participante');