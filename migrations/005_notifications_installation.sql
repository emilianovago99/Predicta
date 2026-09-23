CREATE TABLE IF NOT EXISTS TelegramChannel (
 id INT AUTO_INCREMENT PRIMARY KEY,
 id_empresa INT NOT NULL,
 nombre VARCHAR(100) NOT NULL,
 token_encrypted TEXT NOT NULL,
 chat_id VARCHAR(100) NOT NULL,
 enabled BOOLEAN NOT NULL DEFAULT TRUE,
 next_send_at DATETIME(6) NULL,
 last_status VARCHAR(100) NULL,
 FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa)
);
ALTER TABLE Maquina ADD COLUMN IF NOT EXISTS telegram_channel_id INT NULL;
ALTER TABLE Maquina ADD COLUMN IF NOT EXISTS alert_cooldown_seconds INT NOT NULL DEFAULT 900;
CREATE TABLE IF NOT EXISTS MachineAlert (
 id_maquina VARCHAR(50) PRIMARY KEY,
 episode CHAR(32) NOT NULL,
 severity INT NOT NULL,
 kind VARCHAR(20) NOT NULL,
 payload LONGTEXT NOT NULL,
 occurrences INT NOT NULL DEFAULT 1,
 normal_count INT NOT NULL DEFAULT 0,
 updated_at DATETIME(6) NOT NULL,
 emitted_at DATETIME(6) NOT NULL,
 pending BOOLEAN NOT NULL DEFAULT FALSE,
 FOREIGN KEY (id_maquina) REFERENCES Maquina(id_maquina) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS DeviceInstallation (
 id_maquina VARCHAR(50) PRIMARY KEY,
 code_hash CHAR(64) NOT NULL UNIQUE,
 expires_at DATETIME NOT NULL,
 server_url VARCHAR(255) NOT NULL,
 FOREIGN KEY (id_maquina) REFERENCES Maquina(id_maquina) ON DELETE CASCADE
);
