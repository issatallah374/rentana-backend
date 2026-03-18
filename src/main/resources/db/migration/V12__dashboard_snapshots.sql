CREATE TABLE dashboard_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL,
    year INT NOT NULL,
    month INT NOT NULL,
    rent_expected NUMERIC(12,2) NOT NULL,
    rent_collected NUMERIC(12,2) NOT NULL,
    arrears NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT now(),

    CONSTRAINT fk_snapshot_property
        FOREIGN KEY (property_id)
        REFERENCES properties(id)
        ON DELETE CASCADE,

    CONSTRAINT unique_property_month
        UNIQUE(property_id, year, month)
);
