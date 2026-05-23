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

    -- Lock wallet row during transaction
    SELECT balance
    INTO v_balance
    FROM wallets
    WHERE landlord_id = p_landlord_id
    FOR UPDATE;

    -- Validate wallet exists
    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'Wallet not found';
    END IF;

    -- Prevent invalid withdrawals
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Withdrawal amount must be greater than zero';
    END IF;

    -- Prevent overdraft
    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient wallet balance';
    END IF;

    -- Deduct balance
    UPDATE wallets
    SET balance = balance - p_amount
    WHERE landlord_id = p_landlord_id;

    -- Create immutable ledger record
    INSERT INTO ledger_entries(
        property_id,
        tenancy_id,
        entry_type,
        category,
        amount,
        reference,
        reference_id,
        entry_month,
        entry_year,
        created_at
    )
    VALUES (
        NULL,
        NULL,
        'DEBIT',
        'LANDLORD_PAYOUT',
        p_amount,
        CONCAT(
            'WITHDRAWAL-',
            EXTRACT(EPOCH FROM now())::bigint
        ),
        NULL,
        EXTRACT(MONTH FROM now()),
        EXTRACT(YEAR FROM now()),
        now()
    );

END;
$$;