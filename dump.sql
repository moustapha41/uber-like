--
-- PostgreSQL database dump
--

\restrict 7IyN0ofaP8JA10eNnzgctn0hiJvBfNbZo8g935zA4u0kNC9xbzNqDMpVW38ttSI

-- Dumped from database version 17.7 (Ubuntu 17.7-0ubuntu0.25.04.1)
-- Dumped by pg_dump version 17.7 (Ubuntu 17.7-0ubuntu0.25.04.1)

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
-- Name: cleanup_expired_idempotency_keys(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cleanup_expired_idempotency_keys() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM idempotent_requests WHERE expires_at < NOW();
END;
$$;


ALTER FUNCTION public.cleanup_expired_idempotency_keys() OWNER TO postgres;

--
-- Name: generate_ride_code(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_ride_code() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.ride_code IS NULL THEN
        NEW.ride_code := 'RIDE-' || TO_CHAR(NOW(), 'YYYY') || '-' || 
                        LPAD(NEXTVAL('rides_id_seq')::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.generate_ride_code() OWNER TO postgres;

--
-- Name: update_driver_last_active(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_driver_last_active() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.is_online = true THEN
        NEW.last_active_at = NOW();
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_driver_last_active() OWNER TO postgres;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO postgres;

--
-- Name: update_wallet_last_transaction(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_wallet_last_transaction() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.status = 'completed' THEN
        UPDATE wallets 
        SET last_transaction_at = NOW() 
        WHERE id = NEW.wallet_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_wallet_last_transaction() OWNER TO postgres;

--
-- Name: update_wallet_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_wallet_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_wallet_updated_at() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_logs (
    id integer NOT NULL,
    user_id integer,
    action character varying(100) NOT NULL,
    entity_type character varying(50),
    entity_id integer,
    details jsonb,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.audit_logs OWNER TO postgres;

--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.audit_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_logs_id_seq OWNER TO postgres;

--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: corporate_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.corporate_accounts (
    id integer NOT NULL,
    company_name character varying(255) NOT NULL,
    company_email character varying(255) NOT NULL,
    company_phone character varying(20),
    contact_person_name character varying(255),
    contact_person_email character varying(255),
    contact_person_phone character varying(20),
    billing_address text,
    tax_id character varying(100),
    payment_terms character varying(50) DEFAULT 'net_30'::character varying,
    credit_limit numeric(12,2) DEFAULT 0,
    current_balance numeric(12,2) DEFAULT 0,
    status character varying(50) DEFAULT 'active'::character varying,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.corporate_accounts OWNER TO postgres;

--
-- Name: corporate_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.corporate_accounts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.corporate_accounts_id_seq OWNER TO postgres;

--
-- Name: corporate_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.corporate_accounts_id_seq OWNED BY public.corporate_accounts.id;


--
-- Name: deliveries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.deliveries (
    id integer NOT NULL,
    delivery_code character varying(20) NOT NULL,
    client_id integer NOT NULL,
    driver_id integer,
    sender_id integer,
    recipient_id integer,
    idempotency_key character varying(255),
    pickup_lat numeric(10,8) NOT NULL,
    pickup_lng numeric(11,8) NOT NULL,
    pickup_address text,
    dropoff_lat numeric(10,8) NOT NULL,
    dropoff_lng numeric(11,8) NOT NULL,
    dropoff_address text,
    package_type character varying(50) DEFAULT 'standard'::character varying,
    package_weight_kg numeric(10,2),
    package_dimensions jsonb,
    package_value numeric(10,2),
    package_description text,
    requires_signature boolean DEFAULT false,
    insurance_required boolean DEFAULT false,
    recipient_name character varying(255),
    recipient_phone character varying(20),
    recipient_email character varying(255),
    delivery_instructions text,
    estimated_distance_km numeric(10,2),
    estimated_duration_min integer,
    estimated_fare numeric(10,2) NOT NULL,
    actual_distance_km numeric(10,2),
    actual_duration_min integer,
    fare_final numeric(10,2),
    status character varying(50) DEFAULT 'REQUESTED'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    assigned_at timestamp without time zone,
    picked_up_at timestamp without time zone,
    in_transit_at timestamp without time zone,
    delivered_at timestamp without time zone,
    cancelled_at timestamp without time zone,
    cancellation_reason text,
    payment_method character varying(50),
    payment_status character varying(50) DEFAULT 'UNPAID'::character varying,
    transaction_id character varying(100),
    payment_collected_at timestamp without time zone,
    client_rating integer,
    client_review text,
    driver_rating integer,
    driver_review text,
    recipient_rating integer,
    recipient_review text,
    delivery_proof jsonb,
    notes text,
    metadata jsonb,
    frozen_fare numeric(10,2),
    fare_frozen_at timestamp without time zone,
    payment_frozen_at timestamp without time zone,
    cancellation_fee numeric(10,2) DEFAULT 0,
    refund_amount numeric(10,2) DEFAULT 0,
    refund_reason text,
    loyalty_points_earned integer DEFAULT 0,
    insurance_fee numeric(10,2) DEFAULT 0,
    corporate_account_id integer,
    discount_amount numeric(10,2) DEFAULT 0,
    discount_code character varying(50),
    CONSTRAINT check_delivery_status CHECK (((status)::text = ANY ((ARRAY['REQUESTED'::character varying, 'ASSIGNED'::character varying, 'PICKED_UP'::character varying, 'IN_TRANSIT'::character varying, 'DELIVERED'::character varying, 'CANCELLED_BY_CLIENT'::character varying, 'CANCELLED_BY_DRIVER'::character varying, 'CANCELLED_BY_SYSTEM'::character varying, 'NO_SHOW_CLIENT'::character varying, 'PACKAGE_REFUSED'::character varying, 'DELIVERY_FAILED'::character varying, 'RETURN_TO_SENDER'::character varying])::text[]))),
    CONSTRAINT deliveries_client_rating_check CHECK (((client_rating >= 1) AND (client_rating <= 5))),
    CONSTRAINT deliveries_driver_rating_check CHECK (((driver_rating >= 1) AND (driver_rating <= 5))),
    CONSTRAINT deliveries_recipient_rating_check CHECK (((recipient_rating >= 1) AND (recipient_rating <= 5)))
);


ALTER TABLE public.deliveries OWNER TO postgres;

--
-- Name: deliveries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.deliveries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.deliveries_id_seq OWNER TO postgres;

--
-- Name: deliveries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.deliveries_id_seq OWNED BY public.deliveries.id;


--
-- Name: delivery_fees_breakdown; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.delivery_fees_breakdown (
    id integer NOT NULL,
    delivery_id integer NOT NULL,
    base_fare numeric(10,2) NOT NULL,
    distance_cost numeric(10,2) NOT NULL,
    time_cost numeric(10,2) NOT NULL,
    weight_multiplier numeric(5,2) DEFAULT 1.0,
    type_multiplier numeric(5,2) DEFAULT 1.0,
    time_multiplier numeric(5,2) DEFAULT 1.0,
    subtotal numeric(10,2) NOT NULL,
    total_fare numeric(10,2) NOT NULL,
    pricing_config_id integer,
    frozen_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.delivery_fees_breakdown OWNER TO postgres;

--
-- Name: delivery_fees_breakdown_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.delivery_fees_breakdown_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.delivery_fees_breakdown_id_seq OWNER TO postgres;

--
-- Name: delivery_fees_breakdown_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.delivery_fees_breakdown_id_seq OWNED BY public.delivery_fees_breakdown.id;


--
-- Name: delivery_notifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.delivery_notifications (
    id integer NOT NULL,
    delivery_id integer NOT NULL,
    user_id integer NOT NULL,
    notification_type character varying(50) NOT NULL,
    title character varying(255) NOT NULL,
    message text NOT NULL,
    sent_at timestamp without time zone DEFAULT now(),
    read_at timestamp without time zone,
    clicked_at timestamp without time zone,
    metadata jsonb
);


ALTER TABLE public.delivery_notifications OWNER TO postgres;

--
-- Name: delivery_notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.delivery_notifications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.delivery_notifications_id_seq OWNER TO postgres;

--
-- Name: delivery_notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.delivery_notifications_id_seq OWNED BY public.delivery_notifications.id;


--
-- Name: delivery_proofs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.delivery_proofs (
    id integer NOT NULL,
    delivery_id integer NOT NULL,
    package_photo_url text,
    delivery_photo_url text,
    location_photo_url text,
    signature_url text,
    signature_data jsonb,
    recipient_name character varying(255),
    recipient_phone character varying(20),
    recipient_id_number character varying(50),
    delivered_by character varying(50) DEFAULT 'driver'::character varying,
    delivery_notes text,
    gps_lat numeric(10,8),
    gps_lng numeric(11,8),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.delivery_proofs OWNER TO postgres;

--
-- Name: delivery_proofs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.delivery_proofs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.delivery_proofs_id_seq OWNER TO postgres;

--
-- Name: delivery_proofs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.delivery_proofs_id_seq OWNED BY public.delivery_proofs.id;


--
-- Name: delivery_returns; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.delivery_returns (
    id integer NOT NULL,
    delivery_id integer NOT NULL,
    return_reason character varying(100) NOT NULL,
    return_initiated_by character varying(50) NOT NULL,
    return_initiated_at timestamp without time zone DEFAULT now(),
    return_type character varying(50) DEFAULT 'permanent'::character varying,
    retry_delivery_id integer,
    return_notes text,
    return_photo_url text,
    returned_at timestamp without time zone,
    status character varying(50) DEFAULT 'pending'::character varying,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.delivery_returns OWNER TO postgres;

--
-- Name: delivery_returns_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.delivery_returns_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.delivery_returns_id_seq OWNER TO postgres;

--
-- Name: delivery_returns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.delivery_returns_id_seq OWNED BY public.delivery_returns.id;


--
-- Name: delivery_status_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.delivery_status_history (
    id integer NOT NULL,
    delivery_id integer NOT NULL,
    old_status character varying(50),
    new_status character varying(50) NOT NULL,
    changed_by integer,
    changed_by_type character varying(50),
    reason text,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.delivery_status_history OWNER TO postgres;

--
-- Name: delivery_status_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.delivery_status_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.delivery_status_history_id_seq OWNER TO postgres;

--
-- Name: delivery_status_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.delivery_status_history_id_seq OWNED BY public.delivery_status_history.id;


--
-- Name: delivery_timeouts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.delivery_timeouts (
    id integer NOT NULL,
    delivery_id integer NOT NULL,
    timeout_type character varying(50) NOT NULL,
    execute_at timestamp without time zone NOT NULL,
    processed boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.delivery_timeouts OWNER TO postgres;

--
-- Name: delivery_timeouts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.delivery_timeouts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.delivery_timeouts_id_seq OWNER TO postgres;

--
-- Name: delivery_timeouts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.delivery_timeouts_id_seq OWNED BY public.delivery_timeouts.id;


--
-- Name: delivery_tracking; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.delivery_tracking (
    id integer NOT NULL,
    delivery_id integer NOT NULL,
    lat numeric(10,8) NOT NULL,
    lng numeric(11,8) NOT NULL,
    heading numeric(5,2),
    speed numeric(5,2),
    "timestamp" timestamp without time zone DEFAULT now(),
    battery_level integer,
    network_type character varying(20),
    accuracy numeric(5,2)
);


ALTER TABLE public.delivery_tracking OWNER TO postgres;

--
-- Name: delivery_tracking_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.delivery_tracking_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.delivery_tracking_id_seq OWNER TO postgres;

--
-- Name: delivery_tracking_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.delivery_tracking_id_seq OWNED BY public.delivery_tracking.id;


--
-- Name: driver_locations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.driver_locations (
    id integer NOT NULL,
    driver_id integer NOT NULL,
    lat numeric(10,8) NOT NULL,
    lng numeric(11,8) NOT NULL,
    heading numeric(5,2),
    speed_kmh numeric(5,2),
    accuracy_m numeric(5,2),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.driver_locations OWNER TO postgres;

--
-- Name: driver_locations_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.driver_locations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.driver_locations_id_seq OWNER TO postgres;

--
-- Name: driver_locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.driver_locations_id_seq OWNED BY public.driver_locations.id;


--
-- Name: driver_profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.driver_profiles (
    id integer NOT NULL,
    user_id integer NOT NULL,
    license_number character varying(50),
    license_expiry date,
    license_photo_url text,
    vehicle_type character varying(50) DEFAULT 'motorcycle'::character varying,
    vehicle_plate character varying(20),
    vehicle_brand character varying(100),
    vehicle_model character varying(100),
    vehicle_year integer,
    vehicle_color character varying(50),
    vehicle_photo_url text,
    insurance_number character varying(100),
    insurance_expiry date,
    insurance_company character varying(100),
    insurance_photo_url text,
    identity_card_number character varying(50),
    identity_card_photo_url text,
    criminal_record_url text,
    is_online boolean DEFAULT false,
    is_available boolean DEFAULT false,
    is_verified boolean DEFAULT false,
    verification_status character varying(20) DEFAULT 'pending'::character varying,
    verification_notes text,
    average_rating numeric(3,2) DEFAULT 0.00,
    total_ratings integer DEFAULT 0,
    total_rides integer DEFAULT 0,
    total_earnings numeric(12,2) DEFAULT 0.00,
    total_distance_km numeric(10,2) DEFAULT 0.00,
    preferred_radius_km integer DEFAULT 10,
    max_distance_km integer DEFAULT 50,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    verified_at timestamp without time zone,
    last_active_at timestamp without time zone,
    delivery_capabilities jsonb DEFAULT '{}'::jsonb,
    CONSTRAINT check_average_rating CHECK (((average_rating >= 0.00) AND (average_rating <= 5.00))),
    CONSTRAINT check_verification_status CHECK (((verification_status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'suspended'::character varying])::text[])))
);


ALTER TABLE public.driver_profiles OWNER TO postgres;

--
-- Name: driver_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.driver_profiles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.driver_profiles_id_seq OWNER TO postgres;

--
-- Name: driver_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.driver_profiles_id_seq OWNED BY public.driver_profiles.id;


--
-- Name: idempotent_requests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.idempotent_requests (
    id integer NOT NULL,
    idempotency_key character varying(255) NOT NULL,
    user_id integer,
    endpoint character varying(255) NOT NULL,
    request_hash text,
    response_data jsonb,
    created_at timestamp without time zone DEFAULT now(),
    expires_at timestamp without time zone NOT NULL
);


ALTER TABLE public.idempotent_requests OWNER TO postgres;

--
-- Name: idempotent_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.idempotent_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.idempotent_requests_id_seq OWNER TO postgres;

--
-- Name: idempotent_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.idempotent_requests_id_seq OWNED BY public.idempotent_requests.id;


--
-- Name: loyalty_programs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.loyalty_programs (
    id integer NOT NULL,
    user_id integer NOT NULL,
    total_points integer DEFAULT 0,
    available_points integer DEFAULT 0,
    used_points integer DEFAULT 0,
    tier character varying(50) DEFAULT 'bronze'::character varying,
    tier_multiplier numeric(3,2) DEFAULT 1.0,
    total_deliveries integer DEFAULT 0,
    total_spent numeric(12,2) DEFAULT 0,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.loyalty_programs OWNER TO postgres;

--
-- Name: loyalty_programs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.loyalty_programs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.loyalty_programs_id_seq OWNER TO postgres;

--
-- Name: loyalty_programs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.loyalty_programs_id_seq OWNED BY public.loyalty_programs.id;


--
-- Name: loyalty_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.loyalty_transactions (
    id integer NOT NULL,
    loyalty_program_id integer NOT NULL,
    delivery_id integer,
    transaction_type character varying(50) NOT NULL,
    points integer NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.loyalty_transactions OWNER TO postgres;

--
-- Name: loyalty_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.loyalty_transactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.loyalty_transactions_id_seq OWNER TO postgres;

--
-- Name: loyalty_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.loyalty_transactions_id_seq OWNED BY public.loyalty_transactions.id;


--
-- Name: payment_intents; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payment_intents (
    id integer NOT NULL,
    ref_command character varying(100) NOT NULL,
    token character varying(255),
    reference_type character varying(50) NOT NULL,
    reference_id integer NOT NULL,
    user_id integer NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency character varying(3) DEFAULT 'XOF'::character varying,
    status character varying(50) DEFAULT 'pending'::character varying,
    provider character varying(50) DEFAULT 'paytech'::character varying,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    completed_at timestamp without time zone
);


ALTER TABLE public.payment_intents OWNER TO postgres;

--
-- Name: payment_intents_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.payment_intents_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.payment_intents_id_seq OWNER TO postgres;

--
-- Name: payment_intents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.payment_intents_id_seq OWNED BY public.payment_intents.id;


--
-- Name: pricing_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pricing_config (
    id integer NOT NULL,
    service_type character varying(50) DEFAULT 'ride'::character varying NOT NULL,
    base_fare numeric(10,2) DEFAULT 500.00 NOT NULL,
    cost_per_km numeric(10,2) DEFAULT 300.00 NOT NULL,
    cost_per_minute numeric(10,2) DEFAULT 50.00 NOT NULL,
    commission_rate numeric(5,2) DEFAULT 20.00 NOT NULL,
    max_distance_km numeric(10,2) DEFAULT 50.00,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.pricing_config OWNER TO postgres;

--
-- Name: pricing_config_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pricing_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pricing_config_id_seq OWNER TO postgres;

--
-- Name: pricing_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pricing_config_id_seq OWNED BY public.pricing_config.id;


--
-- Name: pricing_time_slots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pricing_time_slots (
    id integer NOT NULL,
    pricing_config_id integer,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    multiplier numeric(5,2) DEFAULT 1.0 NOT NULL,
    description character varying(255),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.pricing_time_slots OWNER TO postgres;

--
-- Name: pricing_time_slots_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pricing_time_slots_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pricing_time_slots_id_seq OWNER TO postgres;

--
-- Name: pricing_time_slots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pricing_time_slots_id_seq OWNED BY public.pricing_time_slots.id;


--
-- Name: ride_reviews; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ride_reviews (
    id integer NOT NULL,
    ride_id integer NOT NULL,
    reviewer_id integer NOT NULL,
    reviewed_id integer NOT NULL,
    role character varying(20) NOT NULL,
    rating integer NOT NULL,
    comment text,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT ride_reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


ALTER TABLE public.ride_reviews OWNER TO postgres;

--
-- Name: ride_reviews_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ride_reviews_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ride_reviews_id_seq OWNER TO postgres;

--
-- Name: ride_reviews_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ride_reviews_id_seq OWNED BY public.ride_reviews.id;


--
-- Name: ride_timeouts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ride_timeouts (
    id integer NOT NULL,
    ride_id integer NOT NULL,
    timeout_type character varying(50) NOT NULL,
    execute_at timestamp without time zone NOT NULL,
    processed boolean DEFAULT false,
    processed_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.ride_timeouts OWNER TO postgres;

--
-- Name: ride_timeouts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ride_timeouts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ride_timeouts_id_seq OWNER TO postgres;

--
-- Name: ride_timeouts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ride_timeouts_id_seq OWNED BY public.ride_timeouts.id;


--
-- Name: ride_tracking; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ride_tracking (
    id integer NOT NULL,
    ride_id integer NOT NULL,
    lat numeric(10,8) NOT NULL,
    lng numeric(11,8) NOT NULL,
    "timestamp" timestamp without time zone DEFAULT now()
);


ALTER TABLE public.ride_tracking OWNER TO postgres;

--
-- Name: ride_tracking_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ride_tracking_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ride_tracking_id_seq OWNER TO postgres;

--
-- Name: ride_tracking_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ride_tracking_id_seq OWNED BY public.ride_tracking.id;


--
-- Name: rides; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rides (
    id integer NOT NULL,
    ride_code character varying(20) NOT NULL,
    client_id integer NOT NULL,
    driver_id integer,
    idempotency_key character varying(255),
    pickup_lat numeric(10,8) NOT NULL,
    pickup_lng numeric(11,8) NOT NULL,
    pickup_address text,
    dropoff_lat numeric(10,8) NOT NULL,
    dropoff_lng numeric(11,8) NOT NULL,
    dropoff_address text,
    estimated_distance_km numeric(10,2),
    estimated_duration_min integer,
    estimated_fare numeric(10,2) NOT NULL,
    actual_distance_km numeric(10,2),
    actual_duration_min integer,
    fare_final numeric(10,2),
    status character varying(50) DEFAULT 'REQUESTED'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    accepted_at timestamp without time zone,
    driver_arrived_at timestamp without time zone,
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    paid_at timestamp without time zone,
    cancelled_at timestamp without time zone,
    cancellation_reason text,
    payment_method character varying(50),
    payment_status character varying(50) DEFAULT 'UNPAID'::character varying,
    transaction_id character varying(100),
    client_rating integer,
    client_review text,
    driver_rating integer,
    driver_review text,
    notes text,
    metadata jsonb,
    CONSTRAINT rides_client_rating_check CHECK (((client_rating >= 1) AND (client_rating <= 5))),
    CONSTRAINT rides_driver_rating_check CHECK (((driver_rating >= 1) AND (driver_rating <= 5)))
);


ALTER TABLE public.rides OWNER TO postgres;

--
-- Name: rides_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.rides_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rides_id_seq OWNER TO postgres;

--
-- Name: rides_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.rides_id_seq OWNED BY public.rides.id;


--
-- Name: transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transactions (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    user_id integer NOT NULL,
    type character varying(50) NOT NULL,
    amount numeric(12,2) NOT NULL,
    balance_before numeric(12,2) NOT NULL,
    balance_after numeric(12,2) NOT NULL,
    reference_type character varying(50),
    reference_id integer,
    description text,
    metadata jsonb,
    status character varying(50) DEFAULT 'completed'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    processed_at timestamp without time zone,
    CONSTRAINT check_amount_positive CHECK ((amount > 0.00)),
    CONSTRAINT check_transaction_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT check_transaction_type CHECK (((type)::text = ANY ((ARRAY['credit'::character varying, 'debit'::character varying, 'refund'::character varying, 'commission'::character varying, 'withdrawal'::character varying, 'deposit'::character varying])::text[])))
);


ALTER TABLE public.transactions OWNER TO postgres;

--
-- Name: transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.transactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.transactions_id_seq OWNER TO postgres;

--
-- Name: transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.transactions_id_seq OWNED BY public.transactions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    phone character varying(20),
    password_hash character varying(255) NOT NULL,
    first_name character varying(100),
    last_name character varying(100),
    role character varying(20) DEFAULT 'client'::character varying NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying,
    avatar_url text,
    date_of_birth date,
    gender character varying(10),
    language character varying(10) DEFAULT 'fr'::character varying,
    timezone character varying(50) DEFAULT 'Africa/Dakar'::character varying,
    address text,
    city character varying(100),
    country character varying(100) DEFAULT 'Senegal'::character varying,
    email_verified boolean DEFAULT false,
    phone_verified boolean DEFAULT false,
    verification_token character varying(255),
    verification_token_expires_at timestamp without time zone,
    last_login_at timestamp without time zone,
    failed_login_attempts integer DEFAULT 0,
    locked_until timestamp without time zone,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    deleted_at timestamp without time zone,
    CONSTRAINT check_email_format CHECK (((email)::text ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'::text)),
    CONSTRAINT check_role CHECK (((role)::text = ANY ((ARRAY['client'::character varying, 'driver'::character varying, 'admin'::character varying])::text[]))),
    CONSTRAINT check_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying, 'suspended'::character varying, 'pending_verification'::character varying])::text[])))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: wallets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wallets (
    id integer NOT NULL,
    user_id integer NOT NULL,
    balance numeric(12,2) DEFAULT 0.00 NOT NULL,
    currency character varying(3) DEFAULT 'XOF'::character varying,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    last_transaction_at timestamp without time zone,
    CONSTRAINT check_balance_non_negative CHECK ((balance >= 0.00))
);


ALTER TABLE public.wallets OWNER TO postgres;

--
-- Name: wallets_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wallets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallets_id_seq OWNER TO postgres;

--
-- Name: wallets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wallets_id_seq OWNED BY public.wallets.id;


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: corporate_accounts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.corporate_accounts ALTER COLUMN id SET DEFAULT nextval('public.corporate_accounts_id_seq'::regclass);


--
-- Name: deliveries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deliveries ALTER COLUMN id SET DEFAULT nextval('public.deliveries_id_seq'::regclass);


--
-- Name: delivery_fees_breakdown id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_fees_breakdown ALTER COLUMN id SET DEFAULT nextval('public.delivery_fees_breakdown_id_seq'::regclass);


--
-- Name: delivery_notifications id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_notifications ALTER COLUMN id SET DEFAULT nextval('public.delivery_notifications_id_seq'::regclass);


--
-- Name: delivery_proofs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_proofs ALTER COLUMN id SET DEFAULT nextval('public.delivery_proofs_id_seq'::regclass);


--
-- Name: delivery_returns id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_returns ALTER COLUMN id SET DEFAULT nextval('public.delivery_returns_id_seq'::regclass);


--
-- Name: delivery_status_history id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_status_history ALTER COLUMN id SET DEFAULT nextval('public.delivery_status_history_id_seq'::regclass);


--
-- Name: delivery_timeouts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_timeouts ALTER COLUMN id SET DEFAULT nextval('public.delivery_timeouts_id_seq'::regclass);


--
-- Name: delivery_tracking id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_tracking ALTER COLUMN id SET DEFAULT nextval('public.delivery_tracking_id_seq'::regclass);


--
-- Name: driver_locations id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.driver_locations ALTER COLUMN id SET DEFAULT nextval('public.driver_locations_id_seq'::regclass);


--
-- Name: driver_profiles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.driver_profiles ALTER COLUMN id SET DEFAULT nextval('public.driver_profiles_id_seq'::regclass);


--
-- Name: idempotent_requests id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.idempotent_requests ALTER COLUMN id SET DEFAULT nextval('public.idempotent_requests_id_seq'::regclass);


--
-- Name: loyalty_programs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loyalty_programs ALTER COLUMN id SET DEFAULT nextval('public.loyalty_programs_id_seq'::regclass);


--
-- Name: loyalty_transactions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loyalty_transactions ALTER COLUMN id SET DEFAULT nextval('public.loyalty_transactions_id_seq'::regclass);


--
-- Name: payment_intents id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_intents ALTER COLUMN id SET DEFAULT nextval('public.payment_intents_id_seq'::regclass);


--
-- Name: pricing_config id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pricing_config ALTER COLUMN id SET DEFAULT nextval('public.pricing_config_id_seq'::regclass);


--
-- Name: pricing_time_slots id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pricing_time_slots ALTER COLUMN id SET DEFAULT nextval('public.pricing_time_slots_id_seq'::regclass);


--
-- Name: ride_reviews id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_reviews ALTER COLUMN id SET DEFAULT nextval('public.ride_reviews_id_seq'::regclass);


--
-- Name: ride_timeouts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_timeouts ALTER COLUMN id SET DEFAULT nextval('public.ride_timeouts_id_seq'::regclass);


--
-- Name: ride_tracking id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_tracking ALTER COLUMN id SET DEFAULT nextval('public.ride_tracking_id_seq'::regclass);


--
-- Name: rides id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rides ALTER COLUMN id SET DEFAULT nextval('public.rides_id_seq'::regclass);


--
-- Name: transactions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions ALTER COLUMN id SET DEFAULT nextval('public.transactions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: wallets id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallets ALTER COLUMN id SET DEFAULT nextval('public.wallets_id_seq'::regclass);


--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_logs (id, user_id, action, entity_type, entity_id, details, created_at) FROM stdin;
1	22	ride_created	ride	21	{"estimated_fare": 1844}	2026-02-11 00:23:02.854466
2	23	ride_accepted	ride	21	{}	2026-02-11 00:23:02.965616
3	23	ride_started	ride	21	{}	2026-02-11 00:23:03.109779
4	23	ride_completed	ride	21	{"fare_final": 2028}	2026-02-11 00:23:03.242874
5	22	delivery_created	delivery	2	{"estimated_fare": 1801}	2026-02-11 00:23:03.385983
6	23	delivery_accepted	delivery	2	{}	2026-02-11 00:23:03.588906
7	23	delivery_in_transit	delivery	2	{}	2026-02-11 00:23:03.736123
8	23	delivery_completed	delivery	2	{"fare_final": 1981}	2026-02-11 00:23:03.901327
9	25	ride_created	ride	23	{"estimated_fare": 1844}	2026-02-12 05:04:48.609753
10	\N	ride_cancelled	ride	23	{"reason": "Aucun driver disponible dans les délais", "cancelled_by": "system"}	2026-02-12 05:06:48.736887
11	25	ride_created	ride	25	{"estimated_fare": 1722}	2026-02-12 05:28:06.803
12	\N	ride_cancelled	ride	25	{"reason": "Aucun driver disponible dans les délais", "cancelled_by": "system"}	2026-02-12 05:30:06.843235
13	25	ride_created	ride	27	{"estimated_fare": 995}	2026-02-12 05:47:16.708081
14	25	ride_created	ride	29	{"estimated_fare": 646}	2026-02-12 05:48:50.804956
15	\N	ride_cancelled	ride	27	{"reason": "Aucun driver disponible dans les délais", "cancelled_by": "system"}	2026-02-12 05:49:16.783661
16	\N	ride_cancelled	ride	29	{"reason": "Aucun driver disponible dans les délais", "cancelled_by": "system"}	2026-02-12 05:50:50.841257
17	25	ride_created	ride	31	{"estimated_fare": 3015}	2026-02-12 16:37:53.598861
18	25	delivery_created	delivery	3	{"estimated_fare": 895}	2026-02-12 16:38:44.852711
19	\N	ride_cancelled	ride	31	{"reason": "Aucun driver disponible dans les délais", "cancelled_by": "system"}	2026-02-12 16:39:53.691059
20	25	ride_created	ride	33	{"estimated_fare": 688}	2026-02-12 18:38:54.217173
21	\N	ride_cancelled	ride	33	{"reason": "Aucun driver disponible dans les délais", "cancelled_by": "system"}	2026-02-12 18:40:54.277507
22	25	delivery_created	delivery	4	{"estimated_fare": 730}	2026-02-12 20:19:02.092871
23	25	ride_created	ride	35	{"estimated_fare": 825}	2026-02-12 20:19:30.096881
24	\N	ride_cancelled	ride	35	{"reason": "Aucun driver disponible dans les délais", "cancelled_by": "system"}	2026-02-12 20:21:30.147819
25	25	ride_created	ride	37	{"estimated_fare": 628}	2026-02-12 22:06:23.481511
26	58	ride_accepted	ride	37	{}	2026-02-12 22:06:40.556793
27	58	ride_started	ride	37	{}	2026-02-12 22:06:59.800191
28	58	ride_completed	ride	37	{"fare_final": 550}	2026-02-12 22:07:16.406224
29	25	ride_created	ride	39	{"estimated_fare": 759}	2026-02-13 01:26:36.531064
30	58	ride_accepted	ride	39	{}	2026-02-13 01:27:02.604909
31	58	ride_started	ride	39	{}	2026-02-13 01:27:06.168615
32	58	ride_completed	ride	39	{"fare_final": 835}	2026-02-13 01:27:07.321788
33	25	ride_created	ride	41	{"estimated_fare": 831}	2026-02-13 01:27:31.427895
34	\N	ride_cancelled	ride	41	{"reason": "Aucun driver disponible dans les délais", "cancelled_by": "system"}	2026-02-13 01:29:31.458098
35	25	ride_created	ride	43	{"estimated_fare": 1054}	2026-02-13 01:59:30.604339
36	25	ride_cancelled	ride	43	{"reason": "Annulé par le client", "cancelled_by": "client"}	2026-02-13 01:59:50.145601
37	25	delivery_created	delivery	5	{"estimated_fare": 776}	2026-02-13 02:00:07.939061
38	25	ride_created	ride	45	{"estimated_fare": 1063}	2026-02-13 02:19:37.023958
39	58	ride_accepted	ride	45	{}	2026-02-13 02:19:49.420775
40	58	ride_started	ride	45	{}	2026-02-13 02:20:10.957359
41	58	ride_completed	ride	45	{"fare_final": 1000}	2026-02-13 02:20:16.074302
42	25	ride_created	ride	47	{"estimated_fare": 655}	2026-02-13 02:20:40.863453
43	58	ride_accepted	ride	47	{}	2026-02-13 02:20:52.310909
44	58	ride_started	ride	47	{}	2026-02-13 02:21:24.659892
45	58	ride_completed	ride	47	{"fare_final": 721}	2026-02-13 02:21:38.535784
46	25	delivery_created	delivery	6	{"estimated_fare": 1306}	2026-02-13 02:22:07.780821
47	58	delivery_accepted	delivery	6	{}	2026-02-13 02:22:18.885699
48	58	delivery_in_transit	delivery	6	{}	2026-02-13 02:22:43.251371
49	25	ride_created	ride	49	{"estimated_fare": 613}	2026-02-13 15:22:00.07671
50	58	ride_accepted	ride	49	{}	2026-02-13 15:22:21.227988
51	58	ride_started	ride	49	{}	2026-02-13 15:22:34.857095
52	58	ride_completed	ride	49	{"fare_final": 674}	2026-02-13 15:22:35.980689
53	25	ride_created	ride	51	{"estimated_fare": 968}	2026-02-13 15:23:52.589926
54	58	ride_accepted	ride	51	{}	2026-02-13 15:24:05.912489
55	58	ride_started	ride	51	{}	2026-02-13 15:26:24.524399
56	58	ride_completed	ride	51	{"fare_final": 950}	2026-02-13 15:26:25.529982
57	25	ride_created	ride	53	{"estimated_fare": 965}	2026-02-13 15:27:36.325779
58	58	ride_accepted	ride	53	{}	2026-02-13 15:27:55.135756
59	58	ride_started	ride	53	{}	2026-02-13 15:27:57.589226
60	58	ride_completed	ride	53	{"fare_final": 950}	2026-02-13 15:27:58.566369
61	25	ride_created	ride	55	{"estimated_fare": 1284}	2026-02-13 15:28:32.85579
62	\N	ride_cancelled	ride	55	{"reason": "Aucun driver disponible dans les délais", "cancelled_by": "system"}	2026-02-13 15:30:32.892022
63	25	ride_created	ride	57	{"estimated_fare": 1272}	2026-02-13 15:41:24.695661
64	58	ride_accepted	ride	57	{}	2026-02-13 15:41:33.687037
65	58	ride_started	ride	57	{}	2026-02-13 15:46:25.770087
66	25	ride_created	ride	59	{"estimated_fare": 941}	2026-02-13 16:10:43.962069
67	58	ride_accepted	ride	59	{}	2026-02-13 16:10:57.085068
68	58	ride_started	ride	59	{}	2026-02-13 16:11:47.032668
69	58	ride_completed	ride	59	{"fare_final": 950}	2026-02-13 16:11:47.971029
70	25	ride_created	ride	61	{"estimated_fare": 1087}	2026-02-13 16:12:10.983075
71	25	ride_cancelled	ride	61	{"reason": "Annulé par le client", "cancelled_by": "client"}	2026-02-13 16:12:42.899347
72	25	ride_created	ride	63	{"estimated_fare": 1096}	2026-02-13 16:31:59.081919
73	58	ride_accepted	ride	63	{}	2026-02-13 16:32:09.842201
74	58	ride_cancelled	ride	63	{"reason": "Client ne s'est pas présenté dans les délais", "cancelled_by": "driver"}	2026-02-13 16:40:30.545182
75	25	ride_created	ride	65	{"estimated_fare": 923}	2026-02-13 18:29:20.157581
76	58	ride_accepted	ride	65	{}	2026-02-13 18:29:31.795086
77	58	ride_started	ride	65	{}	2026-02-13 18:30:00.112397
78	58	ride_completed	ride	65	{"fare_final": 950}	2026-02-13 18:30:01.143204
79	25	ride_created	ride	67	{"estimated_fare": 1114}	2026-02-13 18:30:47.402897
80	58	ride_accepted	ride	67	{}	2026-02-13 18:31:08.045623
81	58	ride_started	ride	67	{}	2026-02-13 18:31:16.487758
82	58	ride_completed	ride	67	{"fare_final": 1000}	2026-02-13 18:32:03.869233
83	25	ride_created	ride	69	{"estimated_fare": 1105}	2026-02-13 18:32:28.960494
84	25	ride_cancelled	ride	69	{"reason": "Annulé par le client", "cancelled_by": "client"}	2026-02-13 18:32:46.04293
85	25	ride_created	ride	71	{"estimated_fare": 965}	2026-02-13 18:41:26.715028
86	58	ride_accepted	ride	71	{}	2026-02-13 18:41:36.940594
87	58	ride_started	ride	71	{}	2026-02-13 18:41:53.543909
88	58	ride_completed	ride	71	{"fare_final": 950}	2026-02-13 18:42:01.387548
89	25	ride_created	ride	73	{"estimated_fare": 980}	2026-02-13 18:42:48.237599
90	58	ride_accepted	ride	73	{}	2026-02-13 18:42:59.974972
91	58	ride_cancelled	ride	73	{"reason": "Annulé par le chauffeur", "cancelled_by": "driver"}	2026-02-13 18:43:30.723344
92	25	ride_created	ride	75	{"estimated_fare": 947}	2026-02-13 19:03:17.538502
93	25	ride_cancelled	ride	75	{"reason": "Annulé par le client", "cancelled_by": "client"}	2026-02-13 19:03:21.516491
94	25	ride_created	ride	77	{"estimated_fare": 1060}	2026-02-13 19:38:15.178604
95	25	ride_cancelled	ride	77	{"reason": "Annulé par le client", "cancelled_by": "client"}	2026-02-13 19:38:18.445855
\.


--
-- Data for Name: corporate_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.corporate_accounts (id, company_name, company_email, company_phone, contact_person_name, contact_person_email, contact_person_phone, billing_address, tax_id, payment_terms, credit_limit, current_balance, status, is_active, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: deliveries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.deliveries (id, delivery_code, client_id, driver_id, sender_id, recipient_id, idempotency_key, pickup_lat, pickup_lng, pickup_address, dropoff_lat, dropoff_lng, dropoff_address, package_type, package_weight_kg, package_dimensions, package_value, package_description, requires_signature, insurance_required, recipient_name, recipient_phone, recipient_email, delivery_instructions, estimated_distance_km, estimated_duration_min, estimated_fare, actual_distance_km, actual_duration_min, fare_final, status, created_at, assigned_at, picked_up_at, in_transit_at, delivered_at, cancelled_at, cancellation_reason, payment_method, payment_status, transaction_id, payment_collected_at, client_rating, client_review, driver_rating, driver_review, recipient_rating, recipient_review, delivery_proof, notes, metadata, frozen_fare, fare_frozen_at, payment_frozen_at, cancellation_fee, refund_amount, refund_reason, loyalty_points_earned, insurance_fee, corporate_account_id, discount_amount, discount_code) FROM stdin;
1	DELIV-2026-0999	20	21	\N	\N	\N	14.71000000	-17.46800000	Point E, Dakar	14.72000000	-17.45000000	Almadies, Dakar	standard	2.00	\N	\N	Colis simulation	f	f	\N	\N	\N	\N	2.23	7	1801.00	\N	\N	\N	IN_TRANSIT	2026-02-11 00:08:49.925116	2026-02-11 00:08:50.059359	2026-02-11 00:08:50.215948	2026-02-11 00:08:50.252302	\N	\N	\N	wallet	UNPAID	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0.00	0.00	\N	0	0.00	\N	0.00	\N
2	DELIV-2026-6892	22	23	\N	\N	\N	14.71000000	-17.46800000	Point b, Dakar	14.72000000	-17.45000000	Almadies, Dakar	standard	2.00	\N	\N	Colis simulation	f	f	\N	\N	\N	\N	2.23	7	1801.00	4.50	15	1981.00	DELIVERED	2026-02-11 00:23:03.368659	2026-02-11 00:23:03.47762	2026-02-11 00:23:03.641492	2026-02-11 00:23:03.683943	2026-02-11 00:23:03.81027	\N	\N	wallet	UNPAID	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0.00	0.00	\N	0	0.00	\N	0.00	\N
3	DELIV-2026-8647	25	\N	\N	\N	\N	14.42690740	-16.97652490	Position actuelle	14.42901498	-16.97246809	Point sur la carte	standard	2.00	\N	\N	\N	f	f	\N	\N	\N	\N	0.50	2	895.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-12 16:38:44.846759	\N	\N	\N	\N	2026-02-12 16:40:44.885735	Aucun driver disponible dans les délais	wallet	UNPAID	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0.00	895.00	\N	0	0.00	\N	0.00	\N
4	DELIV-2026-2191	25	\N	\N	\N	\N	14.41679540	-16.97129060	Position actuelle	14.41531704	-16.97020099	Point sur la carte	standard	2.00	\N	\N	\N	f	f	\N	\N	\N	\N	0.20	1	730.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-12 20:19:02.081277	\N	\N	\N	\N	2026-02-12 20:21:02.13851	Aucun driver disponible dans les délais	wallet	UNPAID	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0.00	730.00	\N	0	0.00	\N	0.00	\N
5	DELIV-2026-9348	25	\N	\N	\N	\N	14.43430400	-16.96727040	Position actuelle	14.43147111	-16.96630282	Point sur la carte	standard	2.00	\N	\N	\N	f	f	\N	\N	\N	\N	0.33	1	776.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-13 02:00:07.924182	\N	\N	\N	\N	2026-02-13 02:02:07.999872	Aucun driver disponible dans les délais	wallet	UNPAID	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0.00	776.00	\N	0	0.00	\N	0.00	\N
6	DELIV-2026-5291	25	58	\N	\N	\N	14.43430400	-16.96727040	Position actuelle	14.42424055	-16.96056383	Point sur la carte	standard	2.00	\N	\N	\N	f	f	\N	\N	\N	\N	1.33	4	1306.00	\N	\N	\N	IN_TRANSIT	2026-02-13 02:22:07.773356	2026-02-13 02:22:18.712607	2026-02-13 02:22:31.330177	2026-02-13 02:22:43.180398	\N	\N	\N	wallet	UNPAID	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	0.00	0.00	\N	0	0.00	\N	0.00	\N
\.


--
-- Data for Name: delivery_fees_breakdown; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.delivery_fees_breakdown (id, delivery_id, base_fare, distance_cost, time_cost, weight_multiplier, type_multiplier, time_multiplier, subtotal, total_fare, pricing_config_id, frozen_at) FROM stdin;
\.


--
-- Data for Name: delivery_notifications; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.delivery_notifications (id, delivery_id, user_id, notification_type, title, message, sent_at, read_at, clicked_at, metadata) FROM stdin;
1	1	20	delivery_assigned	Livraison acceptée	Un driver a accepté votre livraison	2026-02-11 00:08:50.153421	\N	\N	{"delivery_id": "1"}
2	1	20	package_picked	Colis récupéré	Le driver a récupéré votre colis	2026-02-11 00:08:50.231619	\N	\N	{"delivery_id": "1"}
3	1	20	in_transit	Colis en route	Votre colis est en route vers vous	2026-02-11 00:08:50.289874	\N	\N	{"delivery_id": "1", "estimated_arrival_minutes": 7}
4	2	22	delivery_assigned	Livraison acceptée	Un driver a accepté votre livraison	2026-02-11 00:23:03.578569	\N	\N	{"delivery_id": "2"}
5	2	22	package_picked	Colis récupéré	Le driver a récupéré votre colis	2026-02-11 00:23:03.663604	\N	\N	{"delivery_id": "2"}
6	2	22	in_transit	Colis en route	Votre colis est en route vers vous	2026-02-11 00:23:03.725936	\N	\N	{"delivery_id": "2", "estimated_arrival_minutes": 7}
7	2	22	delivered	Livraison terminée	Votre colis a été livré. Montant: 1981 FCFA	2026-02-11 00:23:03.88791	\N	\N	{"fare": 1981, "delivery_id": "2"}
8	6	25	delivery_assigned	Livraison acceptée	Un driver a accepté votre livraison	2026-02-13 02:22:18.867363	\N	\N	{"delivery_id": "6"}
9	6	25	package_picked	Colis récupéré	Le driver a récupéré votre colis	2026-02-13 02:22:31.369451	\N	\N	{"delivery_id": "6"}
10	6	25	in_transit	Colis en route	Votre colis est en route vers vous	2026-02-13 02:22:43.238259	\N	\N	{"delivery_id": "6", "estimated_arrival_minutes": 4}
\.


--
-- Data for Name: delivery_proofs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.delivery_proofs (id, delivery_id, package_photo_url, delivery_photo_url, location_photo_url, signature_url, signature_data, recipient_name, recipient_phone, recipient_id_number, delivered_by, delivery_notes, gps_lat, gps_lng, created_at) FROM stdin;
\.


--
-- Data for Name: delivery_returns; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.delivery_returns (id, delivery_id, return_reason, return_initiated_by, return_initiated_at, return_type, retry_delivery_id, return_notes, return_photo_url, returned_at, status, created_at) FROM stdin;
\.


--
-- Data for Name: delivery_status_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.delivery_status_history (id, delivery_id, old_status, new_status, changed_by, changed_by_type, reason, metadata, created_at) FROM stdin;
1	1	\N	REQUESTED	20	client	Delivery created	\N	2026-02-11 00:08:49.980651
2	1	REQUESTED	ASSIGNED	21	driver	Driver accepted delivery	\N	2026-02-11 00:08:50.114886
3	1	ASSIGNED	PICKED_UP	21	driver	Package picked up	\N	2026-02-11 00:08:50.224406
4	1	PICKED_UP	IN_TRANSIT	21	driver	Started transit to recipient	\N	2026-02-11 00:08:50.258533
5	2	\N	REQUESTED	22	client	Delivery created	\N	2026-02-11 00:23:03.39852
6	2	REQUESTED	ASSIGNED	23	driver	Driver accepted delivery	\N	2026-02-11 00:23:03.534636
7	2	ASSIGNED	PICKED_UP	23	driver	Package picked up	\N	2026-02-11 00:23:03.646565
8	2	PICKED_UP	IN_TRANSIT	23	driver	Started transit to recipient	\N	2026-02-11 00:23:03.691562
9	2	IN_TRANSIT	DELIVERED	23	driver	Delivery completed	\N	2026-02-11 00:23:03.82398
10	3	\N	REQUESTED	25	client	Delivery created	\N	2026-02-12 16:38:44.856442
11	3	REQUESTED	CANCELLED_BY_SYSTEM	\N	system	Aucun driver disponible dans les délais	{"refund_amount": null, "cancellation_fee": 0}	2026-02-12 16:40:44.89896
12	4	\N	REQUESTED	25	client	Delivery created	\N	2026-02-12 20:19:02.095833
13	4	REQUESTED	CANCELLED_BY_SYSTEM	\N	system	Aucun driver disponible dans les délais	{"refund_amount": null, "cancellation_fee": 0}	2026-02-12 20:21:02.143445
14	5	\N	REQUESTED	25	client	Delivery created	\N	2026-02-13 02:00:07.943151
15	5	REQUESTED	CANCELLED_BY_SYSTEM	\N	system	Aucun driver disponible dans les délais	{"refund_amount": null, "cancellation_fee": 0}	2026-02-13 02:02:08.00289
16	6	\N	REQUESTED	25	client	Delivery created	\N	2026-02-13 02:22:07.785332
17	6	REQUESTED	ASSIGNED	58	driver	Driver accepted delivery	\N	2026-02-13 02:22:18.810986
18	6	ASSIGNED	PICKED_UP	58	driver	Package picked up	\N	2026-02-13 02:22:31.334793
19	6	PICKED_UP	IN_TRANSIT	58	driver	Started transit to recipient	\N	2026-02-13 02:22:43.193207
\.


--
-- Data for Name: delivery_timeouts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.delivery_timeouts (id, delivery_id, timeout_type, execute_at, processed, created_at) FROM stdin;
\.


--
-- Data for Name: delivery_tracking; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.delivery_tracking (id, delivery_id, lat, lng, heading, speed, "timestamp", battery_level, network_type, accuracy) FROM stdin;
1	6	14.43430400	-16.96727040	\N	\N	2026-02-13 02:22:19.364964	\N	\N	\N
2	6	14.43430400	-16.96727040	\N	\N	2026-02-13 02:22:28.970798	\N	\N	\N
3	6	14.43430400	-16.96727040	\N	\N	2026-02-13 02:22:38.971576	\N	\N	\N
4	6	14.43430400	-16.96727040	\N	\N	2026-02-13 02:22:48.974877	\N	\N	\N
\.


--
-- Data for Name: driver_locations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.driver_locations (id, driver_id, lat, lng, heading, speed_kmh, accuracy_m, updated_at) FROM stdin;
1	18	14.70000000	-17.45500000	90.00	30.00	\N	2026-02-05 18:46:26.789846
2	58	14.42690200	-16.97652090	\N	\N	\N	2026-02-13 18:43:30.039246
\.


--
-- Data for Name: driver_profiles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.driver_profiles (id, user_id, license_number, license_expiry, license_photo_url, vehicle_type, vehicle_plate, vehicle_brand, vehicle_model, vehicle_year, vehicle_color, vehicle_photo_url, insurance_number, insurance_expiry, insurance_company, insurance_photo_url, identity_card_number, identity_card_photo_url, criminal_record_url, is_online, is_available, is_verified, verification_status, verification_notes, average_rating, total_ratings, total_rides, total_earnings, total_distance_km, preferred_radius_km, max_distance_km, created_at, updated_at, verified_at, last_active_at, delivery_capabilities) FROM stdin;
1	3	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	f	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-05 18:20:07.953435	2026-02-05 18:20:07.953435	\N	\N	{}
2	5	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	f	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-05 18:27:54.98719	2026-02-05 18:27:54.98719	\N	\N	{}
3	7	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	f	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-05 18:29:03.598626	2026-02-05 18:29:03.598626	\N	\N	{}
4	9	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	f	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-05 18:29:13.604269	2026-02-05 18:29:13.604269	\N	\N	{}
7	12	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	f	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-05 18:34:02.575212	2026-02-05 18:34:02.575212	\N	\N	{}
8	13	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	f	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-05 18:34:13.866881	2026-02-05 18:34:13.866881	\N	\N	{}
9	15	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t	t	f	pending	\N	5.00	1	0	0.00	0.00	10	50	2026-02-05 18:35:00.26364	2026-02-05 18:35:00.737521	\N	2026-02-05 18:35:00.283263	{}
10	16	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t	t	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-05 18:35:24.559493	2026-02-05 18:35:24.593819	\N	2026-02-05 18:35:24.593819	{}
11	18	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t	t	f	pending	\N	5.00	1	0	0.00	0.00	10	50	2026-02-05 18:46:26.450803	2026-02-05 18:46:27.080198	\N	2026-02-05 18:46:26.484745	{}
6	11	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	f	t	approved	\N	0.00	0	0	0.00	0.00	10	50	2026-02-05 18:32:36.255127	2026-02-10 02:53:28.301891	2026-02-10 02:53:28.301891	\N	{}
5	10	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	f	t	approved	\N	0.00	0	0	0.00	0.00	10	50	2026-02-05 18:31:28.454638	2026-02-10 02:53:29.28321	2026-02-10 02:53:29.28321	\N	{}
12	21	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t	f	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-11 00:08:49.363846	2026-02-11 00:08:50.059359	\N	2026-02-11 00:08:49.400417	{}
13	23	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t	t	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-11 00:23:02.734619	2026-02-11 00:23:03.81718	\N	2026-02-11 00:23:02.772554	{}
14	58	\N	\N	\N	motorcycle	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t	t	f	pending	\N	0.00	0	0	0.00	0.00	10	50	2026-02-12 21:33:31.877972	2026-02-13 18:43:30.705174	\N	2026-02-13 18:41:32.714565	{}
\.


--
-- Data for Name: idempotent_requests; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.idempotent_requests (id, idempotency_key, user_id, endpoint, request_hash, response_data, created_at, expires_at) FROM stdin;
1	test-accept-1770316499790	15	/rides/1/accept	\N	{"data": {"id": 1, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 14, "driver_id": 15, "ride_code": "RIDE-2026-000002", "created_at": "2026-02-05T18:35:00.317Z", "fare_final": null, "pickup_lat": "14.69280000", "pickup_lng": "-17.44670000", "started_at": null, "accepted_at": "2026-02-05T18:35:00.390Z", "dropoff_lat": "14.71000000", "dropoff_lng": "-17.46800000", "cancelled_at": null, "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1844.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Plateau, Dakar", "transaction_id": null, "dropoff_address": "Point E, Dakar", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "estimated_distance_km": "2.98", "estimated_duration_min": 9}, "success": true}	2026-02-05 18:35:00.434267	2026-02-06 18:35:00.434267
2	ride-accept-curl-1770317186	18	/rides/3/accept	\N	{"data": {"id": 3, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 17, "driver_id": 18, "ride_code": "RIDE-2026-000004", "created_at": "2026-02-05T18:46:26.542Z", "fare_final": null, "pickup_lat": "14.69280000", "pickup_lng": "-17.44670000", "started_at": null, "accepted_at": "2026-02-05T18:46:26.631Z", "dropoff_lat": "14.71000000", "dropoff_lng": "-17.46800000", "cancelled_at": null, "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1844.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Plateau, Dakar", "transaction_id": null, "dropoff_address": "Point E, Dakar", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "estimated_distance_km": "2.98", "estimated_duration_min": 9}, "success": true}	2026-02-05 18:46:26.667701	2026-02-06 18:46:26.667701
3	sim-accept-ride-1770768528912	21	/rides/19/accept	\N	{"data": {"id": 19, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 20, "driver_id": 21, "ride_code": "RIDE-2026-000020", "created_at": "2026-02-11T00:08:49.440Z", "fare_final": null, "pickup_lat": "14.69280000", "pickup_lng": "-17.44670000", "started_at": null, "accepted_at": "2026-02-11T00:08:49.564Z", "dropoff_lat": "14.71000000", "dropoff_lng": "-17.46800000", "cancelled_at": null, "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1844.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Plateau, Dakar", "transaction_id": null, "dropoff_address": "Point E, Dakar", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "estimated_distance_km": "2.98", "estimated_duration_min": 9}, "success": true}	2026-02-11 00:08:49.621111	2026-02-12 00:08:49.621111
4	sim-accept-del-1770768528912	21	/deliveries/1/accept	\N	{"data": {"id": 1, "notes": null, "status": "ASSIGNED", "metadata": null, "client_id": 20, "driver_id": 21, "sender_id": null, "created_at": "2026-02-11T00:08:49.925Z", "fare_final": null, "pickup_lat": "14.71000000", "pickup_lng": "-17.46800000", "assigned_at": "2026-02-11T00:08:50.059Z", "dropoff_lat": "14.72000000", "dropoff_lng": "-17.45000000", "frozen_fare": null, "cancelled_at": null, "delivered_at": null, "package_type": "standard", "picked_up_at": null, "recipient_id": null, "client_rating": null, "client_review": null, "delivery_code": "DELIV-2026-0999", "discount_code": null, "driver_rating": null, "driver_review": null, "in_transit_at": null, "insurance_fee": "0.00", "package_value": null, "refund_amount": "0.00", "refund_reason": null, "delivery_proof": null, "estimated_fare": "1801.00", "fare_frozen_at": null, "payment_method": "wallet", "payment_status": "UNPAID", "pickup_address": "Point E, Dakar", "recipient_name": null, "transaction_id": null, "discount_amount": "0.00", "dropoff_address": "Almadies, Dakar", "idempotency_key": null, "recipient_email": null, "recipient_phone": null, "cancellation_fee": "0.00", "recipient_rating": null, "recipient_review": null, "package_weight_kg": "2.00", "payment_frozen_at": null, "actual_distance_km": null, "insurance_required": false, "package_dimensions": null, "requires_signature": false, "actual_duration_min": null, "cancellation_reason": null, "package_description": "Colis simulation", "corporate_account_id": null, "payment_collected_at": null, "delivery_instructions": null, "estimated_distance_km": "2.23", "loyalty_points_earned": 0, "estimated_duration_min": 7}, "success": true}	2026-02-11 00:08:50.200126	2026-02-12 00:08:50.200126
5	sim-accept-ride-1770769382210	23	/rides/21/accept	\N	{"data": {"id": 21, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 22, "driver_id": 23, "ride_code": "RIDE-2026-000022", "created_at": "2026-02-11T00:23:02.840Z", "fare_final": null, "pickup_lat": "14.69280000", "pickup_lng": "-17.44670000", "started_at": null, "accepted_at": "2026-02-11T00:23:02.937Z", "dropoff_lat": "14.71000000", "dropoff_lng": "-17.46800000", "cancelled_at": null, "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1844.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Plateau, Dakar", "transaction_id": null, "dropoff_address": "Point b, Dakar", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "estimated_distance_km": "2.98", "estimated_duration_min": 9}, "success": true}	2026-02-11 00:23:02.974431	2026-02-12 00:23:02.974431
6	sim-accept-del-1770769382210	23	/deliveries/2/accept	\N	{"data": {"id": 2, "notes": null, "status": "ASSIGNED", "metadata": null, "client_id": 22, "driver_id": 23, "sender_id": null, "created_at": "2026-02-11T00:23:03.368Z", "fare_final": null, "pickup_lat": "14.71000000", "pickup_lng": "-17.46800000", "assigned_at": "2026-02-11T00:23:03.477Z", "dropoff_lat": "14.72000000", "dropoff_lng": "-17.45000000", "frozen_fare": null, "cancelled_at": null, "delivered_at": null, "package_type": "standard", "picked_up_at": null, "recipient_id": null, "client_rating": null, "client_review": null, "delivery_code": "DELIV-2026-6892", "discount_code": null, "driver_rating": null, "driver_review": null, "in_transit_at": null, "insurance_fee": "0.00", "package_value": null, "refund_amount": "0.00", "refund_reason": null, "delivery_proof": null, "estimated_fare": "1801.00", "fare_frozen_at": null, "payment_method": "wallet", "payment_status": "UNPAID", "pickup_address": "Point b, Dakar", "recipient_name": null, "transaction_id": null, "discount_amount": "0.00", "dropoff_address": "Almadies, Dakar", "idempotency_key": null, "recipient_email": null, "recipient_phone": null, "cancellation_fee": "0.00", "recipient_rating": null, "recipient_review": null, "package_weight_kg": "2.00", "payment_frozen_at": null, "actual_distance_km": null, "insurance_required": false, "package_dimensions": null, "requires_signature": false, "actual_duration_min": null, "cancellation_reason": null, "package_description": "Colis simulation", "corporate_account_id": null, "payment_collected_at": null, "delivery_instructions": null, "estimated_distance_km": "2.23", "loyalty_points_earned": 0, "estimated_duration_min": 7}, "success": true}	2026-02-11 00:23:03.594408	2026-02-12 00:23:03.594408
7	ride_37_1770934000269	58	/rides/37/accept	\N	{"data": {"id": 37, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000038", "created_at": "2026-02-12T22:06:23.459Z", "fare_final": null, "pickup_lat": "14.42694680", "pickup_lng": "-16.97654640", "started_at": null, "accepted_at": "2026-02-12T22:06:40.539Z", "dropoff_lat": "14.42498197", "dropoff_lng": "-16.97521849", "cancelled_at": null, "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "628.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Position actuelle", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "estimated_distance_km": "0.26", "estimated_duration_min": 1}, "success": true}	2026-02-12 22:06:40.574675	2026-02-13 22:06:40.574675
8	ride_39_1770946022424	58	/rides/39/accept	\N	{"data": {"id": 39, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000040", "created_at": "2026-02-13T01:26:36.510Z", "fare_final": null, "pickup_lat": "14.42699990", "pickup_lng": "-16.97656940", "started_at": null, "accepted_at": "2026-02-13T01:27:02.592Z", "dropoff_lat": "14.42972476", "dropoff_lng": "-16.98065061", "cancelled_at": null, "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "759.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Position actuelle", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "estimated_distance_km": "0.53", "estimated_duration_min": 2}, "success": true}	2026-02-13 01:27:02.608498	2026-02-14 01:27:02.608498
9	17fa57aefbf6284c2414349b4001ec288df1e39c1440158d7d71d08cb9299bba	25	/rides/43/cancel	\N	{"data": {"id": 43, "notes": null, "status": "CANCELLED_BY_CLIENT", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": null, "ride_code": "RIDE-2026-000044", "created_at": "2026-02-13T01:59:30.588Z", "fare_final": null, "pickup_lat": "14.43430400", "pickup_lng": "-16.96727040", "started_at": null, "accepted_at": null, "dropoff_lat": "14.44460384", "dropoff_lng": "-16.96458697", "cancelled_at": "2026-02-13T01:59:50.141Z", "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1054.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Position actuelle", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": "Annulé par le client", "estimated_distance_km": "1.18", "estimated_duration_min": 4}, "success": true}	2026-02-13 01:59:50.148913	2026-02-14 01:59:50.148913
10	ride_45_1770949188956	58	/rides/45/accept	\N	{"data": {"id": 45, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000046", "created_at": "2026-02-13T02:19:37.013Z", "fare_final": null, "pickup_lat": "14.43430400", "pickup_lng": "-16.96727040", "started_at": null, "accepted_at": "2026-02-13T02:19:49.395Z", "dropoff_lat": "14.42618250", "dropoff_lng": "-16.95976295", "cancelled_at": null, "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1063.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Position actuelle", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "estimated_distance_km": "1.21", "estimated_duration_min": 4}, "success": true}	2026-02-13 02:19:49.428076	2026-02-14 02:19:49.428076
11	ride_47_1770949252018	58	/rides/47/accept	\N	{"data": {"id": 47, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000048", "created_at": "2026-02-13T02:20:40.849Z", "fare_final": null, "pickup_lat": "14.43430400", "pickup_lng": "-16.96727040", "started_at": null, "accepted_at": "2026-02-13T02:20:52.262Z", "dropoff_lat": "14.43113210", "dropoff_lng": "-16.96747016", "cancelled_at": null, "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "655.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Position actuelle", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "estimated_distance_km": "0.35", "estimated_duration_min": 1}, "success": true}	2026-02-13 02:20:52.321855	2026-02-14 02:20:52.321855
12	delivery_6_1770949338401	58	/deliveries/6/accept	\N	{"data": {"id": 6, "notes": null, "status": "ASSIGNED", "metadata": null, "client_id": 25, "driver_id": 58, "sender_id": null, "created_at": "2026-02-13T02:22:07.773Z", "fare_final": null, "pickup_lat": "14.43430400", "pickup_lng": "-16.96727040", "assigned_at": "2026-02-13T02:22:18.712Z", "dropoff_lat": "14.42424055", "dropoff_lng": "-16.96056383", "frozen_fare": null, "cancelled_at": null, "delivered_at": null, "package_type": "standard", "picked_up_at": null, "recipient_id": null, "client_rating": null, "client_review": null, "delivery_code": "DELIV-2026-5291", "discount_code": null, "driver_rating": null, "driver_review": null, "in_transit_at": null, "insurance_fee": "0.00", "package_value": null, "refund_amount": "0.00", "refund_reason": null, "delivery_proof": null, "estimated_fare": "1306.00", "fare_frozen_at": null, "payment_method": "wallet", "payment_status": "UNPAID", "pickup_address": "Position actuelle", "recipient_name": null, "transaction_id": null, "discount_amount": "0.00", "dropoff_address": "Point sur la carte", "idempotency_key": null, "recipient_email": null, "recipient_phone": null, "cancellation_fee": "0.00", "recipient_rating": null, "recipient_review": null, "package_weight_kg": "2.00", "payment_frozen_at": null, "actual_distance_km": null, "insurance_required": false, "package_dimensions": null, "requires_signature": false, "actual_duration_min": null, "cancellation_reason": null, "package_description": null, "corporate_account_id": null, "payment_collected_at": null, "delivery_instructions": null, "estimated_distance_km": "1.33", "loyalty_points_earned": 0, "estimated_duration_min": 4}, "success": true}	2026-02-13 02:22:18.892796	2026-02-14 02:22:18.892796
13	ride_49_1770996141006	58	/rides/49/accept	\N	{"data": {"id": 49, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000050", "created_at": "2026-02-13T15:22:00.050Z", "driver_lat": 14.434304, "driver_lng": -16.9672704, "fare_final": null, "pickup_lat": "14.42542836", "pickup_lng": "-16.97670967", "started_at": null, "accepted_at": "2026-02-13T15:22:21.201Z", "dropoff_lat": "14.42424732", "dropoff_lng": "-16.97523573", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "613.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "0.21", "estimated_duration_min": 1, "driver_location_updated_at": "2026-02-13T02:22:48.970Z"}, "success": true}	2026-02-13 15:22:21.230746	2026-02-14 15:22:21.230746
14	ride_51_1770996245821	58	/rides/51/accept	\N	{"data": {"id": 51, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000052", "created_at": "2026-02-13T15:23:52.585Z", "driver_lat": 14.4270197, "driver_lng": -16.9765743, "fare_final": null, "pickup_lat": "14.41201307", "pickup_lng": "-16.96684444", "started_at": null, "accepted_at": "2026-02-13T15:24:05.887Z", "dropoff_lat": "14.40582505", "dropoff_lng": "-16.95930457", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "968.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "1.06", "estimated_duration_min": 3, "driver_location_updated_at": "2026-02-13T15:22:31.356Z"}, "success": true}	2026-02-13 15:24:05.917985	2026-02-14 15:24:05.917985
15	ride_53_1770996475047	58	/rides/53/accept	\N	{"data": {"id": 53, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000054", "created_at": "2026-02-13T15:27:36.315Z", "driver_lat": 14.4167954, "driver_lng": -16.9712906, "fare_final": null, "pickup_lat": "14.41679540", "pickup_lng": "-16.97129060", "started_at": null, "accepted_at": "2026-02-13T15:27:55.123Z", "dropoff_lat": "14.40836667", "dropoff_lng": "-16.96694211", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "965.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Position actuelle", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "1.05", "estimated_duration_min": 3, "driver_location_updated_at": "2026-02-13T15:26:15.991Z"}, "success": true}	2026-02-13 15:27:55.139679	2026-02-14 15:27:55.139679
16	ride_57_1770997293570	58	/rides/57/accept	\N	{"data": {"id": 57, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000058", "created_at": "2026-02-13T15:41:24.674Z", "driver_lat": 14.4167954, "driver_lng": -16.9712906, "fare_final": null, "pickup_lat": "14.40934672", "pickup_lng": "-16.96851690", "started_at": null, "accepted_at": "2026-02-13T15:41:33.667Z", "dropoff_lat": "14.41219515", "dropoff_lng": "-16.95262038", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1272.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "1.74", "estimated_duration_min": 5, "driver_location_updated_at": "2026-02-13T15:27:55.361Z"}, "success": true}	2026-02-13 15:41:33.690196	2026-02-14 15:41:33.690196
17	ride_59_1770999056786	58	/rides/59/accept	\N	{"data": {"id": 59, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000060", "created_at": "2026-02-13T16:10:43.931Z", "driver_lat": 14.4167954, "driver_lng": -16.9712906, "fare_final": null, "pickup_lat": "14.41390328", "pickup_lng": "-16.97134976", "started_at": null, "accepted_at": "2026-02-13T16:10:57.058Z", "dropoff_lat": "14.40917013", "dropoff_lng": "-16.96380154", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "941.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "0.97", "estimated_duration_min": 3, "driver_location_updated_at": "2026-02-13T15:47:34.878Z"}, "success": true}	2026-02-13 16:10:57.088689	2026-02-14 16:10:57.088689
18	b522d39039419f215cd7f81a09241c57556bdaf13f1f6d5f881e9a09a46f4c6d	25	/rides/61/cancel	\N	{"data": {"id": 61, "notes": null, "status": "CANCELLED_BY_CLIENT", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": null, "ride_code": "RIDE-2026-000062", "created_at": "2026-02-13T16:12:10.977Z", "fare_final": null, "pickup_lat": "14.41003765", "pickup_lng": "-16.96724785", "started_at": null, "accepted_at": null, "dropoff_lat": "14.42162822", "dropoff_lng": "-16.96636676", "cancelled_at": "2026-02-13T16:12:42.894Z", "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1087.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": "Annulé par le client", "estimated_distance_km": "1.29", "estimated_duration_min": 4}, "success": true}	2026-02-13 16:12:42.90669	2026-02-14 16:12:42.90669
19	ride_63_1771000329719	58	/rides/63/accept	\N	{"data": {"id": 63, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000064", "created_at": "2026-02-13T16:31:59.059Z", "driver_lat": 14.4167954, "driver_lng": -16.9712906, "fare_final": null, "pickup_lat": "14.41006750", "pickup_lng": "-16.96550820", "started_at": null, "accepted_at": "2026-02-13T16:32:09.829Z", "dropoff_lat": "14.42189655", "dropoff_lng": "-16.96636875", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1096.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "1.32", "estimated_duration_min": 4, "driver_location_updated_at": "2026-02-13T16:11:47.292Z"}, "success": true}	2026-02-13 16:32:09.846167	2026-02-14 16:32:09.846167
20	ride_65_1771007371726	58	/rides/65/accept	\N	{"data": {"id": 65, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000066", "created_at": "2026-02-13T18:29:20.138Z", "driver_lat": 14.4167954, "driver_lng": -16.9712906, "fare_final": null, "pickup_lat": "14.42276782", "pickup_lng": "-16.97646770", "started_at": null, "accepted_at": "2026-02-13T18:29:31.776Z", "dropoff_lat": "14.42597002", "dropoff_lng": "-16.96870317", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "923.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "0.91", "estimated_duration_min": 3, "driver_location_updated_at": "2026-02-13T16:38:49.928Z"}, "success": true}	2026-02-13 18:29:31.798941	2026-02-14 18:29:31.798941
21	ride_67_1771007467984	58	/rides/67/accept	\N	{"data": {"id": 67, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000068", "created_at": "2026-02-13T18:30:47.397Z", "driver_lat": 14.4269253, "driver_lng": -16.9765349, "fare_final": null, "pickup_lat": "14.41988836", "pickup_lng": "-16.97384516", "started_at": null, "accepted_at": "2026-02-13T18:31:08.011Z", "dropoff_lat": "14.42806663", "dropoff_lng": "-16.98345677", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1114.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "1.38", "estimated_duration_min": 4, "driver_location_updated_at": "2026-02-13T18:29:51.921Z"}, "success": true}	2026-02-13 18:31:08.051071	2026-02-14 18:31:08.051071
22	c2b9097e8d20f855f790b9a10c2c97c75c888bd6e90641b7fd886a26c661e205	25	/rides/69/cancel	\N	{"data": {"id": 69, "notes": null, "status": "CANCELLED_BY_CLIENT", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": null, "ride_code": "RIDE-2026-000070", "created_at": "2026-02-13T18:32:28.953Z", "fare_final": null, "pickup_lat": "14.42065964", "pickup_lng": "-16.96946746", "started_at": null, "accepted_at": null, "dropoff_lat": "14.41928938", "dropoff_lng": "-16.98195704", "cancelled_at": "2026-02-13T18:32:45.923Z", "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1105.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": "Annulé par le client", "estimated_distance_km": "1.35", "estimated_duration_min": 4}, "success": true}	2026-02-13 18:32:46.135088	2026-02-14 18:32:46.135088
23	ride_71_1771008096856	58	/rides/71/accept	\N	{"data": {"id": 71, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000072", "created_at": "2026-02-13T18:41:26.706Z", "driver_lat": 14.4269253, "driver_lng": -16.9765349, "fare_final": null, "pickup_lat": "14.42227111", "pickup_lng": "-16.97427454", "started_at": null, "accepted_at": "2026-02-13T18:41:36.923Z", "dropoff_lat": "14.41723945", "dropoff_lng": "-16.98250971", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "965.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "1.05", "estimated_duration_min": 3, "driver_location_updated_at": "2026-02-13T18:31:58.111Z"}, "success": true}	2026-02-13 18:41:36.943692	2026-02-14 18:41:36.943692
24	ride_73_1771008179919	58	/rides/73/accept	\N	{"data": {"id": 73, "notes": null, "status": "DRIVER_ASSIGNED", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": 58, "ride_code": "RIDE-2026-000074", "created_at": "2026-02-13T18:42:48.227Z", "driver_lat": 14.4167954, "driver_lng": -16.9712906, "fare_final": null, "pickup_lat": "14.42162250", "pickup_lng": "-16.97497003", "started_at": null, "accepted_at": "2026-02-13T18:42:59.958Z", "dropoff_lat": "14.42081142", "dropoff_lng": "-16.98514134", "cancelled_at": null, "client_phone": null, "completed_at": null, "driver_phone": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "980.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "client_last_name": null, "driver_last_name": null, "client_first_name": null, "driver_arrived_at": null, "driver_avatar_url": null, "driver_first_name": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": null, "driver_average_rating": "0.00", "estimated_distance_km": "1.10", "estimated_duration_min": 3, "driver_location_updated_at": "2026-02-13T18:41:57.037Z"}, "success": true}	2026-02-13 18:42:59.977906	2026-02-14 18:42:59.977906
25	229da620cd08e34c9e24aa27a5ce26f7caac9ef881ab7b74ca6bfa4c29389ecd	58	/rides/73/cancel-driver	\N	{"data": {"id": 73, "notes": null, "status": "CANCELLED_BY_DRIVER", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": null, "ride_code": "RIDE-2026-000074", "created_at": "2026-02-13T18:42:48.227Z", "fare_final": null, "pickup_lat": "14.42162250", "pickup_lng": "-16.97497003", "started_at": null, "accepted_at": "2026-02-13T18:42:59.958Z", "dropoff_lat": "14.42081142", "dropoff_lng": "-16.98514134", "cancelled_at": "2026-02-13T18:43:30.701Z", "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "980.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Point sur la carte", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": "Annulé par le chauffeur", "estimated_distance_km": "1.10", "estimated_duration_min": 3}, "success": true}	2026-02-13 18:43:30.73018	2026-02-14 18:43:30.73018
26	4d3761d2ffd65a3a708808b45f7c3abea766f2d2e3cf95708067900b3d3de11f	25	/rides/75/cancel	\N	{"data": {"id": 75, "notes": null, "status": "CANCELLED_BY_CLIENT", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": null, "ride_code": "RIDE-2026-000076", "created_at": "2026-02-13T19:03:17.532Z", "fare_final": null, "pickup_lat": "14.42932030", "pickup_lng": "-16.97294470", "started_at": null, "accepted_at": null, "dropoff_lat": "14.43522150", "dropoff_lng": "-16.97980430", "cancelled_at": "2026-02-13T19:03:21.514Z", "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "947.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Stade Caroline Faye, N 1, M'bour, Département de M'bour, Thiès, 00510, Sénégal", "transaction_id": null, "dropoff_address": "Maternité Muriel Africa, Grand Mbour, Route Djouti Bou Bess, M'bour, Département de M'bour, Thiès, 00510, Sénégal", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": "Annulé par le client", "estimated_distance_km": "0.99", "estimated_duration_min": 3}, "success": true}	2026-02-13 19:03:21.519747	2026-02-14 19:03:21.519747
27	642d0416415092d98d0ffd7fbf74ad0219882a8e25c608ba0deaf6a2f9207476	25	/rides/77/cancel	\N	{"data": {"id": 77, "notes": null, "status": "CANCELLED_BY_CLIENT", "paid_at": null, "metadata": null, "client_id": 25, "driver_id": null, "ride_code": "RIDE-2026-000078", "created_at": "2026-02-13T19:38:15.166Z", "fare_final": null, "pickup_lat": "14.42690630", "pickup_lng": "-16.97652390", "started_at": null, "accepted_at": null, "dropoff_lat": "14.42217415", "dropoff_lng": "-16.98657144", "cancelled_at": "2026-02-13T19:38:18.436Z", "completed_at": null, "client_rating": null, "client_review": null, "driver_rating": null, "driver_review": null, "estimated_fare": "1060.00", "payment_method": null, "payment_status": "UNPAID", "pickup_address": "Position actuelle", "transaction_id": null, "dropoff_address": "Point sur la carte", "idempotency_key": null, "driver_arrived_at": null, "actual_distance_km": null, "actual_duration_min": null, "cancellation_reason": "Annulé par le client", "estimated_distance_km": "1.20", "estimated_duration_min": 4}, "success": true}	2026-02-13 19:38:18.448791	2026-02-14 19:38:18.448791
\.


--
-- Data for Name: loyalty_programs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.loyalty_programs (id, user_id, total_points, available_points, used_points, tier, tier_multiplier, total_deliveries, total_spent, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: loyalty_transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.loyalty_transactions (id, loyalty_program_id, delivery_id, transaction_type, points, description, created_at) FROM stdin;
\.


--
-- Data for Name: payment_intents; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payment_intents (id, ref_command, token, reference_type, reference_id, user_id, amount, currency, status, provider, metadata, created_at, updated_at, completed_at) FROM stdin;
\.


--
-- Data for Name: pricing_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pricing_config (id, service_type, base_fare, cost_per_km, cost_per_minute, commission_rate, max_distance_km, is_active, created_at, updated_at) FROM stdin;
1	ride	500.00	300.00	50.00	20.00	50.00	t	2026-02-05 15:43:23.122694	2026-02-05 15:43:23.122694
3	delivery	600.00	350.00	60.00	20.00	50.00	t	2026-02-09 16:36:32.182972	2026-02-09 16:36:32.182972
4	delivery	600.00	350.00	60.00	20.00	50.00	t	2026-02-09 17:13:07.221644	2026-02-09 17:13:07.221644
2	ride	500.00	300.00	50.00	20.00	50.00	t	2026-02-05 15:55:49.689125	2026-02-10 02:42:40.368898
\.


--
-- Data for Name: pricing_time_slots; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pricing_time_slots (id, pricing_config_id, start_time, end_time, multiplier, description, created_at) FROM stdin;
1	1	06:00:00	22:00:00	1.00	Jour	2026-02-05 15:43:23.169388
2	1	22:00:00	06:00:00	1.30	Nuit	2026-02-05 15:43:23.169388
3	1	06:00:00	22:00:00	1.00	Jour	2026-02-05 15:55:49.697759
4	1	22:00:00	06:00:00	1.30	Nuit	2026-02-05 15:55:49.697759
5	3	06:00:00	22:00:00	1.00	Jour	2026-02-09 16:36:32.193562
6	3	22:00:00	06:00:00	1.30	Nuit	2026-02-09 16:36:32.193562
7	3	06:00:00	22:00:00	1.00	Jour	2026-02-09 17:13:07.225155
8	3	22:00:00	06:00:00	1.30	Nuit	2026-02-09 17:13:07.225155
\.


--
-- Data for Name: ride_reviews; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ride_reviews (id, ride_id, reviewer_id, reviewed_id, role, rating, comment, created_at) FROM stdin;
1	1	14	15	client	5	Super course, merci !	2026-02-05 18:35:00.712643
2	3	17	18	client	5	Super course, merci !	2026-02-05 18:46:27.066557
\.


--
-- Data for Name: ride_timeouts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ride_timeouts (id, ride_id, timeout_type, execute_at, processed, processed_at, created_at) FROM stdin;
1	1	NO_DRIVER	2026-02-05 18:37:00.348	t	2026-02-05 18:37:30.360192	2026-02-05 18:35:00.363289
2	1	CLIENT_NO_SHOW	2026-02-05 18:42:00.452	t	2026-02-05 18:42:00.665977	2026-02-05 18:35:00.453109
3	3	NO_DRIVER	2026-02-05 18:48:26.549	t	2026-02-05 18:48:30.105604	2026-02-05 18:46:26.567145
4	3	CLIENT_NO_SHOW	2026-02-05 18:53:26.685	t	2026-02-05 18:53:30.465107	2026-02-05 18:46:26.697911
5	5	NO_DRIVER	2026-02-07 05:21:15.238	t	\N	2026-02-07 05:19:15.309319
6	7	NO_DRIVER	2026-02-07 05:21:15.719	t	\N	2026-02-07 05:19:15.801087
7	9	NO_DRIVER	2026-02-07 05:21:15.974	t	\N	2026-02-07 05:19:16.008376
8	11	NO_DRIVER	2026-02-07 05:21:16.08	t	\N	2026-02-07 05:19:16.109312
9	13	NO_DRIVER	2026-02-07 05:21:16.182	t	\N	2026-02-07 05:19:16.286648
10	15	NO_DRIVER	2026-02-07 05:21:16.348	t	\N	2026-02-07 05:19:16.387806
11	17	NO_DRIVER	2026-02-07 05:21:16.449	t	\N	2026-02-07 05:19:16.523344
12	19	NO_DRIVER	2026-02-11 00:10:49.492	t	\N	2026-02-11 00:08:49.518296
13	19	CLIENT_NO_SHOW	2026-02-11 00:15:49.644	t	\N	2026-02-11 00:08:49.645636
14	21	NO_DRIVER	2026-02-11 00:25:02.868	t	\N	2026-02-11 00:23:02.900629
15	21	CLIENT_NO_SHOW	2026-02-11 00:30:03.047	t	\N	2026-02-11 00:23:03.048468
16	23	NO_DRIVER	2026-02-12 05:06:48.64	t	\N	2026-02-12 05:04:48.668531
17	25	NO_DRIVER	2026-02-12 05:30:06.81	t	\N	2026-02-12 05:28:06.822423
18	27	NO_DRIVER	2026-02-12 05:49:16.727	t	\N	2026-02-12 05:47:16.759718
19	29	NO_DRIVER	2026-02-12 05:50:50.81	t	\N	2026-02-12 05:48:50.82349
20	31	NO_DRIVER	2026-02-12 16:39:53.623	t	\N	2026-02-12 16:37:53.672722
21	33	NO_DRIVER	2026-02-12 18:40:54.227	t	\N	2026-02-12 18:38:54.258096
22	35	NO_DRIVER	2026-02-12 20:21:30.099	t	\N	2026-02-12 20:19:30.100244
23	37	NO_DRIVER	2026-02-12 22:08:23.492	t	\N	2026-02-12 22:06:23.492919
24	37	CLIENT_NO_SHOW	2026-02-12 22:13:57.276	t	\N	2026-02-12 22:06:57.2883
25	39	NO_DRIVER	2026-02-13 01:28:36.541	t	\N	2026-02-13 01:26:36.542751
27	41	NO_DRIVER	2026-02-13 01:29:31.43	t	\N	2026-02-13 01:27:31.447993
26	39	CLIENT_NO_SHOW	2026-02-13 01:34:05.04	t	\N	2026-02-13 01:27:05.055921
28	43	NO_DRIVER	2026-02-13 02:01:30.609	t	\N	2026-02-13 01:59:30.623292
29	45	NO_DRIVER	2026-02-13 02:21:37.032	t	\N	2026-02-13 02:19:37.059214
31	47	NO_DRIVER	2026-02-13 02:22:40.867	t	\N	2026-02-13 02:20:40.896516
30	45	CLIENT_NO_SHOW	2026-02-13 02:27:08.443	t	\N	2026-02-13 02:20:08.443929
32	47	CLIENT_NO_SHOW	2026-02-13 02:28:13.175	t	\N	2026-02-13 02:21:13.206557
33	49	NO_DRIVER	2026-02-13 15:24:00.097	t	\N	2026-02-13 15:22:00.114901
35	51	NO_DRIVER	2026-02-13 15:25:52.595	t	\N	2026-02-13 15:23:52.611289
34	49	CLIENT_NO_SHOW	2026-02-13 15:29:33.219	t	\N	2026-02-13 15:22:33.253226
37	53	NO_DRIVER	2026-02-13 15:29:36.328	t	\N	2026-02-13 15:27:36.329158
39	55	NO_DRIVER	2026-02-13 15:30:32.859	t	\N	2026-02-13 15:28:32.859833
36	51	CLIENT_NO_SHOW	2026-02-13 15:32:31.363	t	\N	2026-02-13 15:25:31.378318
38	53	CLIENT_NO_SHOW	2026-02-13 15:34:57.03	t	\N	2026-02-13 15:27:57.041762
40	57	NO_DRIVER	2026-02-13 15:43:24.701	t	\N	2026-02-13 15:41:24.702336
41	57	CLIENT_NO_SHOW	2026-02-13 15:53:16.26	t	\N	2026-02-13 15:46:16.312745
42	59	NO_DRIVER	2026-02-13 16:12:43.98	t	\N	2026-02-13 16:10:43.999395
44	61	NO_DRIVER	2026-02-13 16:14:10.986	t	\N	2026-02-13 16:12:10.987595
43	59	CLIENT_NO_SHOW	2026-02-13 16:18:45.746	t	\N	2026-02-13 16:11:45.773529
45	63	NO_DRIVER	2026-02-13 16:33:59.093	t	\N	2026-02-13 16:31:59.140422
46	63	CLIENT_NO_SHOW	2026-02-13 16:40:21.746	t	\N	2026-02-13 16:33:21.758417
47	65	NO_DRIVER	2026-02-13 18:31:20.177	t	\N	2026-02-13 18:29:20.201939
49	67	NO_DRIVER	2026-02-13 18:32:47.406	t	\N	2026-02-13 18:30:47.418566
51	69	NO_DRIVER	2026-02-13 18:34:28.963	t	\N	2026-02-13 18:32:28.964554
48	65	CLIENT_NO_SHOW	2026-02-13 18:36:57.892	t	\N	2026-02-13 18:29:57.903995
50	67	CLIENT_NO_SHOW	2026-02-13 18:38:15.43	t	\N	2026-02-13 18:31:15.439208
52	71	NO_DRIVER	2026-02-13 18:43:26.718	t	\N	2026-02-13 18:41:26.736768
54	73	NO_DRIVER	2026-02-13 18:44:48.245	t	\N	2026-02-13 18:42:48.246906
53	71	CLIENT_NO_SHOW	2026-02-13 18:48:52.042	t	\N	2026-02-13 18:41:52.051297
55	75	NO_DRIVER	2026-02-13 19:05:17.541	t	\N	2026-02-13 19:03:17.55306
56	77	NO_DRIVER	2026-02-13 19:40:15.182	t	\N	2026-02-13 19:38:15.197702
\.


--
-- Data for Name: ride_tracking; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ride_tracking (id, ride_id, lat, lng, "timestamp") FROM stdin;
1	3	14.70000000	-17.45500000	2026-02-05 18:46:26.797767
2	45	14.43430400	-16.96727040	2026-02-13 02:19:50.390121
3	45	14.43430400	-16.96727040	2026-02-13 02:19:59.478749
4	45	14.43430400	-16.96727040	2026-02-13 02:20:09.489704
5	47	14.43430400	-16.96727040	2026-02-13 02:20:52.787447
6	47	14.43430400	-16.96727040	2026-02-13 02:21:02.449365
7	47	14.43430400	-16.96727040	2026-02-13 02:21:12.452681
8	47	14.43430400	-16.96727040	2026-02-13 02:21:22.461634
9	47	14.43430400	-16.96727040	2026-02-13 02:21:32.461764
10	49	14.42701970	-16.97657430	2026-02-13 15:22:22.05083
11	49	14.42701970	-16.97657430	2026-02-13 15:22:31.361866
12	51	14.42701970	-16.97657430	2026-02-13 15:24:06.14147
13	51	14.41679540	-16.97129060	2026-02-13 15:24:16.00435
14	51	14.41679540	-16.97129060	2026-02-13 15:24:26.010784
15	51	14.41679540	-16.97129060	2026-02-13 15:24:35.99371
16	51	14.41679540	-16.97129060	2026-02-13 15:24:46.003878
17	51	14.41679540	-16.97129060	2026-02-13 15:24:56.015518
18	51	14.41679540	-16.97129060	2026-02-13 15:25:06.026681
19	51	14.41679540	-16.97129060	2026-02-13 15:25:16.010585
20	51	14.41679540	-16.97129060	2026-02-13 15:25:26.492752
21	51	14.41679540	-16.97129060	2026-02-13 15:25:36.132634
22	51	14.41679540	-16.97129060	2026-02-13 15:25:46.015621
23	51	14.41679540	-16.97129060	2026-02-13 15:25:56.025382
24	51	14.41679540	-16.97129060	2026-02-13 15:26:06.005773
25	51	14.41679540	-16.97129060	2026-02-13 15:26:16.002904
26	53	14.41679540	-16.97129060	2026-02-13 15:27:55.37149
27	57	14.41679540	-16.97129060	2026-02-13 15:41:33.938674
28	57	14.41679540	-16.97129060	2026-02-13 15:41:43.791717
29	57	14.41679540	-16.97129060	2026-02-13 15:41:53.785233
30	57	14.41679540	-16.97129060	2026-02-13 15:42:03.817111
31	57	14.41679540	-16.97129060	2026-02-13 15:42:13.802917
32	57	14.41679540	-16.97129060	2026-02-13 15:42:26.808873
33	57	14.41679540	-16.97129060	2026-02-13 15:42:53.26759
34	57	14.41679540	-16.97129060	2026-02-13 15:43:02.855247
35	57	14.41679540	-16.97129060	2026-02-13 15:43:04.45442
36	57	14.41679540	-16.97129060	2026-02-13 15:43:07.54425
37	57	14.41679540	-16.97129060	2026-02-13 15:43:14.907126
38	57	14.41679540	-16.97129060	2026-02-13 15:43:24.916884
39	57	14.41679540	-16.97129060	2026-02-13 15:43:34.887102
40	57	14.41679540	-16.97129060	2026-02-13 15:43:44.88707
41	57	14.41679540	-16.97129060	2026-02-13 15:43:54.896342
42	57	14.41679540	-16.97129060	2026-02-13 15:44:04.886333
43	57	14.41679540	-16.97129060	2026-02-13 15:44:14.9364
44	57	14.41679540	-16.97129060	2026-02-13 15:44:24.901976
45	57	14.41679540	-16.97129060	2026-02-13 15:44:34.909835
46	57	14.41679540	-16.97129060	2026-02-13 15:44:44.905507
47	57	14.41679540	-16.97129060	2026-02-13 15:44:54.894942
48	57	14.41679540	-16.97129060	2026-02-13 15:45:04.897779
49	57	14.41679540	-16.97129060	2026-02-13 15:45:14.887302
50	57	14.41679540	-16.97129060	2026-02-13 15:45:24.88684
51	57	14.41679540	-16.97129060	2026-02-13 15:45:34.889137
52	57	14.41679540	-16.97129060	2026-02-13 15:45:44.892653
53	57	14.41679540	-16.97129060	2026-02-13 15:45:54.886242
54	57	14.41679540	-16.97129060	2026-02-13 15:46:04.886401
55	57	14.41679540	-16.97129060	2026-02-13 15:46:14.892916
56	57	14.41679540	-16.97129060	2026-02-13 15:46:24.909258
57	57	14.41679540	-16.97129060	2026-02-13 15:46:34.888278
58	57	14.41679540	-16.97129060	2026-02-13 15:46:44.884816
59	57	14.41679540	-16.97129060	2026-02-13 15:46:54.888126
60	57	14.41679540	-16.97129060	2026-02-13 15:47:04.880571
61	57	14.41679540	-16.97129060	2026-02-13 15:47:14.883614
62	57	14.41679540	-16.97129060	2026-02-13 15:47:24.905914
63	57	14.41679540	-16.97129060	2026-02-13 15:47:34.881213
64	59	14.42701500	-16.97657720	2026-02-13 16:10:57.630584
65	59	14.41679540	-16.97129060	2026-02-13 16:11:07.21021
66	59	14.41679540	-16.97129060	2026-02-13 16:11:17.194251
67	59	14.41679540	-16.97129060	2026-02-13 16:11:27.214885
68	59	14.41679540	-16.97129060	2026-02-13 16:11:37.210181
69	59	14.41679540	-16.97129060	2026-02-13 16:11:47.294811
70	63	14.41679540	-16.97129060	2026-02-13 16:32:10.116076
71	63	14.41679540	-16.97129060	2026-02-13 16:32:19.929917
72	63	14.41679540	-16.97129060	2026-02-13 16:32:30.128341
73	63	14.41679540	-16.97129060	2026-02-13 16:32:39.934567
74	63	14.41679540	-16.97129060	2026-02-13 16:32:49.946138
75	63	14.41679540	-16.97129060	2026-02-13 16:32:59.941424
76	63	14.41679540	-16.97129060	2026-02-13 16:33:09.935496
77	63	14.41679540	-16.97129060	2026-02-13 16:33:19.956203
78	63	14.41679540	-16.97129060	2026-02-13 16:33:30.097051
79	63	14.41679540	-16.97129060	2026-02-13 16:33:39.932563
80	63	14.41679540	-16.97129060	2026-02-13 16:33:49.93623
81	63	14.41679540	-16.97129060	2026-02-13 16:33:59.939721
82	63	14.41679540	-16.97129060	2026-02-13 16:34:09.938963
83	63	14.41679540	-16.97129060	2026-02-13 16:34:19.939053
84	63	14.41679540	-16.97129060	2026-02-13 16:34:29.938977
85	63	14.41679540	-16.97129060	2026-02-13 16:34:39.93766
86	63	14.41679540	-16.97129060	2026-02-13 16:34:49.941874
87	63	14.41679540	-16.97129060	2026-02-13 16:34:59.939843
88	63	14.41679540	-16.97129060	2026-02-13 16:35:09.933617
89	63	14.41679540	-16.97129060	2026-02-13 16:35:19.948749
90	63	14.41679540	-16.97129060	2026-02-13 16:35:29.938454
91	63	14.41679540	-16.97129060	2026-02-13 16:35:39.93774
92	63	14.41679540	-16.97129060	2026-02-13 16:35:49.935288
93	63	14.41679540	-16.97129060	2026-02-13 16:35:59.931352
94	63	14.41679540	-16.97129060	2026-02-13 16:36:09.938506
95	63	14.41679540	-16.97129060	2026-02-13 16:36:19.952315
96	63	14.41679540	-16.97129060	2026-02-13 16:36:29.938768
97	63	14.41679540	-16.97129060	2026-02-13 16:36:39.940223
98	63	14.41679540	-16.97129060	2026-02-13 16:36:49.938551
99	63	14.41679540	-16.97129060	2026-02-13 16:36:59.937784
100	63	14.41679540	-16.97129060	2026-02-13 16:37:09.937942
101	63	14.41679540	-16.97129060	2026-02-13 16:37:19.938352
102	63	14.41679540	-16.97129060	2026-02-13 16:37:29.941315
103	63	14.41679540	-16.97129060	2026-02-13 16:37:39.942958
104	63	14.41679540	-16.97129060	2026-02-13 16:37:49.939007
105	63	14.41679540	-16.97129060	2026-02-13 16:37:59.937569
106	63	14.41679540	-16.97129060	2026-02-13 16:38:09.939551
107	63	14.41679540	-16.97129060	2026-02-13 16:38:19.938793
108	63	14.41679540	-16.97129060	2026-02-13 16:38:29.937777
109	63	14.41679540	-16.97129060	2026-02-13 16:38:39.937365
110	63	14.41679540	-16.97129060	2026-02-13 16:38:49.938575
111	65	14.42696280	-16.97655460	2026-02-13 18:29:32.094962
112	65	14.42692530	-16.97653490	2026-02-13 18:29:41.926769
113	65	14.42692530	-16.97653490	2026-02-13 18:29:51.929358
114	67	14.42692530	-16.97653490	2026-02-13 18:31:08.088961
115	67	14.42692530	-16.97653490	2026-02-13 18:31:18.097066
116	67	14.42692530	-16.97653490	2026-02-13 18:31:28.116873
117	67	14.42692530	-16.97653490	2026-02-13 18:31:38.116337
118	67	14.42692530	-16.97653490	2026-02-13 18:31:48.126277
119	67	14.42692530	-16.97653490	2026-02-13 18:31:58.113615
120	71	14.42690200	-16.97652090	2026-02-13 18:41:37.13896
121	71	14.41679540	-16.97129060	2026-02-13 18:41:47.042922
122	71	14.41679540	-16.97129060	2026-02-13 18:41:57.042151
123	73	14.41679540	-16.97129060	2026-02-13 18:43:00.102031
124	73	14.42690200	-16.97652090	2026-02-13 18:43:10.024292
125	73	14.42690200	-16.97652090	2026-02-13 18:43:20.045767
126	73	14.42690200	-16.97652090	2026-02-13 18:43:30.042404
\.


--
-- Data for Name: rides; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rides (id, ride_code, client_id, driver_id, idempotency_key, pickup_lat, pickup_lng, pickup_address, dropoff_lat, dropoff_lng, dropoff_address, estimated_distance_km, estimated_duration_min, estimated_fare, actual_distance_km, actual_duration_min, fare_final, status, created_at, accepted_at, driver_arrived_at, started_at, completed_at, paid_at, cancelled_at, cancellation_reason, payment_method, payment_status, transaction_id, client_rating, client_review, driver_rating, driver_review, notes, metadata) FROM stdin;
1	RIDE-2026-000002	14	15	\N	14.69280000	-17.44670000	Plateau, Dakar	14.71000000	-17.46800000	Point E, Dakar	2.98	9	1844.00	5.20	18	2028.00	COMPLETED	2026-02-05 18:35:00.317046	2026-02-05 18:35:00.390398	2026-02-05 18:35:00.446745	2026-02-05 18:35:00.481022	2026-02-05 18:35:00.559035	\N	\N	\N	\N	PAYMENT_PENDING	\N	5	Super course, merci !	\N	\N	\N	\N
3	RIDE-2026-000004	17	18	\N	14.69280000	-17.44670000	Plateau, Dakar	14.71000000	-17.46800000	Point E, Dakar	2.98	9	1844.00	5.20	18	2028.00	COMPLETED	2026-02-05 18:46:26.542055	2026-02-05 18:46:26.631468	2026-02-05 18:46:26.679776	2026-02-05 18:46:26.730523	2026-02-05 18:46:26.843044	\N	\N	\N	\N	PAYMENT_PENDING	\N	5	Super course, merci !	\N	\N	\N	\N
5	RIDE-2026-000006	3	\N	\N	14.71670000	-17.46770000	\N	14.72000000	-17.47000000	\N	0.44	1	682.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-07 05:19:14.947219	\N	\N	\N	\N	\N	2026-02-09 17:14:00.185279	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
7	RIDE-2026-000008	3	\N	\N	14.71670000	-17.46770000	\N	14.72000000	-17.47000000	\N	0.44	1	682.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-07 05:19:15.695718	\N	\N	\N	\N	\N	2026-02-09 17:14:00.293169	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
9	RIDE-2026-000010	3	\N	\N	14.71670000	-17.46770000	\N	14.72000000	-17.47000000	\N	0.44	1	682.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-07 05:19:15.939706	\N	\N	\N	\N	\N	2026-02-09 17:14:00.376073	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
11	RIDE-2026-000012	3	\N	\N	14.71770000	-17.46670000	\N	14.72000000	-17.47000000	\N	0.44	1	682.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-07 05:19:16.04804	\N	\N	\N	\N	\N	2026-02-09 17:14:00.451827	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
13	RIDE-2026-000014	3	\N	\N	14.71870000	-17.46570000	\N	14.72000000	-17.47000000	\N	0.48	1	694.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-07 05:19:16.15003	\N	\N	\N	\N	\N	2026-02-09 17:14:00.528172	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
15	RIDE-2026-000016	3	\N	\N	14.71970000	-17.46470000	\N	14.72000000	-17.47000000	\N	0.57	2	771.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-07 05:19:16.324066	\N	\N	\N	\N	\N	2026-02-09 17:14:00.602638	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
17	RIDE-2026-000018	3	\N	\N	14.72070000	-17.46370000	\N	14.72000000	-17.47000000	\N	0.68	2	804.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-07 05:19:16.420737	\N	\N	\N	\N	\N	2026-02-09 17:14:00.68033	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
19	RIDE-2026-000020	20	21	\N	14.69280000	-17.44670000	Plateau, Dakar	14.71000000	-17.46800000	Point E, Dakar	2.98	9	1844.00	5.20	18	2028.00	COMPLETED	2026-02-11 00:08:49.440776	2026-02-11 00:08:49.564718	2026-02-11 00:08:49.634643	2026-02-11 00:08:49.669304	2026-02-11 00:08:49.757403	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
21	RIDE-2026-000022	22	23	\N	14.69280000	-17.44670000	Plateau, Dakar	14.71000000	-17.46800000	Point b, Dakar	2.98	9	1844.00	5.20	18	2028.00	COMPLETED	2026-02-11 00:23:02.84093	2026-02-11 00:23:02.937109	2026-02-11 00:23:03.038446	2026-02-11 00:23:03.07608	2026-02-11 00:23:03.149226	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
23	RIDE-2026-000024	25	\N	\N	14.69280000	-17.44670000	Plateau, Dakar	14.71000000	-17.46800000	Point E, Dakar	2.98	9	1844.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-12 05:04:48.550915	\N	\N	\N	\N	\N	2026-02-12 05:06:48.730804	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
25	RIDE-2026-000026	25	\N	\N	12.58291200	-16.25620480	Position actuelle	12.56174353	-16.24331775	Point sur la carte	2.74	8	1722.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-12 05:28:06.789606	\N	\N	\N	\N	\N	2026-02-12 05:30:06.831671	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
27	RIDE-2026-000028	25	\N	\N	12.58291200	-16.25620480	Position actuelle	12.57517040	-16.26323280	Poste de Santé de Kandé, Route Santhiaba, Djefaye, Djibock, Ziguinchor, Département de Ziguinchor, Région de Ziguinchor, 52024, Sénégal	1.15	3	995.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-12 05:47:16.658557	\N	\N	\N	\N	\N	2026-02-12 05:49:16.778812	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
29	RIDE-2026-000030	25	\N	\N	12.58291200	-16.25620480	Position actuelle	12.58004981	-16.25575185	Point sur la carte	0.32	1	646.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-12 05:48:50.79828	\N	\N	\N	\N	\N	2026-02-12 05:50:50.829782	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
31	RIDE-2026-000032	25	\N	\N	14.42687290	-16.97650030	Position actuelle	14.47490072	-16.99055627	Point sur la carte	5.55	17	3015.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-12 16:37:53.557879	\N	\N	\N	\N	\N	2026-02-12 16:39:53.685492	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
33	RIDE-2026-000034	25	\N	\N	14.42687340	-16.97650110	Position actuelle	14.42299436	-16.97499798	Point sur la carte	0.46	1	688.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-12 18:38:54.19581	\N	\N	\N	\N	\N	2026-02-12 18:40:54.271708	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
35	RIDE-2026-000036	25	\N	\N	14.41679540	-16.97129060	Position actuelle	14.41170493	-16.96677865	Point sur la carte	0.75	2	825.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-12 20:19:30.089414	\N	\N	\N	\N	\N	2026-02-12 20:21:30.135139	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
37	RIDE-2026-000038	25	58	\N	14.42694680	-16.97654640	Position actuelle	14.42498197	-16.97521849	Point sur la carte	0.26	1	628.00	0.00	1	550.00	COMPLETED	2026-02-12 22:06:23.459353	2026-02-12 22:06:40.53964	2026-02-12 22:06:57.270783	2026-02-12 22:06:59.782839	2026-02-12 22:07:16.348348	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
39	RIDE-2026-000040	25	58	\N	14.42699990	-16.97656940	Position actuelle	14.42972476	-16.98065061	Point sur la carte	0.53	2	759.00	1.00	2	835.00	COMPLETED	2026-02-13 01:26:36.510717	2026-02-13 01:27:02.592187	2026-02-13 01:27:05.036183	2026-02-13 01:27:06.152239	2026-02-13 01:27:07.276107	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
41	RIDE-2026-000042	25	\N	\N	14.42699990	-16.97656940	Position actuelle	14.42053505	-16.97401863	Point sur la carte	0.77	2	831.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-13 01:27:31.423093	\N	\N	\N	\N	\N	2026-02-13 01:29:31.451847	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
43	RIDE-2026-000044	25	\N	\N	14.43430400	-16.96727040	Position actuelle	14.44460384	-16.96458697	Point sur la carte	1.18	4	1054.00	\N	\N	\N	CANCELLED_BY_CLIENT	2026-02-13 01:59:30.588058	\N	\N	\N	\N	\N	2026-02-13 01:59:50.141198	Annulé par le client	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
45	RIDE-2026-000046	25	58	\N	14.43430400	-16.96727040	Position actuelle	14.42618250	-16.95976295	Point sur la carte	1.21	4	1063.00	1.00	4	1000.00	COMPLETED	2026-02-13 02:19:37.013856	2026-02-13 02:19:49.395095	2026-02-13 02:20:08.436112	2026-02-13 02:20:10.926179	2026-02-13 02:20:15.996345	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
47	RIDE-2026-000048	25	58	\N	14.43430400	-16.96727040	Position actuelle	14.43113210	-16.96747016	Point sur la carte	0.35	1	655.00	1.00	1	721.00	COMPLETED	2026-02-13 02:20:40.849968	2026-02-13 02:20:52.262932	2026-02-13 02:21:13.162245	2026-02-13 02:21:24.611283	2026-02-13 02:21:38.460745	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
49	RIDE-2026-000050	25	58	\N	14.42542836	-16.97670967	Point sur la carte	14.42424732	-16.97523573	Point sur la carte	0.21	1	613.00	1.00	1	674.00	COMPLETED	2026-02-13 15:22:00.050545	2026-02-13 15:22:21.201753	2026-02-13 15:22:33.205475	2026-02-13 15:22:34.840522	2026-02-13 15:22:35.926742	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
51	RIDE-2026-000052	25	58	\N	14.41201307	-16.96684444	Point sur la carte	14.40582505	-16.95930457	Point sur la carte	1.06	3	968.00	1.00	3	950.00	COMPLETED	2026-02-13 15:23:52.585758	2026-02-13 15:24:05.887374	2026-02-13 15:25:31.35896	2026-02-13 15:26:24.476581	2026-02-13 15:26:25.495632	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
53	RIDE-2026-000054	25	58	\N	14.41679540	-16.97129060	Position actuelle	14.40836667	-16.96694211	Point sur la carte	1.05	3	965.00	1.00	3	950.00	COMPLETED	2026-02-13 15:27:36.315968	2026-02-13 15:27:55.123906	2026-02-13 15:27:57.020284	2026-02-13 15:27:57.564743	2026-02-13 15:27:58.528978	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
55	RIDE-2026-000056	25	\N	\N	14.41004428	-16.96962741	Point sur la carte	14.41273078	-16.95329796	Point sur la carte	1.78	5	1284.00	\N	\N	\N	CANCELLED_BY_SYSTEM	2026-02-13 15:28:32.844241	\N	\N	\N	\N	\N	2026-02-13 15:30:32.878797	Aucun driver disponible dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
57	RIDE-2026-000058	25	58	\N	14.40934672	-16.96851690	Point sur la carte	14.41219515	-16.95262038	Point sur la carte	1.74	5	1272.00	\N	\N	\N	IN_PROGRESS	2026-02-13 15:41:24.674683	2026-02-13 15:41:33.667292	2026-02-13 15:46:16.238959	2026-02-13 15:46:25.73832	\N	\N	\N	\N	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
59	RIDE-2026-000060	25	58	\N	14.41390328	-16.97134976	Point sur la carte	14.40917013	-16.96380154	Point sur la carte	0.97	3	941.00	1.00	3	950.00	COMPLETED	2026-02-13 16:10:43.931773	2026-02-13 16:10:57.058897	2026-02-13 16:11:45.733577	2026-02-13 16:11:47.011861	2026-02-13 16:11:47.926713	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
61	RIDE-2026-000062	25	\N	\N	14.41003765	-16.96724785	Point sur la carte	14.42162822	-16.96636676	Point sur la carte	1.29	4	1087.00	\N	\N	\N	CANCELLED_BY_CLIENT	2026-02-13 16:12:10.977416	\N	\N	\N	\N	\N	2026-02-13 16:12:42.894607	Annulé par le client	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
63	RIDE-2026-000064	25	\N	\N	14.41006750	-16.96550820	Point sur la carte	14.42189655	-16.96636875	Point sur la carte	1.32	4	1096.00	\N	\N	\N	CANCELLED_BY_DRIVER	2026-02-13 16:31:59.059536	2026-02-13 16:32:09.829324	2026-02-13 16:33:21.735878	\N	\N	\N	2026-02-13 16:40:30.488013	Client ne s'est pas présenté dans les délais	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
65	RIDE-2026-000066	25	58	\N	14.42276782	-16.97646770	Point sur la carte	14.42597002	-16.96870317	Point sur la carte	0.91	3	923.00	1.00	3	950.00	COMPLETED	2026-02-13 18:29:20.138261	2026-02-13 18:29:31.776097	2026-02-13 18:29:57.889165	2026-02-13 18:30:00.096553	2026-02-13 18:30:01.098887	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
67	RIDE-2026-000068	25	58	\N	14.41988836	-16.97384516	Point sur la carte	14.42806663	-16.98345677	Point sur la carte	1.38	4	1114.00	1.00	4	1000.00	COMPLETED	2026-02-13 18:30:47.397725	2026-02-13 18:31:08.011225	2026-02-13 18:31:15.427778	2026-02-13 18:31:16.47564	2026-02-13 18:32:03.841701	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
69	RIDE-2026-000070	25	\N	\N	14.42065964	-16.96946746	Point sur la carte	14.41928938	-16.98195704	Point sur la carte	1.35	4	1105.00	\N	\N	\N	CANCELLED_BY_CLIENT	2026-02-13 18:32:28.953341	\N	\N	\N	\N	\N	2026-02-13 18:32:45.923949	Annulé par le client	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
71	RIDE-2026-000072	25	58	\N	14.42227111	-16.97427454	Point sur la carte	14.41723945	-16.98250971	Point sur la carte	1.05	3	965.00	1.00	3	950.00	COMPLETED	2026-02-13 18:41:26.706701	2026-02-13 18:41:36.923172	2026-02-13 18:41:52.03827	2026-02-13 18:41:53.523026	2026-02-13 18:42:01.347396	\N	\N	\N	\N	PAYMENT_PENDING	\N	\N	\N	\N	\N	\N	\N
73	RIDE-2026-000074	25	\N	\N	14.42162250	-16.97497003	Point sur la carte	14.42081142	-16.98514134	Point sur la carte	1.10	3	980.00	\N	\N	\N	CANCELLED_BY_DRIVER	2026-02-13 18:42:48.227637	2026-02-13 18:42:59.958499	\N	\N	\N	\N	2026-02-13 18:43:30.701948	Annulé par le chauffeur	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
75	RIDE-2026-000076	25	\N	\N	14.42932030	-16.97294470	Stade Caroline Faye, N 1, M'bour, Département de M'bour, Thiès, 00510, Sénégal	14.43522150	-16.97980430	Maternité Muriel Africa, Grand Mbour, Route Djouti Bou Bess, M'bour, Département de M'bour, Thiès, 00510, Sénégal	0.99	3	947.00	\N	\N	\N	CANCELLED_BY_CLIENT	2026-02-13 19:03:17.53258	\N	\N	\N	\N	\N	2026-02-13 19:03:21.514452	Annulé par le client	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
77	RIDE-2026-000078	25	\N	\N	14.42690630	-16.97652390	Position actuelle	14.42217415	-16.98657144	Point sur la carte	1.20	4	1060.00	\N	\N	\N	CANCELLED_BY_CLIENT	2026-02-13 19:38:15.166593	\N	\N	\N	\N	\N	2026-02-13 19:38:18.436903	Annulé par le client	\N	UNPAID	\N	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.transactions (id, wallet_id, user_id, type, amount, balance_before, balance_after, reference_type, reference_id, description, metadata, status, created_at, processed_at) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, email, phone, password_hash, first_name, last_name, role, status, avatar_url, date_of_birth, gender, language, timezone, address, city, country, email_verified, phone_verified, verification_token, verification_token_expires_at, last_login_at, failed_login_attempts, locked_until, created_at, updated_at, deleted_at) FROM stdin;
1	client1@example.com	+221770000001	$2a$10$4vAQwSLQ.LYkCRwArSdL4OH5S01EcaLSsOXNhJ1hHVa1ndWyfLaiS	Client	Test	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:16:57.494809	2026-02-05 18:16:57.494809	\N
2	client2@example.com	+221770000003	$2a$10$h1UQ.dI1zata6K0RCFVDNOciwUtx/IJbCW9gG8B8QWTi19LKKdcVm	Client2	Test	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:18:53.799645	2026-02-05 18:18:53.799645	\N
3	driver1@example.com	+221770000002	$2a$10$ayrdNLX/kyiLQuBiU/BmsuOLxLQY10gPGN9b2fheuK/aPvBBA0Hgm	Driver	Test	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:20:07.934505	2026-02-05 18:20:07.934505	\N
4	client_test_1770316074584@example.com	+221770004584	$2a$10$bOblXyTmZxemZENrvjFIJOQsw.nSQsnnqV/ZZ4r9y4pzlNeCWb.02	Client	Test	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:27:54.790702	2026-02-05 18:27:54.790702	\N
5	driver_test_1770316074584@example.com	+221770004585	$2a$10$l.vWEd3iggDcPqyaAk6QAOiq7LDsPTw74TUzXDMFiS7RFyEdYlW5m	Driver	Test	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:27:54.976361	2026-02-05 18:27:54.976361	\N
6	client_test_1770316143166@example.com	+221770003166	$2a$10$PSqjn39.YCpgJv2k8sI2Kew8Ndmwpeuv1.75j5Et2fUw5/EDYNyZi	Client	Test	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:29:03.403536	2026-02-05 18:29:03.403536	\N
7	driver_test_1770316143166@example.com	+221770003167	$2a$10$EhajTE0rYvOHb56S52Wl0ucoTATWQ5YVzVR1/KX6F4sGeHA49QtNa	Driver	Test	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:29:03.586637	2026-02-05 18:29:03.586637	\N
8	client_test_1770316153228@example.com	+221770003228	$2a$10$mfdgFEchZ4uL00DcAO/r/uOJcky1CG0c9caAjSjfHCkAOlDbRnObq	Client	Test	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:29:13.418977	2026-02-05 18:29:13.418977	\N
9	driver_test_1770316153228@example.com	+221770003229	$2a$10$WAaCWaAR9Z3alFh2AB9NteKp0n9Xz6lSNNGJ2cVwXHoQLtmiIBVI2	Driver	Test	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:29:13.593723	2026-02-05 18:29:13.593723	\N
10	driver_debug_1770316288205@example.com	+221770008205	$2a$10$aHi6b.S0Gd6LHS2L4mANqOaZttIz61Phv8n8JAb8gpC2klumfmEJi	Driver	Debug	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:31:28.441814	2026-02-05 18:31:28.441814	\N
11	driver_debug_1770316356002@example.com	+221770006002	$2a$10$Ovej.shYf4c6FbkoUsXiFOm8l/UqAvig3guWgW6mCEmGCTzPg.T7y	Driver	Debug	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:32:36.242137	2026-02-05 18:32:36.242137	\N
12	driver_debug_1770316442316@example.com	+221770002316	$2a$10$Vw8j8jHXDgK0b7HEL67THuJoYu1HkLotJa0oU8QIj.7MmyEbfwiN2	Driver	Debug	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:34:02.556885	2026-02-05 18:34:02.556885	\N
13	driver_debug_1770316453497@example.com	+221770003497	$2a$10$MNx1ayNKlyl2i0bdeV/o3O3Qg.soSzcri79Clp/W0UpOpoP3AqFuK	Driver	Debug	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:34:13.718682	2026-02-05 18:34:13.718682	\N
14	client_test_1770316499790@example.com	+221770009790	$2a$10$gOodxdqbGBzbKlEpnvgP1eCU.71/PEjxwsmlh7.TXTZ98sbtaEX6C	Client	Test	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:35:00.058343	2026-02-05 18:35:00.058343	\N
15	driver_test_1770316499790@example.com	+221770009791	$2a$10$LSv3QVkRRjCWXMESCJF2s.butxjbhkE/G7sxdQB6AU.dOAXA39HSe	Driver	Test	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:35:00.251095	2026-02-05 18:35:00.251095	\N
16	driver_debug_1770316524352@example.com	+221770004352	$2a$10$rKs.9oA/zfIRettiLnycme2m8On5nkd3BRIQStDXPjBtbrN3RuS2m	Driver	Debug	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:35:24.548316	2026-02-05 18:35:24.548316	\N
17	client_curl_1770317186@example.com	+22177000186	$2a$10$XHG7xkDgoP7rTF1E0GsC7ubS/WJSzN8uoVXMdNwoB0GbyBx/xDL/6	Client	Curl	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:46:26.238811	2026-02-05 18:46:26.238811	\N
18	driver_curl_1770317186@example.com	+22177000187	$2a$10$/m/wij0FWafGAZgMkTrFVew8tQ7GDdwCnu2kzQteL7FueqMSoIaSS	Driver	Curl	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-05 18:46:26.437582	2026-02-05 18:46:26.437582	\N
58	gg1@gmail.com	\N	$2a$10$Xqz2k1l5LPdIp/Doa3xbvOCK4RMK0QyYRQ7o2wdgJQ39kOlcWhsnu	\N	\N	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	2026-02-13 18:39:24.90777	0	\N	2026-02-12 21:33:31.8616	2026-02-13 18:39:24.90777	\N
25	gg@gmail.com	\N	$2a$10$cm1zWF6HVz9ugLcOgdLOY.yLFJMtmk9Cj2F3aw1eWiTyKdNNXDX6q	\N	\N	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	2026-02-13 19:49:11.267747	0	\N	2026-02-12 04:43:16.970624	2026-02-13 19:49:11.267747	\N
19	admin@bikeride.pro	+221770000000	$2a$10$KbtfDv33M/84Eq.CZcoCjOYDB8iWQTTs67izkew5FErjYujCrt9ly	Admin	System	admin	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	2026-02-10 23:50:01.235715	0	\N	2026-02-09 21:57:08.65111	2026-02-10 23:50:01.235715	\N
20	client_sim_1770768528912@example.com	+22177528912	$2a$10$4Mn5raosNL1LhkL.YG86Te3E4fOosHe/KqBoPSFp9ZIDDbqa48eXq	Moustapha	Sy	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-11 00:08:49.122114	2026-02-11 00:08:49.122114	\N
21	driver_sim_1770768528912@example.com	+22178528912	$2a$10$3X9Lbp6mZCH3j70sbOmD2OjhuOwE3oxoZrvrQAxjaMkplwH5h0pFe	Landing	Savage	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-11 00:08:49.339972	2026-02-11 00:08:49.339972	\N
22	client_sim_1770769382210@example.com	+22177382210	$2a$10$h1tKt8OvIFUiFy79iZae5uHHk2EaOGa46p5a9qYdh1l0QC.xpBSvy	Moustapha2	Sy2	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-11 00:23:02.526518	2026-02-11 00:23:02.526518	\N
23	driver_sim_1770769382210@example.com	+22178382210	$2a$10$Iw74giYqRfLYB53I8NkT.eMa/zdo3ifgIG0FsJiX1wiNZ/jw4Q5Oi	Landing2	Savage2	driver	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-11 00:23:02.723361	2026-02-11 00:23:02.723361	\N
24	test@example.com	\N	$2a$10$s8qdaXldSUWS9hmBo9Tu2OF.J7V8b6SawSk2.14aKd3ujXOpACmS2	Test	User	client	active	\N	\N	\N	fr	Africa/Dakar	\N	\N	Senegal	f	f	\N	\N	\N	0	\N	2026-02-12 04:25:06.902486	2026-02-12 04:25:06.902486	\N
\.


--
-- Data for Name: wallets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallets (id, user_id, balance, currency, is_active, created_at, updated_at, last_transaction_at) FROM stdin;
1	14	0.00	XOF	t	2026-02-05 18:35:00.578868	2026-02-05 18:35:00.578868	\N
2	17	0.00	XOF	t	2026-02-05 18:46:26.857928	2026-02-05 18:46:26.857928	\N
3	20	0.00	XOF	t	2026-02-11 00:08:49.784314	2026-02-11 00:08:49.784314	\N
4	22	0.00	XOF	t	2026-02-11 00:23:03.17474	2026-02-11 00:23:03.17474	\N
5	25	0.00	XOF	t	2026-02-12 22:07:16.372881	2026-02-12 22:07:16.372881	\N
\.


--
-- Name: audit_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_logs_id_seq', 95, true);


--
-- Name: corporate_accounts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.corporate_accounts_id_seq', 1, false);


--
-- Name: deliveries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.deliveries_id_seq', 6, true);


--
-- Name: delivery_fees_breakdown_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.delivery_fees_breakdown_id_seq', 1, false);


--
-- Name: delivery_notifications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.delivery_notifications_id_seq', 10, true);


--
-- Name: delivery_proofs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.delivery_proofs_id_seq', 1, false);


--
-- Name: delivery_returns_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.delivery_returns_id_seq', 1, false);


--
-- Name: delivery_status_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.delivery_status_history_id_seq', 19, true);


--
-- Name: delivery_timeouts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.delivery_timeouts_id_seq', 1, false);


--
-- Name: delivery_tracking_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.delivery_tracking_id_seq', 4, true);


--
-- Name: driver_locations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.driver_locations_id_seq', 130, true);


--
-- Name: driver_profiles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.driver_profiles_id_seq', 14, true);


--
-- Name: idempotent_requests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.idempotent_requests_id_seq', 27, true);


--
-- Name: loyalty_programs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.loyalty_programs_id_seq', 1, false);


--
-- Name: loyalty_transactions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.loyalty_transactions_id_seq', 1, false);


--
-- Name: payment_intents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payment_intents_id_seq', 1, false);


--
-- Name: pricing_config_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.pricing_config_id_seq', 4, true);


--
-- Name: pricing_time_slots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.pricing_time_slots_id_seq', 8, true);


--
-- Name: ride_reviews_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ride_reviews_id_seq', 2, true);


--
-- Name: ride_timeouts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ride_timeouts_id_seq', 56, true);


--
-- Name: ride_tracking_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ride_tracking_id_seq', 126, true);


--
-- Name: rides_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.rides_id_seq', 78, true);


--
-- Name: transactions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.transactions_id_seq', 1, false);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 58, true);


--
-- Name: wallets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wallets_id_seq', 5, true);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: corporate_accounts corporate_accounts_company_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.corporate_accounts
    ADD CONSTRAINT corporate_accounts_company_email_key UNIQUE (company_email);


--
-- Name: corporate_accounts corporate_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.corporate_accounts
    ADD CONSTRAINT corporate_accounts_pkey PRIMARY KEY (id);


--
-- Name: deliveries deliveries_delivery_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deliveries
    ADD CONSTRAINT deliveries_delivery_code_key UNIQUE (delivery_code);


--
-- Name: deliveries deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deliveries
    ADD CONSTRAINT deliveries_pkey PRIMARY KEY (id);


--
-- Name: delivery_fees_breakdown delivery_fees_breakdown_delivery_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_fees_breakdown
    ADD CONSTRAINT delivery_fees_breakdown_delivery_id_key UNIQUE (delivery_id);


--
-- Name: delivery_fees_breakdown delivery_fees_breakdown_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_fees_breakdown
    ADD CONSTRAINT delivery_fees_breakdown_pkey PRIMARY KEY (id);


--
-- Name: delivery_notifications delivery_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_notifications
    ADD CONSTRAINT delivery_notifications_pkey PRIMARY KEY (id);


--
-- Name: delivery_proofs delivery_proofs_delivery_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_proofs
    ADD CONSTRAINT delivery_proofs_delivery_id_key UNIQUE (delivery_id);


--
-- Name: delivery_proofs delivery_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_proofs
    ADD CONSTRAINT delivery_proofs_pkey PRIMARY KEY (id);


--
-- Name: delivery_returns delivery_returns_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_returns
    ADD CONSTRAINT delivery_returns_pkey PRIMARY KEY (id);


--
-- Name: delivery_status_history delivery_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_status_history
    ADD CONSTRAINT delivery_status_history_pkey PRIMARY KEY (id);


--
-- Name: delivery_timeouts delivery_timeouts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_timeouts
    ADD CONSTRAINT delivery_timeouts_pkey PRIMARY KEY (id);


--
-- Name: delivery_tracking delivery_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_tracking
    ADD CONSTRAINT delivery_tracking_pkey PRIMARY KEY (id);


--
-- Name: driver_locations driver_locations_driver_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.driver_locations
    ADD CONSTRAINT driver_locations_driver_id_key UNIQUE (driver_id);


--
-- Name: driver_locations driver_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.driver_locations
    ADD CONSTRAINT driver_locations_pkey PRIMARY KEY (id);


--
-- Name: driver_profiles driver_profiles_license_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.driver_profiles
    ADD CONSTRAINT driver_profiles_license_number_key UNIQUE (license_number);


--
-- Name: driver_profiles driver_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.driver_profiles
    ADD CONSTRAINT driver_profiles_pkey PRIMARY KEY (id);


--
-- Name: driver_profiles driver_profiles_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.driver_profiles
    ADD CONSTRAINT driver_profiles_user_id_key UNIQUE (user_id);


--
-- Name: idempotent_requests idempotent_requests_idempotency_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.idempotent_requests
    ADD CONSTRAINT idempotent_requests_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: idempotent_requests idempotent_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.idempotent_requests
    ADD CONSTRAINT idempotent_requests_pkey PRIMARY KEY (id);


--
-- Name: loyalty_programs loyalty_programs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loyalty_programs
    ADD CONSTRAINT loyalty_programs_pkey PRIMARY KEY (id);


--
-- Name: loyalty_programs loyalty_programs_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loyalty_programs
    ADD CONSTRAINT loyalty_programs_user_id_key UNIQUE (user_id);


--
-- Name: loyalty_transactions loyalty_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loyalty_transactions
    ADD CONSTRAINT loyalty_transactions_pkey PRIMARY KEY (id);


--
-- Name: payment_intents payment_intents_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_intents
    ADD CONSTRAINT payment_intents_pkey PRIMARY KEY (id);


--
-- Name: payment_intents payment_intents_ref_command_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_intents
    ADD CONSTRAINT payment_intents_ref_command_key UNIQUE (ref_command);


--
-- Name: pricing_config pricing_config_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pricing_config
    ADD CONSTRAINT pricing_config_pkey PRIMARY KEY (id);


--
-- Name: pricing_time_slots pricing_time_slots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pricing_time_slots
    ADD CONSTRAINT pricing_time_slots_pkey PRIMARY KEY (id);


--
-- Name: ride_reviews ride_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_reviews
    ADD CONSTRAINT ride_reviews_pkey PRIMARY KEY (id);


--
-- Name: ride_timeouts ride_timeouts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_timeouts
    ADD CONSTRAINT ride_timeouts_pkey PRIMARY KEY (id);


--
-- Name: ride_timeouts ride_timeouts_ride_id_timeout_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_timeouts
    ADD CONSTRAINT ride_timeouts_ride_id_timeout_type_key UNIQUE (ride_id, timeout_type);


--
-- Name: ride_tracking ride_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_tracking
    ADD CONSTRAINT ride_tracking_pkey PRIMARY KEY (id);


--
-- Name: rides rides_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rides
    ADD CONSTRAINT rides_pkey PRIMARY KEY (id);


--
-- Name: rides rides_ride_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rides
    ADD CONSTRAINT rides_ride_code_key UNIQUE (ride_code);


--
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_user_id_key UNIQUE (user_id);


--
-- Name: idx_audit_logs_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at);


--
-- Name: idx_audit_logs_entity; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_logs_entity ON public.audit_logs USING btree (entity_type, entity_id);


--
-- Name: idx_audit_logs_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_audit_logs_user_id ON public.audit_logs USING btree (user_id);


--
-- Name: idx_corporate_accounts_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_corporate_accounts_email ON public.corporate_accounts USING btree (company_email);


--
-- Name: idx_corporate_accounts_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_corporate_accounts_status ON public.corporate_accounts USING btree (status);


--
-- Name: idx_deliveries_client_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deliveries_client_id ON public.deliveries USING btree (client_id);


--
-- Name: idx_deliveries_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deliveries_created_at ON public.deliveries USING btree (created_at);


--
-- Name: idx_deliveries_delivery_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deliveries_delivery_code ON public.deliveries USING btree (delivery_code);


--
-- Name: idx_deliveries_driver_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deliveries_driver_id ON public.deliveries USING btree (driver_id);


--
-- Name: idx_deliveries_payment_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deliveries_payment_status ON public.deliveries USING btree (payment_status);


--
-- Name: idx_deliveries_recipient_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deliveries_recipient_id ON public.deliveries USING btree (recipient_id);


--
-- Name: idx_deliveries_sender_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deliveries_sender_id ON public.deliveries USING btree (sender_id);


--
-- Name: idx_deliveries_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deliveries_status ON public.deliveries USING btree (status);


--
-- Name: idx_deliveries_status_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_deliveries_status_created ON public.deliveries USING btree (status, created_at);


--
-- Name: idx_delivery_fees_breakdown_delivery_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_fees_breakdown_delivery_id ON public.delivery_fees_breakdown USING btree (delivery_id);


--
-- Name: idx_delivery_notifications_delivery_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_notifications_delivery_id ON public.delivery_notifications USING btree (delivery_id);


--
-- Name: idx_delivery_notifications_sent_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_notifications_sent_at ON public.delivery_notifications USING btree (sent_at);


--
-- Name: idx_delivery_notifications_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_notifications_user_id ON public.delivery_notifications USING btree (user_id);


--
-- Name: idx_delivery_proofs_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_proofs_created_at ON public.delivery_proofs USING btree (created_at);


--
-- Name: idx_delivery_proofs_delivery_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_proofs_delivery_id ON public.delivery_proofs USING btree (delivery_id);


--
-- Name: idx_delivery_returns_delivery_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_returns_delivery_id ON public.delivery_returns USING btree (delivery_id);


--
-- Name: idx_delivery_returns_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_returns_status ON public.delivery_returns USING btree (status);


--
-- Name: idx_delivery_status_history_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_status_history_created_at ON public.delivery_status_history USING btree (created_at);


--
-- Name: idx_delivery_status_history_delivery_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_status_history_delivery_id ON public.delivery_status_history USING btree (delivery_id);


--
-- Name: idx_delivery_timeouts_delivery_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_timeouts_delivery_id ON public.delivery_timeouts USING btree (delivery_id);


--
-- Name: idx_delivery_timeouts_execute_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_timeouts_execute_at ON public.delivery_timeouts USING btree (execute_at);


--
-- Name: idx_delivery_timeouts_processed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_timeouts_processed ON public.delivery_timeouts USING btree (processed);


--
-- Name: idx_delivery_tracking_delivery_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_tracking_delivery_id ON public.delivery_tracking USING btree (delivery_id);


--
-- Name: idx_delivery_tracking_delivery_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_tracking_delivery_timestamp ON public.delivery_tracking USING btree (delivery_id, "timestamp");


--
-- Name: idx_delivery_tracking_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_delivery_tracking_timestamp ON public.delivery_tracking USING btree ("timestamp");


--
-- Name: idx_driver_locations_location; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_locations_location ON public.driver_locations USING gist (point((lng)::double precision, (lat)::double precision));


--
-- Name: idx_driver_locations_updated_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_locations_updated_at ON public.driver_locations USING btree (updated_at);


--
-- Name: idx_driver_locations_updated_desc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_locations_updated_desc ON public.driver_locations USING btree (updated_at DESC);


--
-- Name: idx_driver_profiles_average_rating; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_profiles_average_rating ON public.driver_profiles USING btree (average_rating DESC);


--
-- Name: idx_driver_profiles_delivery_capabilities; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_profiles_delivery_capabilities ON public.driver_profiles USING gin (delivery_capabilities);


--
-- Name: idx_driver_profiles_is_available; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_profiles_is_available ON public.driver_profiles USING btree (is_available);


--
-- Name: idx_driver_profiles_is_online; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_profiles_is_online ON public.driver_profiles USING btree (is_online);


--
-- Name: idx_driver_profiles_license_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_profiles_license_number ON public.driver_profiles USING btree (license_number);


--
-- Name: idx_driver_profiles_online_available; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_profiles_online_available ON public.driver_profiles USING btree (is_online, is_available) WHERE ((is_online = true) AND (is_available = true));


--
-- Name: idx_driver_profiles_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_profiles_user_id ON public.driver_profiles USING btree (user_id);


--
-- Name: idx_driver_profiles_vehicle_plate; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_profiles_vehicle_plate ON public.driver_profiles USING btree (vehicle_plate);


--
-- Name: idx_driver_profiles_verification_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_driver_profiles_verification_status ON public.driver_profiles USING btree (verification_status);


--
-- Name: idx_idempotent_requests_expires; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_idempotent_requests_expires ON public.idempotent_requests USING btree (expires_at);


--
-- Name: idx_idempotent_requests_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_idempotent_requests_key ON public.idempotent_requests USING btree (idempotency_key);


--
-- Name: idx_loyalty_programs_tier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_loyalty_programs_tier ON public.loyalty_programs USING btree (tier);


--
-- Name: idx_loyalty_programs_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_loyalty_programs_user_id ON public.loyalty_programs USING btree (user_id);


--
-- Name: idx_loyalty_transactions_delivery_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_loyalty_transactions_delivery_id ON public.loyalty_transactions USING btree (delivery_id);


--
-- Name: idx_loyalty_transactions_program_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_loyalty_transactions_program_id ON public.loyalty_transactions USING btree (loyalty_program_id);


--
-- Name: idx_payment_intents_ref_command; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payment_intents_ref_command ON public.payment_intents USING btree (ref_command);


--
-- Name: idx_payment_intents_reference; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payment_intents_reference ON public.payment_intents USING btree (reference_type, reference_id);


--
-- Name: idx_payment_intents_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payment_intents_status ON public.payment_intents USING btree (status);


--
-- Name: idx_payment_intents_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_payment_intents_user_id ON public.payment_intents USING btree (user_id);


--
-- Name: idx_ride_reviews_reviewed_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ride_reviews_reviewed_id ON public.ride_reviews USING btree (reviewed_id);


--
-- Name: idx_ride_reviews_ride_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ride_reviews_ride_id ON public.ride_reviews USING btree (ride_id);


--
-- Name: idx_ride_timeouts_execute_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ride_timeouts_execute_at ON public.ride_timeouts USING btree (execute_at) WHERE (processed = false);


--
-- Name: idx_ride_timeouts_ride_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ride_timeouts_ride_id ON public.ride_timeouts USING btree (ride_id);


--
-- Name: idx_ride_tracking_ride_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ride_tracking_ride_created ON public.ride_tracking USING btree (ride_id, "timestamp");


--
-- Name: idx_ride_tracking_ride_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ride_tracking_ride_id ON public.ride_tracking USING btree (ride_id);


--
-- Name: idx_ride_tracking_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ride_tracking_timestamp ON public.ride_tracking USING btree ("timestamp");


--
-- Name: idx_rides_client_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rides_client_id ON public.rides USING btree (client_id);


--
-- Name: idx_rides_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rides_created_at ON public.rides USING btree (created_at);


--
-- Name: idx_rides_driver_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rides_driver_id ON public.rides USING btree (driver_id);


--
-- Name: idx_rides_payment_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rides_payment_status ON public.rides USING btree (payment_status);


--
-- Name: idx_rides_pickup_location; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rides_pickup_location ON public.rides USING gist (point((pickup_lng)::double precision, (pickup_lat)::double precision));


--
-- Name: idx_rides_ride_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rides_ride_code ON public.rides USING btree (ride_code);


--
-- Name: idx_rides_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rides_status ON public.rides USING btree (status);


--
-- Name: idx_rides_status_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rides_status_created ON public.rides USING btree (status, created_at);


--
-- Name: idx_transactions_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transactions_created_at ON public.transactions USING btree (created_at DESC);


--
-- Name: idx_transactions_reference; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transactions_reference ON public.transactions USING btree (reference_type, reference_id);


--
-- Name: idx_transactions_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transactions_status ON public.transactions USING btree (status);


--
-- Name: idx_transactions_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transactions_type ON public.transactions USING btree (type);


--
-- Name: idx_transactions_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transactions_user_id ON public.transactions USING btree (user_id);


--
-- Name: idx_transactions_wallet_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transactions_wallet_id ON public.transactions USING btree (wallet_id);


--
-- Name: idx_users_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_created_at ON public.users USING btree (created_at);


--
-- Name: idx_users_deleted_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_deleted_at ON public.users USING btree (deleted_at) WHERE (deleted_at IS NULL);


--
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_email ON public.users USING btree (email);


--
-- Name: idx_users_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_phone ON public.users USING btree (phone);


--
-- Name: idx_users_role; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_role ON public.users USING btree (role);


--
-- Name: idx_users_role_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_role_status ON public.users USING btree (role, status);


--
-- Name: idx_users_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_status ON public.users USING btree (status);


--
-- Name: idx_wallets_is_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallets_is_active ON public.wallets USING btree (is_active);


--
-- Name: idx_wallets_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallets_user_id ON public.wallets USING btree (user_id);


--
-- Name: rides trigger_generate_ride_code; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_generate_ride_code BEFORE INSERT ON public.rides FOR EACH ROW EXECUTE FUNCTION public.generate_ride_code();


--
-- Name: driver_profiles trigger_update_driver_last_active; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_driver_last_active BEFORE UPDATE OF is_online ON public.driver_profiles FOR EACH ROW WHEN (((new.is_online = true) AND (old.is_online = false))) EXECUTE FUNCTION public.update_driver_last_active();


--
-- Name: driver_profiles trigger_update_driver_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_driver_profiles_updated_at BEFORE UPDATE ON public.driver_profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: pricing_config trigger_update_pricing_config_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_pricing_config_updated_at BEFORE UPDATE ON public.pricing_config FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: users trigger_update_users_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: transactions trigger_update_wallet_last_transaction; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_wallet_last_transaction AFTER INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.update_wallet_last_transaction();


--
-- Name: wallets trigger_update_wallets_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_wallets_updated_at BEFORE UPDATE ON public.wallets FOR EACH ROW EXECUTE FUNCTION public.update_wallet_updated_at();


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: deliveries deliveries_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deliveries
    ADD CONSTRAINT deliveries_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: deliveries deliveries_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deliveries
    ADD CONSTRAINT deliveries_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: deliveries deliveries_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deliveries
    ADD CONSTRAINT deliveries_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: deliveries deliveries_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deliveries
    ADD CONSTRAINT deliveries_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: delivery_fees_breakdown delivery_fees_breakdown_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_fees_breakdown
    ADD CONSTRAINT delivery_fees_breakdown_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE;


--
-- Name: delivery_notifications delivery_notifications_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_notifications
    ADD CONSTRAINT delivery_notifications_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE;


--
-- Name: delivery_notifications delivery_notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_notifications
    ADD CONSTRAINT delivery_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: delivery_proofs delivery_proofs_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_proofs
    ADD CONSTRAINT delivery_proofs_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE;


--
-- Name: delivery_returns delivery_returns_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_returns
    ADD CONSTRAINT delivery_returns_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE;


--
-- Name: delivery_returns delivery_returns_retry_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_returns
    ADD CONSTRAINT delivery_returns_retry_delivery_id_fkey FOREIGN KEY (retry_delivery_id) REFERENCES public.deliveries(id);


--
-- Name: delivery_status_history delivery_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_status_history
    ADD CONSTRAINT delivery_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);


--
-- Name: delivery_status_history delivery_status_history_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_status_history
    ADD CONSTRAINT delivery_status_history_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE;


--
-- Name: delivery_timeouts delivery_timeouts_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_timeouts
    ADD CONSTRAINT delivery_timeouts_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE;


--
-- Name: delivery_tracking delivery_tracking_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.delivery_tracking
    ADD CONSTRAINT delivery_tracking_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE;


--
-- Name: driver_locations driver_locations_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.driver_locations
    ADD CONSTRAINT driver_locations_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: driver_profiles driver_profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.driver_profiles
    ADD CONSTRAINT driver_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: idempotent_requests idempotent_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.idempotent_requests
    ADD CONSTRAINT idempotent_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: loyalty_programs loyalty_programs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loyalty_programs
    ADD CONSTRAINT loyalty_programs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: loyalty_transactions loyalty_transactions_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loyalty_transactions
    ADD CONSTRAINT loyalty_transactions_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id);


--
-- Name: loyalty_transactions loyalty_transactions_loyalty_program_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.loyalty_transactions
    ADD CONSTRAINT loyalty_transactions_loyalty_program_id_fkey FOREIGN KEY (loyalty_program_id) REFERENCES public.loyalty_programs(id) ON DELETE CASCADE;


--
-- Name: payment_intents payment_intents_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_intents
    ADD CONSTRAINT payment_intents_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: pricing_time_slots pricing_time_slots_pricing_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pricing_time_slots
    ADD CONSTRAINT pricing_time_slots_pricing_config_id_fkey FOREIGN KEY (pricing_config_id) REFERENCES public.pricing_config(id) ON DELETE CASCADE;


--
-- Name: ride_reviews ride_reviews_reviewed_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_reviews
    ADD CONSTRAINT ride_reviews_reviewed_id_fkey FOREIGN KEY (reviewed_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: ride_reviews ride_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_reviews
    ADD CONSTRAINT ride_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: ride_reviews ride_reviews_ride_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_reviews
    ADD CONSTRAINT ride_reviews_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE CASCADE;


--
-- Name: ride_timeouts ride_timeouts_ride_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_timeouts
    ADD CONSTRAINT ride_timeouts_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE CASCADE;


--
-- Name: ride_tracking ride_tracking_ride_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ride_tracking
    ADD CONSTRAINT ride_tracking_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES public.rides(id) ON DELETE CASCADE;


--
-- Name: rides rides_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rides
    ADD CONSTRAINT rides_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: rides rides_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rides
    ADD CONSTRAINT rides_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: transactions transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: transactions transactions_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE RESTRICT;


--
-- Name: wallets wallets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict 7IyN0ofaP8JA10eNnzgctn0hiJvBfNbZo8g935zA4u0kNC9xbzNqDMpVW38ttSI

