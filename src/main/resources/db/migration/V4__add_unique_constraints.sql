CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique
ON users(email);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mpesa_tx_code_unique
ON mpesa_transactions(transaction_code);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_tx_code_unique
ON payments(transaction_code);

CREATE UNIQUE INDEX IF NOT EXISTS idx_units_account_number_unique
ON units(account_number);

CREATE UNIQUE INDEX IF NOT EXISTS idx_units_reference_number_unique
ON units(reference_number);