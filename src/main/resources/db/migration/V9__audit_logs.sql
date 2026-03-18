CREATE TABLE audit_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES users(id),
    action varchar(255),
    entity_type varchar(255),
    entity_id uuid,
    metadata jsonb,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP
);