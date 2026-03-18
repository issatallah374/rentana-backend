CREATE INDEX IF NOT EXISTS idx_payments_tenancy
ON payments(tenancy_id);

CREATE INDEX IF NOT EXISTS idx_payments_created_at
ON payments(created_at);

CREATE INDEX IF NOT EXISTS idx_mpesa_created_at
ON mpesa_transactions(created_at);

CREATE INDEX IF NOT EXISTS idx_units_property
ON units(property_id);

CREATE INDEX IF NOT EXISTS idx_tenancies_unit
ON tenancies(unit_id);

CREATE INDEX IF NOT EXISTS idx_wallets_landlord
ON wallets(landlord_id);