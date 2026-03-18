ALTER TABLE properties
ADD CONSTRAINT fk_properties_landlord
FOREIGN KEY (landlord_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE units
ADD CONSTRAINT fk_units_property
FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE;

ALTER TABLE tenancies
ADD CONSTRAINT fk_tenancies_unit
FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE;

ALTER TABLE tenancies
ADD CONSTRAINT fk_tenancies_tenant
FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;

ALTER TABLE payments
ADD CONSTRAINT fk_payments_tenancy
FOREIGN KEY (tenancy_id) REFERENCES tenancies(id) ON DELETE CASCADE;

ALTER TABLE wallets
ADD CONSTRAINT fk_wallets_landlord
FOREIGN KEY (landlord_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ledger_entries
ADD CONSTRAINT fk_ledger_property
FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE CASCADE;

ALTER TABLE ledger_entries
ADD CONSTRAINT fk_ledger_tenancy
FOREIGN KEY (tenancy_id) REFERENCES tenancies(id) ON DELETE CASCADE;