ALTER TABLE TelegramChannel ADD COLUMN IF NOT EXISTS destination_hash CHAR(64) NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_telegram_destination ON TelegramChannel(destination_hash);
