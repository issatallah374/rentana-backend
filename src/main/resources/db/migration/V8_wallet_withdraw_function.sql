CREATE OR REPLACE FUNCTION withdraw_from_wallet(
    p_landlord_id uuid,
    p_amount numeric
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance numeric;
BEGIN

    SELECT balance INTO v_balance
    FROM wallets
    WHERE landlord_id = p_landlord_id
    FOR UPDATE;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient wallet balance';
    END IF;

    UPDATE wallets
    SET balance = balance - p_amount
    WHERE landlord_id = p_landlord_id;

    INSERT INTO ledger_entries(
        property_id,
        entry_type,
        category,
        amount,
        created_at
    )
    VALUES (
        NULL,
        'DEBIT',
        'LANDLORD_PAYOUT',
        p_amount,
        now()
    );

END;
$$;