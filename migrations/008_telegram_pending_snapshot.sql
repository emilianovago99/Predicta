-- Keep the most severe unsent incident separate from the current machine state.
ALTER TABLE MachineAlert ADD COLUMN IF NOT EXISTS pending_payload LONGTEXT NULL;
ALTER TABLE MachineAlert ADD COLUMN IF NOT EXISTS pending_revision CHAR(32) NULL;
UPDATE MachineAlert
SET pending_payload=payload, pending_revision=REPLACE(UUID(), '-', '')
WHERE pending=1 AND pending_payload IS NULL;
