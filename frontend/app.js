-- PostgreSQL database dump
--

\restrict Db6Ii3gPnamMt3FAaMMOShXAhDqTeP7xTWH1ONGJ9sRTd84GdByrtMclwLwkeSU

-- Dumped from database version 18.1 (Ubuntu 18.1-1.pgdg22.04+2)
-- Dumped by pg_dump version 18.1 (Ubuntu 18.1-1.pgdg22.04+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgres
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO postgres;

--
-- Name: ledger_entry_type; Type: TYPE; Schema: public; Owner: rent_user_new
--

CREATE TYPE public.ledger_entry_type AS ENUM (
    'DEBIT',
    'CREDIT'
);


ALTER TYPE public.ledger_entry_type OWNER TO rent_user_new;

--
-- Name: charge_monthly_rent(); Type: FUNCTION; Schema: public; Owner: rent_user_new
--

CREATE FUNCTION public.charge_monthly_rent() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
BEGIN

    FOR r IN
        SELECT 
            t.id AS tenancy_id,
            t.rent_amount,
            u.property_id
        FROM tenancies t
        JOIN units u ON t.unit_id = u.id
        WHERE t.is_active = true
    LOOP

        -- Increase balance
        UPDATE tenancies
        SET balance = balance + r.rent_amount
        WHERE id = r.tenancy_id;

        -- Insert ledger entry (DEBIT)
        INSERT INTO ledger_entries(
            id,
            property_id,
            tenancy_id,
            entry_type,
            category,
            amount,
            created_at
        )
        VALUES (
            gen_random_uuid(),
            r.property_id,
            r.tenancy_id,
            'DEBIT',
            'MONTHLY_RENT',
            r.rent_amount,
            now()
        );

    END LOOP;

END;
$$;


ALTER FUNCTION public.charge_monthly_rent() OWNER TO rent_user_new;

--
-- Name: credit_landlord_wallet(); Type: FUNCTION; Schema: public; Owner: rent_user_new
--

CREATE FUNCTION public.credit_landlord_wallet() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    UPDATE wallets
    SET balance = balance + NEW.amount
    WHERE landlord_id = (
        SELECT p.landlord_id
        FROM tenancies t
        JOIN units u ON t.unit_id = u.id
        JOIN properties p ON u.property_id = p.id
        WHERE t.id = NEW.tenancy_id
    );

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.credit_landlord_wallet() OWNER TO rent_user_new;

--
-- Name: process_payment(uuid, numeric, text, text); Type: FUNCTION; Schema: public; Owner: rent_user_new
--

CREATE FUNCTION public.process_payment(p_tenancy_id uuid, p_amount numeric, p_method text, p_reference text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_receipt text;
BEGIN

-- Generate receipt number
v_receipt := 'RCPT-' || to_char(NOW(), 'YYYYMMDDHH24MISS');

-- Insert payment
INSERT INTO payments (
    tenancy_id,
    amount,
    payment_method,
    transaction_code,
    receipt_number,
    payment_date
)
VALUES (
    p_tenancy_id,
    p_amount,
    p_method,
    p_reference,
    v_receipt,
    NOW()
);

-- Reduce balance
UPDATE tenancies
SET balance = balance - p_amount
WHERE id = p_tenancy_id;

END;
$$;


ALTER FUNCTION public.process_payment(p_tenancy_id uuid, p_amount numeric, p_method text, p_reference text) OWNER TO rent_user_new;

--
-- Name: record_payment_ledger_entry(); Type: FUNCTION; Schema: public; Owner: rent_user_new
--

CREATE FUNCTION public.record_payment_ledger_entry() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

INSERT INTO ledger_entries (
    property_id,
    tenancy_id,
    entry_type,
    category,
    amount,
    reference_id,
    created_at
)
SELECT
    u.property_id,
    NEW.tenancy_id,
    'CREDIT',
    'RENT_PAYMENT',
    NEW.amount,
    NEW.id,
    NOW()
FROM tenancies t
JOIN units u ON u.id = t.unit_id
WHERE t.id = NEW.tenancy_id;

RETURN NEW;

END;
$$;


ALTER FUNCTION public.record_payment_ledger_entry() OWNER TO rent_user_new;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: flyway_schema_history; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.flyway_schema_history (
    installed_rank integer NOT NULL,
    version character varying(50),
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
);


ALTER TABLE public.flyway_schema_history OWNER TO rent_user_new;

--
-- Name: ledger_entries; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.ledger_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    property_id uuid,
    entry_type character varying(255),
    category character varying(255),
    amount numeric(38,2) NOT NULL,
    reference_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    tenancy_id uuid,
    CONSTRAINT ledger_entries_entry_type_check CHECK (((entry_type)::text = ANY (ARRAY[('DEBIT'::character varying)::text, ('CREDIT'::character varying)::text])))
);


ALTER TABLE public.ledger_entries OWNER TO rent_user_new;

--
-- Name: mpesa_transactions; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.mpesa_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    transaction_code character varying(255) NOT NULL,
    phone_number character varying(50),
    account_reference character varying(255),
    amount numeric(18,2),
    raw_payload jsonb,
    processed boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.mpesa_transactions OWNER TO rent_user_new;

--
-- Name: payments; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenancy_id uuid NOT NULL,
    amount numeric(38,2) NOT NULL,
    payment_method character varying(255) NOT NULL,
    transaction_code character varying(255),
    payment_date timestamp without time zone NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    receipt_number character varying(50),
    receipt_url text
);


ALTER TABLE public.payments OWNER TO rent_user_new;

--
-- Name: properties; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.properties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    address character varying(255) NOT NULL,
    city character varying(255) NOT NULL,
    country character varying(255) NOT NULL,
    account_prefix character varying(255) NOT NULL,
    landlord_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.properties OWNER TO rent_user_new;

--
-- Name: tenancies; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.tenancies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    rent_amount numeric(19,2) NOT NULL,
    start_date date NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    rent_due_day integer DEFAULT 1 NOT NULL,
    last_rent_charged_date date
);


ALTER TABLE public.tenancies OWNER TO rent_user_new;

--
-- Name: units; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.units (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    unit_number character varying(255) NOT NULL,
    account_number character varying(255) NOT NULL,
    reference_number character varying(255) NOT NULL,
    rent_amount numeric(38,2) NOT NULL,
    is_active boolean DEFAULT true,
    property_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.units OWNER TO rent_user_new;

--
-- Name: property_summary; Type: VIEW; Schema: public; Owner: rent_user_new
--

CREATE VIEW public.property_summary AS
 SELECT p.id AS property_id,
    count(DISTINCT u.id) AS unit_count,
    count(DISTINCT t.id) FILTER (WHERE (t.is_active = true)) AS active_tenancies,
    COALESCE(sum(t.rent_amount) FILTER (WHERE (t.is_active = true)), (0)::numeric) AS total_expected,
    COALESCE(sum(
        CASE
            WHEN ((l.entry_type)::text = 'CREDIT'::text) THEN l.amount
            ELSE (0)::numeric
        END), (0)::numeric) AS total_collected
   FROM (((public.properties p
     LEFT JOIN public.units u ON ((u.property_id = p.id)))
     LEFT JOIN public.tenancies t ON ((t.unit_id = u.id)))
     LEFT JOIN public.ledger_entries l ON ((l.property_id = p.id)))
  GROUP BY p.id;


ALTER VIEW public.property_summary OWNER TO rent_user_new;

--
-- Name: tenancy_balances; Type: VIEW; Schema: public; Owner: rent_user_new
--

CREATE VIEW public.tenancy_balances AS
 SELECT tenancy_id,
    sum(
        CASE
            WHEN ((entry_type)::text = 'DEBIT'::text) THEN amount
            WHEN ((entry_type)::text = 'CREDIT'::text) THEN (- amount)
            ELSE NULL::numeric
        END) AS balance
   FROM public.ledger_entries
  GROUP BY tenancy_id;


ALTER VIEW public.tenancy_balances OWNER TO rent_user_new;

--
-- Name: tenants; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.tenants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    full_name character varying(255) NOT NULL,
    phone_number character varying(50) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.tenants OWNER TO rent_user_new;

--
-- Name: users; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    full_name character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    phone character varying(255),
    password_hash character varying(255) NOT NULL,
    role character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT users_role_check CHECK (((role)::text = ANY (ARRAY[('LANDLORD'::character varying)::text, ('TENANT'::character varying)::text, ('ADMIN'::character varying)::text])))
);


ALTER TABLE public.users OWNER TO rent_user_new;

--
-- Name: wallets; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.wallets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    landlord_id uuid NOT NULL,
    balance numeric(38,2) DEFAULT 0,
    auto_payout_enabled boolean DEFAULT false,
    admin_approval_enabled boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.wallets OWNER TO rent_user_new;

--
-- Data for Name: flyway_schema_history; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success) FROM stdin;
1       1       init    SQL     V1__init.sql    1333074512      rent_user_new   2026-02-18 15:17:21.81914639      t
\.


--
-- Data for Name: ledger_entries; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.ledger_entries (id, property_id, entry_type, category, amount, reference_id, created_at, tenancy_id) FROM stdin;
\.


--
-- Data for Name: mpesa_transactions; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.mpesa_transactions (id, transaction_code, phone_number, account_reference, amount, raw_payload, processed, created_at) FROM stdin;
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.payments (id, tenancy_id, amount, payment_method, transaction_code, payment_date, created_at, receipt_number, receipt_url) FROM stdin;
\.


--
-- Data for Name: properties; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.properties (id, name, address, city, country, account_prefix, landlord_id, created_at) FROM stdin;
\.


--
-- Data for Name: tenancies; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.tenancies (id, tenant_id, unit_id, rent_amount, start_date, is_active, created_at, rent_due_day, last_rent_charged_date) FROM stdin;
\.


--
-- Data for Name: tenants; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.tenants (id, full_name, phone_number, is_active, created_at) FROM stdin;
\.


--
-- Data for Name: units; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.units (id, unit_number, account_number, reference_number, rent_amount, is_active, property_id, created_at) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.users (id, full_name, email, phone, password_hash, role, is_active, created_at) FROM stdin;
\.


--
-- Data for Name: wallets; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.wallets (id, landlord_id, balance, auto_payout_enabled, admin_approval_enabled, created_at) FROM stdin;
\.


--
-- Name: flyway_schema_history flyway_schema_history_pk; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.flyway_schema_history
    ADD CONSTRAINT flyway_schema_history_pk PRIMARY KEY (installed_rank);


--
-- Name: ledger_entries ledger_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_pkey PRIMARY KEY (id);


--
-- Name: mpesa_transactions mpesa_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.mpesa_transactions
    ADD CONSTRAINT mpesa_transactions_pkey PRIMARY KEY (id);


--
-- Name: mpesa_transactions mpesa_transactions_transaction_code_key; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.mpesa_transactions
    ADD CONSTRAINT mpesa_transactions_transaction_code_key UNIQUE (transaction_code);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: properties properties_account_prefix_key; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_account_prefix_key UNIQUE (account_prefix);


--
-- Name: properties properties_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_pkey PRIMARY KEY (id);


--
-- Name: tenancies tenancies_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: units uktah7k94bauuojgt37fwjf0cch; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT uktah7k94bauuojgt37fwjf0cch UNIQUE (account_number);


--
-- Name: properties unique_account_prefix; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT unique_account_prefix UNIQUE (account_prefix);


--
-- Name: units unique_reference_number; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT unique_reference_number UNIQUE (reference_number);


--
-- Name: payments unique_transaction_code; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT unique_transaction_code UNIQUE (transaction_code);


--
-- Name: units unique_unit_per_property; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT unique_unit_per_property UNIQUE (property_id, unit_number);


--
-- Name: units units_account_number_key; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_account_number_key UNIQUE (account_number);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (id);


--
-- Name: units units_property_id_unit_number_key; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_property_id_unit_number_key UNIQUE (property_id, unit_number);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);


--
-- Name: flyway_schema_history_s_idx; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX flyway_schema_history_s_idx ON public.flyway_schema_history USING btree (success);


--
-- Name: idx_ledger_entries_property; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_ledger_entries_property ON public.ledger_entries USING btree (property_id);


--
-- Name: idx_ledger_tenancy_id; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_ledger_tenancy_id ON public.ledger_entries USING btree (tenancy_id);


--
-- Name: idx_payments_tenancy; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_payments_tenancy ON public.payments USING btree (tenancy_id);


--
-- Name: idx_payments_tenancy_id; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_payments_tenancy_id ON public.payments USING btree (tenancy_id);


--
-- Name: idx_properties_landlord; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_properties_landlord ON public.properties USING btree (landlord_id);


--
-- Name: idx_tenancies_unit; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_tenancies_unit ON public.tenancies USING btree (unit_id);


--
-- Name: idx_tenancies_unit_id; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_tenancies_unit_id ON public.tenancies USING btree (unit_id);


--
-- Name: idx_units_property; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_units_property ON public.units USING btree (property_id);


--
-- Name: idx_units_property_id; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_units_property_id ON public.units USING btree (property_id);


--
-- Name: idx_wallets_landlord; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_wallets_landlord ON public.wallets USING btree (landlord_id);


--
-- Name: uq_active_tenancy_per_unit; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE UNIQUE INDEX uq_active_tenancy_per_unit ON public.tenancies USING btree (unit_id) WHERE (is_active = true);


--
-- Name: payments trigger_credit_wallet; Type: TRIGGER; Schema: public; Owner: rent_user_new
--

CREATE TRIGGER trigger_credit_wallet AFTER INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION public.credit_landlord_wallet();


--
-- Name: payments trigger_payment_ledger; Type: TRIGGER; Schema: public; Owner: rent_user_new
--

CREATE TRIGGER trigger_payment_ledger AFTER INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION public.record_payment_ledger_entry();


--
-- Name: ledger_entries ledger_entries_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id);


--
-- Name: ledger_entries ledger_entries_tenancy_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_tenancy_fkey FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE CASCADE;


--
-- Name: payments payments_tenancy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_tenancy_id_fkey FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id);


--
-- Name: properties properties_landlord_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_landlord_id_fkey FOREIGN KEY (landlord_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tenancies tenancies_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: tenancies tenancies_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id);


--
-- Name: units units_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: wallets wallets_landlord_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_landlord_id_fkey FOREIGN KEY (landlord_id) REFERENCES public.users(id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

\unrestrict Db6Ii3gPnamMt3FAaMMOShXAhDqTeP7xTWH1ONGJ9sRTd84GdByrtMclwLwkeSU
