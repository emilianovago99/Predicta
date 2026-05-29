-- Migración: temperatura ambiente + alertas por evento (cambio brusco)
-- Ejecutar si ya tienes la BD creada (sin borrar volúmenes):
--   Get-Content migrations/003_temp_ambiente_evento.sql | docker exec -i hack-db-1 mysql -u api_user -papi_password_seguro mecanimales_db

ALTER TABLE Maquina
    ADD COLUMN temp_amb_alerta FLOAT DEFAULT 30.0 AFTER hum_peligro;

ALTER TABLE Maquina
    ADD COLUMN temp_amb_peligro FLOAT DEFAULT 38.0 AFTER temp_amb_alerta;

ALTER TABLE Maquina
    ADD COLUMN medir_temp_amb BOOLEAN DEFAULT TRUE AFTER medir_hum;

ALTER TABLE SensorData
    ADD COLUMN temp_ambiente FLOAT NOT NULL DEFAULT 25.0 AFTER temperatura;

ALTER TABLE Alertas
    MODIFY COLUMN tipo ENUM('critico', 'predictivo', 'evento') DEFAULT 'critico';
