--
-- PostgreSQL database dump
--

\restrict 8sYmgbVpZ9aOHj0deSWegAV6nJsqrMfwu1wvduOoTTqqwNchQvEDrtUFk9HQF5y

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
-- Name: ledger_category; Type: TYPE; Schema: public; Owner: rent_user_new
--

CREATE TYPE public.ledger_category AS ENUM (
    'RENT_CHARGE',
    'RENT_PAYMENT',
    'WITHDRAWAL',
    'REVERSAL',
    'MONTHLY_RENT'
);


ALTER TYPE public.ledger_category OWNER TO rent_user_new;

--
-- Name: ledger_entry_type; Type: TYPE; Schema: public; Owner: rent_user_new
--

CREATE TYPE public.ledger_entry_type AS ENUM (
    'DEBIT',
    'CREDIT',
    'RENT_CHARGE',
    'PAYMENT'
);


ALTER TYPE public.ledger_entry_type OWNER TO rent_user_new;

--
-- Name: payout_status; Type: TYPE; Schema: public; Owner: rent_user_new
--

CREATE TYPE public.payout_status AS ENUM (
    'PENDING',
    'APPROVED',
    'SENT',
    'FAILED'
);


ALTER TYPE public.payout_status OWNER TO rent_user_new;

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
            u.property_id,
            t.last_rent_charged_date
        FROM tenancies t
        JOIN units u ON t.unit_id = u.id
        WHERE t.is_active = true
    LOOP

        -- Charge only once per month

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


ALTER FUNCTION public.charge_monthly_rent() OWNER TO rent_user_new;

--
-- Name: create_wallet_for_landlord(); Type: FUNCTION; Schema: public; Owner: rent_user_new
--

CREATE FUNCTION public.create_wallet_for_landlord() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.role = 'LANDLORD' THEN
        INSERT INTO wallets (
            landlord_id,
            balance,
            auto_payout_enabled,
            admin_approval_enabled,
            created_at
        )
        VALUES (
            NEW.id,
            0,
            false,
            true,
            now()
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_wallet_for_landlord() OWNER TO rent_user_new;

--
-- Name: prevent_ledger_delete(); Type: FUNCTION; Schema: public; Owner: rent_user_new
--

CREATE FUNCTION public.prevent_ledger_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'Ledger entries cannot be deleted';
END;
$$;


ALTER FUNCTION public.prevent_ledger_delete() OWNER TO rent_user_new;

--
-- Name: prevent_ledger_update(); Type: FUNCTION; Schema: public; Owner: rent_user_new
--

CREATE FUNCTION public.prevent_ledger_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'Ledger entries are immutable and cannot be updated';
END;
$$;


ALTER FUNCTION public.prevent_ledger_update() OWNER TO rent_user_new;

--
-- Name: process_payment(uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: rent_user_new
--

CREATE FUNCTION public.process_payment(p_tenancy_id uuid, p_amount numeric, p_reference text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_property_id UUID;
BEGIN

    -- Save payment
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
        now(),
        now()
    )
    ON CONFLICT (transaction_code) DO NOTHING;


    -- Get property id
    SELECT u.property_id
    INTO v_property_id
    FROM tenancies t
    JOIN units u ON u.id = t.unit_id
    WHERE t.id = p_tenancy_id;


    -- Ledger entry
    INSERT INTO ledger_entries(
        property_id,
        entry_type,
        category,
        amount,
        reference,
        created_at,
        tenancy_id
    )
    VALUES(
        v_property_id,
        'CREDIT',
        'RENT_PAYMENT',
        p_amount,
        p_reference,
        now(),
        p_tenancy_id
    );


    -- Credit wallet
    UPDATE wallets
    SET balance = balance + p_amount
    WHERE property_id = v_property_id;

END;
$$;


ALTER FUNCTION public.process_payment(p_tenancy_id uuid, p_amount numeric, p_reference text) OWNER TO rent_user_new;

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
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: rent_user_new
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


ALTER TABLE public.audit_logs OWNER TO rent_user_new;

--
-- Name: dashboard_snapshots; Type: TABLE; Schema: public; Owner: rent_user_new
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


ALTER TABLE public.dashboard_snapshots OWNER TO rent_user_new;

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
    entry_type public.ledger_entry_type,
    category public.ledger_category,
    amount numeric(38,2) NOT NULL,
    reference_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    tenancy_id uuid,
    reference text,
    CONSTRAINT ledger_amount_positive CHECK ((amount > (0)::numeric)),
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
-- Name: payouts; Type: TABLE; Schema: public; Owner: rent_user_new
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


ALTER TABLE public.payouts OWNER TO rent_user_new;

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


ALTER VIEW public.property_summary OWNER TO rent_user_new;

--
-- Name: sms_logs; Type: TABLE; Schema: public; Owner: rent_user_new
--

CREATE TABLE public.sms_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recipient character varying(50),
    message text,
    status character varying(50),
    provider_response text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.sms_logs OWNER TO rent_user_new;

--
-- Name: tenancy_balances; Type: VIEW; Schema: public; Owner: rent_user_new
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
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    property_id uuid,
    CONSTRAINT wallet_balance_non_negative CHECK ((balance >= (0)::numeric))
);


ALTER TABLE public.wallets OWNER TO rent_user_new;

--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.audit_logs (id, user_id, action, entity_type, entity_id, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: dashboard_snapshots; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.dashboard_snapshots (id, property_id, year, month, rent_expected, rent_collected, arrears, created_at) FROM stdin;
ce47d1bd-1358-4888-a518-7e5496f9212f    f128186e-47c5-4ed7-aea8-a7295376f35d    2026    3       25000.00 0.00     25000.00        2026-03-14 22:49:27.16718
63522310-8e2f-4229-8529-39c454e26dac    53009a0e-37a7-475b-b7fe-ae3419103b04    2026    3       2000.00 0.00      2000.00 2026-03-14 22:49:27.200219
a706d389-bc40-46fc-a6d1-e9782d8f47d9    21003980-9dd5-4490-9ed4-3d5f4e7164c8    2026    3       20000.00 0.00     20000.00        2026-03-14 22:49:27.208119
e2946ad9-ea5f-4f00-b367-f3d423f006fe    bc053a7f-8dd4-4c8b-adb8-8cc9a54d2e8d    2026    3       0.00    0.00      0.00    2026-03-14 22:49:27.216205
406591db-cf93-46c7-8faf-074585d2c05d    16985376-25d3-4fc5-b049-a7e72b8d4182    2026    3       0.00    0.00      0.00    2026-03-14 22:49:27.224527
69df7264-86df-4a90-b75e-553d963f4253    accc69fd-93b1-4739-940a-0483fc07fa09    2026    3       38000.00 12000.00 26000.00        2026-03-14 22:49:27.232173
d0c40ae5-fc55-4240-a2c4-03150fef08b6    805407c1-b6fc-4154-865f-824883d91e05    2026    3       0.00    0.00      0.00    2026-03-14 22:49:27.239699
d053ad9f-b830-4926-bc69-95803b41aeb8    a99520a0-5799-45c7-8382-fa183de6cf54    2026    3       0.00    0.00      0.00    2026-03-14 22:49:27.2471
4583974b-83ba-48ff-9992-a4396dcce972    29fa61c8-b97c-486d-95ae-aadcc1c1a4fb    2026    3       0.00    0.00      0.00    2026-03-14 22:49:27.257651
\.


--
-- Data for Name: flyway_schema_history; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success) FROM stdin;
1       1       init    SQL     V1__init.sql    1333074512      rent_user_new   2026-02-18 15:17:21.81914639      t
2       2       fix charge monthly rent SQL     V2__fix_charge_monthly_rent.sql -320625225      rent_user_new     2026-03-03 13:34:05.75561       20      t
3       3       add foreign keys        SQL     V3__add_foreign_keys.sql        -2139509895     rent_user_new     2026-03-03 13:34:05.804244      23      t
4       4       add unique constraints  SQL     V4__add_unique_constraints.sql  977706592       rent_user_new     2026-03-03 13:40:47.516283      15      t
5       5       add indexes     SQL     V5__add_indexes.sql     -1161627252     rent_user_new   2026-03-03 13:42:04.08444 13      t
6       6       ledger category enum    SQL     V6__ledger_category_enum.sql    976534492       rent_user_new     2026-03-03 13:43:53.759896      20      t
7       7       create payouts table    SQL     V7__create_payouts_table.sql    -25697975       rent_user_new     2026-03-03 13:43:53.800065      4       t
8       9       audit logs      SQL     V9__audit_logs.sql      -1350729087     rent_user_new   2026-03-03 13:43:53.815887        3       t
9       10      financial hardening     SQL     V10__financial_hardening.sql    883621684       rent_user_new     2026-03-04 13:24:26.540454      20      t
10      11      ledger immutability     SQL     V11__ledger_immutability.sql    -846777132      rent_user_new     2026-03-04 13:36:29.825082      8       t
11      12      dashboard snapshots     SQL     V12__dashboard_snapshots.sql    1756503060      rent_user_new     2026-03-14 18:06:10.141118      19      t
\.


--
-- Data for Name: ledger_entries; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.ledger_entries (id, property_id, entry_type, category, amount, reference_id, created_at, tenancy_id, reference) FROM stdin;
0797314f-f469-4018-a7f1-6855efd35ec5    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   RENT_CHARGE     2000.00   48a4c1e4-1103-4b27-bf95-f2b7355f24b7    2026-02-27 20:57:20.27433       48a4c1e4-1103-4b27-bf95-f2b7355f24b7      \N
99d6cf7e-adf9-49a2-bd73-cfd898795ccf    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   RENT_CHARGE     20000.00  f3d8da6e-1469-4374-ab01-e065b2950c5f    2026-02-27 21:05:37.817221      f3d8da6e-1469-4374-ab01-e065b2950c5f      \N
de2947a3-7294-4f47-8ba7-560742463c29    f128186e-47c5-4ed7-aea8-a7295376f35d    CREDIT  RENT_PAYMENT    25000.00  1a452875-34b5-44ab-bb51-b4fb45f78a60    2026-02-27 16:47:39.886364      80dc3bd0-cab8-4365-b49a-27fedcab74b2      \N
5a9b0a83-04c5-466c-83f8-2aad3ec0e848    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     2000.00   8ba2678c-72bc-4255-8ec9-f2cdafe461de    2026-03-04 16:37:09.264658      8ba2678c-72bc-4255-8ec9-f2cdafe461de      \N
7cf72239-2b46-41a4-8511-76e95ca09656    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     2000.00   de154a94-4abd-493c-b4f8-1a58a8c4e632    2026-03-04 21:51:10.118703      de154a94-4abd-493c-b4f8-1a58a8c4e632      \N
b983fbd6-0f92-4007-8999-6326836563c2    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     2000.00   991ef00c-a4cd-43de-972d-09064693e803    2026-03-05 18:15:11.129213      991ef00c-a4cd-43de-972d-09064693e803      \N
c21c6d7c-0ba7-462d-b88e-ad2b62ff3b76    accc69fd-93b1-4739-940a-0483fc07fa09    CREDIT  RENT_PAYMENT    2000.00   8e9fb4d0-0b1f-4b95-807a-9d20075b8c4f    2026-03-08 15:31:15.145467      991ef00c-a4cd-43de-972d-09064693e803      \N
81490d9f-72e7-4c2d-ad20-b938de47a12e    accc69fd-93b1-4739-940a-0483fc07fa09    CREDIT  \N      2000.00 \N2026-03-08 15:31:15.145467      \N      TESTPAY012
36ce8bff-2367-4333-906c-4f9e92eda042    accc69fd-93b1-4739-940a-0483fc07fa09    CREDIT  RENT_PAYMENT    2000.00   aef046d4-3cd7-45e7-8ddb-6d46fcf8ea1b    2026-03-08 15:36:06.850222      991ef00c-a4cd-43de-972d-09064693e803      \N
bcd6dce6-46d2-4de6-a787-091ddf78efdc    accc69fd-93b1-4739-940a-0483fc07fa09    CREDIT  \N      2000.00 \N2026-03-08 15:36:06.850222      \N      TESTPAY013
29a74888-aff6-4597-a747-655141f74d68    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     3000.00   5330efaf-2134-4ef4-9f6c-65851f7d896f    2026-03-08 16:41:20.652961      5330efaf-2134-4ef4-9f6c-65851f7d896f      \N
8c336439-dc94-42e6-8ebd-640a4b978340    accc69fd-93b1-4739-940a-0483fc07fa09    CREDIT  RENT_PAYMENT    2000.00   d5fdf070-cf23-4ebc-ac86-419333defeec    2026-03-08 16:47:55.482869      991ef00c-a4cd-43de-972d-09064693e803      \N
7b4e4403-1c9a-46ab-baaa-3cff57dd4c5d    accc69fd-93b1-4739-940a-0483fc07fa09    CREDIT  RENT_PAYMENT    2000.00   \N      2026-03-08 16:47:55.482869      991ef00c-a4cd-43de-972d-09064693e803    TESTPAY015
b83fa64c-677a-48df-808c-90a7bbe4579d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     3000.00   4f4de413-2957-42c7-be91-0e03e4af7966    2026-03-08 17:37:51.853927      4f4de413-2957-42c7-be91-0e03e4af7966      \N
0d3139b7-a3cb-421a-92ae-28922fe22223    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     5000.00   9b567931-7dd5-41a9-9db5-33a9bfbba6a0    2026-03-08 18:48:51.583642      9b567931-7dd5-41a9-9db5-33a9bfbba6a0      \N
1498ab66-6c38-4f55-852b-72531ce61b32    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     5000.00   77b8d7c6-5fce-448d-ac6b-a67dd40d2ba6    2026-03-08 18:54:38.319655      77b8d7c6-5fce-448d-ac6b-a67dd40d2ba6      \N
2046dfe9-7903-44d0-844f-a73b34d8c59e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     2000.00   b6b666c8-bff8-4c50-9bff-84cac8634ca1    2026-03-10 21:14:46.864124      b6b666c8-bff8-4c50-9bff-84cac8634ca1      \N
4104af7b-16a0-49ea-ab37-34da10c31150    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     5000.00   69918614-bb8b-4e25-b70f-a513e038ecfe    2026-03-11 19:19:15.58851       69918614-bb8b-4e25-b70f-a513e038ecfe      \N
ec0a33ac-7ea5-4c5b-8a99-f97291d67732    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-14 19:11:00.023571      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
01f82785-bca4-42ad-968a-abe3d2266dc0    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-14 19:11:00.023571      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
2f1cf0c1-c7c2-4391-9603-63914b633ffa    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-14 19:11:00.023571      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3fee1de6-c663-4c46-a49d-3b309f8480e2    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    5000.00   \N      2026-03-14 19:11:00.023571      69918614-bb8b-4e25-b70f-a513e038ecfe    \N
02e6adc8-534a-429f-acf6-bf04cd68cb22    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   RENT_CHARGE     2000.00   9f21396e-7416-46ef-b981-ba43a36ff6e7    2026-03-14 22:44:02.680434      9f21396e-7416-46ef-b981-ba43a36ff6e7      \N
fc2608f6-c3f0-4dad-8ef1-ef228326cddd    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-14 22:44:03.000638      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1bb8cc27-1240-4e86-bc63-21a8f827b626    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:14:51.001217      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5c38a3ba-2de1-4793-8bdd-02aa34f62488    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:51.001217      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8b7a0faf-cd6a-432d-a253-8c470c42dc37    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:14:51.001217      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
5c52645f-0547-4b97-b71f-1273b66ab906    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:51.001217      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
051100d8-de61-4ea3-bdac-7e820536637d    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:14:52.000748      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8d319aad-38a1-421f-9fd9-685e40a71159    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:52.000748      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
537d0533-ba9c-4fd6-9da9-11b090331603    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:14:52.000748      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
dae328d4-25d3-4679-92c4-af5a366fc5de    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:52.000748      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
692e7c3c-7d01-462c-aa65-93566786a770    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:14:53.000526      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5e39bad7-a131-4556-8854-eb2579ba4679    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:53.000526      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9a501a2e-241a-4407-96ee-f6ef61c4d6cb    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:14:53.000526      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
afc6827e-378d-42c6-9f56-65b0a0c868d3    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:53.000526      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
bbb827f5-549a-43db-9e7e-ffaa50ecbbe7    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:14:54.000645      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
944b2b8b-b42a-4159-84c2-319c3b6be918    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:54.000645      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
df8ec141-230f-49a0-ad78-17acb82a4650    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:14:54.000645      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f5ee76be-0c0c-42e5-8c62-4240f81b4460    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:54.000645      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
466ea80d-d583-4812-8d1f-5fd3a6e31f37    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:14:55.00049       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7f102f3e-16c5-4100-9071-2dd201aa3ce6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:55.00049       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d622070b-3ed4-46e8-9c37-cdf94f712b49    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:14:55.00049       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e72651e8-ab07-4cfa-bbb7-58155a937ac5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:55.00049       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d45c8ccc-bc98-4d67-9842-179089e5785e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:14:56.000582      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
28a1d41f-5fdb-49f4-84a6-fdb3780660c5    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:56.000582      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
edfa91c7-0961-4f22-a2f9-9ec2d3dd4bb0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:14:56.000582      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
fb62045e-0c7f-41e9-8385-ac2c4bb7d653    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:56.000582      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
886d7ddf-fffc-4701-a2f5-5a852242bfbd    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:14:57.000566      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6ebceedc-22fa-473e-8802-56ba4e9c6be8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:57.000566      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a40c88a4-66af-48f4-bea2-379d71fad5b7    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:14:57.000566      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f91d9492-acf9-43ac-b666-3aac59c087e4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:57.000566      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d353c50c-1c56-4655-96eb-2fc96b161445    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:14:58.000426      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d3679632-0690-40df-a5a2-f27dc8f1148d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:58.000426      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
6a32f97a-a5f2-4317-bf32-6c65554b3e99    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:14:58.000426      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
69e48ab5-a4f1-4d86-8302-bc5032e73456    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:58.000426      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
7c0006dd-504f-4de2-9854-2bdca0075dd4    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:59.000404      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
f7724fec-bfb5-49b4-bca0-9439558e8480    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:14:59.000404      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
41c85386-78aa-4154-9a73-6f322976a8a1    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:14:59.000404      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
9b615af2-1bc2-4e00-9417-86c23131472e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:14:59.000404      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
4c833995-b7a9-4cea-8643-0a7c0ef04d46    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:00.000399      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
f44f0cad-4b85-4f4e-a9f3-9e467aa6a559    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:00.000399      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f1522f07-16f3-496d-a94e-64fb7a29bf26    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:00.000399      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
05032bd8-27ae-4572-a983-3bbf9c09fd08    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:00.000399      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
2725451d-3162-41f6-a246-64f0070af800    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:01.00054       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
cb503076-96ef-420d-9159-e68985d160e6    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:01.00054       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
45d18134-fca4-4abe-a027-e952b0e3c94c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:01.00054       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
9384cdfe-46b5-4aec-92be-a5a5cdf340c8    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:01.00054       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
32abb61c-0261-4d05-b77c-87c29882008a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:02.000558      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
c96d13f2-1e74-4e88-a92d-96f98ad9c266    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:02.000558      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
a3361461-28ee-41b7-9e9c-a6dce40c21d9    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:02.000558      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
52581e05-8dc4-4eac-9333-f96290632b3c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:02.000558      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
3fce6b98-6ace-4eff-9c8d-6e9411e8323c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:03.000553      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8be94d0e-a213-4a35-a544-99d8d1292411    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:03.000553      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
147f3386-67df-4c11-8b37-47416a1f112a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:03.000553      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
7c8f28cf-8ab7-435d-abd2-2b246e7f2e2b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:03.000553      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d954ff64-9eb3-466c-acdb-da57bb44dcd8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:04.000387      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
2d72ac85-a9ef-4608-8386-63b4b224bc79    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:04.000387      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
864ee8c3-0706-49c9-a266-d688565e68bf    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:04.000387      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8fccd235-8522-4b76-a874-df78d36f6e5b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:04.000387      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
575cdcbb-3e4e-4885-995d-071d9221894f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:05.000633      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
df72f28b-2261-49d9-8ac3-90167045650a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:05.000633      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
22f8a753-094b-48d9-95a4-45f1ccd4bec2    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:05.000633      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8fa7ec6c-89f8-448a-8944-2aa9b52d4b69    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:05.000633      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
c1d8c9bd-8e62-4525-8a66-e8c4c66e4baf    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:06.00059       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
041b13ef-7c4d-4182-bf6a-e5dd69d13364    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:06.00059       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
d5cce764-9808-4aa3-a9f4-dd9e2b4fdd98    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:06.00059       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
6479e777-9a89-45da-90d2-5619b703adf7    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:06.00059       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b66e8df5-f4e5-46d6-8b74-c1f54f564bd3    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:07.000651      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
486b8dc6-53a7-4506-b4bb-b2815cb3a96d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:07.000651      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
39464e6b-601d-4129-aeb6-424fed10619d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:07.000651      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
986df56e-4804-4f53-bd46-03dcc3e3922f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:07.000651      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
3a709aa9-75cc-4fb2-93c2-b630738f1ed7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:08.000465      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
fe80cc64-b87c-496b-95cf-4b0ad304c936    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:08.000465      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
57eac314-c839-4600-8705-0055df2e3f73    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:08.000465      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d1522a45-6452-4b54-a163-75cad220abe6    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:08.000465      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ba3975cd-df5d-4df4-b759-3b1a30094a0a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:09.00052       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
6172e10a-9870-4a43-aaeb-99acf8c0d4c0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:09.00052       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
519e06c6-a8fd-4433-b08c-a1e81c00ae66    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:09.00052       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
40e69ba8-390e-44e2-af25-123acc8107fc    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:09.00052       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
428fa1d4-5203-4aec-b611-b8e56c516fe1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:10.000478      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
22fdfc8c-fc74-4339-9096-fa52d90ae482    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:10.000478      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
d7eef380-b92e-4f7c-88f1-4b802c5cc8a7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:10.000478      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
14e35554-bc55-4c2d-a043-65021f3a7242    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:10.000478      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ea360b2a-62b5-4958-9e5e-f05dd45ca2da    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:11.000596      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f740a3c5-98a1-4a93-8fb7-cbecf41ebb97    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:11.000596      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
aca372cc-304a-4833-90b3-c2ee58d64439    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:11.000596      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b4a88a9d-3699-416c-9d87-1fb054e097ab    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:11.000596      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
8358a5e8-f570-4199-83ec-3eb319b69cd4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:12.000626      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ad65cddc-28d4-4482-99f8-e7d09c783ba5    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:12.000626      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
bd8f63c9-78bd-418b-90af-8a42bda5b7cc    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:12.000626      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
bc452c2d-28fd-43f3-a835-edad66589e36    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:12.000626      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
925ebac2-b774-46e8-9d54-326803560089    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:13.000566      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c647d0c0-3d40-455b-97bb-a92cfad17924    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:13.000566      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a7c71646-5001-4be6-8ce6-ec0a2258e6e1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:13.000566      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
3b00352d-756a-4ec8-907a-24808ece9e2a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:13.000566      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7959ea69-20ff-45ab-b5df-f8e4ce9d7fd7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:14.001405      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
0670de89-ba2c-43ca-a1c5-c6dd92f6cdae    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:14.001405      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
381b7f14-b1e2-43ea-b37f-505b4bf45966    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:14.001405      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
e3d4185e-f67a-4d8e-8e0a-7d95ede8ec68    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:14.001405      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
429a0ad9-0d71-4d25-9c60-92de9bc3b987    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:15.000533      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8b114fa9-c392-4475-90d1-60e37bf19de8    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:15.000533      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7733f23f-f8e8-4825-82da-f3c40e438f7c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:15.000533      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
f3213448-3dd2-421f-a941-07811005e74a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:15.000533      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ef95a2c0-6870-4160-9b0f-ae3f457f4ed2    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:16.001154      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1e6562d8-7ad3-4f0b-bc1f-f757eb0a8bac    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:16.001154      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
12dddff5-668d-4ee9-8dcb-c77e1ebeb58f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:16.001154      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
1bc84dbf-4f93-4996-97a5-21673b208047    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:16.001154      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
699631f2-df53-4796-931c-8806e3892b5a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:17.000487      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
26ebd599-bec2-42f8-b356-cb7f8a4052aa    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:17.000487      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d7d9cd94-0955-4b4d-8d65-adeeecd4c9f3    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:17.000487      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
462b3094-7f87-4e5e-aa25-0ed8c02de921    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:17.000487      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
a88774e4-4af4-40d6-a4e1-d38963815a49    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:18.00052       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
407aea15-4dda-4d90-83bf-5b5ca287e715    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:18.00052       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
c867dda7-7ad9-4300-97ae-3b90ef81d8bf    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:18.00052       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
bdc8ee25-f309-4517-9930-7c0dca1ab25b    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:18.00052       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
221b2039-f3df-474c-85ca-4c88f76f5633    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:19.000615      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
bbde7d11-65b0-4194-a118-1cfe655d2814    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:19.000615      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6b937159-2bbd-4e49-83fc-f5f27e00e04a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:19.000615      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
256c4c60-d87d-4555-95e6-8ac8fab25a18    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:19.000615      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
2fcb71a0-1fa6-46db-a9b9-68132a7eef3e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:20.000789      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5fea43d2-7434-4677-a892-c7da06f297f7    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:20.000789      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6d381936-e8da-431b-bdf7-4746e95cd2ba    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:20.000789      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ceb93629-6135-4fda-b1b3-8ad86ecf4c7c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:20.000789      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e77706ef-847c-4d9b-b0f6-63786af7d312    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:21.000621      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
fb88e818-9680-43e4-bb83-030dbb06e3d2    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:21.000621      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
f1205308-c9f1-4331-be51-e8093fc89c19    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:21.000621      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
94d608e3-7f06-420c-9f52-8ea91429f453    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:21.000621      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
35812e71-2d34-408e-8471-0208833311cb    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:22.000528      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
78e71ba6-90c8-46bb-809e-047719f10143    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:22.000528      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
4c8db666-1beb-4e58-9efd-7b49f58160c0    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:22.000528      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
0f18756e-84d8-4798-ae4e-8bd3007e6a41    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:22.000528      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
d65e41d1-7772-434f-923c-e64cdc0649f9    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:23.000693      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
febbf164-0f40-448e-b77a-32157b61ea6b    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:23.000693      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c5d777d7-06d2-4f12-a0da-35991326b6aa    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:23.000693      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f701f4ff-c560-44eb-8ce4-405b0547309e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:23.000693      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
44b1f0cd-f3d4-4e83-aed0-81c3aafa81e0    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:24.000629      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b2c8c2b6-8f19-4ff7-98de-0a45e62ba7c7    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:24.000629      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
0c0aaecd-faa0-434c-a65f-53f7d406970d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:24.000629      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
e62a170f-cf23-43d0-b3b1-950e0794df61    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:24.000629      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
01192519-3764-4e2f-ac91-9becd09ba6f7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:25.001611      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
12428b84-b948-483c-ab1d-a40d38cc283d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:25.001611      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9f9e49e2-c4b5-444b-a02e-66ac6d7e4a3b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:25.001611      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
a5688aa8-6b58-48db-9cbe-96fcedde65d1    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:25.001611      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9f118dfc-2ae1-456e-be4c-0e55d4a203ba    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:26.001484      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
222a347e-fd35-4be9-9226-3b95a5f8538c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:26.001484      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
da46e39e-99d2-433c-bd33-47b1bcaf8f6b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:26.001484      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
4572f2d3-3183-4584-9afa-d30a4407019f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:26.001484      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a8b80bcb-46cf-4cfb-a6ce-72cec8f9a4c7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:27.00051       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
c9fbbb22-1942-43f7-9793-170f66b9f3c0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:27.00051       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ea2bc0d0-a288-43b6-b4db-650e32123369    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:27.00051       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
816fec82-4662-49fc-96e7-6951caae2ef9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:27.00051       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8abccaf8-a5dc-4f9d-a986-4b686c16d1b4    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:28.000646      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
1ffb64ef-67d8-4f7a-8eb0-cbc478201182    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:28.000646      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4529fb7d-e808-4e44-bdca-9cd1fd7c20d6    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:28.000646      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
276dc322-a804-4768-abda-bdddc3d894ba    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:28.000646      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
062153cc-e50e-4697-8a3c-6ffdf4748293    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:29.000584      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ee794044-af4a-453d-9eba-e0cd8ac3a2fb    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:29.000584      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
77484e5f-2daf-4b89-8f55-9b58d53ee42a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:29.000584      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ea9d8cb8-a4c4-41ca-8905-de4e3e0ea100    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:29.000584      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
31f53402-6b20-4de0-8bac-2bb381ded8a1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:30.000722      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
bd75f45f-826a-407b-98fb-32e2586cbbc4    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:30.000722      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4ec64676-d8a7-4bd1-a6de-df2346769197    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:30.000722      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c901bd57-dcb0-4c6c-87ae-0afeb938a3b4    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:30.000722      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
12dfa25e-2dfd-47dc-afaa-23a646f5b0ba    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:31.000484      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ef10b634-7c03-4ae0-a6f7-4670675d8071    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:31.000484      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
8b6bac36-1066-4174-8d9d-0d3c3ec0853e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:31.000484      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d41be051-24a2-4296-b28b-f434c169f86f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:31.000484      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ffe0dfdf-e1bd-4e68-91b3-cd62dbfc48dd    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:32.000658      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
bc3acc4e-7873-429e-be42-720d0906f299    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:32.000658      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
76771949-ee4d-431d-a6b5-8a71d0ebb4ea    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:32.000658      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
bcaeddb0-96b1-4fe6-9b27-d2234270b04a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:32.000658      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
78096ea4-fecf-41be-b844-2ccde788e697    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:33.000494      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b1cb19dd-35d2-4ec8-9131-710bb6b7825f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:33.000494      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ac3f4515-942c-4e81-86d1-7d63616f59c5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:33.000494      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5a94a73f-d14c-44d1-8997-8507aeb7a4bf    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:33.000494      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
4467339a-8f55-4cf0-a3b8-8e074af70cca    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:34.000583      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
74cb89e3-7dc0-41f5-88d9-d10b582f73ae    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:34.000583      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
09c73aca-0e6d-4cdb-bd73-07ab2bfdfa99    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:34.000583      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
0b7b3759-8a1c-46eb-a0f0-5b80d27275a6    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:34.000583      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
1cc32333-8269-447e-a8c0-8e0f9e0d83da    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:35.001525      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
033ea260-b3ce-4f06-a3eb-1eb2072d4b5b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:35.001525      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
70feea27-4f6e-43c9-b9f1-f4a2ac70af71    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:35.001525      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9d2ed369-1af4-4a05-aa91-2c7bdb12acba    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:35.001525      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c4c6d9a9-a8b2-486c-9e8b-4f12b4ab6d58    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:36.000524      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c9c85b23-3e72-44c0-b4d9-7a09b2237c4a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:36.000524      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
4e4f2c74-978b-455b-9d07-438c3b5ecc8d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:36.000524      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
e69bc580-0d25-4ed1-a34c-cee9151646d3    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:36.000524      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7b4898f9-c249-4bee-8bca-06dd4cc13595    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:37.000585      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
39dc63bf-02f9-4fcb-97e4-597bd2d30373    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:37.000585      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
60ea02a6-93d1-4953-acd6-575520bec98e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:37.000585      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
43d6adeb-b3c0-4842-b42d-98cdce0d74bc    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:37.000585      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
faa7cb30-1472-47ae-bcfc-e28dbd21f6e2    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:38.000867      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
40f2ae8d-8b52-491d-98d5-6c7367caa943    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:38.000867      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
c3a6cade-50fd-45ca-bcf0-2d4877043962    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:38.000867      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
542747dc-37e4-4ea8-8f2e-6a03981d92ca    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:38.000867      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
616dae37-e6ca-489e-9804-02003f382169    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:54.023647      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ff126b04-c841-4898-bbbd-dc09e33e08c9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:54.023647      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d85ee3bf-363c-4385-bea2-b3e65fbf16dd    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:54.023647      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
1c6438b3-4ac8-492d-9aad-8dac1abbc148    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:54.023647      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
5d6af024-e353-4264-9532-288c24675b41    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:55.002699      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
3bd0b521-e84a-4f24-920a-80dd37e04f81    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:55.002699      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b9ca185e-c301-4df8-88d0-e1b6fe75a9a7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:55.002699      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d77df538-875a-4e19-b3c3-6b472c2d4afe    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:55.002699      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
815f16f3-8a8a-4ded-b3a3-dbb48ac0847b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:56.002752      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
b543af8c-13c0-4ff0-aeda-89022cc71a11    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:56.002752      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
3918c9cf-1f92-42ed-abc7-6c16a8085654    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:56.002752      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
48f6aea3-88c4-48fe-a86d-fe45700b2145    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:56.002752      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1626f3e2-4797-44ab-b847-4f3fcd3801ec    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:57.002696      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d8b21617-bfbd-4eed-abcc-a375f291cd49    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:57.002696      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
eb2da0bb-2da5-4143-8ec0-961ee8f005a8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:57.002696      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
86755b1a-e9b3-49d5-be5a-0e527e3afd42    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:57.002696      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9602c378-3b07-41d4-98bf-e33e5894a99b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:58.001063      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d92b6896-b9be-4f3c-872d-69d614ff3768    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:58.001063      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5ae886f7-1b47-4674-a997-a0c08adac3da    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:58.001063      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b8c61f7a-83e2-4462-af1c-52289eb26139    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:58.001063      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
0dddf38d-aa73-4454-8f2d-240d78251bc7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:59.00214       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d0a98341-4a09-451f-9fa9-27e37fbd7918    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:15:59.00214       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0f4edc0b-a864-4c21-9b87-db1a04ef4595    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:15:59.00214       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b8bbf5d6-8edb-441d-84c6-b5797d2bfe92    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:15:59.00214       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f0eddb81-c48f-4f23-8ae1-64d6d9f7aa0a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:00.002794      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
a5ac4a26-748f-406b-b206-1390c0d172c4    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:00.002794      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9f3e1285-c5c9-45db-9e82-c4843d3657dd    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:00.002794      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d1856797-d7c9-4dfa-9019-586856f7e3b3    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:00.002794      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f87a8366-3351-49bd-9a05-0c765e8274b5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:01.003293      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f29c863e-0301-41fb-a68d-a4ee64592952    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:01.003293      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d33cc523-22b4-4b7a-8109-4f6e6ff2a721    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:01.003293      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
42aef5ea-1aba-494d-82ac-f57e5dd2c2cd    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:01.003293      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
55de0a6c-af7f-4185-87bd-b22a226c8fed    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:02.000874      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a77d8800-8342-49a1-ab57-9c997f4a5726    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:02.000874      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
10f2308c-1330-4163-b2e1-11f095bef851    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:02.000874      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
abcbde27-1ef1-4dff-96e4-6e1d82f55d8c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:02.000874      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a1d3ae28-5727-43b9-814e-a671809aa79c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:03.002387      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
1e1f8627-d8ef-4cf5-8af2-5a2b82a90d85    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:03.002387      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4d266764-66b5-4042-98cf-059f0f4e51be    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:03.002387      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ac17cf4e-4617-46dd-916e-99864c707656    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:03.002387      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
21df995e-a36d-4b78-89be-6cbae5e2bb5e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:04.001908      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d524f2f3-5ad8-4eb2-8ac2-d120c558c800    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:04.001908      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
6f99994b-f534-433c-b4d1-83bc9fc0d8a1    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:04.001908      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d21871cf-84ed-40b9-b790-6bae07b337c9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:04.001908      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ea8dcdae-9856-45c4-86e3-267a7ec69e84    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:05.001247      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
7c2314c4-27bd-4ffc-9394-cc50cb640f3a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:05.001247      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
6271856a-b6af-4648-9e9e-975d7cbca5e9    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:05.001247      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
eebeb25a-d7b0-4963-867b-ac45c53713d3    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:05.001247      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
3a3c9195-4b68-4990-95b4-2d9e2b4e6505    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:06.00145       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4ecfdf71-efff-46d8-b3f6-7fc8a6d84d89    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:06.00145       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
814ae2b0-2598-4a76-b0f2-1f0134f7cada    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:06.00145       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
9d090ea8-b737-4415-990d-738d8800f12f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:06.00145       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5a8c97b9-5ae8-4f7a-8db3-789af47bb33c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:07.00254       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d2a6ce13-d523-4b3e-a987-ec93766c2207    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:07.00254       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
2033703e-de48-4abb-ac9b-3197c7f620a3    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:07.00254       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
7505a224-9c6e-40ea-8391-a0970e4fae82    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:07.00254       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d325eb59-df73-451f-8e4f-148178f5566a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:08.00248       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
20467fe2-02d4-4889-8c08-d5e70577634f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:08.00248       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
bb9a99da-5c31-4982-bc88-0668ac303d19    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:08.00248       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
21b9d4b7-d969-4a68-addf-1377de22e52b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:08.00248       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
18398c85-21b0-4274-a053-e1b48cddea4e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:09.00235       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
41382ae2-44ba-4ffe-8cf9-39dfc1d73570    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:09.00235       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
50f187c8-77e6-4ab8-ad77-5ec95835c5c2    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:09.00235       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
44f56264-51f8-4cd6-9289-49727528125b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:09.00235       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6323da4c-bd47-41cb-bad8-218a8939f07e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:10.002732      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
3319c5d3-497b-40ee-9411-81248f99309d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:10.002732      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
349f5037-48e9-4f20-8e93-302a2c256d3e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:10.002732      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
625ee126-149d-425f-8c73-13becc5322ba    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:10.002732      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8c12e5f2-5189-4183-a114-9a4954f57e6b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:11.002278      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
eec9936c-5221-44f2-bc8c-a2f81233e18f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:11.002278      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c1aeb5f0-832f-4c0a-80db-2b845008c4c4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:11.002278      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d213dddc-355f-4a16-98e7-7b3abf4e5564    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:11.002278      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
93e1cdf1-f3d0-440b-9131-eb1f8a65f758    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:12.002646      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
44c0daca-3458-4797-921b-dc201ab979ed    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:12.002646      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
a6fc63a8-9943-4366-b272-e7d37ed61575    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:12.002646      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1b52db9a-46d2-4479-b2a5-c314d44dab7b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:12.002646      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
abcaf5ea-fa60-4bf7-ae09-9e16f6b641e5    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:13.002041      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
57c51bb4-459d-4833-b291-0e7c3460ac46    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:13.002041      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
148e9e69-b3ec-402c-9893-0c6dd1a485da    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:13.002041      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1792e8d5-b222-422c-90bf-6a8bccae0729    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:13.002041      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
f0b0d80b-615d-4675-9767-b78d9fba4b31    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:14.002318      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f0466924-6ec6-47e1-b353-51b066d05df5    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:14.002318      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
91c62209-dcd0-4f94-a33c-375463b8b7e7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:14.002318      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4d411733-bc52-4c1f-a0fa-be874b401347    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:14.002318      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9f7a6459-9474-44cc-8c58-006853a76414    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:15.001419      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
726c35ec-8f6a-4b64-a5d2-794038148e2d    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:15.001419      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
910b378c-bdad-4dc9-af42-94a228189999    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:15.001419      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
dddbf30c-6d89-412e-aa39-322b123cc0cc    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:15.001419      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
88e0dac6-826e-4030-b5d6-f433f6d28172    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:16.001875      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
450d8272-d358-49ee-8789-fa4f04afbe39    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:16.001875      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9ee14188-2fcc-4acb-8c02-494caa53960b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:16.001875      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d5203e92-9a50-4146-93bc-6debda48b346    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:16.001875      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
aa8a324a-f8a4-4243-8aa6-291ad83571a5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:17.001268      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
af411eb9-353f-4a49-b393-96203dc50ca9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:17.001268      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9aa96c54-3e24-4513-af53-19b187a91268    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:17.001268      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
1041fe65-15aa-46cf-a075-a908f6794c49    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:17.001268      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
61b9ddb3-8e5d-4bff-9bc0-75c3c583821b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:18.000943      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
cf56d912-a385-41f4-ad60-db84363bd2cb    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:18.000943      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
f00a01ec-da71-4461-9a15-915e38bd47d9    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:18.000943      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
83f16904-2295-41a7-8f18-3118bc7560f4    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:18.000943      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
10a27193-773e-48ce-9c61-bc054294d15a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:19.00305       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ffb137a6-1d0d-4495-9b37-c6eefff3bcd5    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:19.00305       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
63ff427e-c461-4319-a844-bea511b63ca6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:19.00305       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
00d0c78a-47bb-4cdd-bcec-6a7f772dc215    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:19.00305       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f068a5d3-9039-4bd6-8c11-ba09bedd7bde    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:20.002346      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
525b81ee-0295-4397-b975-22bd22522453    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:20.002346      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b788a3c5-8a9c-4b36-8c0f-8df06c98cc96    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:20.002346      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b6a84d65-2747-4b77-9d10-fdd906e83466    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:20.002346      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
162c07e6-c431-47a6-93d4-31a00b6da809    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:21.003602      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
451ff640-78f5-4f51-b0c0-9beb80fc3ecc    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:21.003602      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0aca249b-48cd-4c06-a906-69d84d311839    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:21.003602      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
f714dbfa-f115-4d14-b024-17305a6efeab    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:21.003602      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
38ccb29b-9593-4eee-8b8f-6b3a0b832ddb    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:22.001907      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c275ea68-c06c-4b79-8f71-ea2428316dc7    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:22.001907      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
4ff0cce1-d99e-45b4-9f01-c8310cd3285a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:22.001907      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a185c396-3339-4723-84f1-056d43b74b6d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:22.001907      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9d1aa235-6302-4128-b2be-82c43a2d3171    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:23.000707      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
cf4b1c87-01f3-4b3f-9d57-652b840e2f64    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:23.000707      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9ffb4914-0fe5-4918-bec9-41c161805bc5    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:23.000707      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
76dd9fe4-be1e-4e6d-abc0-921431af4559    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:23.000707      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f4c86035-094f-4ac3-98e9-99e1e38eb818    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:24.00171       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c4e6c112-c0df-43a0-bddd-fe871e2dd6ce    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:24.00171       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
22a01091-6377-4fce-8f98-9013dbe024cf    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:24.00171       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
88203f15-4af4-43d1-ad8b-e550c2d2d19b    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:24.00171       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
dce2ef75-73e3-4876-9e71-0c8171441892    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:25.001887      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8e9d933e-da11-41a9-82f2-078af7f61161    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:25.001887      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5c6cb726-3a54-4e35-8291-d9b9af4f168f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:25.001887      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
0e761b29-a763-4cd8-9e1a-b34aa436e1ef    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:25.001887      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
8a2ea022-2529-4c25-bc58-dc1e9357e930    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:26.001781      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
6cda5fbe-450e-499c-a2fb-3cec4b1d2071    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:26.001781      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
288f769c-423d-47a0-8f12-6994d9f6e873    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:26.001781      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
4713f9b4-b0d0-40a3-a480-0062ebe83db9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:26.001781      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e9661a68-d8f4-4fd9-a689-a2eb91701cdb    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:27.001957      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
20b58a0d-0be2-475c-a6ee-0db685eb4417    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:27.001957      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c5deb1f5-f47a-4c26-af84-ffeb0f794a11    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:27.001957      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
002588e8-7b5c-4ce1-8766-750524eaad93    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:27.001957      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d4d0124a-e366-43e3-a674-b9ddbb2b337c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:28.001986      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ba13d275-143f-41f7-80a7-ef641c4b243e    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:28.001986      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
5993735b-71a8-471f-85c0-2d9f208d7275    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:28.001986      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
27dd64a3-63d1-4418-80dc-7553ceb472d2    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:28.001986      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
39a03ded-f2bb-449c-9241-20249ecf816c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:29.001838      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
0072128f-3e17-4e7e-a4b5-d2752bef936a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:29.001838      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9f3da103-aeaf-4473-80dd-caa560e121a4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:29.001838      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
2cc842e2-bd35-4025-a192-200b91fcad77    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:29.001838      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a4f41c3d-7869-4adc-9072-8f2592253585    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:30.001402      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
0f4f7888-6cb9-499a-9574-6bf1d5bef4d2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:30.001402      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
cffc6937-41f5-4eaf-bbfc-984b1e6d3b95    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:30.001402      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
4cc25d2e-154b-4178-96cd-69fda487f3c9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:30.001402      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
3eee50dd-6967-4ba4-a2ae-a0c009830c2b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:31.001929      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4cff5e0c-f38f-4a7a-8285-5aea9f4e0d87    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:31.001929      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3a6745cf-14f9-4c56-9c31-128fcdb92df0    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:31.001929      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
0694ccbd-2200-4f78-bd18-60ce1c09654e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:31.001929      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
11255f2d-3313-4450-ab30-b0e8923fe09e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:32.001139      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ec116e37-a808-458e-b37c-f64add3aec04    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:32.001139      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b5c24595-e26e-4b18-9f50-ddd9a7c015c7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:32.001139      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
92fa1960-980d-4780-b68a-ccd0dbef9a05    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:32.001139      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
83d52a97-4e38-43d1-a797-2f8faf827cf9    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:33.001894      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
fab1ef27-743d-4a85-906a-c00dcdbb3b34    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:33.001894      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
67b407c4-7d4b-4944-8efe-280be080f5f5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:33.001894      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
418fd9aa-48d8-4df0-8705-d1ace0c3577b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:33.001894      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
f14bec79-fd31-4a0b-8612-a736c6ad9e76    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:34.00108       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d74b2de9-4c10-4fc3-bf72-48a6356f71c1    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:34.00108       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
889c1928-d96e-45a6-8d52-c849fb4d14a5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:34.00108       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c1bc704f-6d28-424c-8d00-d51cc955df80    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:34.00108       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ab8100f8-ecc6-4ce7-b3a9-43fe2327f31a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:35.001731      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
cb53b124-bb9b-471a-8755-8523083d4b64    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:35.001731      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7b37aca4-874b-46cd-a9b0-4b8c859bdc98    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:35.001731      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
0e964167-5c3a-473e-a054-d3304d6ae892    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:35.001731      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ec0e8305-4ecb-48c9-851c-c79b45c81005    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:36.001985      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
59e940d0-f2d3-4a5d-bd44-edb54b828fb6    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:36.001985      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
76a13df7-a628-4c04-9fc3-67dc7436c15d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:36.001985      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5c989908-360f-4d1a-b20b-de5b0374a5ee    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:36.001985      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
cf255f35-c18d-412b-9e3b-d78adf440488    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:37.000758      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
15e504f6-2452-4bdd-b972-07fac1a1aaf8    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:37.000758      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b78cf8e4-fc12-4d40-8a3c-81e31690f8fe    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:37.000758      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f78a8dcb-3e6d-4de8-ad24-8d87f1cb84e5    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:37.000758      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d5986f46-7601-4ba7-8802-08731412e963    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:38.001901      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
af30e07d-0a48-47d4-be4a-2edce0077a69    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:38.001901      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7ceb73a8-f8bc-4407-996d-304eeac634c9    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:38.001901      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
33c92d21-80c3-457b-888b-8ceb46f2f8fb    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:38.001901      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3380ad47-08b3-4c63-8fae-0f18e5cec346    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:39.001784      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
579e7230-298c-4402-936d-0d17b1d6a3f6    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:39.001784      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6236d1be-6b59-4fbc-9816-d0ff4db6d96a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:39.001784      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d439a63c-9905-47a4-82fc-18e890391db2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:39.001784      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
50cac418-16e6-49ee-ba22-49780302430b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:40.001763      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
e9aaf956-b7d5-4187-bd91-031539f2e861    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:40.001763      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a931f732-d1ff-49d5-8b11-d79b25ae8d96    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:40.001763      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4bc268c9-4e5c-4f25-bc6d-445421b1ac9c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:40.001763      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
416af9e7-1c45-4f06-b49e-1cfda8c8fec5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:41.0018        9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8cde84e9-8328-4650-be1b-2fc666803f6a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:41.0018        80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e18dd46c-f252-45cd-a29b-d0d5b617cf87    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:41.0018        48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
dde5c410-890d-4b82-ac25-2f368ee2e184    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:41.0018        f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ea56474d-da2f-42b2-a433-904803ea765a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:42.001361      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
b9479ed9-74ba-44a9-a94b-bad8447a67ac    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:42.001361      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6f74638d-14da-46ae-ae5e-c8c16e1373b8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:42.001361      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ba918a81-a69d-4aa1-a5cb-9b9a1ebba8cf    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:42.001361      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
312f22e4-4b9c-42f4-a245-e635c56a764f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:43.001717      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
0fb014e1-7486-4c94-918d-09ead0e8e550    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:43.001717      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
85b5b9f7-f5cf-49c7-884b-a9f1bc5b145f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:43.001717      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
5b474dbc-4165-4539-b966-f64bb0061824    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:43.001717      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
375eea05-0fe3-497b-8980-e19f794ac987    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:44.001978      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
938c10f7-79a1-4ac8-b0b3-dbcb5a4f751d    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:44.001978      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
87f78845-ed61-412a-bdf9-0f6860969781    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:44.001978      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
73b34384-2749-4097-b3c3-ff77922565a4    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:44.001978      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
99046359-3df0-454b-9717-f9a74f5e6abb    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:45.001895      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
12bbe818-89c6-42c6-ad8e-fb0febc2fc05    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:45.001895      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d3448a3b-128b-4d2a-ac90-b083685719f1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:45.001895      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
31d8bfe5-1921-419b-9364-d149c1920ba4    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:45.001895      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
d431a687-b8cb-4798-887f-1da6cf289344    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:46.003114      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
206e291d-cf37-4252-ab03-12ce6842b0e9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:46.003114      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ce9e12f6-9e09-4637-b684-e951abe49d9f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:46.003114      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
686ee9c4-a7e2-414a-8f12-79659faa3967    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:46.003114      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3fe83216-300f-422e-ae86-1cd05ca54a14    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:47.001912      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
dcbda4ec-7c5c-464b-8257-9dbd280b1a6a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:47.001912      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d135fb51-c98c-4eb4-a220-147105a32ead    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:47.001912      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8dc73f6d-7ce8-495c-bfb4-89c1105dec98    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:47.001912      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1f70c674-50ee-46b3-8dc5-3ffe58b75db6    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:48.0019        9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c2ecc1f6-1cd7-4d69-bf66-2c920c3b76a9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:48.0019        80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
df06742c-9385-42c3-9e2e-d20c799c0ff0    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:48.0019        48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
f6769a53-0a17-480e-92ee-2bd16051dc6b    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:48.0019        f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7c45b7af-6a36-47e4-a969-e47d62e049a6    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:49.001729      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ccffb321-7947-4f7e-a500-ab6e2182ac5a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:49.001729      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5c8077ed-ba83-44b8-bf8f-ecc2ebf22bd7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:49.001729      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d4151fbd-0df6-4236-9487-2cb3ba7fe9e1    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:49.001729      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b8c701d3-e2de-469c-8260-06cf50ee40ad    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:50.001797      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
7d574aac-c85e-4a24-8377-e4723a550ab6    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:50.001797      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
297ae469-df1e-4842-bee4-106a74301750    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:50.001797      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
da038a97-95ee-494a-9b49-a779e8900cd9    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:50.001797      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c3487e3e-2d53-4571-a2bc-f3ccd94ec0fc    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:51.00188       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
43d189a2-0918-4ad7-9eff-5759af078723    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:51.00188       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a165a4fc-1cb6-4aa1-9e30-64fffe9a881a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:51.00188       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
c18c75c6-cffd-4eb2-bbe0-b6dc5acc67a0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:51.00188       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
09659694-6ae4-458c-abb2-f47b16f87198    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:52.001968      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
11034057-5b9d-43b5-ad54-b3177e8df5f9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:52.001968      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
cb0c8696-55e3-4895-8a72-bf6cf40453d8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:52.001968      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
5a847b7c-c79b-4b60-a35a-d5d0bab4f7e6    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:52.001968      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7a01b02f-eccd-48ee-82a3-0a3a739d3bd4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:53.002121      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ca3f50f7-97a3-4014-a9f9-2ce61821f6f3    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:53.002121      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8d1e163d-9777-46f3-abde-5e34190f10e6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:53.002121      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
383bf010-5688-4dae-afea-526453dc81e3    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:53.002121      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
0deab606-8ae6-4f31-9d6e-e1cffffb67f4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:54.001924      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
9c1ba4af-fc04-4c92-868d-e66d6fa49cb8    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:54.001924      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
3c978967-1185-4dc4-a45f-723686d2a4ea    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:54.001924      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8234dd22-919f-42a5-ab97-6197a533ca16    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:54.001924      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9f4a9387-de66-4f1e-8747-f6d3e8b6b25c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:55.002053      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
6eef9d20-672f-4391-9376-f0ac936dcb19    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:55.002053      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8dfc60d5-4d20-4642-a618-40e8ae8fe8f8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:55.002053      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a78b11f6-1c18-4b86-8a5e-62108fc51a0d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:55.002053      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
574dcad1-edb2-44fb-8a0a-610d1bd0e058    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:56.001979      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
fd134f15-cc19-4157-b63b-f589e243c527    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:56.001979      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
1a6b5e69-d695-4752-87ed-d83856ad928d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:56.001979      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
737c326c-f3ec-4b5f-ab34-dbd4afdbbff2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:56.001979      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e13f32e7-41ef-4319-8ebd-fa36c562b0f7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:57.002288      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ec0a83e0-f978-4a7c-92cc-d70881afafb5    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:57.002288      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
eef5ff23-1e55-4add-aa86-6e5b14bc757d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:57.002288      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
39609ff3-5142-40d3-8afb-717e3abf6b9e    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:57.002288      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
62185012-6c0b-4dec-9658-1962dd95da72    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:58.00085       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
fa2920c0-93cc-4380-b59a-6f957a76388c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:58.00085       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d6dad97d-7b9b-459d-9853-0e3233fb3ca4    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:58.00085       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8213a04a-5a97-4591-953b-0c4184028a8e    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:58.00085       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
10d55313-48b5-435f-93c6-36bd882b754f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:59.001837      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d1c35deb-0eae-44e8-9cdb-90502d8a47ad    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:16:59.001837      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6c7c6da9-711f-4378-989f-a3c9e5432f46    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:16:59.001837      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
1568fc64-8a43-4846-b449-ee7a4d23662c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:16:59.001837      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
0eee89b8-c18e-4367-9314-094f4d4031e3    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:00.002176      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4277a629-8b96-4041-89d7-f5414d025c8b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:00.002176      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
40051be2-03a3-4501-be29-113d032ca7b7    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:00.002176      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
31d91129-64e3-4925-befb-511482be2bcb    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:00.002176      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4bd6e17b-e564-4665-9973-2c8e9430cf6d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:01.001902      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
be18f06c-ae3d-49f1-8d2b-95eef7543d1f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:01.001902      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
b7c5d7de-b6a9-4cd0-924f-1d44cb799dfd    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:01.001902      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ded35c7d-2542-4c1d-80bd-77a3a8051836    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:01.001902      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
2d22bd2a-5535-4016-823b-64492a42ab8a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:02.001704      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
55e5fb4c-8219-45d5-8127-1d20743f1771    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:02.001704      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ca062879-107c-4a99-a8dc-f7a45739fee8    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:02.001704      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
36707aba-ebe0-4032-b62c-43fad46811b6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:02.001704      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
442db737-3a90-4634-a8df-5c88d6f6cf3e    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:03.001644      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
67f05423-7517-404b-b332-d4756fd0f7ca    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:03.001644      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
0bb67eec-791c-4d5a-a7f0-9a7246b36875    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:03.001644      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6db11abb-c91c-4445-8845-430ceb155a79    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:03.001644      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
14645aff-5ebd-4623-b3ec-be7fbdf55778    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:04.00177       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
dc5205e0-a170-46d3-b731-0496fb6f86a9    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:04.00177       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
379affe0-6ce1-485e-aaf3-ace81ba5f396    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:04.00177       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
03b34483-082b-4e3d-8da1-fcb5e8919f19    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:04.00177       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
55d785b4-7ace-4617-9107-18e6ba86288f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:05.001685      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1e40fbdc-468b-4a17-b365-b151822441f2    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:05.001685      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
3f716c20-1a4e-47ec-8396-fbba76fc78ee    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:05.001685      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
094e5516-7c7d-43e5-bbc8-686a39e86abc    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:05.001685      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
01bcfa43-0113-49f1-9443-0a4cab4b925a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:06.001766      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
801c01d3-ec7c-41ef-80ee-dd42d1d6e77f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:06.001766      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
4c3046f6-8a19-44d9-9e5e-8b08252dd06f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:06.001766      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
f50f4602-56e3-441e-81fb-52994f0ebc84    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:06.001766      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9b6c4f57-1eed-49e5-8a94-38d45aa2b8ca    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:07.001865      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7d4fb7a0-cc86-4184-b24a-85cd59ffc0b3    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:07.001865      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
4577363e-be03-45f5-b894-49a8d706a01b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:07.001865      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
eef1a7c0-e0c6-4ca0-841f-b1e7e6a638fa    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:07.001865      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
be2da598-dcdf-46f7-ac70-511ff2c3c111    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:08.00064       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1e4bab84-727e-4955-a0d3-4bf444659ce1    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:08.00064       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
582e3289-90c5-4d30-ab3a-60bcade1b512    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:08.00064       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
170574a7-4d6b-45a0-8623-5b4a76c52a5b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:08.00064       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
297286e6-c19d-4da5-af92-a4eece9cda9d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:09.001765      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
93f1d294-87f9-49e6-a231-b2039aba542e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:09.001765      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1d4bfb9e-d68e-4011-a3d8-2d0ca80aa410    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:09.001765      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e65e49de-11c7-4b3a-91d9-d72ebba2bbb1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:09.001765      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
e21fea88-9028-4b31-b30c-4375c4560a53    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:10.001891      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
267b2b76-ef21-40bc-a8c7-6a75c186e23d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:10.001891      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
11badcd8-4a47-4a58-b4a9-dd2400963b97    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:10.001891      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7cb67ef2-cb5b-465d-9ebf-83068d74d73d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:10.001891      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9bf0c83f-4632-4781-ad1c-d9d376188f5e    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:11.001292      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
84bb7aa4-1233-43b1-8295-261515086c78    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:11.001292      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
9ea181c0-5b68-451f-b9a3-1805dad9dcf7    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:11.001292      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b0499f90-21ee-4c61-ad58-4518c747fbe8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:11.001292      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
84e9645f-6817-499b-ad75-02164d68ba48    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:12.000937      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
32a53914-70d4-4f89-b166-e1bd3d401ffd    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:12.000937      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
cfa93ef8-d906-476e-9670-c6da69db94b7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:12.000937      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
af00b324-1bee-46c4-86dc-48d686b3b738    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:12.000937      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
11d575df-202b-4f91-8fae-f631bed299c6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:13.001961      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
99d39ddb-9367-4ecf-8f0d-4c74b3b7ca55    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:13.001961      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
77470a57-d05a-484e-a5eb-f04f2f8ba638    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:13.001961      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
e0a89b3a-115e-4dc7-a1e9-416e4db861dd    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:13.001961      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
bed44fe7-3594-4f65-8fb4-5422e4ba945f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:14.001726      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
93958d42-9174-4066-b9dc-b05db64e99b0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:14.001726      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c79b2f47-db72-4891-9328-f428d3177d86    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:14.001726      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d97e0497-5d70-4a6a-9cff-ca5306d797ef    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:14.001726      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
41f081fe-1dbd-476a-a2a1-6cb3cdfbc9a3    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:15.001563      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
3252e9a7-6206-4a66-8892-4ed132698c19    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:15.001563      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
d3fe8584-d2f2-4ec9-ad36-b771dedec4b8    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:15.001563      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
3fe070f1-86a9-464f-a979-50af4ce39585    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:15.001563      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0d45b546-236c-46ff-ad49-8cd66c15e190    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:16.001969      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d60f0525-e275-4e50-a702-2657e030d65c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:16.001969      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ea1ae65b-e5f7-40d5-8aba-58a2a68ab8bc    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:16.001969      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8091f955-c775-4987-a231-e0e7006564b6    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:16.001969      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0170acbd-f3f3-460a-afc3-e5c0d447b44b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:17.000708      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d9745f51-cad7-4979-a0fd-a2ad2e194286    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:17.000708      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b16a383b-e571-4e60-8245-9bf749994e66    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:17.000708      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c09b14e6-b2af-4c00-8a3c-9e67155b06a2    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:17.000708      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
88bd9e26-2ae8-4d4b-83f7-6afe36fc6c84    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:18.001688      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
e9ee1808-05be-440c-bf7a-bbb2c0140b01    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:18.001688      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
cfb65dbe-b7b3-4cb2-a0f1-71928058353b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:18.001688      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
3b87aea2-e8a1-45df-8f47-142278ca5ac5    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:18.001688      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
3d062dae-eb16-4285-a289-23bbc1fb9cdc    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:19.002401      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d1973362-b6b8-4960-ab8a-6f3475d8343c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:19.002401      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e28e48be-e869-4f80-91a9-e97c6897cab4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:19.002401      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
af9aff83-9f3a-476c-897e-e9de79f151da    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:19.002401      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
663fb943-9c61-4535-bacc-22a6664cc185    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:20.001818      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
fe19fa33-ff7e-4ea8-9911-1aa7ce07c5f8    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:20.001818      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1394344f-52e5-4291-9dea-e95d94a15a7c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:20.001818      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8ac9fd2a-0b1b-41bb-be60-1c66d190649b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:20.001818      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
19d4ffb2-488c-4924-97ee-75f489288b03    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:21.001894      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
3282dd2a-2d99-4b0b-aacc-c0b3edef09e1    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:21.001894      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
0dcdc5d4-7e75-4386-9396-70c337e2e808    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:21.001894      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ef4d9470-4628-4688-b9b2-01999e8148b9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:21.001894      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b5bc06c0-22f0-4dbe-8154-6001c83ca1e2    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:22.001859      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
46b370db-ccbf-4aa1-a4a0-fc34723bad30    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:22.001859      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
aea69299-81a6-42ad-9b82-e3e39929614b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:22.001859      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
96c1ba48-5c44-4566-9f02-ee80f2745fdd    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:22.001859      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8613af0e-4f3f-4240-aebc-0f5da700dca5    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:23.001715      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b294177c-f758-463d-b8eb-6ffcc0d404bd    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:23.001715      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
5d6f4065-ce45-432f-a321-448c92741a93    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:23.001715      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
92e5ac01-145f-43ad-9a44-1611d5757864    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:23.001715      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9b7859d5-a270-443a-90fd-a0da25dfce95    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:24.001431      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ea88aa3f-e1cc-4e51-a301-76b2a8d8287a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:24.001431      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a05cf942-f69a-46c8-a90a-ef0dd19b632e    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:24.001431      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e6222464-3733-4a3f-a92e-334d57f99750    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:24.001431      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d84bc014-994f-4e50-8602-c02c170cc594    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:25.001912      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
2ae69a94-a610-44ab-bfb6-65badcf873bb    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:25.001912      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
82f7fa69-ff77-4f15-8ed7-92edd493cf5a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:25.001912      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
aeb45cf6-257f-4846-8141-8db7923fabdb    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:25.001912      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
3a63b84c-6e30-4e2a-9bf6-9a943ae066ae    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:26.001791      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
69c4191a-5193-4158-b9e3-a740f94a021e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:26.001791      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8fd4175a-639c-458b-9042-fb484cbda5a6    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:26.001791      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9e2d0087-7aae-4ccf-899b-50c25453a9e4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:26.001791      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
bd7cc11b-afcc-4691-8af9-9e9ba82462cf    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:27.000643      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7314cabe-2cc0-44ff-86d1-a78faaf976f3    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:27.000643      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
26f2daef-9417-4c5e-981f-4bcb915c7c89    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:27.000643      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
43a2ae72-076e-4637-85f8-56a9fba9b84b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:27.000643      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d3b3a58a-49ab-44ff-9932-bf7cbe1a249e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:28.001319      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d2f67dd2-d822-4d95-a363-89a8cd848fba    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:28.001319      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
0d49b77b-0765-4f9f-8831-dca19670d665    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:28.001319      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f4413f90-5168-4875-9669-29479839209c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:28.001319      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
050a2230-41b1-48d7-82ef-8295f58f1a99    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:29.001459      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
18a3eec9-ad10-41a3-94d8-0386354d7482    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:29.001459      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
442fba38-09f0-4ecd-846d-75758ef62e8c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:29.001459      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
a75db847-f467-4aab-b531-94c68036274d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:29.001459      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
2137e908-709c-4fa0-96b6-a9f0dcaddfd5    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:30.000692      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
54b84873-d41c-4c7c-912c-bf4b1bb6ffe6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:30.000692      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
369caadb-a442-46c0-b4fc-21a3e4eda171    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:30.000692      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e568e1db-cd19-4851-ae63-36c1a54e634a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:30.000692      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ba0778ea-95ff-4f2e-ab7c-2d2fa5de1a46    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:31.000735      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5121fa5c-6300-4e24-9a2b-c50e91b94a2b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:31.000735      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8cacee69-3ef1-4179-8615-6cbf28e09bab    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:31.000735      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
75231219-0a8b-48f5-bd37-517854f71b14    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:31.000735      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1bb0246e-cc5c-4702-af34-a7426788083b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:32.000957      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
45a83996-709e-4d78-8829-30a0e8d6d744    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:32.000957      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
baca9175-6507-43e3-91af-046a7e22086f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:32.000957      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b07a2e2d-8d97-4fb9-9de5-1a53c652f047    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:32.000957      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
abe02c80-e0c1-4280-bf16-aa5b61404987    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:33.000698      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8d7ee478-e48a-47bc-9f90-6e08c8a33e1b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:33.000698      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
3cd8a835-bb6c-4e6e-991a-facdbd944391    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:33.000698      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1f624eb8-843b-4b7d-a5ad-f03d1a4afed9    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:33.000698      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
721425f1-01b5-4abf-9f8d-051759f8963f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:34.001268      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
88b5029a-2f95-423e-ba1c-15b6bef99d43    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:34.001268      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d2b02c48-caf7-4604-8c08-807f638365fe    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:34.001268      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ff6145a4-beaf-4a16-836a-56f0c33e691b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:34.001268      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
abee19f3-642b-4e59-a552-9c98f000ba57    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:35.0031        80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
fd149ff5-196c-4fc5-9d75-8515862e79f0    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:35.0031        48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
18ad102f-9845-4d77-893e-515027f7fefb    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:35.0031        f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4b8daaac-4263-4fa3-9c15-684ebd29bfdb    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:35.0031        9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
581bd2de-4c6a-4148-9a48-a820f9665922    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:36.000849      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
3899a1b2-1c0c-4bd2-b1b2-86bfd2853d0e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:36.000849      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
fb77dac9-b3f5-4a6e-8645-caa4ba8f28a1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:36.000849      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
2ca7cac4-3271-4f53-9351-34e026c19eb2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:36.000849      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c2a869c0-3aaf-48c8-a237-a23fc4c81bcc    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:37.001668      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
b0eee082-da66-4427-a307-498e149b6471    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:37.001668      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ce987b2f-c5d0-4031-b9e5-0f9e5d9017b2    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:37.001668      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
912de44f-b42e-469a-ba78-387af25f1a8a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:37.001668      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3322c5ce-2b7e-498a-b8dc-b0587eccd189    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:38.0007        9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5eb65079-0744-4309-a920-46e5f854d309    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:38.0007        80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
1a7274d8-83cc-4cd4-83d6-6f378a727a6f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:38.0007        48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b82f8bcb-0bc7-44b7-a4e2-76dab4d0e6c2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:38.0007        f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4e81bd22-01cf-4418-a25a-835b4afca3b8    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:39.001694      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
6b85485c-743a-4391-a5ad-fdd3742e747d    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:39.001694      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0b39b6c1-bf4a-43d4-9f03-daa7e10d6c09    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:39.001694      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
cd40e97f-047a-4783-a0ae-30bf739f116a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:39.001694      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e6ebe886-6cdd-45e1-8f38-dbb482bfa131    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:40.001897      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
a0bd053f-c480-41a5-a3a3-0c9568276684    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:40.001897      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5a554675-59a5-4550-a3a6-073c952bcdbb    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:40.001897      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
17ab8755-7651-4b38-97e9-ba0e3db16d01    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:40.001897      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1f06adae-8727-4db5-9501-dbd47ba9f29a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:41.001619      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ad16393d-c632-4f5a-9a22-ca53f3c21d1c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:41.001619      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b69909d9-a574-47e1-83bb-e9db126290b6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:41.001619      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
609a1330-d279-4b4c-bd8f-791fd7575cad    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:41.001619      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f48d1013-a985-488c-a855-6419f1768938    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:42.002653      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
60c1731a-ea15-4161-b919-90220c2c84d3    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:42.002653      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9b9b84b8-e412-4cdb-a81a-c6f0387c1158    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:42.002653      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b03843e7-3cfd-4ba9-b5ed-73d79abe94a6    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:42.002653      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f4876ece-e9e1-455c-93de-e37a76727938    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:43.001805      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
faf73476-1f56-4293-8527-3e6ae7d36819    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:43.001805      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
00e32033-f41f-48f4-850c-364c0af5cd1d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:43.001805      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9b9c3776-d10c-4fc8-a07f-bd808b2f6e91    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:43.001805      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
fbac99d1-4ead-42c4-853d-e3ce3ed0443c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:44.002016      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
82efc0c3-7d90-41ec-b1d6-fbb3ce7b4f4d    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:44.002016      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e9df0f74-9fd2-4956-ba0c-d605273b57f7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:44.002016      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
e122f4a0-6272-484b-a042-2e1a8871d0ea    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:44.002016      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7001bb6a-93a5-475f-a7eb-7ce19d8dd0e7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:45.001397      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f4046580-f100-4b41-b7f1-cda771c1f8ac    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:45.001397      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9649e146-9057-487c-9979-7cd82f5ec13c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:45.001397      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4594fadb-ef4d-43d2-b065-2838b9a4cee5    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:45.001397      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
5922dd9d-8127-4f1e-b05d-8334820799a7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:46.001559      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
29307e78-1ba1-4aeb-bb3d-e77ea4393c1e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:46.001559      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
186f370a-f9f9-4a6d-9537-ae722f64e616    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:46.001559      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
defcc6b3-ab7b-4cc4-afce-943e8f5b0aaa    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:46.001559      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
04e21b86-560d-48cf-b708-e7e5b12b2de5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:47.001655      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
cc44807e-8ec3-4f17-9040-119870a874bd    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:47.001655      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
49b7ea81-40df-4b2b-8ad9-09bc7531623d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:47.001655      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
238019d0-88bc-4289-b387-3d42acd38393    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:47.001655      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
5a317e13-cbe8-4493-974a-21fd4ddfa66f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:48.001706      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
76fe00cd-b240-4456-a3e4-5999b9554f70    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:48.001706      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ca015944-f47e-4e3b-b19d-5b5023e7b93b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:48.001706      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8257aa6f-1ea0-4245-b520-e7a83e6a05f1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:48.001706      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b12c34e5-cb82-4847-a15a-c6dc9ecd4564    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:49.001554      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
5c936c87-54d1-408f-a43e-426e76215d7e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:49.001554      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
72b33942-da9a-4163-b8a4-0b018121a645    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:49.001554      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
c70ca894-b0e1-46ad-8c7b-9ccbc532fd7f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:49.001554      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
2304ea24-6a92-4819-82c7-106eac6a0958    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:50.000543      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f846283c-f02c-4e38-8dc5-423f2996fda2    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:50.000543      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
7b50f41c-e10a-420b-926a-c424df99c5d1    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:50.000543      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
df093d99-642c-47ef-b92c-f2545f195ef1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:50.000543      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
565543a0-1048-481c-aabf-a3643b1bf0fb    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:51.001735      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
a3ae9919-12d2-4386-9240-8591de4eb7df    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:51.001735      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
a4651cf2-3689-433d-a9b8-1ef88e31f91e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:51.001735      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b72bcaf3-22ff-447f-8aee-45e32bdea2ac    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:51.001735      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
0bbd3085-2ec2-4050-bcc2-dfc7755f8df9    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:52.001691      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
abd5d57d-1cd8-4b59-a65d-e1c21225595b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:52.001691      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5aa9601a-8a26-4cb9-b891-f293e23845dd    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:52.001691      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8b3ee79c-2955-4259-955a-478b0a430e80    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:52.001691      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
7459942d-379f-4fec-b9d1-6aa034aee48d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:53.001964      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
6f2510e4-6ee5-4be0-bb95-967afd3d61ee    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:53.001964      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c2d18f23-c2ee-4016-a307-218b3e871952    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:53.001964      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ab2eb79c-b5aa-4e66-bd05-334ea8a850d8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:53.001964      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8847bf20-4e03-4641-84ec-0fb7f5f170f3    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:54.000759      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
6b58d1ee-9a24-4db8-9aae-4f9631849bd4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:54.000759      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
2fd3c313-ddb6-430c-b946-1fcc199e5fcc    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:54.000759      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9f14fb6c-506a-4aec-ab16-1a6b34b527e5    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:54.000759      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
cc9c86a5-15af-423b-841a-8bb1a0cab9e0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:55.001581      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
cfec3d1d-134f-47f8-a5a8-66388573478c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:55.001581      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8e8da531-1c0e-4069-845e-bb17972e984c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:55.001581      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7472cb5d-b8eb-4c96-8ce9-8300d73f4029    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:55.001581      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
3e2bf882-a2ae-4f37-8fce-cd7d2126a4e0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:56.001028      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4364689c-d127-4358-938a-938ab36d7372    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:56.001028      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5e252e61-2399-4549-a312-12ad2cf0b591    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:56.001028      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a684c66c-8961-4e81-a8ed-fec0628567b4    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:56.001028      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
1eb8c726-d628-4d12-b2dd-eed0d72c7d56    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:57.001782      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
beeddd33-80c8-4918-85c0-0b060f3ace65    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:57.001782      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
593ebae5-6deb-46b2-ae19-9ad388169732    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:57.001782      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
4692a8c5-f4ac-498e-8e40-4f854caed33a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:57.001782      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b584f41f-8f6a-4400-aa65-8b02761ab676    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:58.001932      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4e70fa06-578d-4260-af80-d48216175918    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:58.001932      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
241b10a5-839d-40cd-8b1f-00bd036bf31a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:58.001932      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
2a6214eb-2465-4780-b6a7-7588f6b39858    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:58.001932      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
42c9aa71-2c0b-4ce2-b444-643efbfc19c2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:17:59.001964      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c1b46db9-9cd1-4077-adb8-b18b69925dac    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:59.001964      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
3c1f080f-f25f-47f1-84e9-09af51d71484    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:17:59.001964      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7e60942c-e0c1-4f93-a3d7-cbd9568203e1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:17:59.001964      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
c51ed861-79c4-413f-b19b-62d1b63a7b5b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:00.001811      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
5dc784cb-e87d-4d0c-a722-dee41ffdf072    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:00.001811      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
13ad8715-8418-406d-89c1-bbe0dbbd51ad    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:00.001811      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
dce6d6ed-6d56-499f-8394-cf1f7b1aef6a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:00.001811      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
cf37ad33-a047-49cb-969c-0e5d0c5ad328    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:01.002645      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a042fdb1-8921-479f-a5c1-ea946f2541e3    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:01.002645      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7bf6d320-2bd4-4fa2-965b-8b07a15cf85d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:01.002645      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8ad0cf93-ab93-4ee4-80a3-db00e9cb4da8    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:01.002645      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
90c7ff9c-4553-4c14-b2f3-061af535116d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:02.000556      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
7add8dee-7011-49b4-8ee1-5b87fc85f5a6    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:02.000556      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ea8cce2e-9ac7-46ab-ba1d-ac7bfb5e9917    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:02.000556      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
6fe146af-81d4-4de5-81d2-433b750c1bd2    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:02.000556      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
4d59a7f4-d5d0-4655-8180-90824caef7c1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:03.001393      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
50bafe60-0451-48fb-ba67-60862f8102ee    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:03.001393      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c23dcaff-c69f-4735-a3c5-c7b17b19c0e8    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:03.001393      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
bf1a7dec-1609-4c46-b838-90734595ea10    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:03.001393      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
59ce7f94-6ce2-4e1d-8a40-dae5b8b0e4e1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:04.000744      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d3fd3ab2-ba6b-4243-bb74-31f96837fe28    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:04.000744      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e99c0c4e-2b3c-469b-9202-9767ade0d05c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:04.000744      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
b6f61795-bc95-48e6-94c5-8ee3062e959f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:04.000744      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
594a2c93-85ba-4c59-adcb-9dad52d4508a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:05.001009      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
34272b54-4eb4-4544-b5ff-b7deb4018d26    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:05.001009      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3f5b285a-d051-4980-9dee-b8b05004fb68    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:05.001009      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
77e0a40e-f7a9-4492-bfd6-813a5fbe08dd    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:05.001009      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
151656c5-feab-487f-8879-6aa188e6f512    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:06.001526      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
7ed6243e-7988-4577-bb95-eabb8325ed7f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:06.001526      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f2322a15-ca44-4766-81b9-8799460946ef    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:06.001526      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
26b5b966-87ab-492a-ad44-da4e2c9cbb71    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:06.001526      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
97ab8ca9-81ec-44f7-9c08-acdbc1d9d6c1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:07.00156       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9e65f29b-a898-4489-822a-6273d3bd19dd    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:07.00156       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c074078a-583a-4a8d-98da-9acc7ec95346    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:07.00156       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f78924fe-e7b5-4095-b259-2f6a07ec38b0    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:07.00156       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
204c662f-a564-4139-9982-973088c9de58    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:08.001711      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d5d192cc-1e21-4c62-bd47-cab0e6776f4c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:08.001711      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
704d1de6-b618-4c5d-8aee-2a29c533bd9a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:08.001711      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
6fbc0378-f0f9-4705-8867-a99415492146    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:08.001711      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
fb8b1bfa-d772-47c3-9c77-9f6a1290d08d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:09.001829      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
04b54d72-e28f-45e5-b5c7-bdd05b5e39f2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:09.001829      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
dcffdfda-154b-470b-9565-672effd4ff1d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:09.001829      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
43e64969-e3c4-4c7f-823d-d032fa723cec    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:09.001829      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e2f681ae-0b2e-4684-ba77-a5f72f8bf03d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:10.001716      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8941ec4c-0ae4-405c-9523-b99de9581c01    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:10.001716      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
2a7a31ab-75af-46b2-a90a-543590a4c828    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:10.001716      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
87ad02ce-b27b-4bde-a1f0-882c6403d618    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:10.001716      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
865c0edf-ee19-4958-a696-8bd6f67cc710    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:11.000744      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9a041f5b-fb52-4624-b9f7-04001a538a4f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:11.000744      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e7ffa591-c305-4c4b-8f7e-8a5276be2995    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:11.000744      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
64761402-eaf9-4591-8f29-c096c08be276    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:11.000744      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
068ccebd-83a8-409a-bac6-b06e5e40cd80    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:12.000633      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
340bf545-fd1e-48fd-8409-cc0977f75e3d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:12.000633      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
e0c378b3-330b-4190-83ff-376ca7271131    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:12.000633      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b8dd2a77-90d7-4376-ae32-da9d5f4be4ab    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:12.000633      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c4103e6d-f170-41de-a370-6af1c88caafc    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:13.000837      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
682b929c-7272-4644-aebf-78f4cdff5ece    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:13.000837      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
3d317716-5728-49d3-99c7-10315ad29b07    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:13.000837      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
746c75ef-5aad-4ef3-b767-814ad2ea2f0e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:13.000837      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
fdd32d3a-64d3-4f84-9e95-fd8c2df0a76e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:14.00075       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
67125a8a-f744-49c7-8e12-db7af319b608    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:14.00075       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8823fbd7-1aae-4e5e-9009-6a3fb4815af1    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:14.00075       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7680c01b-f7ac-48eb-9807-c185d0d0f88b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:14.00075       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8fa93087-9963-420c-b432-669e9d496d85    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:15.000786      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9ef7bb0b-36dc-48a7-8b3d-414769ca060d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:15.000786      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4d15ddbf-952b-4012-a18a-b3c20a56ddca    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:15.000786      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f9dc8f5b-0ae4-457c-8b1a-fedf5eb4239d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:15.000786      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1d2b3907-cd4e-4d24-97b6-0ca3fcb5537f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:16.000638      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a83b3ccc-2e08-413f-8d1c-027fca32da62    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:16.000638      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ef9546ae-c4d0-4440-90a9-028d08b1c093    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:16.000638      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
a14d06b4-1503-481d-999d-c3dd76769f82    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:16.000638      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
3b224089-16c8-49ec-8f49-6394e7f2a35b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:17.000799      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
c7e14c8f-6b10-46ee-8363-8f761fa07ff2    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:17.000799      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
e9b391be-bf93-4310-bd8e-2967398d6749    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:17.000799      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9800e361-5498-4c57-aa5b-4d2c871d9690    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:17.000799      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
27afb562-1265-4a94-9f75-155ca64bc669    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:18.000934      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
2fea2b95-79bb-4407-9c4d-9260aa8f1b6b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:18.000934      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ef22d314-2f31-4921-83f3-68551fd60c39    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:18.000934      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ae884998-1753-4375-913a-190f8733ba26    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:18.000934      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
381a6eb2-5f34-439e-a1f1-1e1f57aee88e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:19.00155       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b06bdecc-c424-4e19-b726-05aae6d8ecf4    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:19.00155       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
742843e9-0781-4370-98f2-564bc95489ab    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:19.00155       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
68ddf75a-422d-4693-b93d-ce4cf58eb4d5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:19.00155       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
67fe52b2-26cf-4442-ac4f-982e138dd462    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:20.000441      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
2d2a60f7-1d01-4b77-933d-130907e05aa0    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:20.000441      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
67a9f092-251c-4af3-8088-a3a03c606c31    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:20.000441      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
aeb375c2-976a-4c7d-9f93-27cdb5094b11    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:20.000441      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
389ad0cc-2ef4-4d2d-aa09-acf245eb2f75    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:21.002168      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d179a3d1-f72f-4649-87a5-b710add03a7d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:21.002168      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
02ff2e32-b789-43ee-8c49-44160edead78    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:21.002168      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1ba1fdd9-fa49-4ecd-9251-5ae20cd73f4f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:21.002168      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ecd9306c-fc65-4f09-807f-4829290415c9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:22.001577      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0c0246f7-6b03-4f39-b3cf-0cd24a236926    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:22.001577      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
cbba8d9a-ba80-42f5-8758-f854e27bc5b3    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:22.001577      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f11573a0-4cec-430d-bf7b-59e195e19faa    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:22.001577      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
fe7b1e6a-35f2-411f-a45a-5db3e59cac93    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:23.000629      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
355c4416-264b-4e95-8e2c-1c19357f11d1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:23.000629      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9c82d1f9-0e8b-44d8-926f-2a7329b2efc5    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:23.000629      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4e1f1c3d-18b6-46a6-913e-4dd1e9914efb    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:23.000629      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
067ae414-4a61-41d0-99b9-2fd65751ace1    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:24.00147       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
d9c1c15f-9229-4dc4-b309-c7bb5ab07386    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:24.00147       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a669a852-a2e7-4dde-b8f9-f7e4dca5440c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:24.00147       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a4f047f8-9e9b-47ad-88bf-92369157e2d5    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:24.00147       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
d6c56f88-1725-4efe-95a4-0f22e9d707f9    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:25.000395      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f5c68c47-7555-43ae-a4eb-6e7644e9e395    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:25.000395      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
615df04c-2fc7-4158-a746-f2ab21bd03e5    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:25.000395      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ede78326-05b9-4a01-a081-b5989c9441cc    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:25.000395      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
21a4e384-609f-4dad-9a2c-f7b4a7cfb15e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:26.001903      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1e8e5af3-fcac-4baa-b3d9-4613dcded2e0    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:26.001903      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
1cbbc0c3-baff-404f-83db-cf8915a708dc    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:26.001903      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
21c5bf4d-138f-460b-bd47-e4602d40007a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:26.001903      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
64d4c15d-f577-492e-a1b4-0242fd7d4da5    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:27.000619      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
bbc17b3d-649c-46e0-8a63-5c291d2d941a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:27.000619      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
89b51302-7eb4-48a7-a314-f1a9b44c3e11    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:27.000619      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
fa64cd9e-a25a-4637-ada1-470105e12c61    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:27.000619      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
6199f53d-9461-45a5-80c8-d5c245ba43d9    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:28.000614      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
b5207c98-1adc-4be3-8176-5f98e234156d    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:28.000614      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
393c1235-4c4d-4e8e-8172-2b952fda39d2    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:28.000614      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8b7d8572-b098-4611-ae74-f1214ccc5ddb    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:28.000614      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
5d0eeaf7-87d0-4cb8-88d1-82aa82155f1f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:29.001651      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
063fead8-d4d3-421a-8c56-d0ae96030308    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:29.001651      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6cfc406b-211a-4247-b747-51ffafa8c8c4    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:29.001651      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9e454b88-2758-4fb8-b2b5-417bd22869dc    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:29.001651      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
21fb8b5d-9a3e-43e5-a929-e84b2c0fe66e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:30.000722      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
177eeac7-b576-4947-b617-69e331c4f90b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:30.000722      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5f112fb3-4d1c-4618-8271-a772345c0b99    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:30.000722      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a3f4dd23-e7f7-42f7-946b-377807d7ff8c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:30.000722      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c7dbb3ae-6029-4ac0-8787-09d8fcbe0429    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:31.001674      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f619b587-8938-4dad-b6e7-26128807ad91    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:31.001674      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5f4a71a6-3895-4ec5-bd35-f968334b72a7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:31.001674      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
93dad234-991f-478c-8dea-f1907049945f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:31.001674      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
95f34821-6be6-4f80-b4ff-92cdd33e21f6    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:32.001543      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
de1218a9-84a8-470c-9b88-b5abd4594d78    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:32.001543      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9199f720-1603-4614-889b-2894e4667b79    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:32.001543      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
fcc2f290-26a0-43f6-ba50-1393862fe136    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:32.001543      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9f00a4d6-a312-488d-965d-ad150a9fd904    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:33.001911      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
955e7a29-986a-41f0-b12e-e315324f1285    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:33.001911      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
16bfa076-d583-44dc-95d9-b97a46b56d60    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:33.001911      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
6512c1ea-c0da-46c7-b5f4-c575c49eb538    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:33.001911      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
2b1863fb-9416-4f86-876b-296ad26297b8    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:34.001319      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
800a85f9-6d83-4417-8ff7-f7c02d9b1e3c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:34.001319      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
cdae61ef-e3dc-4c60-8d09-ab9a38949f29    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:34.001319      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
2635f775-bb95-4216-83b4-be313219d4a2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:34.001319      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
504ed050-e879-43e7-97f0-301a729bb43d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:35.000871      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
4d272c5a-17dc-4ef8-9f4f-c88a79d268f8    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:35.000871      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a99287e2-2417-461e-a042-ecb6f06da489    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:35.000871      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d7ea325d-be00-436b-bee8-b2c8192866f1    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:35.000871      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
eea71729-9df1-4ef3-951f-d58197db5642    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:36.001886      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3d9629a4-60c4-400d-81aa-a056ed87cdbc    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:36.001886      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
abfcee38-9c2c-45a2-8dbf-6d5303c73da4    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:36.001886      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
10639334-092d-4208-8cca-44788bdd8d06    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:36.001886      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
b02fe440-d1ee-4765-9bc9-497de0a36fd7    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:37.000786      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
22b31b78-b251-4327-a868-c3cb996c44cd    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:37.000786      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
7930880e-dc98-4b79-b1f9-094747a35ee9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:37.000786      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e5f04fe5-8405-4480-b934-b9b77b47f020    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:37.000786      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
74ad02b8-4b83-4986-8be1-bcbfc148c12a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:38.00061       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ca4e2ab8-8c4f-44e2-9b25-2d4b2e6d7616    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:38.00061       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c4a33353-7db1-4edb-b2b2-007afc5dc61a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:38.00061       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7f3bf371-872b-4f56-a647-4022edb12c74    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:38.00061       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
cd8bcb39-04e8-4e60-ba38-d50bcbb60d6f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:39.00045       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3709a768-d5c3-40a6-89f7-07e58ce9498f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:39.00045       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5a1ecd17-dda9-462e-84aa-06c7748bb407    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:39.00045       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
1251e401-436e-4f88-b131-dcdc699a52fa    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:39.00045       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
cbe6e785-3c03-40e2-bc02-a4b51f97df47    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:40.00177       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
385c679f-800a-448d-992b-7b2c46756b6d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:40.00177       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
9082301d-1bda-4dde-b93a-cce8264c2d58    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:40.00177       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
50cc8dbe-f556-4e7b-bbe7-06b1ecb9f10d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:40.00177       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a09b23c4-3fec-41ba-8536-41b53f8ab5d9    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:41.001835      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9d18e844-af65-447f-87d3-d9c3f91ee395    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:41.001835      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
21e5d602-67f4-42d5-9285-87e57ee55f5c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:41.001835      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
242fbea3-130c-4959-8c82-cca3696bcd81    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:41.001835      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
1cbbdf70-7050-406a-8702-713e3a6b8e80    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:42.001701      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9ccbbe3c-d548-4c96-9d60-e7c8dae6ce34    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:42.001701      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
3ee937b5-b1c7-4221-9883-7b9cfcafe2c7    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:42.001701      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
803783f7-db57-47d1-89f5-369ab364a01a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:42.001701      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
0e46603b-7a5f-4128-8755-47a817582ffb    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:43.001577      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1665eb5c-7904-42f1-9169-a5ba02e90574    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:43.001577      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
07d74542-d27e-41cd-802c-e80c018bf0bd    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:43.001577      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7322244c-0e6f-408e-8169-35d3a889e0fd    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:43.001577      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
af313166-ec23-4e1c-b652-16097ff9d405    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:44.001035      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4b671d63-1807-4262-ba7e-704c71474677    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:44.001035      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c2f53fc9-8110-4c69-94ce-a6d4d1a673bb    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:44.001035      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0a93c910-0f7a-4e5a-8176-9caa7725545e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:44.001035      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
843f56ff-c554-4a1b-be15-330cc3c6fbab    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:45.001461      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1f7fb1c8-c521-45ed-bcbd-639e5de83b4c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:45.001461      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
4a1af23a-0daf-492f-871a-c98532ea36ba    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:45.001461      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a0639465-3bd9-4928-8261-d228f3530740    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:45.001461      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
5d16e9c5-3df2-4c8b-9901-536b47d265d0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:46.001654      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
1b7fa58d-e3e6-4d0d-886e-64f6e3138662    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:46.001654      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
25266249-d288-4ebb-a0bb-19f6ce2eae37    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:46.001654      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
26e0aff1-29ca-490e-bf01-2a2912e51f8c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:46.001654      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
36243ed9-82c2-413b-bead-4582cf5e3ec2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:47.00161       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
d4044a02-5fbc-4103-afc7-c87345b4bb00    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:47.00161       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ca0df484-8523-4a26-b0a1-213b6716d181    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:47.00161       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
54830f59-7b79-404f-b7cb-06546f503be3    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:47.00161       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8509c921-1151-47c6-a42c-64dafba7fab7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:48.000535      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
07aa761a-eede-4875-b571-b66f4b9c98be    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:48.000535      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
0ea94b16-32f7-490d-89ea-26d4e2fda5a3    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:48.000535      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
355c2f81-9c33-4d26-95c3-4c348e4bbfb6    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:48.000535      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b1328b79-87da-4151-aee1-ab00c03a24d8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:49.002232      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
095cb003-a59c-4635-9ca4-6d01bc332da0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:49.002232      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
71369802-2b97-4da4-b5b9-0062d32c4cd1    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:49.002232      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5e9f4cab-611c-4bdf-a330-c9d9b8694164    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:49.002232      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
643e380f-12cd-40c9-95b5-5b7a824cceff    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:50.001399      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a8029c69-5ac5-4c12-9b25-292324a3c3bc    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:50.001399      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
76c986f2-c952-4381-88a6-0e02f678501f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:50.001399      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
fdc512b2-67e6-45b5-af92-015596d6a175    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:50.001399      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6b5225ff-0ac9-4a60-bb75-03a3a37090b1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:51.00172       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
65e74e0c-96b1-44f0-88b7-d2b67f1ecf7f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:51.00172       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
bccbea88-7583-4e37-b331-0058dfb6f30e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:51.00172       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
a3297f51-7450-4063-a09c-8864c9af82eb    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:51.00172       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d5d37562-7768-4e14-a8dc-cc1db80927ad    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:52.000469      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
17009f82-3f9c-479d-8b6d-bc958d14738f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:52.000469      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b22757be-1b07-47e3-b743-6b05f1918a7c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:52.000469      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
52bb179a-3e47-456b-a991-2d8ef8464e2f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:52.000469      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
282a3303-60b1-41c4-902b-a455957db5be    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:53.001562      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
561e2fa9-b9ee-485c-a9cf-9b66e8193c74    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:53.001562      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
28fdd471-7f9c-43c5-bd6a-85818ea88cc1    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:53.001562      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
fd2efde4-aeb1-409f-80fe-0fc557d6eeb0    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:53.001562      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0aa6bfe4-1054-4889-bab0-16946f9855b6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:54.001128      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
382b8726-905b-4763-899d-61583d5f2384    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:54.001128      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
6eb1214a-e619-4f7e-b792-9ea9997976b3    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:54.001128      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
e064ea54-dee3-4133-8592-0ffa6a9285b9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:54.001128      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5b0aff0e-5379-47e4-8412-383c28367b5e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:55.000841      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
86c1d7b5-450c-4412-91e2-70bd3d64d750    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:55.000841      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
5ffb93dd-d9e0-41cd-913a-39a15ced82a4    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:55.000841      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ac352e27-28ba-4225-b870-1d383ce91bba    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:55.000841      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b72cbdb0-a467-4afd-b0fe-b45c02fcdcc4    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:56.000665      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
157f618b-52bc-4d7e-89ee-6306b4e225a0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:56.000665      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
91e1358b-2359-450f-895d-1f260939ed40    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:56.000665      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c0ed4ddd-5cf6-4f2c-b31a-4900ba423592    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:56.000665      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
69385842-512a-4a63-8d7a-c4c61f3be1cc    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:57.001449      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
7bbb411c-cc7a-4d0c-8b72-6f296339f7cb    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:57.001449      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e4c8c2a8-1e31-4624-ab6f-2ea1a9477b95    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:57.001449      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ca6ec1a2-238f-43ff-920e-2b654bb4832c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:57.001449      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0bc6e8a6-3651-48d7-ae38-61a04ab6930d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:58.000739      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
31fca0f1-7c5c-473f-8fbb-9f9d78cce5c3    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:58.000739      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b43fce17-528c-4541-b7a3-9840c3c3138c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:58.000739      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
7501d2b6-e429-4fa4-b18a-53acc48486a3    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:58.000739      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
2f124113-8a33-487d-9eb0-92a0650d3fec    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:59.000824      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
e5fe859d-2aa6-4eb1-a0ac-17b98cee4218    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:18:59.000824      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
8b705de7-2e36-4905-b7e1-01601cdeaf0a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:18:59.000824      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c8967895-0fba-45c3-833b-839f94d0333a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:18:59.000824      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
eef64adc-7145-4c10-bc53-c41066240944    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:00.001364      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e24844fd-3f4c-400a-aa63-412019cdb1f0    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:00.001364      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
f56fd365-2ad9-4ff3-ba3e-c18c6fcaa7f7    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:00.001364      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
2fe10df0-c3c3-4360-a92b-352897ec4593    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:00.001364      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
4ab2a8a6-fa05-415f-94d2-943908008d45    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:01.000885      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7782452c-27db-4447-82e5-f3b43dba693b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:01.000885      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
377062f1-3e91-4396-889b-4870ec7495d8    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:01.000885      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
8dd14de5-8f7b-41f9-9c35-d6b6b54a6e97    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:01.000885      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5e2d23da-68c9-4a45-bea5-ab0fee2cef2f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:02.000764      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
80bd831d-6fac-4a0b-bd73-17f7cbf2df00    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:02.000764      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d15e50ed-7a6a-4bc3-aca9-fe205b7f0e17    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:02.000764      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
692cc535-7046-4cd3-ad42-eba6beb67743    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:02.000764      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
02c3b894-0044-47b0-ab19-d18efe7f2831    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:03.000378      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
90b00882-dd7f-4e3b-acd4-6ca580874616    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:03.000378      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
234bd2b3-33c0-4041-a370-8340eda2adca    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:03.000378      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
bbdea74f-fd8e-404e-b0ac-f264752fbb7e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:03.000378      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
9b5cc8ed-a81a-4325-9f5a-7467682fe391    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:04.001656      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e66212bc-ba04-456f-804b-74a3fc62abcc    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:04.001656      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
aa3af374-14bc-4f53-8672-361ab5f21407    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:04.001656      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
cc6b4c43-439c-4cba-8bbe-fc14234eec89    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:04.001656      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
18fedea1-91c0-4214-aba3-6a9649f1a9ec    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:05.001509      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
cd100632-f2cb-43c9-b271-0dc7120d8da0    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:05.001509      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
6be7463e-7ed2-4305-a1a4-3eb965f06064    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:05.001509      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9d686ccb-a205-4ff4-bc08-d74cccee5851    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:05.001509      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
acac8429-135f-4c76-8147-968d4e30ad69    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:06.000593      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
fd4f6919-35d9-4fe5-8aef-5ef47d078f65    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:06.000593      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
76dfe32a-b643-4d3c-92b9-fb69cfcecb16    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:06.000593      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3fbf0b29-bc68-4a58-a261-8a6d5acaf146    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:06.000593      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
0a39165f-b9ac-4ea4-8bce-00c850e01342    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:07.001655      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
75890ddc-bdee-456f-b454-75b38924e4de    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:07.001655      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
110868e7-b3d6-4f2d-acbc-790a6562aac0    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:07.001655      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7852d6f4-f4ff-4e2d-9dfa-5b6fd3dd13d7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:07.001655      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
90c92517-7fe5-4b10-8522-0e4ed5bf4242    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:08.001556      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
07208465-0e22-4e90-b47a-d0acc47e2c85    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:08.001556      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
fe9391bb-a736-4d90-ba29-ff6e41173991    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:08.001556      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
4542ff0b-dc66-4731-8de6-e28838cdea3e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:08.001556      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
9419e5b1-0af4-458d-907b-b698aa117075    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:09.001727      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b745a617-9484-494a-be17-83e49326dcc6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:09.001727      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a3ae7757-0a2e-40a6-84ee-67af2b8a599b    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:09.001727      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
33edde14-4d4d-4b23-88b6-375c2c258f39    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:09.001727      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
487dbb00-014c-4b27-9375-35e7cc254c05    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:10.001681      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
5fa1b43c-75ec-4ae5-916f-2838498fc92f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:10.001681      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
beca6572-e0f7-4639-8126-36702f09821f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:10.001681      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
069ac54e-8bbe-4c6a-832a-50bb6f454af3    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:10.001681      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1cd0d41a-1fdf-4e1a-aad8-774cf7a6035a    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:11.001666      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6f4eb900-7720-4b68-89b2-51475b1a91e5    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:11.001666      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
bc279f96-6145-4dd7-a04b-a493ef0ffa19    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:11.001666      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
af0fc6f0-500c-44cc-8758-7cb8a58eb9c7    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:11.001666      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
54c2d9d3-0dac-4856-9355-38d8336c45f9    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:12.001683      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
5ee25333-26e6-4412-9f2a-77911e06a73e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:12.001683      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e3881712-5f9d-419e-beaa-2d3fd48474cf    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:12.001683      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
13f6760b-cff2-4d6f-8036-8addbaf7c72d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:12.001683      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3f847ec5-1dc5-455e-899d-1058a8e348c8    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:13.001604      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
dfff5699-b01f-4de0-b34a-832065ecfe74    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:13.001604      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9b0f8820-6687-4c4e-b6ef-4b3d5d0bdaef    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:13.001604      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8e30608e-72be-4cca-b6ff-7f406ecb4f2a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:13.001604      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f28d207e-0a83-464f-a82d-afc66f5e36ef    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:14.001746      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
2e0a8532-1a9d-4174-b542-8bb263a6c91f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:14.001746      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9ed287bd-b1e3-4c12-8c79-7f3321c798a6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:14.001746      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8e7ef779-5795-41ba-b66b-5e9a335272f1    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:14.001746      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
218850fc-940a-407d-8197-a9d8023c1b77    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:15.001527      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
03643db3-41bc-4029-8889-3ee6261fdb7c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:15.001527      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
10aba526-092c-415d-8d24-5f7c51344b73    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:15.001527      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d1ef240e-6c68-41e8-a338-6a937067d088    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:15.001527      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b1a90138-06b7-498f-8366-604e1bd54b31    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:16.001751      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
40495440-565a-46e3-9c46-ebdded4f8991    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:16.001751      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
42326700-7b3f-425c-ab52-c1b44ae9f21b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:16.001751      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
59bf95dd-dbd7-4158-9627-781c88c8a07f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:16.001751      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
eb561f47-d438-4058-9291-e38f5cb3fe20    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:17.001714      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
ff7560a5-fa66-4233-9a90-aec439805b89    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:17.001714      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
28e8d1d1-ade8-4ca8-9e24-1722a4ef3d49    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:17.001714      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9e3c8cb1-5e81-434f-8fca-75e84d3de7d9    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:17.001714      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ca068a4e-32b7-4063-954c-7dea3de25c38    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:18.001605      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
15af6d04-1eb5-4354-9092-b2d278e56b22    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:18.001605      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6efa8431-eaff-4d09-86e6-141238420b5b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:18.001605      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a7abd312-6c28-477f-a532-f73954686705    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:18.001605      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
cc8a5029-3824-4dae-89ec-d977b232274a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:19.001683      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
6806698e-d7cb-4422-95e6-2a483b49af49    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:19.001683      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
66fb9f4b-dee0-41aa-93a5-d998229d2ce2    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:19.001683      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4e5e7cc3-ae30-4259-a4d4-57d3151ebd15    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:19.001683      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
00c4b1df-f1fd-436b-8a8e-f42f9404be4d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:20.00145       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
95d98179-d101-4eef-a2b9-1e5d050733f9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:20.00145       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
70ad0d9e-7941-47e9-8869-804a80e72fa8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:20.00145       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4466d604-5587-4126-afe8-b9b1137d47cb    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:20.00145       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
bf18e88a-a45b-46a7-84a8-83a01d3bbf29    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:21.001654      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
df64ac06-cc68-4a9c-8413-ff884e2b4b2f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:21.001654      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
e791cb45-2960-4e41-ac4d-dfe2fecf52ea    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:21.001654      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
17d005f6-461d-4e70-bc1d-fdd0cd33da33    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:21.001654      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
cfd83c5c-9ada-4795-8665-d506157a3426    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:22.001569      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
fef236b7-be3b-447f-b032-195b0f384966    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:22.001569      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d536048f-71e7-42ee-a94f-8df8d28af21f    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:22.001569      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
0df3e256-f943-48b9-be19-3db3e06e0199    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:22.001569      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
13313fa4-a390-47ce-bbb4-572e1236042a    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:23.000612      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
a2ca05be-91e8-4352-b1f4-052b09d4055c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:23.000612      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
c9fb11b5-4651-49e1-8dcd-188d073b6e3a    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:23.000612      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ae4cd9a9-a08e-42d9-b010-bd04604dcef6    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:23.000612      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3000b83c-88fa-4593-83af-396d85a26cc5    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:24.001699      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
61b16519-fa78-4740-9e1e-0227045c090c    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:24.001699      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8c64432d-8398-4d84-913a-d201aac7d446    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:24.001699      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9fb2c0df-26a0-46a7-94c4-0bef7bcca1b3    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:24.001699      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
db975adf-2262-4bfa-a3c9-a8ee4c9ee0f4    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:25.001891      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7bdcd306-1fb6-4182-a4be-648ccd577b98    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:25.001891      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
0bdb9c7c-6765-4fc1-ac2b-d61083d90def    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:25.001891      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
43b29ace-cf03-4f74-ba6c-47eb7dcafef4    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:25.001891      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
9cd69283-55cf-46c5-9a2d-9f6dbb8f5f4f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:26.001822      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
9f3d323f-7e82-41dd-b865-ec8fe643b257    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:26.001822      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
28b94c50-145c-4e43-ab1d-02580778fb92    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:26.001822      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
dbc48982-c9f4-49a1-8970-35f0440b0be7    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:26.001822      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
d13f88d2-8725-4564-8390-3b75fe814234    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:27.000707      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f2c2a7d6-ba26-4ad4-9127-b90f048985da    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:27.000707      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
36a2587b-1ddc-41a2-be04-40d33cb140fc    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:27.000707      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
59b90408-5617-41e8-99cd-4499d353f28c    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:27.000707      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
4a855566-77ef-4117-8198-a2546e3d1523    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:28.001412      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7942afce-79a5-4a13-925b-780f04bc7f8d    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:28.001412      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
589e145e-4f6a-4ff2-88d1-730d231b648b    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:28.001412      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
206bc85c-b210-491f-9617-e08cecfa3f2e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:28.001412      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
c1037e2b-f4f4-4f9c-bb4a-952ca4b5739a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:29.001597      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c3614194-8b5e-471c-b05f-704973402498    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:29.001597      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
b8dcb377-cc63-41a9-88f8-97e06e08fe5e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:29.001597      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0fbe8a79-af9e-4e5f-8c9f-9d324ec188dc    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:29.001597      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
87efd22c-1afe-47b0-ae05-7adc4137b01f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:30.000395      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
a86a30c7-56ac-45ee-a6c8-d92f69951bf8    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:30.000395      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
db3ed101-da71-4700-8ffa-da1956e9d211    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:30.000395      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
3a94b6df-b2ab-4c5f-b9a0-cad7103b44bf    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:30.000395      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
379ac941-a190-4d4f-8a53-d76ed714f702    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:31.001591      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
768bac5a-ebd1-4d69-b0b2-11d28e43bc0b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:31.001591      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
8d6beac6-14c9-4e31-9c8a-34ea095b55cb    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:31.001591      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
18458403-3eed-4824-830b-94dc83b15db0    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:31.001591      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
f72d9fc5-df1a-4750-ad16-ef23ce038a9f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:32.001706      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
453265bc-f94f-44c1-9887-2cc6a30b06bc    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:32.001706      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
54c10b19-023f-4297-ba3c-5d6125928283    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:32.001706      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
3a0a3a1e-ccde-4820-8c39-557096eb44b1    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:32.001706      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
c214621d-84ee-4ea1-94d5-77c42b94822b    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:33.001848      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
6463dafc-cad0-449b-bf03-b984b0290d3f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:33.001848      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
e7f00db9-b05d-483f-8d01-e00d5df9e4aa    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:33.001848      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
32d9456a-cfb0-4d70-afd0-aee6e82d5b47    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:33.001848      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a8de302c-166a-4f41-b4eb-cac46f280b9c    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:34.00186       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3909e83e-1a10-4281-8c41-7491530c17cd    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:34.00186       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c5f8795e-6102-4e81-a483-0ba4556b8171    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:34.00186       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
eedfe9a2-4300-43f8-9546-79cefec37314    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:34.00186       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
23c64c71-089d-4238-8ae1-a0f4c14fcccc    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:35.001316      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
994ff4bf-6385-4cc0-9632-8018bc80881b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:35.001316      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
b3b61205-254e-41a1-a4e7-481e885ee99e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:35.001316      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
cc567567-b3ee-4e0e-a66f-32b716bc3c06    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:35.001316      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
11b70f0e-34bc-4026-95b0-8bcf1ef11853    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:36.001734      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
42383ceb-e010-48d9-b20c-25c5ca8578c2    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:36.001734      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
67f891f1-8db9-47f2-ad72-4bed46a4b028    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:36.001734      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
520bd083-816c-46c4-bd93-842933c60fbf    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:36.001734      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
25e08f11-417a-4459-87c5-ed9d0866a810    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:37.000616      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
a1048306-50f8-47e0-8de4-cc3ca41d476d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:37.000616      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
f3853166-21c3-4d11-b3f6-6113bba58ba3    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:37.000616      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
64082d30-0793-439e-a569-d26b95a1a8ea    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:37.000616      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
cb496270-06c6-4a59-9638-3ee943fe6445    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:38.001502      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
8dd774fb-d1c7-48f5-b44a-50b7899af5f7    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:38.001502      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e7b0eb86-fab1-43e9-befe-7df0037ff897    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:38.001502      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
dfe65e84-7247-4fcb-a844-fcde507f355e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:38.001502      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
16651ca9-8891-462b-bab3-b1eba79d3009    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:39.001467      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ccf7b66e-3f53-4edf-a11b-d2181a0a8d88    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:39.001467      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
3e91b9e0-4e3b-46e9-9749-a81a8a2e12e1    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:39.001467      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
26129542-6e63-467a-9560-b3e548737569    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:39.001467      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
95567e47-7541-4e3e-ac1b-d15012cb189d    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:40.001622      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
c80f2c48-e7f2-4770-bf46-84c3916a69f7    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:40.001622      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
cd10f0aa-1362-4040-8339-bbf4c8c04d90    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:40.001622      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
2746ff46-be76-46b9-9e6f-766dabc379ad    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:40.001622      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
83dd0897-1177-4798-b1cd-1e6598c7d510    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:41.001769      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
ae08a961-0677-4aad-9821-fd2e1e79bdd9    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:41.001769      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
2b2b3a78-8d05-487b-b61b-ad6e96da0403    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:41.001769      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
f07f16e7-40e3-46e7-9a12-4ef2d45bfc9f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:41.001769      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d587e92b-706c-4c0d-8290-5140e61da8bf    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:42.001018      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
e8dc726d-919d-486a-b2a2-9de69117f5df    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:42.001018      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
c6ffdda2-2a13-449a-9f84-1acc75a4833e    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:42.001018      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
fcf4670e-e3e3-43b0-af0e-8a7cd893ca7e    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:42.001018      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a0543062-e3cd-4b26-aeea-4fa13ddb8461    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:43.001723      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
78d00771-6fbe-4e7a-b821-803be38ff8af    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:43.001723      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
e8a22cd3-a574-4c3a-8d41-7d96cf06ea1b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:43.001723      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
b736a96e-4d2d-4406-8e96-986525af84e4    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:43.001723      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
4a8c03be-1b60-42dc-bd1c-75c24a0081c4    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:44.001679      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
84d4be60-58f4-44f9-a815-c48ba59a1154    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:44.001679      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7e96011e-664a-4499-8732-b523cc72c328    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:44.001679      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
80db4c68-d0cc-4943-9b79-96e75000afd9    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:44.001679      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
ac7fc933-276c-464f-9e03-18e27d105403    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:45.001649      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
71bf8a25-6d33-477c-bf73-1424bb270656    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:45.001649      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
22d0f8f5-3b6f-4dc1-997d-6605182bb0aa    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:45.001649      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
22a5d392-c453-4cdf-a4a3-ac33ef1d52c4    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:45.001649      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d028b551-260c-4460-bbf0-203856f52eb8    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:46.001028      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
09fa1b7f-9d90-4094-be3d-d4fd8b4aa564    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:46.001028      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
b148e27d-d1a6-41bb-924d-2ad43af376d9    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:46.001028      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
74103302-4dec-4680-9c3c-6d17af33914f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:46.001028      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
4168b32a-3ccb-4fbc-b155-1ceda240908b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:47.000901      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
eb83efdf-3a48-42fc-ac2c-a02c1590be1f    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:47.000901      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
540a35b8-9a02-4f55-9732-08f4660e9511    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:47.000901      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
e1ef9ba8-b51c-4c79-8004-fc2b4068ed9f    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:47.000901      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d6ce5218-cc48-4858-b0fa-1d10f2266f80    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:48.00191       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
a6555bb2-b637-480a-87a0-e46100789cec    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:48.00191       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
0a517ed8-48e8-4131-bedc-5b74c9260094    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:48.00191       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
6022d948-d967-470a-9a9a-39fa614459cf    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:48.00191       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
26da8aba-d4c9-433d-b2ea-b26a2cb196b6    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:49.001651      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
1584bca8-fa92-425a-bb00-2955f3b093ba    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:49.001651      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
2e956705-ec18-46da-be0c-38d09aadbf2a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:49.001651      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
ce1e92d2-c365-4f7d-9c66-522808c149cf    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:49.001651      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
4673f8e8-512d-4f6e-87ae-a6e8ffec2fe2    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:50.001649      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
78d30f75-9734-4e65-bcff-0c82cfac0d77    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:50.001649      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
408c43e8-d732-4fc3-be8b-c32a9b7c43bf    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:50.001649      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
943d1483-988f-4f84-9b18-1fc232bee938    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:50.001649      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
c58a866c-53ac-4f0f-8569-14e4fc918dc8    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:51.001571      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
d140b0ae-1357-4afa-b3b0-84fa135d9598    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:51.001571      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
35a65e89-4073-4d94-8312-4f9224b47618    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:51.001571      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
acf7c092-9db9-42c0-b4d7-2644e401d887    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:51.001571      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
7c1f5ad2-dc1e-4a98-91db-d75ce1121eab    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:52.001734      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
7f51fe18-b93c-4910-9b1c-4ca40d14c46b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:52.001734      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
82011cc4-f788-45fe-af84-7778b758f91e    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:52.001734      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
00fc62a3-1e2b-484f-909d-e11104c4f6ba    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:52.001734      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
948796eb-3611-4979-9763-b2ccbd816c2c    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:53.000577      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
9036841d-edd9-4e4b-bfb0-9bfe8a0533a2    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:53.000577      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
43de4df4-cee2-4ddb-89d3-df237502581a    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:53.000577      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
dff77cd7-6a73-4b15-b352-d5fb38e0892f    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:53.000577      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
e85f0bb2-b198-4464-aef9-e6a9d9786e54    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:54.000795      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b9cf5626-4954-4e9a-86ed-bcd516d3504e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:54.000795      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
3c6f3ef5-5556-42e0-aa53-393e635a8902    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:54.000795      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7dd79668-e27f-4f27-869a-bd46da1951e8    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:54.000795      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
a34eba6d-d812-475f-93ff-40fa5f6bd624    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:55.001621      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
6d0cae3d-57c2-4f3d-9753-29be626e7f14    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:55.001621      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
c84e64ef-d14b-466d-8989-2f747350336b    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:55.001621      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
09626963-0b4c-4a82-ab09-f3de8aaacae1    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:55.001621      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
6505bdca-facb-4171-b43f-60c6be2e075d    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:56.001964      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
8990452b-509a-493e-a539-9e4ba0c9520e    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:56.001964      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
f7a2603b-0e43-432f-9648-1fdd4d1664d1    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:56.001964      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
0ce733a8-a359-4527-80b3-44e3be09d355    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:56.001964      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
6b0872ce-de72-4bbd-a04a-fff2befb6c25    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:57.000756      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
add0c787-66f8-4adc-bdd1-593584a60744    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:57.000756      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
03d3fd0a-b093-49ef-9959-f328d0cfb910    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:57.000756      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
0fdaa52e-a9d0-4f15-b238-0bf2e63933f9    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:57.000756      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
0e5bb3b5-775e-4446-bf34-36e349af5014    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:58.001691      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
629f77ef-9af0-4a79-a98c-22bf9e3412b3    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:58.001691      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
db1ac0fe-fe6c-4227-9f9e-d7a5b0243256    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:58.001691      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
d5ccdde1-dd2d-4d60-891d-b371b6d04a47    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:58.001691      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
e9853de0-0bfa-4603-9b92-06b106a23a74    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:19:59.000542      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
0ce3f42f-df15-46c2-9e5f-6dd029717bd6    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:59.000542      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
84c39db6-a32e-44e4-8bfc-7dc93c984d0d    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:19:59.000542      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
109790da-ef33-4251-8b43-f884a7fb813b    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:19:59.000542      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
1602fb5d-a23b-4735-96b8-177b1d585718    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:20:00.001231      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
42923593-5379-4580-8aa7-76cf4c4719df    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:20:00.001231      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
47f6c4f9-6e4e-47fe-99cc-2faad3d3d67b    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:20:00.001231      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
78d8f7ee-f358-4acd-91b8-c88d2b88acb9    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:20:00.001231      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
068f3ffd-2ee2-4416-b452-5e9dd02095d1    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:20:01.001408      9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
209aaf29-285e-4db5-9525-910024711e4d    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:20:01.001408      80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
25a36f9d-fec3-4cd7-b86d-d9b6ae875324    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:20:01.001408      48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
406ed290-d4d6-4b4f-8a57-dc47533c216e    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:20:01.001408      f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
7ff875d9-4248-4a04-bbb1-20149aaacba2    accc69fd-93b1-4739-940a-0483fc07fa09    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:20:02.00064       9f21396e-7416-46ef-b981-ba43a36ff6e7    \N
64fb56b2-4671-4965-b2f6-110ed1f57cd6    f128186e-47c5-4ed7-aea8-a7295376f35d    DEBIT   MONTHLY_RENT    25000.00  \N      2026-03-16 15:20:02.00064       80dc3bd0-cab8-4365-b49a-27fedcab74b2    \N
b2b1626e-f542-4fe9-aa9c-d024d4427daa    53009a0e-37a7-475b-b7fe-ae3419103b04    DEBIT   MONTHLY_RENT    2000.00   \N      2026-03-16 15:20:02.00064       48a4c1e4-1103-4b27-bf95-f2b7355f24b7    \N
42275dc4-a0ac-4ffe-9eb0-56cf4274e157    21003980-9dd5-4490-9ed4-3d5f4e7164c8    DEBIT   MONTHLY_RENT    20000.00  \N      2026-03-16 15:20:02.00064       f3d8da6e-1469-4374-ab01-e065b2950c5f    \N
\.


--
-- Data for Name: mpesa_transactions; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.mpesa_transactions (id, transaction_code, phone_number, account_reference, amount, raw_payload, processed, created_at) FROM stdin;
8fa0a724-224d-4486-b901-35be0268a3d3    TESTPAY002      254112678976    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY002"}, {"Name": "PhoneNumber", "Value": "254112678976"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 14:55:03.462999
36e7ccf3-6255-430d-8def-68cfee218fb0    TESTPAY003      254112678976    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY003"}, {"Name": "PhoneNumber", "Value": "254112678976"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 14:59:39.37271
79c5034c-02fd-42c8-983f-6f12c76da366    TESTPAY004      254112678976    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY004"}, {"Name": "PhoneNumber", "Value": "254112678976"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 15:08:04.61596
f0c067fc-75ce-4721-928e-8d56b9828922    TESTPAY005      254112678976    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY005"}, {"Name": "PhoneNumber", "Value": "254112678976"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 15:13:17.501657
d02e18d6-d427-4938-9188-54c5bc7ba266    TESTPAY007      254112678976    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY007"}, {"Name": "PhoneNumber", "Value": "254112678976"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 15:19:14.576247
f5c12a53-c09e-43d9-9c21-51956cb5bfb2    TESTPAY008      254112678976    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY008"}, {"Name": "PhoneNumber", "Value": "254112678976"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 15:21:54.720906
9bba6a65-6749-40df-9762-4181941b9e05    TESTPAY011      254112678976    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY011"}, {"Name": "PhoneNumber", "Value": "254112678976"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 15:28:37.52299
15e8689e-dc6e-4d9d-998b-7e5dc126293a    TESTPAY012      254112678976    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY012"}, {"Name": "PhoneNumber", "Value": "254112678976"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 15:31:15.062486
c7046955-200b-4dbc-bbcf-c84b10f69bb2    TESTPAY013      254112678976    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY013"}, {"Name": "PhoneNumber", "Value": "254112678976"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 15:36:06.761177
4d600174-728f-4c11-b15d-f04e2108fb1f    TESTPAY014      254712345678    M1-2    2000.00 {"Body": {"stkCallback": {"ResultCode": 0, "ResultDesc": "The service request is processed successfully.", "CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY014"}, {"Name": "PhoneNumber", "Value": "254712345678"}, {"Name": "AccountReference", "Value": "M1-2"}]}, "CheckoutRequestID": "ws_CO_123456789", "MerchantRequestID": "12345"}}}   f       2026-03-08 16:43:00.073926
7ee36eee-e920-43f8-ac50-79005b15883d    TESTPAY015      254712345678    M1-2    2000.00 {"Body": {"stkCallback": {"CallbackMetadata": {"Item": [{"Name": "Amount", "Value": 2000}, {"Name": "MpesaReceiptNumber", "Value": "TESTPAY015"}, {"Name": "PhoneNumber", "Value": "254712345678"}, {"Name": "AccountReference", "Value": "M1-2"}]}}}}        f       2026-03-08 16:47:55.471438
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.payments (id, tenancy_id, amount, payment_method, transaction_code, payment_date, created_at, receipt_number, receipt_url) FROM stdin;
1a452875-34b5-44ab-bb51-b4fb45f78a60    80dc3bd0-cab8-4365-b49a-27fedcab74b2    25000.00        MPESA   SAFE001   2026-02-27 16:47:39.886364      2026-02-27 16:47:39.886364      RCPT-20260227164739     \N
8e9fb4d0-0b1f-4b95-807a-9d20075b8c4f    991ef00c-a4cd-43de-972d-09064693e803    2000.00 MPESA   TESTPAY0122026-03-08 15:31:15.145467      2026-03-08 15:31:15.145467      \N      \N
aef046d4-3cd7-45e7-8ddb-6d46fcf8ea1b    991ef00c-a4cd-43de-972d-09064693e803    2000.00 MPESA   TESTPAY0132026-03-08 15:36:06.850222      2026-03-08 15:36:06.850222      \N      \N
d5fdf070-cf23-4ebc-ac86-419333defeec    991ef00c-a4cd-43de-972d-09064693e803    2000.00 MPESA   TESTPAY0152026-03-08 16:47:55.482869      2026-03-08 16:47:55.482869      \N      \N
\.


--
-- Data for Name: payouts; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.payouts (id, landlord_id, amount, transaction_cost, status, mpesa_reference, created_at, processed_at) FROM stdin;
\.


--
-- Data for Name: properties; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.properties (id, name, address, city, country, account_prefix, landlord_id, created_at) FROM stdin;
f128186e-47c5-4ed7-aea8-a7295376f35d    Sunset Apartments       Westlands Road  Nairobi Kenya   SUN     c20e89f4-6af2-4eb3-8753-d62dc9407544      2026-02-27 16:17:48.310169
53009a0e-37a7-475b-b7fe-ae3419103b04    kaa Mbaya       ruiru   Nairobi kenya   KM      738aba50-b6a9-45d5-88ef-18e06ae06300      2026-02-27 20:56:18.505272
21003980-9dd5-4490-9ed4-3d5f4e7164c8    mavha   gg      hhhh    america M       738aba50-b6a9-45d5-88ef-18e06ae06300      2026-02-27 21:00:44.084038
bc053a7f-8dd4-4c8b-adb8-8cc9a54d2e8d    Hassan Nassim   Ruiru   Nairobi Kenya   HN      56ce0292-7e84-46b2-b087-f134beb01c32      2026-03-01 18:25:59.49179
16985376-25d3-4fc5-b049-a7e72b8d4182    Hassan Nassim   Ruiru   Nairobi Kenya   HN1     56ce0292-7e84-46b2-b087-f134beb01c32      2026-03-01 18:28:25.489054
accc69fd-93b1-4739-940a-0483fc07fa09    mama    Ruiru   Nairobi Kenya   M1      3abfc0c8-ac6a-4e94-b1d6-c24c85958ebf      2026-03-04 15:18:57.17017
805407c1-b6fc-4154-865f-824883d91e05    Hello   ruiru   Nairobi Kenya   H       3abfc0c8-ac6a-4e94-b1d6-c24c85958ebf      2026-03-05 18:16:18.426009
a99520a0-5799-45c7-8382-fa183de6cf54    seasons Clayton Nairobi kenya   S       c79be6c7-751c-4f47-b776-28131001fdb4      2026-03-08 18:34:18.833704
29fa61c8-b97c-486d-95ae-aadcc1c1a4fb    samirah holding 00112   nairobi kenya   SH      3abfc0c8-ac6a-4e94-b1d6-c24c85958ebf      2026-03-08 18:42:33.911765
\.


--
-- Data for Name: sms_logs; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.sms_logs (id, recipient, message, status, provider_response, created_at) FROM stdin;
\.


--
-- Data for Name: tenancies; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.tenancies (id, tenant_id, unit_id, rent_amount, start_date, is_active, created_at, rent_due_day, last_rent_charged_date) FROM stdin;
8ba2678c-72bc-4255-8ec9-f2cdafe461de    fb7d0c4d-e98a-4d50-90b9-ccb2ca690de4    61288290-fae1-48e6-8c44-ea7eef571b6e      2000.00 2026-03-04      f       2026-03-04 16:37:09.240789      1       \N
9f21396e-7416-46ef-b981-ba43a36ff6e7    17f655f3-4343-4302-8090-7ccf3c1159bd    61288290-fae1-48e6-8c44-ea7eef571b6e      2000.00 2026-03-14      t       2026-03-14 22:44:02.672437      1       2026-03-16
de154a94-4abd-493c-b4f8-1a58a8c4e632    bc42616f-198d-430c-a2a2-a954ae462a79    61288290-fae1-48e6-8c44-ea7eef571b6e      2000.00 2026-03-04      f       2026-03-04 21:51:10.065316      1       \N
80dc3bd0-cab8-4365-b49a-27fedcab74b2    4613c6fe-5426-4bb9-a121-120b0afe01d4    24bca9e8-4f63-43e5-bbb1-0564e5906a3c      25000.00        2026-02-27      t       2026-02-27 16:24:42.686523      1       2026-03-16
48a4c1e4-1103-4b27-bf95-f2b7355f24b7    ebca5b3c-8ba2-4a6d-b250-ab8df6f7df59    c87685b2-8f32-4c0f-ae00-2050ce833b79      2000.00 2026-02-27      t       2026-02-27 20:57:20.269741      1       2026-03-16
5330efaf-2134-4ef4-9f6c-65851f7d896f    0cf05100-2654-41df-9c77-7472b1667fea    0d38624d-53d4-4cb5-aec3-02193e5cbb7c      3000.00 2026-03-08      f       2026-03-08 16:41:20.645053      1       \N
f3d8da6e-1469-4374-ab01-e065b2950c5f    06f56cdf-a542-499a-b106-46a1d5ca5818    9c3fd7cd-0069-4a33-a60e-14270e2fd30d      20000.00        2026-02-27      t       2026-02-27 21:05:37.814416      1       2026-03-16
9b567931-7dd5-41a9-9db5-33a9bfbba6a0    771357e8-0454-4c28-8252-850d5ef860b6    55d43ea0-6f71-41a1-95d0-bbaf0e3d190b      5000.00 2026-03-08      f       2026-03-08 18:48:51.567912      1       \N
991ef00c-a4cd-43de-972d-09064693e803    aa6b7f73-9a4d-4e90-8a4e-cf773f93c763    61288290-fae1-48e6-8c44-ea7eef571b6e      2000.00 2026-03-05      f       2026-03-05 18:15:11.038366      1       \N
4f4de413-2957-42c7-be91-0e03e4af7966    b1d87e80-d6d7-4d27-88ee-539d574aefe9    0d38624d-53d4-4cb5-aec3-02193e5cbb7c      3000.00 2026-03-08      f       2026-03-08 17:37:51.830778      1       \N
77b8d7c6-5fce-448d-ac6b-a67dd40d2ba6    670dd5f7-aba3-4460-81aa-831e1ced30ea    55d43ea0-6f71-41a1-95d0-bbaf0e3d190b      5000.00 2026-04-08      f       2026-03-08 18:54:38.289613      1       \N
b6b666c8-bff8-4c50-9bff-84cac8634ca1    9dc56b0e-5428-4bc1-99c7-77577216544f    61288290-fae1-48e6-8c44-ea7eef571b6e      2000.00 2026-03-10      f       2026-03-10 21:14:46.795639      1       \N
69918614-bb8b-4e25-b70f-a513e038ecfe    33689864-6f28-4f68-9e16-9f2da2fc6869    55d43ea0-6f71-41a1-95d0-bbaf0e3d190b      5000.00 2026-03-10      f       2026-03-11 19:19:15.535646      1       2026-03-14
\.


--
-- Data for Name: tenants; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.tenants (id, full_name, phone_number, is_active, created_at) FROM stdin;
4613c6fe-5426-4bb9-a121-120b0afe01d4    John Doe        254711111111    t       2026-02-27 16:23:41.031245
ebca5b3c-8ba2-4a6d-b250-ab8df6f7df59    Brandon Macharia        0114713717      t       2026-02-27 20:57:20.273185
06f56cdf-a542-499a-b106-46a1d5ca5818    Brandon Macharia        0789008588      t       2026-02-27 21:05:37.816793
fb7d0c4d-e98a-4d50-90b9-ccb2ca690de4    Rapper Me       0112378797      f       2026-03-04 16:37:09.256038
bc42616f-198d-430c-a2a2-a954ae462a79    master  0114713717      f       2026-03-04 21:51:10.113156
0cf05100-2654-41df-9c77-7472b1667fea    mnnn    0114713717      f       2026-03-08 16:41:20.651862
771357e8-0454-4c28-8252-850d5ef860b6    rara kara       +254797546387   f       2026-03-08 18:48:51.578841
aa6b7f73-9a4d-4e90-8a4e-cf773f93c763    Michelle Kamuta 0112678976      f       2026-03-05 18:15:11.118666
b1d87e80-d6d7-4d27-88ee-539d574aefe9    mdffff  0114712548      f       2026-03-08 17:37:51.848346
670dd5f7-aba3-4460-81aa-831e1ced30ea    thjga lana      +254797546387   f       2026-03-08 18:54:38.318951
9dc56b0e-5428-4bc1-99c7-77577216544f    Master Vk       0114713717      f       2026-03-10 21:14:46.843076
33689864-6f28-4f68-9e16-9f2da2fc6869    Iano    0114713717      f       2026-03-11 19:19:15.573991
17f655f3-4343-4302-8090-7ccf3c1159bd    Kareem  0742620498      t       2026-03-14 22:44:02.674409
\.


--
-- Data for Name: units; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.units (id, unit_number, account_number, reference_number, rent_amount, is_active, property_id, created_at) FROM stdin;
24bca9e8-4f63-43e5-bbb1-0564e5906a3c    101     SUN-101 SUN-101 25000.00        t       f128186e-47c5-4ed7-aea8-a7295376f35d      2026-02-27 16:19:40.025641
c87685b2-8f32-4c0f-ae00-2050ce833b79    23      KM-23   KM-23   2000.00 t       53009a0e-37a7-475b-b7fe-ae3419103b04      2026-02-27 20:56:42.542438
10628807-788e-4a41-babf-b19cd73da202    55      KM-55   KM-55   2000.00 t       53009a0e-37a7-475b-b7fe-ae3419103b04      2026-02-27 21:00:04.921255
17bcffb9-238a-4fae-8bf8-c4f01a0c80b0    1       M-1     M-1     500.00  t       21003980-9dd5-4490-9ed4-3d5f4e7164c8      2026-02-27 21:01:01.572999
9c3fd7cd-0069-4a33-a60e-14270e2fd30d    56      M-56    M-56    20000.00        t       21003980-9dd5-4490-9ed4-3d5f4e7164c8      2026-02-27 21:04:52.30038
d04d53f7-3925-4ff3-a807-59411db6aaa4    20      HN-20   HN-20   10000.00        t       bc053a7f-8dd4-4c8b-adb8-8cc9a54d2e8d      2026-03-01 18:26:30.306438
0ff0e11d-f034-494f-a189-b39d131b8d56    20      HN1-20  HN1-20  2000.00 t       16985376-25d3-4fc5-b049-a7e72b8d4182      2026-03-01 18:28:42.68603
61288290-fae1-48e6-8c44-ea7eef571b6e    2       M1-2    M1-2    2000.00 t       accc69fd-93b1-4739-940a-0483fc07fa09      2026-03-04 15:47:37.006606
0eb3f860-851b-49c8-bf83-c351b3e45853    1       H-1     H-1     1500.00 t       805407c1-b6fc-4154-865f-824883d91e05      2026-03-05 18:16:44.573315
0d38624d-53d4-4cb5-aec3-02193e5cbb7c    25      M1-25   M1-25   3000.00 t       accc69fd-93b1-4739-940a-0483fc07fa09      2026-03-08 16:40:48.554625
55d43ea0-6f71-41a1-95d0-bbaf0e3d190b    12      M1-12   M1-12   5000.00 t       accc69fd-93b1-4739-940a-0483fc07fa09      2026-03-08 18:44:56.679504
a8eca70b-8f35-4e54-8e9e-9f85a043586d    1       M1-1    M1-1    2000.00 t       accc69fd-93b1-4739-940a-0483fc07fa09      2026-03-11 19:20:33.980213
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.users (id, full_name, email, phone, password_hash, role, is_active, created_at) FROM stdin;
c20e89f4-6af2-4eb3-8753-d62dc9407544    Issa Landlord   issa@gmail.com  254700000001    Issa    LANDLORD t2026-02-27 16:11:48.599007
8dca0662-6bdf-40e5-86f8-f6c20b76648d    Test Landlord   test@gmail.com  254700000002    test    LANDLORD t2026-02-27 16:15:21.581402
738aba50-b6a9-45d5-88ef-18e06ae06300    Brandon Macharia        machariabrandon99@gmail.com     \N      $2a$10$5b8NDVRmPLnC/B2YCnpx2e6HMVw6WWa5026VsKrq9u5RwrgI6pwS2      LANDLORD        t       2026-02-27 20:55:40.414818
56ce0292-7e84-46b2-b087-f134beb01c32    Kareem Issa     Kareem@gmail.com        \N      $2a$10$yB/0OuOwU9Ix5vfLe0Ebs.HP3WTmA0UtI9RENzOJ1TDmhtTk7e41W      LANDLORD        t       2026-03-01 18:25:16.516023
8cd9b4a7-de09-4a80-ad82-dcc96b20fc43    Kareem  user@gmail.com  \N      $2a$10$QgkDd5YasSWQs8QulMzBoeMcdrEj2PKi/JfZy5zOj2yX4wYA8yilC      LANDLORD        t       2026-03-01 19:07:13.858047
3abfc0c8-ac6a-4e94-b1d6-c24c85958ebf    User user       userme@gmail.com        \N      $2a$10$1IvjIVqR9bsEs/eqXb92Me2fiDgixnmxCQWakAiW0g9RxezFceW4m      LANDLORD        t       2026-03-01 19:11:07.780452
c79be6c7-751c-4f47-b776-28131001fdb4    michellekamuta@gmail.com        michellekamuta@gmail.com        \N$2a$10$QUGzntXJHlyMUjmPz/LS1.uCC2G1b4dqk8omGMC2ocjzLSJjdFp52    LANDLORD        t       2026-03-08 18:33:36.299129
\.


--
-- Data for Name: wallets; Type: TABLE DATA; Schema: public; Owner: rent_user_new
--

COPY public.wallets (id, landlord_id, balance, auto_payout_enabled, admin_approval_enabled, created_at, property_id) FROM stdin;
ebac516e-4046-4869-b7f8-a42a5bee2785    8dca0662-6bdf-40e5-86f8-f6c20b76648d    0.00    f       t       2026-02-27 16:15:21.581402        \N
ace642e7-8068-4f21-9b4a-7ea89bceafab    c20e89f4-6af2-4eb3-8753-d62dc9407544    25000.00        f       t2026-02-27 16:16:07.473028       \N
9b9e5221-810e-4bcc-9f0d-3e61947777bb    738aba50-b6a9-45d5-88ef-18e06ae06300    0.00    f       t       2026-02-27 20:55:40.449911        \N
b042fc91-7d16-454f-92e1-93846bb9668e    56ce0292-7e84-46b2-b087-f134beb01c32    0.00    f       t       2026-03-01 18:25:16.547559        \N
80371780-1bc0-4c2b-8cc7-064e90b3b76b    8cd9b4a7-de09-4a80-ad82-dcc96b20fc43    0.00    f       t       2026-03-01 19:07:13.861695        \N
959b1e05-4113-4a86-a1f0-33d6f79283d6    3abfc0c8-ac6a-4e94-b1d6-c24c85958ebf    0.00    f       t       2026-03-01 19:11:07.781698        \N
05ec4e80-ef81-4019-89db-8cd46e877267    3abfc0c8-ac6a-4e94-b1d6-c24c85958ebf    1400.00 f       t       2026-03-08 16:34:23.503265        accc69fd-93b1-4739-940a-0483fc07fa09
e496893b-d8b6-404f-b564-05b1acd9cc47    c79be6c7-751c-4f47-b776-28131001fdb4    0.00    f       t       2026-03-08 18:33:36.330547        \N
fdd0e01e-d070-4694-853b-bd9f7e2398a4    c79be6c7-751c-4f47-b776-28131001fdb4    0.00    f       t       2026-03-08 18:34:42.315982        a99520a0-5799-45c7-8382-fa183de6cf54
050b6b2a-aa1f-4b87-9ab8-7ff7450cc585    3abfc0c8-ac6a-4e94-b1d6-c24c85958ebf    0.00    f       t       2026-03-08 18:38:48.837248        805407c1-b6fc-4154-865f-824883d91e05
3f920463-17e6-45a6-bea0-ed77267c23c6    3abfc0c8-ac6a-4e94-b1d6-c24c85958ebf    0.00    f       t       2026-03-08 18:43:20.60366 29fa61c8-b97c-486d-95ae-aadcc1c1a4fb
\.


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: dashboard_snapshots dashboard_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.dashboard_snapshots
    ADD CONSTRAINT dashboard_snapshots_pkey PRIMARY KEY (id);


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
-- Name: payouts payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_pkey PRIMARY KEY (id);


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
-- Name: sms_logs sms_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.sms_logs
    ADD CONSTRAINT sms_logs_pkey PRIMARY KEY (id);


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
-- Name: dashboard_snapshots unique_property_month; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.dashboard_snapshots
    ADD CONSTRAINT unique_property_month UNIQUE (property_id, year, month);


--
-- Name: wallets unique_property_wallet; Type: CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT unique_property_wallet UNIQUE (property_id);


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
-- Name: idx_ledger_tenancy_balance; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_ledger_tenancy_balance ON public.ledger_entries USING btree (tenancy_id, entry_type);


--
-- Name: idx_ledger_tenancy_id; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_ledger_tenancy_id ON public.ledger_entries USING btree (tenancy_id);


--
-- Name: idx_mpesa_created_at; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_mpesa_created_at ON public.mpesa_transactions USING btree (created_at);


--
-- Name: idx_mpesa_tx_code_unique; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE UNIQUE INDEX idx_mpesa_tx_code_unique ON public.mpesa_transactions USING btree (transaction_code);


--
-- Name: idx_payments_created_at; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_payments_created_at ON public.payments USING btree (created_at);


--
-- Name: idx_payments_tenancy; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_payments_tenancy ON public.payments USING btree (tenancy_id);


--
-- Name: idx_payments_tenancy_id; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_payments_tenancy_id ON public.payments USING btree (tenancy_id);


--
-- Name: idx_payments_tx_code_unique; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE UNIQUE INDEX idx_payments_tx_code_unique ON public.payments USING btree (transaction_code);


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
-- Name: idx_units_account_number_unique; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE UNIQUE INDEX idx_units_account_number_unique ON public.units USING btree (account_number);


--
-- Name: idx_units_property; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_units_property ON public.units USING btree (property_id);


--
-- Name: idx_units_property_id; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_units_property_id ON public.units USING btree (property_id);


--
-- Name: idx_units_reference_number_unique; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE UNIQUE INDEX idx_units_reference_number_unique ON public.units USING btree (reference_number);


--
-- Name: idx_users_email_unique; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE UNIQUE INDEX idx_users_email_unique ON public.users USING btree (email);


--
-- Name: idx_wallets_landlord; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE INDEX idx_wallets_landlord ON public.wallets USING btree (landlord_id);


--
-- Name: uq_active_tenancy_per_unit; Type: INDEX; Schema: public; Owner: rent_user_new
--

CREATE UNIQUE INDEX uq_active_tenancy_per_unit ON public.tenancies USING btree (unit_id) WHERE (is_active = true);


--
-- Name: ledger_entries trg_prevent_ledger_delete; Type: TRIGGER; Schema: public; Owner: rent_user_new
--

CREATE TRIGGER trg_prevent_ledger_delete BEFORE DELETE ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_delete();


--
-- Name: ledger_entries trg_prevent_ledger_update; Type: TRIGGER; Schema: public; Owner: rent_user_new
--

CREATE TRIGGER trg_prevent_ledger_update BEFORE UPDATE ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_update();


--
-- Name: users trigger_create_wallet; Type: TRIGGER; Schema: public; Owner: rent_user_new
--

CREATE TRIGGER trigger_create_wallet AFTER INSERT ON public.users FOR EACH ROW EXECUTE FUNCTION public.create_wallet_for_landlord();


--
-- Name: payments trigger_payment_ledger; Type: TRIGGER; Schema: public; Owner: rent_user_new
--

CREATE TRIGGER trigger_payment_ledger AFTER INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION public.record_payment_ledger_entry();


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ledger_entries fk_ledger_property; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_ledger_property FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: ledger_entries fk_ledger_tenancy; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_ledger_tenancy FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE CASCADE;


--
-- Name: payments fk_payments_tenancy; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_tenancy FOREIGN KEY (tenancy_id) REFERENCES public.tenancies(id) ON DELETE CASCADE;


--
-- Name: properties fk_properties_landlord; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT fk_properties_landlord FOREIGN KEY (landlord_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: dashboard_snapshots fk_snapshot_property; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.dashboard_snapshots
    ADD CONSTRAINT fk_snapshot_property FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: tenancies fk_tenancies_tenant; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT fk_tenancies_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: tenancies fk_tenancies_unit; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.tenancies
    ADD CONSTRAINT fk_tenancies_unit FOREIGN KEY (unit_id) REFERENCES public.units(id) ON DELETE CASCADE;


--
-- Name: units fk_units_property; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT fk_units_property FOREIGN KEY (property_id) REFERENCES public.properties(id) ON DELETE CASCADE;


--
-- Name: wallets fk_wallet_property; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT fk_wallet_property FOREIGN KEY (property_id) REFERENCES public.properties(id);


--
-- Name: wallets fk_wallets_landlord; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT fk_wallets_landlord FOREIGN KEY (landlord_id) REFERENCES public.users(id) ON DELETE CASCADE;


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
-- Name: payouts payouts_landlord_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rent_user_new
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_landlord_id_fkey FOREIGN KEY (landlord_id) REFERENCES public.users(id) ON DELETE CASCADE;


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

\unrestrict 8sYmgbVpZ9aOHj0deSWegAV6nJsqrMfwu1wvduOoTTqqwNchQvEDrtUFk9HQF5y

