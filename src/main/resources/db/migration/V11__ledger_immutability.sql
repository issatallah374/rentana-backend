-- ===============================================
-- V11__ledger_immutability.sql
-- Ledger Immutability + Safe Indexing
-- ===============================================


-- =====================================================
-- 1. Prevent UPDATE on ledger_entries
-- =====================================================

CREATE OR REPLACE FUNCTION prevent_ledger_update()
RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'Ledger entries are immutable and cannot be updated';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_ledger_update ON ledger_entries;

CREATE TRIGGER trg_prevent_ledger_update
BEFORE UPDATE ON ledger_entries
FOR EACH ROW
EXECUTE FUNCTION prevent_ledger_update();


-- =====================================================
-- 2. Prevent DELETE on ledger_entries
-- =====================================================

CREATE OR REPLACE FUNCTION prevent_ledger_delete()
RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'Ledger entries cannot be deleted';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_ledger_delete ON ledger_entries;

CREATE TRIGGER trg_prevent_ledger_delete
BEFORE DELETE ON ledger_entries
FOR EACH ROW
EXECUTE FUNCTION prevent_ledger_delete();


-- =====================================================
-- 3. Prevent negative wallet balances (safe)
-- =====================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'wallet_balance_non_negative'
    ) THEN
        ALTER TABLE wallets
        ADD CONSTRAINT wallet_balance_non_negative
        CHECK (balance >= 0);
    END IF;
END
$$;


-- =====================================================
-- 4. Performance indexes (SAFE)
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ledger_tenancy_id
ON ledger_entries(tenancy_id);

CREATE INDEX IF NOT EXISTS idx_units_property_id
ON units(property_id);

CREATE INDEX IF NOT EXISTS idx_tenancies_unit_id
ON tenancies(unit_id);