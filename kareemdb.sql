--
-- PostgreSQL database dump
--

\restrict 6l3lgtnuwt1Fii1yG0qxAbrbHevZuMijRKn9ge1LrFztB0ETX5y63fHpwCMR1f5

-- Dumped from database version 18.3 (Debian 18.3-1.pgdg12+1)
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
-- Name: public; Type: SCHEMA; Schema: -; Owner: spin
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO spin;

--
-- Name: ledger_category; Type: TYPE; Schema: public; Owner: spin
--

CREATE TYPE public.ledger_category AS ENUM (
    'RENT_CHARGE',
    'RENT_PAYMENT',
    'WITHDRAWAL',
    'REVERSAL',
    'MONTHLY_RENT',
    'PAYOUT'
);


ALTER TYPE public.ledger_category OWNER TO spin;

--
-- Name: ledger_entry_type; Type: TYPE; Schema: public; Owner: spin
--

CREATE TYPE public.ledger_entry_type AS ENUM (
    'DEBIT',
    'CREDIT',
    'RENT_CHARGE',
    'PAYMENT'
);


ALTER TYPE public.ledger_entry_type OWNER TO spin;

--
-- Name: payout_status; Type: TYPE; Schema: public; Owner: spin
--

CREATE TYPE public.payout_status AS ENUM (
    'PENDING',
    'APPROVED',
    'SENT',
    'FAILED'
);


ALTER TYPE public.payout_status OWNER TO spin;

--
-- Name: approve_withdrawal(uuid, uuid); Type: FUNCTION; Schema: public; Owner: spin
--

CREATE FUNCTION public.approve_withdrawal(p_request_id uuid, p_admin_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_property_id UUID;
    v_amount NUMERIC;
BEGIN

    SELECT property_id, amount
    INTO v_property_id, v_amount
    FROM payout_requests
    WHERE id = p_request_id
    AND status = 'PENDING';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or already processed request';
    END IF;

    UPDATE payout_requests
    SET status = 'PAID',
        processed_at = now()
    WHERE id = p_request_id;

    INSERT INTO ledger_entries (
        property_id,
        entry_type,
        category,
        amount,
        entry_month,
        entry_year,
        created_at,
        reference
    )
    VALUES (
        v_property_id,
        'DEBIT',
        'PAYOUT',
        v_amount,
        EXTRACT(MONTH FROM now()),
        EXTRACT(YEAR FROM now()),
        now(),
        'PAYOUT:' || p_request_id
    );

    INSERT INTO audit_logs (
        user_id,
        action,
        entity_type,
        entity_id,
        metadata
    )
    VALUES (
        p_admin_id,
        'APPROVE_WITHDRAWAL',
        'PAYOUT_REQUEST',
        p_request_id,
        jsonb_build_object('amount', v_amount)
    );

END;
$$;


ALTER FUNCTION public.approve_withdrawal(p_request_id uuid, p_admin_id uuid) OWNER TO spin;

--
-- Name: charge_monthly_rent(); Type: FUNCTION; Schema: public; Owner: spin
--

CREATE FUNCTION public.charge_monthly_rent() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
    v_month INT := EXTRACT(MONTH FROM now());
    v_year INT := EXTRACT(YEAR FROM now());
BEGIN

    FOR r IN
        SELECT
            t.id AS tenancy_id,
            t.rent_amount,
            u.property_id,
            t.last_rent_charged_date,
            t.rent_due_day
        FROM tenancies t
        JOIN units u ON t.unit_id = u.id
        WHERE t.is_active = true
    LOOP

        -- Charge only if:
        -- 1. Not charged this month
        -- 2. Today >= due day

        IF (
            r.last_rent_charged_date IS NULL OR
            date_trunc('month', r.last_rent_charged_date) < date_trunc('month', now())
        )
        AND EXTRACT(DAY FROM now()) >= r.rent_due_day
        THEN

            INSERT INTO ledger_entries(
                property_id,
                tenancy_id,
                entry_type,
                category,
                amount,
                created_at,
                entry_month,
                entry_year
            )
            VALUES (
                r.property_id,
                r.tenancy_id,
                'DEBIT',
                'MONTHLY_RENT',
                r.rent_amount,
                now(),
                v_month,
                v_year
            );

            UPDATE tenancies
            SET last_rent_charged_date = now()
            WHERE id = r.tenancy_id;

        END IF;

    END LOOP;

END;
$$;


ALTER FUNCTION public.charge_monthly_rent() OWNER TO spin;

--
-- Name: generate_monthly_snapshot(integer, integer); Type: FUNCTION; Schema: public; Owner: spin
--

CREATE FUNCTION public.generate_monthly_snapshot(p_year integer, p_month integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

    INSERT INTO dashboard_snapshots (
        property_id,
        year,
        month,
        rent_expected,
        rent_collected,
        arrears
    )
    SELECT
        property_id,
        p_year,
        p_month,

        COALESCE(SUM(
            CASE WHEN entry_type = 'DEBIT' THEN amount END
        ), 0),

        COALESCE(SUM(
            CASE WHEN entry_type = 'CREDIT' THEN amount END
        ), 0),

        COALESCE(SUM(
            CASE
                WHEN entry_type = 'DEBIT' THEN amount
                WHEN entry_type = 'CREDIT' THEN -amount
            END
        ), 0)

    FROM ledger_entries
    WHERE entry_year = p_year
      AND entry_month = p_month
    GROUP BY property_id

    ON CONFLICT (property_id, year, month)
    DO UPDATE SET
        rent_expected = EXCLUDED.rent_expected,
        rent_collected = EXCLUDED.rent_collected,
        arrears = EXCLUDED.arrears,
        created_at = now();

END;
$$;


ALTER FUNCTION public.generate_monthly_snapshot(p_year integer, p_month integer) OWNER TO spin;

--
-- Name: prevent_ledger_delete(); Type: FUNCTION; Schema: public; Owner: spin
--

CREATE FUNCTION public.prevent_ledger_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'Ledger entries cannot be deleted';
END;
$$;


ALTER FUNCTION public.prevent_ledger_delete() OWNER TO spin;

--
-- Name: prevent_ledger_update(); Type: FUNCTION; Schema: public; Owner: spin
--

CREATE FUNCTION public.prevent_ledger_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'Ledger entries are immutable and cannot be updated';
END;
$$;


ALTER FUNCTION public.prevent_ledger_update() OWNER TO spin;

--
-- Name: process_payment(uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: spin
--

CREATE FUNCTION public.process_payment(p_tenancy_id uuid, p_amount numeric, p_reference text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_property_id UUID;
    v_remaining NUMERIC := p_amount;
    r RECORD;
BEGIN

    -- 🛑 Prevent duplicates
    IF EXISTS (
        SELECT 1 FROM payments WHERE transaction_code = p_reference
    ) THEN
        RAISE NOTICE 'Duplicate payment ignored: %', p_reference;
        RETURN;
    END IF;

    -- 💰 Save payment
    INSERT INTO payments (
        tenancy_id,
        amount,
        payment_method,
        transaction_code,
        payment_date,
        created_at
    )
    VALUES (
        p_tenancy_id,
        p_amount,
        'MPESA',
        p_reference,
        NOW(),
        NOW()
    );

    -- 🏠 Get property
    SELECT u.property_id
    INTO v_property_id
    FROM tenancies t
    JOIN units u ON u.id = t.unit_id
    WHERE t.id = p_tenancy_id;

    -- 🔁 LOOP THROUGH DEBTS (FIFO)
    FOR r IN
        SELECT
            entry_year,
            entry_month,
            SUM(
                CASE
                    WHEN entry_type = 'DEBIT' THEN amount
                    WHEN entry_type = 'CREDIT' THEN -amount
                END
            ) AS balance
        FROM ledger_entries
        WHERE tenancy_id = p_tenancy_id
        GROUP BY entry_year, entry_month
        HAVING SUM(
            CASE
                WHEN entry_type = 'DEBIT' THEN amount
                WHEN entry_type = 'CREDIT' THEN -amount
            END
        ) > 0
        ORDER BY entry_year, entry_month
    LOOP

        EXIT WHEN v_remaining <= 0;

        -- 🔒 Prevent null crash
        IF r.entry_month IS NULL OR r.entry_year IS NULL THEN
            CONTINUE;
        END IF;

        IF v_remaining >= r.balance THEN

            -- ✅ FULL PAYMENT
            INSERT INTO ledger_entries (
                property_id,
                tenancy_id,
                entry_type,
                category,
                amount,
                reference,
                entry_month,
                entry_year,
                created_at
            )
            VALUES (
                v_property_id,
                p_tenancy_id,
                'CREDIT',
                'RENT_PAYMENT',
                r.balance,
                p_reference,
                r.entry_month,
                r.entry_year,
                NOW()
            );

            v_remaining := v_remaining - r.balance;

        ELSE

            -- ✅ PARTIAL PAYMENT
            INSERT INTO ledger_entries (
                property_id,
                tenancy_id,
                entry_type,
                category,
                amount,
                reference,
                entry_month,
                entry_year,
                created_at
            )
            VALUES (
                v_property_id,
                p_tenancy_id,
                'CREDIT',
                'RENT_PAYMENT',
                v_remaining,
                p_reference,
                r.entry_month,
                r.entry_year,
                NOW()
            );

            v_remaining := 0;
        END IF;

    END LOOP;

    -- 🆕 REMAINING → CURRENT MONTH
    IF v_remaining > 0 THEN
        INSERT INTO ledger_entries (
            property_id,
            tenancy_id,
            entry_type,
            category,
            amount,
            reference,
            entry_month,
            entry_year,
            created_at
        )
        VALUES (
            v_property_id,
            p_tenancy_id,
            'CREDIT',
            'RENT_PAYMENT',
            v_remaining,
            p_reference,
            EXTRACT(MONTH FROM NOW())::INT,
            EXTRACT(YEAR FROM NOW())::INT,
            NOW()
        );
    END IF;

    -- 💰 UPDATE WALLET
    UPDATE wallets
    SET balance = balance + p_amount
    WHERE property_id = v_property_id;

    RAISE NOTICE '✅ Payment allocated successfully';

END;
$$;


ALTER FUNCTION public.process_payment(p_tenancy_id uuid, p_amount numeric, p_reference text) OWNER TO spin;

--
-- Name: process_payment_by_reference(text); Type: FUNCTION; Schema: public; Owner: spin
--

CREATE FUNCTION public.process_payment_by_reference(p_ref text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_tenancy UUID;
    v_amount NUMERIC;
BEGIN

    SELECT t.id, m.amount
    INTO v_tenancy, v_amount
    FROM mpesa_transactions m
    JOIN units u ON u.reference_number = m.account_reference
    JOIN tenancies t ON t.unit_id = u.id AND t.is_active = true
    WHERE m.transaction_code = p_ref;

    IF v_tenancy IS NULL THEN
        RAISE EXCEPTION 'Tenancy not found';
    END IF;

    PERFORM process_payment(v_tenancy, v_amount, p_ref);

END;
$$;


ALTER FUNCTION public.process_payment_by_reference(p_ref text) OWNER TO spin;

--
-- Name: request_withdrawal(uuid, uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: spin
--

CREATE FUNCTION public.request_withdrawal(p_landlord_id uuid, p_property_id uuid, p_amount numeric, p_phone text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_balance NUMERIC;
BEGIN

    -- 🔍 Get wallet balance
    SELECT balance INTO v_balance
    FROM wallet_balances
    WHERE property_id = p_property_id;

    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'Wallet not found';
    END IF;

    -- 🚫 Prevent overdraft
    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance. Available: %, Requested: %', v_balance, p_amount;
    END IF;

    -- 🚫 Prevent multiple pending withdrawals
    IF EXISTS (
        SELECT 1 FROM payout_requests
        WHERE property_id = p_property_id
        AND status = 'PENDING'
    ) THEN
        RAISE EXCEPTION 'There is already a pending withdrawal';
    END IF;

    -- ✅ Insert safely
    INSERT INTO payout_requests (
        landlord_id,
        property_id,
        amount,
        method,
        destination,
        status,
        created_at
    )
    VALUES (
        p_landlord_id,
        p_property_id,
        p_amount,
        'MPESA',
        p_phone,
        'PENDING',
        now()
    );

END;
$$;


ALTER FUNCTION public.request_withdrawal(p_landlord_id uuid, p_property_id uuid, p_amount numeric, p_phone text) OWNER TO spin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    action character varying(255),
    entity_type character varying(255),
    entity_id uuid,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.audit_logs OWNER TO spin;

--
-- Name: dashboard_snapshots; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.dashboard_snapshots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    property_id uuid NOT NULL,
    year integer NOT NULL,
    month integer NOT NULL,
    rent_expected numeric(12,2) NOT NULL,
    rent_collected numeric(12,2) NOT NULL,
    arrears numeric(12,2) NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.dashboard_snapshots OWNER TO spin;

--
-- Name: flyway_schema_history; Type: TABLE; Schema: public; Owner: spin
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


ALTER TABLE public.flyway_schema_history OWNER TO spin;

--
-- Name: ledger_entries; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.ledger_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    property_id uuid,
    entry_type public.ledger_entry_type,
    category public.ledger_category,
    amount numeric(38,2) NOT NULL,
    reference_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    tenancy_id uuid,
    reference text,
    entry_month integer DEFAULT EXTRACT(month FROM now()) NOT NULL,
    entry_year integer DEFAULT EXTRACT(year FROM now()) NOT NULL,
    CONSTRAINT ledger_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT ledger_entries_entry_type_check CHECK (((entry_type)::text = ANY (ARRAY[('DEBIT'::character varying)::text, ('CREDIT'::character varying)::text])))
);


ALTER TABLE public.ledger_entries OWNER TO spin;

--
-- Name: mpesa_transactions; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.mpesa_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    transaction_code text NOT NULL,
    phone_number text,
    account_reference text,
    amount numeric(18,2),
    raw_payload jsonb,
    processed boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    retry_count integer DEFAULT 0,
    last_attempt_at timestamp without time zone,
    error_message text
);


ALTER TABLE public.mpesa_transactions OWNER TO spin;

--
-- Name: payments; Type: TABLE; Schema: public; Owner: spin
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
    receipt_url text,
    processed_at timestamp without time zone DEFAULT now(),
    status character varying(20) DEFAULT 'SUCCESS'::character varying NOT NULL
);


ALTER TABLE public.payments OWNER TO spin;

--
-- Name: payout_requests; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.payout_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    landlord_id uuid NOT NULL,
    property_id uuid NOT NULL,
    amount numeric(18,2) NOT NULL,
    method character varying(20),
    destination text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    processed_at timestamp without time zone,
    status character varying(20) DEFAULT 'PENDING'::character varying,
    national_id character varying(50),
    processed_by uuid,
    CONSTRAINT payout_requests_status_check CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'PAID'::character varying, 'REJECTED'::character varying])::text[])))
);


ALTER TABLE public.payout_requests OWNER TO spin;

--
-- Name: payouts; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.payouts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    landlord_id uuid NOT NULL,
    amount numeric(38,2) NOT NULL,
    transaction_cost numeric(18,2) DEFAULT 0,
    status public.payout_status DEFAULT 'PENDING'::public.payout_status,
    mpesa_reference character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    processed_at timestamp without time zone
);


ALTER TABLE public.payouts OWNER TO spin;

--
-- Name: platform_transactions; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.platform_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    landlord_id uuid,
    amount numeric(38,2),
    reference text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.platform_transactions OWNER TO spin;

--
-- Name: platform_wallet; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.platform_wallet (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    balance numeric(38,2) DEFAULT 0,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.platform_wallet OWNER TO spin;

--
-- Name: properties; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.properties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    address character varying(255) NOT NULL,
    city character varying(255) NOT NULL,
    country character varying(255) NOT NULL,
    account_prefix character varying(255) NOT NULL,
    landlord_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    payout_setup_complete boolean DEFAULT false NOT NULL
);


ALTER TABLE public.properties OWNER TO spin;

--
-- Name: tenancies; Type: TABLE; Schema: public; Owner: spin
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


ALTER TABLE public.tenancies OWNER TO spin;

--
-- Name: units; Type: TABLE; Schema: public; Owner: spin
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


ALTER TABLE public.units OWNER TO spin;

--
-- Name: property_summary; Type: VIEW; Schema: public; Owner: spin
--

CREATE VIEW public.property_summary AS
 SELECT p.id AS property_id,
    count(DISTINCT u.id) AS unit_count,
    count(DISTINCT t.id) FILTER (WHERE (t.is_active = true)) AS active_tenancies,
    COALESCE(sum(
        CASE
            WHEN (l.entry_type = 'DEBIT'::public.ledger_entry_type) THEN l.amount
            ELSE NULL::numeric
        END), (0)::numeric) AS total_expected,
    COALESCE(sum(
        CASE
            WHEN (l.entry_type = 'CREDIT'::public.ledger_entry_type) THEN l.amount
            ELSE NULL::numeric
        END), (0)::numeric) AS total_collected
   FROM (((public.properties p
     LEFT JOIN public.units u ON ((u.property_id = p.id)))
     LEFT JOIN public.tenancies t ON ((t.unit_id = u.id)))
     LEFT JOIN public.ledger_entries l ON ((l.tenancy_id = t.id)))
  GROUP BY p.id;


ALTER VIEW public.property_summary OWNER TO spin;

--
-- Name: sms_logs; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.sms_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recipient character varying(50),
    message text,
    status character varying(50),
    provider_response text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.sms_logs OWNER TO spin;

--
-- Name: stk_requests; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.stk_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    checkout_request_id character varying(255) NOT NULL,
    merchant_request_id character varying(255),
    landlord_id uuid NOT NULL,
    phone_number character varying(20),
    amount numeric(10,2),
    status character varying(20) DEFAULT 'PENDING'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    plan_id uuid NOT NULL
);


ALTER TABLE public.stk_requests OWNER TO spin;

--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.subscription_plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50),
    property_limit integer,
    price numeric(10,2),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.subscription_plans OWNER TO spin;

--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    landlord_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    start_date timestamp without time zone,
    end_date timestamp without time zone,
    status character varying(20) DEFAULT 'ACTIVE'::character varying,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.subscriptions OWNER TO spin;

--
-- Name: tenancy_balances; Type: VIEW; Schema: public; Owner: spin
--

CREATE VIEW public.tenancy_balances AS
 SELECT t.id AS tenancy_id,
    COALESCE(sum(
        CASE
            WHEN (l.entry_type = 'DEBIT'::public.ledger_entry_type) THEN l.amount
            ELSE NULL::numeric
        END), (0)::numeric) AS total_charged,
    COALESCE(sum(
        CASE
            WHEN (l.entry_type = 'CREDIT'::public.ledger_entry_type) THEN l.amount
            ELSE NULL::numeric
        END), (0)::numeric) AS total_paid,
    COALESCE(sum(
        CASE
            WHEN (l.entry_type = 'DEBIT'::public.ledger_entry_type) THEN l.amount
            WHEN (l.entry_type = 'CREDIT'::public.ledger_entry_type) THEN (- l.amount)
            ELSE NULL::numeric
        END), (0)::numeric) AS raw_balance,
    abs(COALESCE(sum(
        CASE
            WHEN (l.entry_type = 'DEBIT'::public.ledger_entry_type) THEN l.amount
            WHEN (l.entry_type = 'CREDIT'::public.ledger_entry_type) THEN (- l.amount)
            ELSE NULL::numeric
        END), (0)::numeric)) AS balance,
        CASE
            WHEN (COALESCE(sum(
            CASE
                WHEN (l.entry_type = 'DEBIT'::public.ledger_entry_type) THEN l.amount
                WHEN (l.entry_type = 'CREDIT'::public.ledger_entry_type) THEN (- l.amount)
                ELSE NULL::numeric
            END), (0)::numeric) > (0)::numeric) THEN 'OWING'::text
            WHEN (COALESCE(sum(
            CASE
                WHEN (l.entry_type = 'DEBIT'::public.ledger_entry_type) THEN l.amount
                WHEN (l.entry_type = 'CREDIT'::public.ledger_entry_type) THEN (- l.amount)
                ELSE NULL::numeric
            END), (0)::numeric) < (0)::numeric) THEN 'PAID_EXTRA'::text
            ELSE 'CLEARED'::text
        END AS status
   FROM (public.tenancies t
     LEFT JOIN public.ledger_entries l ON ((l.tenancy_id = t.id)))
  GROUP BY t.id;


ALTER VIEW public.tenancy_balances OWNER TO spin;

--
-- Name: tenants; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.tenants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    full_name character varying(255) NOT NULL,
    phone_number character varying(50) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.tenants OWNER TO spin;

--
-- Name: users; Type: TABLE; Schema: public; Owner: spin
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
    payout_locked boolean DEFAULT false,
    payout_setup_complete boolean DEFAULT false,
    national_id_hash character varying(255),
    CONSTRAINT users_role_check CHECK (((role)::text = ANY (ARRAY[('LANDLORD'::character varying)::text, ('TENANT'::character varying)::text, ('ADMIN'::character varying)::text])))
);


ALTER TABLE public.users OWNER TO spin;

--
-- Name: wallet_balances; Type: VIEW; Schema: public; Owner: spin
--

CREATE VIEW public.wallet_balances AS
 SELECT property_id,
    COALESCE(sum(
        CASE
            WHEN (entry_type = 'CREDIT'::public.ledger_entry_type) THEN amount
            WHEN ((entry_type = 'DEBIT'::public.ledger_entry_type) AND (category = 'PAYOUT'::public.ledger_category)) THEN (- amount)
            ELSE NULL::numeric
        END), (0)::numeric) AS balance
   FROM public.ledger_entries
  GROUP BY property_id;


ALTER VIEW public.wallet_balances OWNER TO spin;

--
-- Name: wallets; Type: TABLE; Schema: public; Owner: spin
--

CREATE TABLE public.wallets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    balance numeric(38,2) DEFAULT 0,
    auto_payout_enabled boolean DEFAULT false,
    admin_approval_enabled boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    property_id uuid NOT NULL,
    bank_name character varying(100),
    account_number character varying(100),
    mpesa_phone character varying(20),
    pin_hash text,
    national_id text,
    phone_number text,
    otp_code text,
    otp_expiry timestamp without time zone,
    CONSTRAINT valid_bank_account CHECK (((account_number IS NULL) OR ((account_number)::text !~ '^07'::text))),
    CONSTRAINT wallet_balance_non_negative CHECK ((balance >= (0)::numeric))
);


ALTER TABLE public.wallets OWNER TO spin;

--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.audit_logs (id, user_id, action, entity_type, entity_id, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: dashboard_snapshots; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.dashboard_snapshots (id, property_id, year, month, rent_expected, rent_collected, arrears, created_at) FROM stdin;
\.


--
-- Data for Name: flyway_schema_history; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success) FROM stdin;
1	1	init	SQL	V1__init.sql	1333074512	rent_user_new	2026-02-18 15:17:21.819146	39	t
2	2	fix charge monthly rent	SQL	V2__fix_charge_monthly_rent.sql	-320625225	rent_user_new	2026-03-03 13:34:05.75561	20	t
3	3	add foreign keys	SQL	V3__add_foreign_keys.sql	-2139509895	rent_user_new	2026-03-03 13:34:05.804244	23	t
4	4	add unique constraints	SQL	V4__add_unique_constraints.sql	977706592	rent_user_new	2026-03-03 13:40:47.516283	15	t
5	5	add indexes	SQL	V5__add_indexes.sql	-1161627252	rent_user_new	2026-03-03 13:42:04.08444	13	t
6	6	ledger category enum	SQL	V6__ledger_category_enum.sql	976534492	rent_user_new	2026-03-03 13:43:53.759896	20	t
7	7	create payouts table	SQL	V7__create_payouts_table.sql	-25697975	rent_user_new	2026-03-03 13:43:53.800065	4	t
8	9	audit logs	SQL	V9__audit_logs.sql	-1350729087	rent_user_new	2026-03-03 13:43:53.815887	3	t
9	10	financial hardening	SQL	V10__financial_hardening.sql	883621684	rent_user_new	2026-03-04 13:24:26.540454	20	t
10	11	ledger immutability	SQL	V11__ledger_immutability.sql	-846777132	rent_user_new	2026-03-04 13:36:29.825082	8	t
11	12	dashboard snapshots	SQL	V12__dashboard_snapshots.sql	1756503060	rent_user_new	2026-03-14 18:06:10.141118	19	t
\.


--
-- Data for Name: ledger_entries; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.ledger_entries (id, property_id, entry_type, category, amount, reference_id, created_at, tenancy_id, reference, entry_month, entry_year) FROM stdin;
6c82e531-64e5-4038-84d1-6d62afb8f9c1	03acbaec-5ab5-4e92-b01e-6cd41017c550	DEBIT	RENT_CHARGE	10.00	bfdd11c9-2f97-4f33-91c7-b02916f570f9	2026-03-23 18:36:29.309146	bfdd11c9-2f97-4f33-91c7-b02916f570f9	\N	3	2026
0238bc4b-dcdb-462e-9478-61dfec71c63a	03acbaec-5ab5-4e92-b01e-6cd41017c550	CREDIT	RENT_PAYMENT	4.00	\N	2026-03-23 18:50:17.327681	bfdd11c9-2f97-4f33-91c7-b02916f570f9	TEST123	3	2026
181221f5-0dc6-48b8-ba0c-1c1bcf9c6a0e	03acbaec-5ab5-4e92-b01e-6cd41017c550	CREDIT	RENT_PAYMENT	4.00	\N	2026-03-23 20:13:21.805756	bfdd11c9-2f97-4f33-91c7-b02916f570f9	LIVECHECK123	3	2026
768529fa-c820-4a41-900f-087e857d977c	03acbaec-5ab5-4e92-b01e-6cd41017c550	CREDIT	RENT_PAYMENT	2.00	\N	2026-03-23 20:56:53.201155	bfdd11c9-2f97-4f33-91c7-b02916f570f9	UCNAHA8V09	3	2026
390cb5ca-4b0e-4a3b-8ec3-80f1f76cabb4	03acbaec-5ab5-4e92-b01e-6cd41017c550	CREDIT	RENT_PAYMENT	3.00	\N	2026-03-23 20:56:53.201155	bfdd11c9-2f97-4f33-91c7-b02916f570f9	UCNAHA8V09	3	2026
cb6cd4a4-cb67-423b-aefa-9bcc3348c57e	03acbaec-5ab5-4e92-b01e-6cd41017c550	CREDIT	RENT_PAYMENT	2.00	\N	2026-03-23 22:40:00.554048	bfdd11c9-2f97-4f33-91c7-b02916f570f9	UCOAHA9380	3	2026
396bf077-8330-4990-bf16-a5943bec67bf	03acbaec-5ab5-4e92-b01e-6cd41017c550	DEBIT	PAYOUT	4.00	\N	2026-03-24 08:45:19.300274	\N	PAYOUT:9b8ccb24-05c8-4fe4-8532-df0f44b2bee6	3	2026
dc098f9b-64b1-4d9c-aeac-f293781cc4ec	03acbaec-5ab5-4e92-b01e-6cd41017c550	CREDIT	RENT_PAYMENT	1.00	\N	2026-03-24 07:38:39.271439	bfdd11c9-2f97-4f33-91c7-b02916f570f9	UCOAHA9S6J	3	2026
48903a44-a7fa-427f-8091-4d9672bbacfb	03acbaec-5ab5-4e92-b01e-6cd41017c550	DEBIT	PAYOUT	4.00	\N	2026-03-24 12:53:08.241566	\N	PAYOUT:412b43d2-5709-4d2b-b0fd-eb4561401026	3	2026
926b69fc-9b0e-40ab-970c-cd9cc6e8af46	03acbaec-5ab5-4e92-b01e-6cd41017c550	DEBIT	PAYOUT	4.00	\N	2026-03-24 14:19:32.334966	\N	PAYOUT:4827c4a3-2d66-45b5-8c03-89bdeac6d2ef	3	2026
1d8ba8c5-1d5d-4929-86f9-65a1a055b35a	03acbaec-5ab5-4e92-b01e-6cd41017c550	CREDIT	RENT_PAYMENT	3.00	\N	2026-03-24 12:35:01.144467	bfdd11c9-2f97-4f33-91c7-b02916f570f9	UCOAHAARED	3	2026
db032469-1503-4c31-938d-a694c3491ea3	03acbaec-5ab5-4e92-b01e-6cd41017c550	DEBIT	PAYOUT	5.00	\N	2026-03-24 16:08:59.23988	\N	PAYOUT:2994a1bf-ab4d-4753-bacc-63a5409f16fa	3	2026
94cd4076-3285-4807-b766-11e730af7c3d	d24bc224-8e8b-421b-a901-1a41cc859d0c	DEBIT	RENT_CHARGE	200000.00	a2007bd3-e9bb-44c1-aa3f-da19adc22827	2026-03-24 20:23:52.498266	a2007bd3-e9bb-44c1-aa3f-da19adc22827	\N	3	2026
7b8ff7ac-0008-47ca-8e3c-39d1b6973781	d24bc224-8e8b-421b-a901-1a41cc859d0c	DEBIT	RENT_CHARGE	200000.00	7746a50d-6c46-47db-99f0-518174ca9223	2026-03-24 20:24:27.145344	7746a50d-6c46-47db-99f0-518174ca9223	\N	3	2026
6e61fd92-315a-490c-b4c5-004d8ee128f9	d24bc224-8e8b-421b-a901-1a41cc859d0c	CREDIT	RENT_PAYMENT	1.00	\N	2026-03-24 20:30:03.803591	7746a50d-6c46-47db-99f0-518174ca9223	UCOLHAJHNT	3	2026
4d9abf11-8b17-4986-af0d-e2275aafba1e	03acbaec-5ab5-4e92-b01e-6cd41017c550	DEBIT	RENT_CHARGE	3.00	6ad82669-69cb-4e2b-80e2-7d6c7f24297c	2026-03-25 07:47:54.360158	6ad82669-69cb-4e2b-80e2-7d6c7f24297c	\N	3	2026
14bffc66-592d-455c-98e0-238e27fed3d7	03acbaec-5ab5-4e92-b01e-6cd41017c550	CREDIT	RENT_PAYMENT	3.00	\N	2026-03-25 07:49:06.190717	6ad82669-69cb-4e2b-80e2-7d6c7f24297c	UCPAHADKJT	3	2026
e9bd4eb2-813c-49ce-923c-e9202f855ce1	03acbaec-5ab5-4e92-b01e-6cd41017c550	CREDIT	RENT_PAYMENT	1.00	\N	2026-03-25 07:49:06.190717	6ad82669-69cb-4e2b-80e2-7d6c7f24297c	UCPAHADKJT	3	2026
e1329a7a-8642-4c37-b401-ae370026dea8	03acbaec-5ab5-4e92-b01e-6cd41017c550	DEBIT	RENT_CHARGE	3.00	9921db37-d448-4fa6-a2f1-55543347b26a	2026-03-25 07:51:42.041877	9921db37-d448-4fa6-a2f1-55543347b26a	\N	3	2026
050e2bbd-b8db-41d6-b045-ddde840873d1	cf1b2aef-dfd4-4800-ac1c-a1f7cd0a6fe9	DEBIT	RENT_CHARGE	5.00	eb82afec-c563-495b-a627-a9f4e796a4b9	2026-03-25 19:47:29.47162	eb82afec-c563-495b-a627-a9f4e796a4b9	\N	3	2026
2cd55b54-3ea1-49a3-a90a-52277b509a79	cf1b2aef-dfd4-4800-ac1c-a1f7cd0a6fe9	CREDIT	RENT_PAYMENT	5.00	\N	2026-03-25 19:48:16.386344	eb82afec-c563-495b-a627-a9f4e796a4b9	UCPAHAGLXK	3	2026
2a46ab56-43bd-4df3-b01b-4ac13db5ccb2	cf1b2aef-dfd4-4800-ac1c-a1f7cd0a6fe9	DEBIT	PAYOUT	3.00	\N	2026-03-26 11:50:37.478181	\N	PAYOUT:fb3db7c2-d2fb-4718-bfc1-90496a6c5eee	3	2026
\.


--
-- Data for Name: mpesa_transactions; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.mpesa_transactions (id, transaction_code, phone_number, account_reference, amount, raw_payload, processed, created_at, retry_count, last_attempt_at, error_message) FROM stdin;
6f544318-4a0d-450b-9e21-8d684c27672c	TEST123	254742620498	RA3	4.00	{"MSISDN": "254742620498", "TransID": "TEST123", "TransAmount": "4", "BillRefNumber": "RA3"}	t	2026-03-23 18:50:17.311372	0	\N	\N
bc1d3e1b-92c4-41a8-8779-6b75e24d9297	UCNAHA8V09	035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549	RA3	5.00	{"MSISDN": "035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549", "TransID": "UCNAHA8V09", "FirstName": "KAREEM", "TransTime": "20260323235651", "TransAmount": "5.00", "BillRefNumber": "RA3", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "94.00", "ThirdPartyTransID": ""}	t	2026-03-23 20:56:52.494702	0	\N	\N
d8f5e780-0b74-410e-9e36-f70ca1df5f7b	UCOAHA9380	035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549	RA3	2.00	{"MSISDN": "035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549", "TransID": "UCOAHA9380", "FirstName": "KAREEM", "TransTime": "20260324013959", "TransAmount": "2.00", "BillRefNumber": "RA3", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "97.00", "ThirdPartyTransID": ""}	t	2026-03-23 22:40:00.544468	0	\N	\N
c7b8f6df-6ba6-4b56-87a7-f046c28fee00	UCOLHAJHNT	4e31bad10e98a51f80af2777806682d27f8bbd13e0d684d9d28d341221e59f9d	AE122	1.00	{"MSISDN": "4e31bad10e98a51f80af2777806682d27f8bbd13e0d684d9d28d341221e59f9d", "TransID": "UCOLHAJHNT", "FirstName": "ISSA", "TransTime": "20260324233003", "TransAmount": "1.00", "BillRefNumber": "AE122", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "103.00", "ThirdPartyTransID": ""}	f	2026-03-24 20:30:03.794414	5	2026-03-24 20:32:26.499625	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
2b0c5085-0765-4258-8413-93dbf57407d8	UCOAHA8YIR	035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549	SUB_E009E4	1.00	{"MSISDN": "035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549", "TransID": "UCOAHA8YIR", "FirstName": "KAREEM", "TransTime": "20260324001508", "TransAmount": "1.00", "BillRefNumber": "SUB_e009e4", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "95.00", "ThirdPartyTransID": ""}	f	2026-03-23 21:15:09.046514	5	2026-03-24 06:31:38.381904	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
888e4613-c4f7-4acf-b99a-d42e476496b1	LIVECHECK123	254742620498	RA3	4.00	{"MSISDN": "254742620498", "TransID": "LIVECHECK123", "TransAmount": "4", "BillRefNumber": "RA3"}	f	2026-03-23 20:13:21.112302	5	2026-03-24 06:31:38.486539	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
d754ede5-eddf-4c81-a822-2184e31f0dd7	UCOAHA9S6J	035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549	RA3	1.00	{"MSISDN": "035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549", "TransID": "UCOAHA9S6J", "FirstName": "KAREEM", "TransTime": "20260324103838", "TransAmount": "1.00", "BillRefNumber": "RA3", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "98.00", "ThirdPartyTransID": ""}	f	2026-03-24 07:38:39.242206	5	2026-03-24 07:41:09.59464	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
62e8a72a-df94-47a6-aa0b-027f1086b08a	UCOLHAJOGK	4e31bad10e98a51f80af2777806682d27f8bbd13e0d684d9d28d341221e59f9d	SUB_2CD1D4	1.00	{"MSISDN": "4e31bad10e98a51f80af2777806682d27f8bbd13e0d684d9d28d341221e59f9d", "TransID": "UCOLHAJOGK", "FirstName": "ISSA", "TransTime": "20260324230654", "TransAmount": "1.00", "BillRefNumber": "SUB_2cd1d4", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "102.00", "ThirdPartyTransID": ""}	f	2026-03-24 20:06:55.490567	5	2026-03-24 20:08:55.995679	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
b8b96a7d-7fd1-4546-80da-f8b8b2a2a7cd	UCOAHAARED	035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549	RA3	3.00	{"MSISDN": "035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549", "TransID": "UCOAHAARED", "FirstName": "KAREEM", "TransTime": "20260324153500", "TransAmount": "3.00", "BillRefNumber": "RA3", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "101.00", "ThirdPartyTransID": ""}	f	2026-03-24 12:35:01.113301	5	2026-03-24 12:37:21.384296	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
4c5334c1-110e-4407-8b22-416725260432	UCPAHADKJT	035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549	RA7	4.00	{"MSISDN": "035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549", "TransID": "UCPAHADKJT", "FirstName": "KAREEM", "TransTime": "20260325104905", "TransAmount": "4.00", "BillRefNumber": "RA7", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "27.00", "ThirdPartyTransID": ""}	f	2026-03-25 07:49:06.098366	5	2026-03-25 07:51:16.381851	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
7922087c-c841-493e-a57a-5cd2aa3778f0	UCPAHAG8MB	035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549	SUB_237765	1.00	{"MSISDN": "035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549", "TransID": "UCPAHAG8MB", "FirstName": "KAREEM", "TransTime": "20260325212238", "TransAmount": "1.00", "BillRefNumber": "SUB_237765", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "30.00", "ThirdPartyTransID": ""}	f	2026-03-25 18:22:39.577935	5	2026-03-25 18:24:51.502411	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
2fa5a454-050d-4ad6-a294-32e55ce0552e	UCPAHAFIS4	035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549	SUB_EB2DB5	1.00	{"MSISDN": "035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549", "TransID": "UCPAHAFIS4", "FirstName": "KAREEM", "TransTime": "20260325185148", "TransAmount": "1.00", "BillRefNumber": "SUB_eb2db5", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "29.00", "ThirdPartyTransID": ""}	f	2026-03-25 15:51:49.56267	5	2026-03-25 15:53:56.53731	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
fd19225e-7014-4fe4-9b2e-adc0f7639eae	UCP06ACPNK	e2489961c8f4e2a021d1292c57d783892d7166e573f0af33439c5097ebfa2720	SUB_283D04	1.00	{"MSISDN": "e2489961c8f4e2a021d1292c57d783892d7166e573f0af33439c5097ebfa2720", "TransID": "UCP06ACPNK", "FirstName": "BRANDON", "TransTime": "20260325152702", "TransAmount": "1.00", "BillRefNumber": "SUB_283d04", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "28.00", "ThirdPartyTransID": ""}	f	2026-03-25 12:27:03.479281	5	2026-03-25 12:29:15.251804	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
fcc9262c-20fa-459f-b81f-a7706a1debf8	UCPAHAGLXK	035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549	NX12	5.00	{"MSISDN": "035634c89c47fbda15b35b8e13cf37a89c9c5b76f18ba47e02005c7633e97549", "TransID": "UCPAHAGLXK", "FirstName": "KAREEM", "TransTime": "20260325224815", "TransAmount": "5.00", "BillRefNumber": "NX12", "InvoiceNumber": "", "TransactionType": "Pay Bill", "BusinessShortCode": "4026213", "OrgAccountBalance": "35.00", "ThirdPartyTransID": ""}	f	2026-03-25 19:48:16.373736	5	2026-03-25 19:50:22.365201	PreparedStatementCallback; uncategorized SQLException for SQL [\n                    SELECT COUNT(*) FROM mpesa_transactions\n                    WHERE transaction_code = ? AND processed = false\n                    FOR UPDATE\n                    ]; SQL state [0A000]; error code [0]; ERROR: FOR UPDATE is not allowed with aggregate functions
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.payments (id, tenancy_id, amount, payment_method, transaction_code, payment_date, created_at, receipt_number, receipt_url, processed_at, status) FROM stdin;
ac9fb9f1-e365-4553-a43d-9fe1c70b7a28	bfdd11c9-2f97-4f33-91c7-b02916f570f9	4.00	MPESA	TEST123	2026-03-23 18:50:17.327681	2026-03-23 18:50:17.327681	\N	\N	2026-03-24 06:09:03.285395	SUCCESS
1f4a65f7-de45-4855-a36f-6e3e15eac3fd	bfdd11c9-2f97-4f33-91c7-b02916f570f9	4.00	MPESA	LIVECHECK123	2026-03-23 20:13:21.805756	2026-03-23 20:13:21.805756	\N	\N	2026-03-24 06:09:03.285395	SUCCESS
4f5667bb-84d6-4d81-8839-e203507148fc	bfdd11c9-2f97-4f33-91c7-b02916f570f9	5.00	MPESA	UCNAHA8V09	2026-03-23 20:56:53.201155	2026-03-23 20:56:53.201155	\N	\N	2026-03-24 06:09:03.285395	SUCCESS
fc4ad576-d3ef-41e2-a6e3-675a8e391835	bfdd11c9-2f97-4f33-91c7-b02916f570f9	2.00	MPESA	UCOAHA9380	2026-03-23 22:40:00.554048	2026-03-23 22:40:00.554048	\N	\N	2026-03-24 06:09:03.285395	SUCCESS
21fb49a9-8ee6-4a22-abc7-1b695f53162c	bfdd11c9-2f97-4f33-91c7-b02916f570f9	1.00	MPESA	UCOAHA9S6J	2026-03-24 07:38:39.271439	2026-03-24 07:38:39.271439	\N	\N	2026-03-24 07:38:39.271439	SUCCESS
6c3f3d3f-67f5-4180-b597-3b48c5bc9e3c	bfdd11c9-2f97-4f33-91c7-b02916f570f9	3.00	MPESA	UCOAHAARED	2026-03-24 12:35:01.144467	2026-03-24 12:35:01.144467	\N	\N	2026-03-24 12:35:01.144467	SUCCESS
a6e2ba21-8163-433e-a077-4302dd792263	7746a50d-6c46-47db-99f0-518174ca9223	1.00	MPESA	UCOLHAJHNT	2026-03-24 20:30:03.803591	2026-03-24 20:30:03.803591	\N	\N	2026-03-24 20:30:03.803591	SUCCESS
7dae9259-3177-4468-a54c-abeef8cfc8d3	6ad82669-69cb-4e2b-80e2-7d6c7f24297c	4.00	MPESA	UCPAHADKJT	2026-03-25 07:49:06.190717	2026-03-25 07:49:06.190717	\N	\N	2026-03-25 07:49:06.190717	SUCCESS
ff2689c6-b6bb-4aaf-8e19-c3a19620212a	eb82afec-c563-495b-a627-a9f4e796a4b9	5.00	MPESA	UCPAHAGLXK	2026-03-25 19:48:16.386344	2026-03-25 19:48:16.386344	\N	\N	2026-03-25 19:48:16.386344	SUCCESS
\.


--
-- Data for Name: payout_requests; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.payout_requests (id, landlord_id, property_id, amount, method, destination, created_at, processed_at, status, national_id, processed_by) FROM stdin;
9b8ccb24-05c8-4fe4-8532-df0f44b2bee6	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	03acbaec-5ab5-4e92-b01e-6cd41017c550	4.00	BANK	456667788	2026-03-24 00:10:28.507097	2026-03-24 08:45:19.300274	PAID	VERIFIED	23486c7e-56ab-49c6-9626-dfb3a9836179
412b43d2-5709-4d2b-b0fd-eb4561401026	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	03acbaec-5ab5-4e92-b01e-6cd41017c550	4.00	BANK	456667788	2026-03-24 10:14:19.261512	2026-03-24 12:53:08.241566	PAID	VERIFIED	23486c7e-56ab-49c6-9626-dfb3a9836179
4827c4a3-2d66-45b5-8c03-89bdeac6d2ef	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	03acbaec-5ab5-4e92-b01e-6cd41017c550	4.00	BANK	456667788	2026-03-24 14:18:53.462993	2026-03-24 14:19:32.334966	PAID	VERIFIED	23486c7e-56ab-49c6-9626-dfb3a9836179
2994a1bf-ab4d-4753-bacc-63a5409f16fa	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	03acbaec-5ab5-4e92-b01e-6cd41017c550	5.00	BANK	456667788	2026-03-24 15:35:54.834334	2026-03-24 16:08:59.23988	PAID	VERIFIED	23486c7e-56ab-49c6-9626-dfb3a9836179
fb3db7c2-d2fb-4718-bfc1-90496a6c5eee	23776547-f86b-4401-92c6-4ab0cd2c9f99	cf1b2aef-dfd4-4800-ac1c-a1f7cd0a6fe9	3.00	BANK	975556788	2026-03-26 00:27:47.367565	2026-03-26 11:50:37.478181	PAID	\N	23486c7e-56ab-49c6-9626-dfb3a9836179
\.


--
-- Data for Name: payouts; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.payouts (id, landlord_id, amount, transaction_cost, status, mpesa_reference, created_at, processed_at) FROM stdin;
\.


--
-- Data for Name: platform_transactions; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.platform_transactions (id, landlord_id, amount, reference, created_at) FROM stdin;
6f577157-c9b2-4829-b0db-39df348c4cc6	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	1.00	UCNAHA8K8V	2026-03-23 18:14:36.128961
d2cc7277-b339-4679-b740-8364f16c0387	e009e4d2-77cd-4756-b5db-838fcf094a15	1.00	UCOAHA8YIR	2026-03-23 21:15:08.813535
d12ae49f-f03d-4226-b66d-b7f16dd0a0fa	2cd1d41c-6fd3-411c-8b54-ec4499439e3f	1.00	UCOLHAJOGK	2026-03-24 20:06:55.576421
fecbe887-6154-4c03-9318-658680e643dd	283d04cb-a065-4dd6-960e-b932f47c922b	1.00	UCP06ACPNK	2026-03-25 12:27:02.978778
aaa9ea1e-4efa-4953-8a88-f8fc4d06b589	eb2db531-23fa-40f9-9861-7497fa106aa5	1.00	UCPAHAFIS4	2026-03-25 15:51:49.415193
886d19ff-c870-4124-94cd-040c91acf0c2	23776547-f86b-4401-92c6-4ab0cd2c9f99	1.00	UCPAHAG8MB	2026-03-25 18:22:39.423306
\.


--
-- Data for Name: platform_wallet; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.platform_wallet (id, balance, created_at) FROM stdin;
bb4d7497-24c2-415f-9e18-ba1e26c2ea03	6.00	2026-03-23 16:29:36.178407
\.


--
-- Data for Name: properties; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.properties (id, name, address, city, country, account_prefix, landlord_id, created_at, payout_setup_complete) FROM stdin;
03acbaec-5ab5-4e92-b01e-6cd41017c550	Rentana Aparts	ruiru	Nairobi	Kenya	RA	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	2026-03-23 18:35:37.179156	t
d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	Almadie Estate	Webuye	Nairobi	Kenya	AE	e009e4d2-77cd-4756-b5db-838fcf094a15	2026-03-23 21:16:09.097801	f
d24bc224-8e8b-421b-a901-1a41cc859d0c	Almadie Estate	660	Webuye	Kenya	AE1	2cd1d41c-6fd3-411c-8b54-ec4499439e3f	2026-03-24 20:19:45.218182	f
39f224df-9e29-4dcf-bf63-e7e5544fdf39	Brandon	Ruiru	Nairobi	Kenya	B	283d04cb-a065-4dd6-960e-b932f47c922b	2026-03-25 12:28:04.828826	t
66649c53-066a-47fc-b0ba-3922dee52282	saa	ruiru	Nairobi	Kenya	S	eb2db531-23fa-40f9-9861-7497fa106aa5	2026-03-25 15:52:35.884204	t
cf1b2aef-dfd4-4800-ac1c-a1f7cd0a6fe9	nnnnnn xxxxx	kisumu	Kisumu	Kenya	NX	23776547-f86b-4401-92c6-4ab0cd2c9f99	2026-03-25 18:23:43.407201	t
\.


--
-- Data for Name: sms_logs; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.sms_logs (id, recipient, message, status, provider_response, created_at) FROM stdin;
\.


--
-- Data for Name: stk_requests; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.stk_requests (id, checkout_request_id, merchant_request_id, landlord_id, phone_number, amount, status, created_at, plan_id) FROM stdin;
dfff5848-cc95-4504-8eeb-b820faf05c08	ws_CO_23032026135757166742620498	2757-41ee-bf6e-f2c1d2debae91469977	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	254742620498	1.00	PENDING	2026-03-23 10:57:57.455122	d5a38f22-f0ad-4031-9aca-f18f1d201b07
d31ede71-27f2-4037-b85d-cbb31cec5002	ws_CO_23032026145416739742620498	32b6-41a3-856d-436f2dd58ed0133145	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	254742620498	1.00	PENDING	2026-03-23 11:54:16.465397	d5a38f22-f0ad-4031-9aca-f18f1d201b07
0ec97ccd-9cbc-4bcb-9a2b-2dba24dae2c2	ws_CO_23032026152617201742620498	102a-4e21-ada9-20e4aff77d7c594895	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	254742620498	1.00	PENDING	2026-03-23 12:26:18.009735	d5a38f22-f0ad-4031-9aca-f18f1d201b07
f3511431-308c-47e6-9147-735a9b6fd084	ws_CO_23032026191540170742620498	3948-4930-96bb-9079f7c562515260114	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	254742620498	1.00	PENDING	2026-03-23 16:15:40.832332	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
0ee99a37-6fb3-43f7-8105-3545807882b0	ws_CO_23032026191702047742620498	870f-4b30-a80c-584fbea4e5993971895	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	254742620498	1.00	PENDING	2026-03-23 16:17:02.711409	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
7d49f8c5-f2fe-46b3-a33f-6a39d58164fe	ws_CO_23032026194928791742620498	36ad-4429-8974-bfe843b6b84b7173	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	254742620498	1.00	PENDING	2026-03-23 16:49:28.224204	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
baca5385-6be9-4be9-b181-70ad7fa5f296	ws_CO_23032026195155102742620498	2757-41ee-bf6e-f2c1d2debae92277463	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	254742620498	1.00	PENDING	2026-03-23 16:51:55.294739	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
d4556141-7493-4b2a-a677-f61a8d358472	ws_CO_23032026211408889742620498	157b-4058-aade-33cb8b564bad14310	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	254742620498	1.00	SUCCESS	2026-03-23 18:14:09.383001	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
f0b81f00-625a-4ab6-84ed-f468911c7604	ws_CO_24032026001458248742620498	5dde-46b6-a939-4d470d9dab071332196	e009e4d2-77cd-4756-b5db-838fcf094a15	254742620498	1.00	SUCCESS	2026-03-23 21:14:58.397921	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
6f6d049d-923f-4716-b92a-92204a651761	ws_CO_24032026230638364742877291	1c1f-4c0f-ba9e-001f1390ac2661697	2cd1d41c-6fd3-411c-8b54-ec4499439e3f	254742877291	1.00	SUCCESS	2026-03-24 20:06:39.082053	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
b66f98fb-295c-4562-b760-65aecffda04a	ws_CO_25032026152648018741177703	0538-4927-9d65-ccb47766753f1662785	283d04cb-a065-4dd6-960e-b932f47c922b	254741177703	1.00	SUCCESS	2026-03-25 12:26:48.621984	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
5c75cadf-1511-470c-8160-7ffbe8baec49	ws_CO_25032026185139142742620498	5d77-49d7-b4f1-b2cf4b651ca05480522	eb2db531-23fa-40f9-9861-7497fa106aa5	254742620498	1.00	SUCCESS	2026-03-25 15:51:39.660373	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
55553f3a-f127-4786-989b-b7564c7ffe61	ws_CO_25032026212217005742620498	19c7-46a6-a926-bcb2ce2670502181711	23776547-f86b-4401-92c6-4ab0cd2c9f99	254742620498	1.00	SUCCESS	2026-03-25 18:22:17.411096	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a
\.


--
-- Data for Name: subscription_plans; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.subscription_plans (id, name, property_limit, price, created_at) FROM stdin;
d5a38f22-f0ad-4031-9aca-f18f1d201b07	Starter	1	2000.00	2026-03-18 18:08:18.12413
55085c32-0be3-4c2f-9aa6-092fee3ea89d	Growth	2	3500.00	2026-03-18 18:08:18.12413
10802a12-d347-48c2-beb3-2f1bdeb63811	Pro	3	4500.00	2026-03-18 18:08:18.12413
7af4bc5d-abdb-4346-86f0-e5449e561f61	Business	5	6500.00	2026-03-18 18:08:18.12413
9ef40dba-8f79-4fc1-bcb5-14b4a7264f97	Enterprise	10	8000.00	2026-03-18 18:08:18.12413
a2e3bc1e-1c14-4b6b-9512-5eeeec66643a	Test Plan	1	1.00	2026-03-19 00:49:52.616293
\.


--
-- Data for Name: subscriptions; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.subscriptions (id, landlord_id, plan_id, start_date, end_date, status, created_at) FROM stdin;
cfd0a94d-2ab0-4bb5-a74c-b675748169d5	39ce9b5e-af3e-4d2b-aa74-d8e30bade307	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a	2026-03-23 18:14:36.179435	2026-04-23 18:14:36.179435	ACTIVE	2026-03-23 18:14:36.181308
309b9af2-ad24-4123-ae2f-df61ff644466	e009e4d2-77cd-4756-b5db-838fcf094a15	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a	2026-03-23 21:15:08.828912	2026-04-23 21:15:08.828912	ACTIVE	2026-03-23 21:15:08.82962
08060653-1d26-4dae-8a2e-8a4211f8fc29	2cd1d41c-6fd3-411c-8b54-ec4499439e3f	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a	2026-03-24 20:06:55.618853	2026-04-24 20:06:55.618853	ACTIVE	2026-03-24 20:06:55.620034
4142111f-a87a-44f6-9115-ec0ea0c0d882	283d04cb-a065-4dd6-960e-b932f47c922b	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a	2026-03-25 12:27:02.992242	2026-04-25 12:27:02.992242	ACTIVE	2026-03-25 12:27:02.991643
1de035d1-1449-49ea-81d0-d26e90aeff6d	eb2db531-23fa-40f9-9861-7497fa106aa5	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a	2026-03-25 15:51:49.459321	2026-04-25 15:51:49.459321	ACTIVE	2026-03-25 15:51:49.460672
97dbe18f-31da-4a1c-b656-7e46d119a0c9	23776547-f86b-4401-92c6-4ab0cd2c9f99	a2e3bc1e-1c14-4b6b-9512-5eeeec66643a	2026-03-25 18:22:39.438162	2026-04-25 18:22:39.438162	ACTIVE	2026-03-25 18:22:39.439171
\.


--
-- Data for Name: tenancies; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.tenancies (id, tenant_id, unit_id, rent_amount, start_date, is_active, created_at, rent_due_day, last_rent_charged_date) FROM stdin;
bfdd11c9-2f97-4f33-91c7-b02916f570f9	2be24883-030a-4592-93ab-1c41bc4a0ccf	d51cb7ea-6501-45b4-982a-026a3293a0a1	10.00	2026-03-23	t	2026-03-23 18:36:29.300304	1	\N
a2007bd3-e9bb-44c1-aa3f-da19adc22827	c17bbfe2-0e44-4f56-afa9-5f9eb6ede3f6	707d22a1-8c71-4917-9f35-f7c2ffde8aab	200000.00	2026-03-24	f	2026-03-24 20:23:52.494249	1	\N
7746a50d-6c46-47db-99f0-518174ca9223	7af8cb67-bcf9-4bcb-aad7-17d756d5cea5	707d22a1-8c71-4917-9f35-f7c2ffde8aab	200000.00	2026-03-24	t	2026-03-24 20:24:27.135298	1	\N
6ad82669-69cb-4e2b-80e2-7d6c7f24297c	3b982415-a12b-4b44-987f-5b87bb084f34	106f2b97-fcb0-4bea-b670-ee9d9fc69881	3.00	2026-03-25	f	2026-03-25 07:47:54.353693	1	\N
9921db37-d448-4fa6-a2f1-55543347b26a	8995be10-ab58-45e3-8191-1c5b9cbacfe7	7aa7b2f3-82b0-44bf-9f75-0f469322a559	3.00	2026-03-25	f	2026-03-25 07:51:42.036468	1	\N
eb82afec-c563-495b-a627-a9f4e796a4b9	9f11cb11-2b15-4b24-a6d8-c7c1bcf02bce	4eb413a2-dbfa-4e9a-bd43-88e68a6fcd22	5.00	2026-03-25	t	2026-03-25 19:47:29.461803	1	\N
\.


--
-- Data for Name: tenants; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.tenants (id, full_name, phone_number, is_active, created_at) FROM stdin;
dc8786b7-cfc9-458c-a928-a80bbf83d4b9	kareen	0114713717	t	2026-03-19 12:52:58.992145
837a1e89-bfeb-42e1-8bcd-e2fa594a6f36	kareem	0742620498	f	2026-03-19 13:51:39.665887
e8d842b5-6f99-4913-b789-600f748dd51f	Mister	0113456789	f	2026-03-19 14:50:31.957061
c484aa09-7ea3-49af-9379-a565cc326453	Brandon Macharia	0742620485	f	2026-03-19 18:30:38.776562
18a89c0d-d55d-4d3d-929c-7bf318a9e0f2	Brandon Macharia	0742620498	t	2026-03-19 18:52:43.577799
398707c1-abc3-49de-bcc7-d2e352e009de	Hassan	0742620498	t	2026-03-20 18:40:01.388112
6c7a8c0f-9abb-42ca-a96d-10d832a08766	Milama	0742620498	t	2026-03-21 11:27:32.056456
2be24883-030a-4592-93ab-1c41bc4a0ccf	sain Mall	0735678970	t	2026-03-23 18:36:29.307646
c17bbfe2-0e44-4f56-afa9-5f9eb6ede3f6	John Omeyo	+254742877291	f	2026-03-24 20:23:52.497253
7af8cb67-bcf9-4bcb-aad7-17d756d5cea5	John	254726131416	t	2026-03-24 20:24:27.144977
3b982415-a12b-4b44-987f-5b87bb084f34	Sava	254742620498	f	2026-03-25 07:47:54.358773
8995be10-ab58-45e3-8191-1c5b9cbacfe7	Juma	254742620498	f	2026-03-25 07:51:42.041414
9f11cb11-2b15-4b24-a6d8-c7c1bcf02bce	Kass	254745678909	t	2026-03-25 19:47:29.470048
\.


--
-- Data for Name: units; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.units (id, unit_number, account_number, reference_number, rent_amount, is_active, property_id, created_at) FROM stdin;
d51cb7ea-6501-45b4-982a-026a3293a0a1	3	RA3	RA3	10.00	t	03acbaec-5ab5-4e92-b01e-6cd41017c550	2026-03-23 18:36:02.764584
66988ccf-b249-4e26-a52c-2cf0fc7973a4	1	AE1	AE1	13000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-23 21:17:19.296319
ab4a1107-6bda-43b3-8348-e5ef322cfc06	2	AE2	AE2	13000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-23 21:17:41.464284
e8068428-4240-494c-9d65-10387b01b527	3	AE3	AE3	13000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-23 21:17:58.548857
ca21ba1a-aa1e-4a63-90f3-c08821f1b143	4	AE4	AE4	13000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-23 21:19:54.219667
ef1c7153-502b-4c1a-b555-26afd4bfe7cc	5	AE5	AE5	4000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:17:35.970999
32262a7a-f8c7-4758-90be-fade8fe5e02c	6	AE6	AE6	4000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:18:08.158703
c0c8a60c-5959-4978-9869-082f7b32ea8e	7	AE7	AE7	4000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:18:23.597631
57c1264b-c4c6-40e9-a597-9f63be69f29a	8	AE8	AE8	4000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:19:21.197914
506ff3aa-bc8e-47e4-8da8-156fc667aa5e	9	AE9	AE9	3800.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:19:49.212253
8c8e43db-10bb-4293-a350-f5b3472bf5b5	10	AE10	AE10	3800.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:20:08.202081
361b1d91-4786-44b1-9124-0710a59dfd37	11	AE11	AE11	4000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:20:32.300369
2653c89b-8a2f-426c-9da4-af20bb291dc2	12	AE12	AE12	4000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:20:53.862845
d61af0fd-9b18-4ef5-b65d-8fb832c2f676	13	AE13	AE13	4000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:21:36.001881
ad5966ae-ccee-4a87-a523-80fa41f35db2	14	AE14	AE14	4000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:21:55.291687
951fcf24-09b4-4ea4-89e3-fee2d3c7f79a	15	AE15	AE15	5000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:22:27.307261
b48a76d8-3fa0-48c0-adb9-598ac2af5c2f	16	AE16	AE16	5000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:22:43.533144
05393c3f-d04c-4d48-bd29-a4172f52cbae	17	AE17	AE17	5000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:22:52.488082
49af7f6f-828b-4661-a90d-f840246dfc6c	18	AE18	AE18	5000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:23:17.174781
1cd0dfdc-07eb-449a-9595-865f2a2d5c48	19	AE19	AE19	5000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:23:31.425095
6c6647df-e909-420f-a846-ea0d209b54d8	20	AE20	AE20	5000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:23:47.613781
7351d2cd-d7a7-4ce5-8733-8139b881e3b4	21	AE21	AE21	5000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:24:13.912238
008e1f7a-b735-4c90-8b4f-8a3ea4afa83c	22	AE22	AE22	5000.00	t	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	2026-03-24 07:24:34.285685
707d22a1-8c71-4917-9f35-f7c2ffde8aab	22	AE122	AE122	200000.00	t	d24bc224-8e8b-421b-a901-1a41cc859d0c	2026-03-24 20:21:25.74915
106f2b97-fcb0-4bea-b670-ee9d9fc69881	7	RA7	RA7	3.00	t	03acbaec-5ab5-4e92-b01e-6cd41017c550	2026-03-25 07:47:33.479394
7aa7b2f3-82b0-44bf-9f75-0f469322a559	6	RA6	RA6	3.00	t	03acbaec-5ab5-4e92-b01e-6cd41017c550	2026-03-25 07:51:18.552118
4eb413a2-dbfa-4e9a-bd43-88e68a6fcd22	12	NX12	NX12	5.00	t	cf1b2aef-dfd4-4800-ac1c-a1f7cd0a6fe9	2026-03-25 19:46:38.489033
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.users (id, full_name, email, phone, password_hash, role, is_active, created_at, payout_locked, payout_setup_complete, national_id_hash) FROM stdin;
23486c7e-56ab-49c6-9626-dfb3a9836179	Kareem Issa	kareemspin@icloud.com	\N	$2a$12$Ov2g6OwHw74YkhFiEupUxeEti63LoCwl0dPcsc6iNjimPmIPnabGK	ADMIN	t	2026-03-18 22:54:41.007147	f	f	$2a$12$AA7dwHScrHOpqwAWEm08cuX4D54PudWOdTLiMJjNXBEN2FwwdfbkW
39ce9b5e-af3e-4d2b-aa74-d8e30bade307	Admin me	admin@gmail.com	0742620498	$2a$10$L9cZ7iGHatqN5eP5cyUoIuKnS1.W/xiYM8hyqp0JjXJ2nQP12kM9m	LANDLORD	t	2026-03-23 10:31:47.282486	f	f	\N
e009e4d2-77cd-4756-b5db-838fcf094a15	Tallah	tallahissa@yahoo.com		$2a$10$8go7.0aY7JnX2ujflAv8veDfdMau4raquyRDAZsFO8Or5tg.2qMlO	LANDLORD	t	2026-03-23 21:14:12.993709	f	f	\N
bc6e9155-a147-479e-9a8e-7d97d30b8b37	brayoa Mwali	spin@icloud.com	0756789056	$2a$10$uRLPTzbcnv8zfCw3shCHmOiq7fQbZ2d8Ed5cmDnBOppD.8tUgLxHO	LANDLORD	t	2026-03-24 18:30:17.818912	f	f	\N
2cd1d41c-6fd3-411c-8b54-ec4499439e3f	Issa Tallah	tallahissa2@gmail.com	0742877291	$2a$10$r/PBDXppNsM.XVrg3jiGN.KMQNsRMQgPECT1dGZb/h3AcuNyIEqau	LANDLORD	t	2026-03-24 20:04:31.327441	f	f	\N
fab04bc2-4a82-4549-9717-79e8ac723c3d	Sama	pin@gmail.com	0112535727	$2a$10$zzdnxLK5ceiHmensrIhUQeOvHw6Bk.JvAvtSCR7g8C3cAXKVOE0Bm	LANDLORD	t	2026-03-25 09:35:20.65656	f	f	\N
283d04cb-a065-4dd6-960e-b932f47c922b	Brandon	brandonmacharia55@gmail.com	0745369870	$2a$10$KKIvO8ZRCukVQXl5aUI.3.2p.4Zm5B1UTNz7VV0BoVIkNvEQ3BR6q	LANDLORD	t	2026-03-25 12:26:06.133098	f	f	\N
eb2db531-23fa-40f9-9861-7497fa106aa5	man	man@gmail.com	0125637890	$2a$10$.MqI0Zr4MrnJdAXK1lnXuOUTp16Nmq8RjbUgWv3S05mS/lbRo46Ti	LANDLORD	t	2026-03-25 15:51:00.164796	f	f	\N
23776547-f86b-4401-92c6-4ab0cd2c9f99	nnnnnn xxxxx	sss@gmail.com	0745679850	$2a$10$xIkHevHdO8r.evZyCURW6O31nOTpYtCafXCIc8MsEmn6oeGs4Ed2q	LANDLORD	t	2026-03-25 18:20:39.987918	f	f	\N
\.


--
-- Data for Name: wallets; Type: TABLE DATA; Schema: public; Owner: spin
--

COPY public.wallets (id, balance, auto_payout_enabled, admin_approval_enabled, created_at, property_id, bank_name, account_number, mpesa_phone, pin_hash, national_id, phone_number, otp_code, otp_expiry) FROM stdin;
7d8d7477-4df9-4df0-aec9-2062831f4122	0.00	f	t	2026-03-23 21:22:04.485117	d6129353-7a96-42b0-b1b5-f6ae3fa7f05f	\N	\N	\N	\N	\N	\N	\N	\N
82bd93e6-edbe-45a5-9c66-d48e583976fa	0.00	f	t	2026-03-24 20:34:07.488571	d24bc224-8e8b-421b-a901-1a41cc859d0c	\N	\N	\N	\N	\N	\N	\N	\N
84ac4867-bcd8-4759-8360-caf9c2583803	23.00	f	t	2026-03-23 18:38:15.187295	03acbaec-5ab5-4e92-b01e-6cd41017c550	Equity Bank	456667788	\N	\N	\N	\N	\N	\N
ffcaa8a4-1447-483f-a919-4e7222af5d15	0.00	f	t	2026-03-25 12:29:57.791054	39f224df-9e29-4dcf-bf63-e7e5544fdf39	\N	\N	254742620498	\N	\N	\N	\N	\N
d2cfeb45-b241-4d21-a5c8-b67c483c8be2	0.00	f	t	2026-03-25 15:52:41.664298	66649c53-066a-47fc-b0ba-3922dee52282	KCB Bank	1234567	\N	\N	\N	\N	\N	\N
c3dcaac3-b206-4d1d-8eb3-d7ff7d09738e	5.00	f	t	2026-03-25 18:24:01.205181	cf1b2aef-dfd4-4800-ac1c-a1f7cd0a6fe9	Equity Bank	975556788	\N	$2a$10$0TLyEdL/iPdGbyHWJkD0K.C3aviu/HWfP/Nrc6XaWilqN5Hvp77d2	244822314	0742620498	\N	\N
\.


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: dashboard_snapshots dashboard_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.dashboard_snapshots
    ADD CONSTRAINT dashboard_snapshots_pkey PRIMARY KEY (id);


--
-- Name: flyway_schema_history flyway_schema_history_pk; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.flyway_schema_history
    ADD CONSTRAINT flyway_schema_history_pk PRIMARY KEY (installed_rank);


--
-- Name: ledger_entries ledger_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_pkey PRIMARY KEY (id);


--
-- Name: mpesa_transactions mpesa_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.mpesa_transactions
    ADD CONSTRAINT mpesa_transactions_pkey PRIMARY KEY (id);


--
-- Name: mpesa_transactions mpesa_transactions_transaction_code_key; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.mpesa_transactions
    ADD CONSTRAINT mpesa_transactions_transaction_code_key UNIQUE (transaction_code);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: payout_requests payout_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.payout_requests
    ADD CONSTRAINT payout_requests_pkey PRIMARY KEY (id);


--
-- Name: payouts payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_pkey PRIMARY KEY (id);


--
-- Name: platform_transactions platform_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.platform_transactions
    ADD CONSTRAINT platform_transactions_pkey PRIMARY KEY (id);


--
-- Name: platform_wallet platform_wallet_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.platform_wallet
    ADD CONSTRAINT platform_wallet_pkey PRIMARY KEY (id);


--
-- Name: properties properties_account_prefix_key; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_account_prefix_key UNIQUE (account_prefix);


--
-- Name: properties properties_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_pkey PRIMARY KEY (id);


--
-- Name: sms_logs sms_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.sms_logs
    ADD CONSTRAINT sms_logs_pkey PRIMARY KEY (id);


--
-- Name: stk_requests stk_requests_checkout_request_id_key; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.stk_requests
    ADD CONSTRAINT stk_requests_checkout_request_id_key UNIQUE (checkout_request_id);


--
-- Name: stk_requests stk_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.stk_requests
    ADD CONSTRAINT stk_requests_pkey PRIMARY KEY (id);


--
-- Name: subscription_plans subscription_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: tenancies tenancies_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: units uktah7k94bauuojgt37fwjf0cch; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT uktah7k94bauuojgt37fwjf0cch UNIQUE (account_number);


--
-- Name: properties unique_account_prefix; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT unique_account_prefix UNIQUE (account_prefix);


--
-- Name: users unique_phone; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT unique_phone UNIQUE (phone);


--
-- Name: dashboard_snapshots unique_property_month; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.dashboard_snapshots
    ADD CONSTRAINT unique_property_month UNIQUE (property_id, year, month);


--
-- Name: wallets unique_property_wallet; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT unique_property_wallet UNIQUE (property_id);


--
-- Name: units unique_reference_number; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT unique_reference_number UNIQUE (reference_number);


--
-- Name: payments unique_transaction_code; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT unique_transaction_code UNIQUE (transaction_code);


--
-- Name: units unique_unit_per_property; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT unique_unit_per_property UNIQUE (property_id, unit_number);


--
-- Name: wallets unique_wallet_property; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT unique_wallet_property UNIQUE (property_id);


--
-- Name: units units_account_number_key; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_account_number_key UNIQUE (account_number);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (id);


--
-- Name: units units_property_id_unit_number_key; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_property_id_unit_number_key UNIQUE (property_id, unit_number);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);


--
-- Name: flyway_schema_history_s_idx; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX flyway_schema_history_s_idx ON public.flyway_schema_history USING btree (success);


--
-- Name: idx_ledger_entries_property; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_ledger_entries_property ON public.ledger_entries USING btree (property_id);


--
-- Name: idx_ledger_month_year; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_ledger_month_year ON public.ledger_entries USING btree (entry_year, entry_month);


--
-- Name: idx_ledger_tenancy_balance; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_ledger_tenancy_balance ON public.ledger_entries USING btree (tenancy_id, entry_type);


--
-- Name: idx_ledger_tenancy_id; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_ledger_tenancy_id ON public.ledger_entries USING btree (tenancy_id);


--
-- Name: idx_mpesa_created_at; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_mpesa_created_at ON public.mpesa_transactions USING btree (created_at);


--
-- Name: idx_mpesa_tx_code_unique; Type: INDEX; Schema: public; Owner: spin
--

CREATE UNIQUE INDEX idx_mpesa_tx_code_unique ON public.mpesa_transactions USING btree (transaction_code);


--
-- Name: idx_payments_created_at; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_payments_created_at ON public.payments USING btree (created_at);


--
-- Name: idx_payments_tenancy; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_payments_tenancy ON public.payments USING btree (tenancy_id);


--
-- Name: idx_payments_tenancy_id; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_payments_tenancy_id ON public.payments USING btree (tenancy_id);


--
-- Name: idx_payments_tx_code_unique; Type: INDEX; Schema: public; Owner: spin
--

CREATE UNIQUE INDEX idx_payments_tx_code_unique ON public.payments USING btree (transaction_code);


--
-- Name: idx_properties_landlord; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_properties_landlord ON public.properties USING btree (landlord_id);


--
-- Name: idx_stk_checkout_id; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_stk_checkout_id ON public.stk_requests USING btree (checkout_request_id);


--
-- Name: idx_stk_plan_id; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_stk_plan_id ON public.stk_requests USING btree (plan_id);


--
-- Name: idx_tenancies_unit; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_tenancies_unit ON public.tenancies USING btree (unit_id);


--
-- Name: idx_tenancies_unit_id; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_tenancies_unit_id ON public.tenancies USING btree (unit_id);


--
-- Name: idx_units_account_number_unique; Type: INDEX; Schema: public; Owner: spin
--

CREATE UNIQUE INDEX idx_units_account_number_unique ON public.units USING btree (account_number);


--
-- Name: idx_units_property; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_units_property ON public.units USING btree (property_id);


--
-- Name: idx_units_property_id; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_units_property_id ON public.units USING btree (property_id);


--
-- Name: idx_units_reference_number_unique; Type: INDEX; Schema: public; Owner: spin
--

CREATE UNIQUE INDEX idx_units_reference_number_unique ON public.units USING btree (reference_number);


--
-- Name: idx_users_email_unique; Type: INDEX; Schema: public; Owner: spin
--

CREATE UNIQUE INDEX idx_users_email_unique ON public.users USING btree (email);


--
-- Name: idx_wallet_property; Type: INDEX; Schema: public; Owner: spin
--

CREATE INDEX idx_wallet_property ON public.wallets USING btree (property_id);


--
-- Name: uq_active_tenancy_per_unit; Type: INDEX; Schema: public; Owner: spin
--

CREATE UNIQUE INDEX uq_active_tenancy_per_unit ON public.tenancies USING btree (unit_id) WHERE (is_active = true);


--
-- Name: ledger_entries trg_prevent_ledger_delete; Type: TRIGGER; Schema: public; Owner: spin
--

CREATE TRIGGER trg_prevent_ledger_delete BEFORE DELETE ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_delete();


--
-- Name: ledger_entries trg_prevent_ledger_update; Type: TRIGGER; Schema: public; Owner: spin
--

CREATE TRIGGER trg_prevent_ledger_update BEFORE UPDATE ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_update();


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ledger_entries fk_ledger_property; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_ledger_property FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: ledger_entries fk_ledger_tenancy; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_ledger_tenancy FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE CASCADE;


--
-- Name: payments fk_payments_tenancy; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_tenancy FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE CASCADE;


--
-- Name: payout_requests fk_processed_by; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.payout_requests
    ADD CONSTRAINT fk_processed_by FOREIGN KEY (processed_by) REFERENCES public.users(id);


--
-- Name: properties fk_properties_landlord; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT fk_properties_landlord FOREIGN KEY (landlord_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: dashboard_snapshots fk_snapshot_property; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.dashboard_snapshots
    ADD CONSTRAINT fk_snapshot_property FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: tenancies fk_tenancies_tenant; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT fk_tenancies_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: tenancies fk_tenancies_unit; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT fk_tenancies_unit FOREIGN KEY (unit_id) REFERENCES public.units(id) ON DELETE CASCADE;


--
-- Name: units fk_units_property; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT fk_units_property FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: wallets fk_wallet_property; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT fk_wallet_property FOREIGN KEY (property_id) REFERENCES public.properties(id);


--
-- Name: ledger_entries ledger_entries_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id);


--
-- Name: ledger_entries ledger_entries_tenancy_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_tenancy_fkey FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE CASCADE;


--
-- Name: payments payments_tenancy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_tenancy_id_fkey FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id);


--
-- Name: payouts payouts_landlord_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_landlord_id_fkey FOREIGN KEY (landlord_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: properties properties_landlord_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_landlord_id_fkey FOREIGN KEY (landlord_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tenancies tenancies_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: tenancies tenancies_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT tenancies_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id);


--
-- Name: units units_property_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spin
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_property_id_fkey FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: -; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON SEQUENCES TO spin;


--
-- Name: DEFAULT PRIVILEGES FOR TYPES; Type: DEFAULT ACL; Schema: -; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON TYPES TO spin;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: -; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON FUNCTIONS TO spin;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: -; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON TABLES TO spin;


--
-- PostgreSQL database dump complete
--

\unrestrict 6l3lgtnuwt1Fii1yG0qxAbrbHevZuMijRKn9ge1LrFztB0ETX5y63fHpwCMR1f5

