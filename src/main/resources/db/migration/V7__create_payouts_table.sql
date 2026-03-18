CREATE TYPE payout_status AS ENUM (
    'PENDING',
    'APPROVED',
    'SENT',
    'FAILED'
);

CREATE TABLE payouts (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    landlord_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount numeric(38,2) NOT NULL,
    transaction_cost numeric(18,2) DEFAULT 0,
    status payout_status DEFAULT 'PENDING',
    mpesa_reference varchar(255),
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    processed_at timestamp
);