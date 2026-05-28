DROP TABLE IF EXISTS Alertas;
DROP TABLE IF EXISTS SensorData;
DROP TABLE IF EXISTS Maquina;
DROP TABLE IF EXISTS Area;
DROP TABLE IF EXISTS Usuario;
DROP TABLE IF EXISTS Empresa;

CREATE TABLE Empresa (
    id_empresa INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Usuario (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    id_empresa INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    rol ENUM('instalador', 'jefe', 'participante') NOT NULL,
    FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa) ON DELETE CASCADE
);

CREATE TABLE Area (
    id_area INT AUTO_INCREMENT PRIMARY KEY,
    id_empresa INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa) ON DELETE CASCADE
);

CREATE TABLE Maquina (
    id_maquina VARCHAR(50) PRIMARY KEY,
    id_area INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    estado ENUM('optimo', 'alerta', 'peligro') DEFAULT 'optimo',
    temp_alerta FLOAT DEFAULT 50.0,
    temp_peligro FLOAT DEFAULT 60.0,
    vib_alerta FLOAT DEFAULT 4.0,
    vib_peligro FLOAT DEFAULT 7.0,
    volt_alerta FLOAT DEFAULT 100.0,
    volt_peligro FLOAT DEFAULT 130.0,
    vel_alerta INT DEFAULT 800,
    vel_peligro INT DEFAULT 1500,
    FOREIGN KEY (id_area) REFERENCES Area(id_area) ON DELETE CASCADE
);

CREATE TABLE SensorData (
    id_data BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_maquina VARCHAR(50) NOT NULL,
    temperatura FLOAT NOT NULL,
    vibracion FLOAT NOT NULL,
    voltaje FLOAT NOT NULL,
    velocidad FLOAT NOT NULL,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_maquina) REFERENCES Maquina(id_maquina) ON DELETE CASCADE
);

CREATE TABLE Alertas (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    id_maquina VARCHAR(50) NOT NULL,
    riesgo FLOAT NOT NULL,
    diagnostico TEXT NOT NULL,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_maquina) REFERENCES Maquina(id_maquina) ON DELETE CASCADE
);

INSERT INTO Empresa (nombre) VALUES ('Mecanimales Core');
INSERT INTO Empresa (nombre) VALUES ('Planta Ensambladora Alpha');

INSERT INTO Area (id_empresa, nombre) VALUES (2, 'Linea de Motores');
INSERT INTO Maquina (id_maquina, id_area, nombre, estado) VALUES ('M-01', 1, 'Motor Principal', 'optimo');

INSERT INTO Usuario (id_empresa, nombre, email, password_hash, rol) VALUES (1, 'Equipo Mecanimales', 'admin@mecanimales.com', 'root', 'instalador');
INSERT INTO Usuario (id_empresa, nombre, email, password_hash, rol) VALUES (2, 'Emiliano Valdez', 'jefe@mecanimales.com', 'hackatec2026', 'jefe');
INSERT INTO Usuario (id_empresa, nombre, email, password_hash, rol) VALUES (2, 'Técnico de Planta', 'tecnico@mecanimales.com', '1234', 'participante');