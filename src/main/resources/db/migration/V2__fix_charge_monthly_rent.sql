-- Drop broken function
DROP FUNCTION IF EXISTS public.charge_monthly_rent();

CREATE OR REPLACE FUNCTION public.charge_monthly_rent()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT
            t.id AS tenancy_id,
            t.rent_amount,
            u.property_id,
            t.last_rent_charged_date
        FROM tenancies t
        JOIN units u ON t.unit_id = u.id
        WHERE t.is_active = true
    LOOP

        -- Prevent double charge within same month
        IF r.last_rent_charged_date IS NULL
           OR date_trunc('month', r.last_rent_charged_date) < date_trunc('month', now())
        THEN

            INSERT INTO ledger_entries(
                property_id,
                tenancy_id,
                entry_type,
                category,
                amount,
                created_at
            )
            VALUES (
                r.property_id,
                r.tenancy_id,
                'DEBIT',
                'MONTHLY_RENT',
                r.rent_amount,
                now()
            );

            UPDATE tenancies
            SET last_rent_charged_date = now()
            WHERE id = r.tenancy_id;

        END IF;

    END LOOP;
END;
$$;