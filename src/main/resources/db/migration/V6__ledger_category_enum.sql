-- 1. Create enum if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_type WHERE typname = 'ledger_category'
    ) THEN
        CREATE TYPE ledger_category AS ENUM (
            'RENT',
            'PAYMENT',
            'WITHDRAWAL',
            'REVERSAL'
        );
    END IF;
END$$;

-- 2. Add column if not exists
ALTER TABLE ledger_entries
ADD COLUMN IF NOT EXISTS category ledger_category;

-- 3. If column existed as text before, convert safely (optional safety)
-- (Only runs if column is text)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name='ledger_entries'
        AND column_name='category'
        AND data_type='text'
    ) THEN
        ALTER TABLE ledger_entries
        ALTER COLUMN category TYPE ledger_category
        USING category::ledger_category;
    END IF;
END$$;