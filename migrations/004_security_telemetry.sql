CREATE TABLE IF NOT EXISTS DeviceCredential (
    id_maquina VARCHAR(50) PRIMARY KEY,
    key_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
    rotated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_maquina) REFERENCES Maquina(id_maquina) ON DELETE CASCADE
);
ALTER TABLE SensorData ADD COLUMN IF NOT EXISTS `sequence` BIGINT UNSIGNED NULL;
ALTER TABLE SensorData ADD COLUMN IF NOT EXISTS boot_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL;
ALTER TABLE SensorData ADD COLUMN IF NOT EXISTS firmware_version VARCHAR(64) NULL;
ALTER TABLE SensorData ADD COLUMN IF NOT EXISTS received_at TIMESTAMP(6) NULL DEFAULT NULL;
UPDATE SensorData SET received_at=fecha WHERE received_at IS NULL;
ALTER TABLE SensorData MODIFY received_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6);
CREATE UNIQUE INDEX IF NOT EXISTS uq_sensor_identity ON SensorData (id_maquina, boot_id, `sequence`);
CREATE INDEX IF NOT EXISTS idx_sensor_maquina_fecha ON SensorData (id_maquina, fecha);
CREATE INDEX IF NOT EXISTS idx_sensor_received ON SensorData (id_maquina, received_at);
CREATE INDEX IF NOT EXISTS idx_alertas_maquina_fecha ON Alertas (id_maquina, fecha);
