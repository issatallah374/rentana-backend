-- V1__init.sql

-- Create the "users" table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    phone VARCHAR(20) UNIQUE,
    password_hash TEXT NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('LANDLORD','TENANT','ADMIN')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create the "properties" table
CREATE TABLE properties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL,
    address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL,
    account_prefix VARCHAR(20) UNIQUE NOT NULL,
    landlord_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create the "units" table
CREATE TABLE units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    unit_number VARCHAR(20) NOT NULL,
    account_number VARCHAR(50) UNIQUE NOT NULL,
    reference_number VARCHAR(50) NOT NULL,
    rent_amount NUMERIC(12,2) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    property_id UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (property_id, unit_number)
);

-- Create the "tenancies" table
CREATE TABLE tenancies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES users(id),
    unit_id UUID NOT NULL REFERENCES units(id),
    rent_amount NUMERIC(12,2) NOT NULL,
    start_date DATE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create the "payments" table
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenancy_id UUID NOT NULL REFERENCES tenancies(id),
    amount NUMERIC(12,2) NOT NULL,
    payment_method VARCHAR(20) NOT NULL,
    transaction_code VARCHAR(50),
    payment_date TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create the "ledger_entries" table
CREATE TABLE ledger_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES properties(id),
    entry_type VARCHAR(20) CHECK (entry_type IN ('DEBIT', 'CREDIT')),
    category VARCHAR(50),
    amount NUMERIC(12,2) NOT NULL,
    reference_id UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create the "wallets" table
CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    landlord_id UUID NOT NULL REFERENCES users(id),
    balance NUMERIC(12,2) DEFAULT 0,
    auto_payout_enabled BOOLEAN DEFAULT FALSE,
    admin_approval_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes for better query performance
CREATE INDEX idx_properties_landlord ON properties(landlord_id);
CREATE INDEX idx_units_property ON units(property_id);
CREATE INDEX idx_tenancies_unit ON tenancies(unit_id);
CREATE INDEX idx_payments_tenancy ON payments(tenancy_id);
CREATE INDEX idx_ledger_entries_property ON ledger_entries(property_id);
CREATE INDEX idx_wallets_landlord ON wallets(landlord_id);

-- Optional: Add some sample data (this can be skipped or modified as needed)
INSERT INTO users (full_name, email, phone, password_hash, role) VALUES
('Landlord 1', 'landlord1@rent.com', '1234567890', 'hashedpassword1', 'LANDLORD'),
('Tenant 1', 'tenant1@rent.com', '0987654321', 'hashedpassword2', 'TENANT');

-- You can continue adding other seed data as per your use case
