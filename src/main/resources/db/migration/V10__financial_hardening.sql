-- ===============================================
-- V10__financial_hardening.sql
-- Production Financial Integrity Lockdown (FINAL FIX)
-- ===============================================

-- Flyway runs inside transaction. No BEGIN/COMMIT.


-- =====================================================
-- 1. DROP ALL DEPENDENT VIEWS (CRITICAL)
-- =====================================================

DROP VIEW IF EXISTS tenancy_balances CASCADE;
DROP VIEW IF EXISTS property_summary CASCADE;


-- =====================================================
-- 2. NORMALIZE EXISTING DATA
-- =====================================================

UPDATE ledger_entries
SET category = 'RENT_CHARGE'
WHERE category IN ('RENT', 'MONTHLY_RENT');

UPDATE ledger_entries
SET category = 'RENT_PAYMENT'
WHERE category IN ('PAYMENT', 'RENT_PAYMENT');


-- =====================================================
-- 3. REMOVE DUPLICATE FUNCTION
-- =====================================================

DROP FUNCTION IF EXISTS process_payment(uuid, numeric, text, text);


-- =====================================================
-- 4. DROP OLD ENUM TYPES
-- =====================================================

DROP TYPE IF EXISTS ledger_category CASCADE;
DROP TYPE IF EXISTS ledger_entry_type CASCADE;


-- =====================================================
-- 5. RECREATE STRICT ENUM TYPES
-- =====================================================

CREATE TYPE ledger_category AS ENUM (
    'RENT_CHARGE',
    'RENT_PAYMENT',
    'WITHDRAWAL',
    'REVERSAL'
);

CREATE TYPE ledger_entry_type AS ENUM (
    'DEBIT',
    'CREDIT'
);


-- =====================================================
-- 6. CONVERT TABLE COLUMNS
-- =====================================================

ALTER TABLE ledger_entries
    ALTER COLUMN category TYPE ledger_category
    USING category::ledger_category;

ALTER TABLE ledger_entries
    ALTER COLUMN entry_type TYPE ledger_entry_type
    USING entry_type::ledger_entry_type;


-- =====================================================
-- 7. RECREATE tenancy_balances VIEW
-- =====================================================

CREATE VIEW tenancy_balances AS
SELECT
    t.id AS tenancy_id,
    COALESCE(
        SUM(
            CASE
                WHEN l.entry_type = 'DEBIT' THEN l.amount
                WHEN l.entry_type = 'CREDIT' THEN -l.amount
                ELSE 0
            END
        ),
        0
    ) AS balance
FROM tenancies t
LEFT JOIN ledger_entries l
    ON l.tenancy_id = t.id
GROUP BY t.id;


-- =====================================================
-- 8. RECREATE property_summary VIEW
-- =====================================================
-- =====================================================
-- 8. RECREATE property_summary VIEW (CORRECTED)
-- =====================================================

CREATE VIEW property_summary AS
SELECT
    p.id AS property_id,
    p.name AS property_name,
    COALESCE(SUM(
        CASE
            WHEN l.entry_type = 'DEBIT' THEN l.amount
            ELSE 0
        END
    ),0) AS total_debits,
    COALESCE(SUM(
        CASE
            WHEN l.entry_type = 'CREDIT' THEN l.amount
            ELSE 0
        END
    ),0) AS total_credits,
    COALESCE(SUM(
        CASE
            WHEN l.entry_type = 'DEBIT' THEN l.amount
            WHEN l.entry_type = 'CREDIT' THEN -l.amount
            ELSE 0
        END
    ),0) AS balance
FROM properties p
LEFT JOIN units u ON u.property_id = p.id
LEFT JOIN tenancies t ON t.unit_id = u.id
LEFT JOIN ledger_entries l ON l.tenancy_id = t.id
GROUP BY p.id, p.name;

-- =====================================================
-- 9. WALLET CREDIT FUNCTION
-- =====================================================

CREATE OR REPLACE FUNCTION credit_landlord_wallet()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.entry_type = 'CREDIT'
       AND NEW.category = 'RENT_PAYMENT' THEN

        UPDATE wallets
        SET balance = balance + NEW.amount
        WHERE landlord_id = (
            SELECT landlord_id
            FROM properties
            WHERE id = NEW.property_id
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =====================================================
-- 10. WALLET PROTECTION
-- =====================================================

ALTER TABLE wallets
DROP CONSTRAINT IF EXISTS wallet_balance_non_negative;

ALTER TABLE wallets
ADD CONSTRAINT wallet_balance_non_negative
CHECK (balance >= 0);


-- =====================================================
-- 11. LEDGER PROTECTION
-- =====================================================

ALTER TABLE ledger_entries
DROP CONSTRAINT IF EXISTS ledger_amount_positive;

ALTER TABLE ledger_entries
ADD CONSTRAINT ledger_amount_positive
CHECK (amount > 0);