-- =============================================================
-- BanqueParle -- schema Neon (PostgreSQL)
--
-- A executer une seule fois sur la base Neon, via la console SQL
-- Neon ou psql. Ce fichier definit toute la logique metier des
-- virements directement dans la base, de sorte que l'application
-- mobile n'a jamais besoin d'executer de UPDATE directement sur
-- les soldes : elle appelle uniquement des fonctions controlees.
--
-- Principe de securite : un role client ne peut qu'executer les
-- fonctions ci-dessous. Il n'a aucun privilege direct SELECT,
-- INSERT, UPDATE ou DELETE sur les tables. Meme avec son mot de
-- passe entre de mauvaises mains, un attaquant ne peut agir que
-- sur le compte associe a ce role precis, jamais sur un autre.
-- =============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -------------------------------------------------------------
-- Tables
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounts (
  account_number text PRIMARY KEY,
  owner_name     text NOT NULL,
  balance        numeric(14,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  pg_role_name   text UNIQUE NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transactions (
  id           bigserial PRIMARY KEY,
  from_account text NOT NULL REFERENCES accounts(account_number),
  to_account   text NOT NULL REFERENCES accounts(account_number),
  amount       numeric(14,2) NOT NULL CHECK (amount > 0),
  created_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- Un role client peut uniquement consulter sa propre ligne de compte
-- et ses propres transactions (en lecture, via les fonctions ci-dessous
-- ou une consultation directe SELECT si vous l'autorisez plus tard).
-- CREATE POLICY ne supporte pas IF NOT EXISTS : on supprime d'abord
-- toute politique existante du meme nom, pour que ce script reste
-- rejouable sans erreur.
DROP POLICY IF EXISTS account_self_select ON accounts;
CREATE POLICY account_self_select ON accounts
  FOR SELECT
  USING (pg_role_name = current_user);

DROP POLICY IF EXISTS tx_self_select ON transactions;
CREATE POLICY tx_self_select ON transactions
  FOR SELECT
  USING (
    from_account = (SELECT account_number FROM accounts WHERE pg_role_name = current_user)
    OR to_account = (SELECT account_number FROM accounts WHERE pg_role_name = current_user)
  );

-- -------------------------------------------------------------
-- Role de groupe accorde a chaque client (regroupe les permissions
-- d'execution des fonctions ; aucun privilege sur les tables).
-- -------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'customer_base') THEN
    CREATE ROLE customer_base NOLOGIN;
  END IF;
END
$$;

GRANT SELECT ON accounts TO customer_base;
GRANT SELECT ON transactions TO customer_base;

-- -------------------------------------------------------------
-- Role "provisionneur" : utilise uniquement par l'application au
-- moment de l'enrolement, pour creer un nouveau role client. Ce
-- role n'a AUCUN privilege sur les tables ; seulement le droit
-- d'executer create_customer_role(), qui est SECURITY DEFINER et
-- fait le travail avec les privileges du proprietaire des tables.
--
-- Definir son mot de passe directement dans la console Neon (onglet
-- Roles), jamais dans ce fichier ni dans le depot Git.
-- -------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'banqueparle_provisioner') THEN
    CREATE ROLE banqueparle_provisioner LOGIN PASSWORD 'A_CHANGER_DANS_LA_CONSOLE_NEON';
  END IF;
END
$$;

-- -------------------------------------------------------------
-- Fonction de provisionnement : appelee une seule fois par compte,
-- lors de l'enrolement. Cree un role Postgres dedie a faibles
-- privileges et renvoie son mot de passe genere aleatoirement.
-- Ce mot de passe n'est jamais stocke en clair cote serveur : seul
-- l'appelant (l'application, a cet instant precis) le recoit.
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION create_customer_role(p_account_number text, p_owner_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_name text := 'cust_' || regexp_replace(p_account_number, '[^a-zA-Z0-9]', '', 'g');
  v_password  text := encode(gen_random_bytes(24), 'base64');
BEGIN
  IF EXISTS (SELECT 1 FROM accounts WHERE account_number = p_account_number) THEN
    RAISE EXCEPTION 'ACCOUNT_ALREADY_EXISTS';
  END IF;

  EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', v_role_name, v_password);
  EXECUTE format('GRANT customer_base TO %I', v_role_name);

  INSERT INTO accounts(account_number, owner_name, balance, pg_role_name)
  VALUES (p_account_number, p_owner_name, 0, v_role_name);

  RETURN v_password;
END;
$$;

REVOKE ALL ON FUNCTION create_customer_role(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_customer_role(text, text) TO banqueparle_provisioner;

-- -------------------------------------------------------------
-- Fonction de virement : seule porte d'entree pour deplacer de
-- l'argent. Verrouille la ligne de l'emetteur (FOR UPDATE) pour
-- empecher deux virements simultanes de depasser le solde
-- disponible (protection contre la double depense), verifie le
-- solde, puis debite et credite dans une seule transaction
-- atomique (tout reussit, ou rien n'est applique).
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION transfer_funds(p_to_account text, p_amount numeric)
RETURNS TABLE(new_balance numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from_account text;
BEGIN
  SELECT account_number INTO v_from_account
  FROM accounts WHERE pg_role_name = session_user;

  IF v_from_account IS NULL THEN
    RAISE EXCEPTION 'CALLER_ACCOUNT_NOT_FOUND';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT';
  END IF;
  IF v_from_account = p_to_account THEN
    RAISE EXCEPTION 'SAME_ACCOUNT';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM accounts WHERE account_number = p_to_account) THEN
    RAISE EXCEPTION 'RECIPIENT_NOT_FOUND';
  END IF;

  -- Verrouille les deux comptes dans un ordre fixe (ordre alphabetique
  -- du numero de compte). Sans cet ordre, deux virements croises
  -- simultanes (A vers B et B vers A) pourraient se bloquer
  -- mutuellement et l'un serait annule par Postgres.
  PERFORM 1 FROM accounts
  WHERE account_number IN (v_from_account, p_to_account)
  ORDER BY account_number
  FOR UPDATE;
  IF (SELECT balance FROM accounts WHERE account_number = v_from_account) < p_amount THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE';
  END IF;

  UPDATE accounts SET balance = balance - p_amount WHERE account_number = v_from_account;
  UPDATE accounts SET balance = balance + p_amount WHERE account_number = p_to_account;

  INSERT INTO transactions(from_account, to_account, amount)
  VALUES (v_from_account, p_to_account, p_amount);

  RETURN QUERY SELECT balance FROM accounts WHERE account_number = v_from_account;
END;
$$;

REVOKE ALL ON FUNCTION transfer_funds(text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION transfer_funds(text, numeric) TO customer_base;

-- -------------------------------------------------------------
-- Fonction de consultation du solde (pratique pour une future
-- commande vocale "consulter le solde").
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_balance()
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance numeric;
BEGIN
  SELECT balance INTO v_balance FROM accounts WHERE pg_role_name = session_user;
  IF v_balance IS NULL THEN
    RAISE EXCEPTION 'CALLER_ACCOUNT_NOT_FOUND';
  END IF;
  RETURN v_balance;
END;
$$;

REVOKE ALL ON FUNCTION get_balance() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_balance() TO customer_base;

-- -----------------------------------------------------------------------
-- NOTE SECURITE IMPORTANTE : dans une fonction SECURITY DEFINER,
-- current_user designe le PROPRIETAIRE de la fonction, pas l'appelant.
-- Pour identifier le client connecte il faut session_user (le role
-- avec lequel la connexion a ete ouverte). Toutes les fonctions
-- ci-dessus et ci-dessous utilisent donc session_user.
-- -----------------------------------------------------------------------

-- -----------------------------------------------------------------------
-- Historique : les dernieres operations du client connecte (envoyees ou
-- recues), de la plus recente a la plus ancienne. Les valeurs sont
-- converties en types simples (float8, text) pour que le client mobile
-- n'ait aucun type PostgreSQL special a decoder.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_history(p_limit integer DEFAULT 3)
RETURNS TABLE (
  tx_direction text,
  other_account text,
  other_name text,
  tx_amount double precision,
  tx_epoch double precision
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH me AS (
    SELECT account_number FROM accounts WHERE pg_role_name = session_user
  )
  SELECT
    CASE WHEN t.from_account = (SELECT account_number FROM me)
         THEN 'sent' ELSE 'received' END,
    o.account_number,
    o.owner_name,
    t.amount::double precision,
    extract(epoch FROM t.created_at)::double precision
  FROM transactions t
  JOIN accounts o
    ON o.account_number = CASE
         WHEN t.from_account = (SELECT account_number FROM me)
         THEN t.to_account ELSE t.from_account END
  WHERE t.from_account = (SELECT account_number FROM me)
     OR t.to_account = (SELECT account_number FROM me)
  ORDER BY t.created_at DESC, t.id DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 10);
$$;

REVOKE ALL ON FUNCTION get_history FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_history TO customer_base;

-- -----------------------------------------------------------------------
-- Code a usage unique (OTP). Genere COTE BASE DE DONNEES (jamais sur le
-- telephone) avec un generateur cryptographique, valable 5 minutes,
-- stocke uniquement sous forme de hachage, invalide des qu'un nouveau
-- code est demande. Limite a 5 codes par periode de 10 minutes.
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otp_codes (
  id bigserial PRIMARY KEY,
  account_number text NOT NULL REFERENCES accounts (account_number),
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  used boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_otp_account ON otp_codes (account_number, created_at);

-- RLS active sans aucune politique : les roles clients ne peuvent ni lire
-- ni ecrire cette table. Seules les fonctions ci-dessous y accedent.
ALTER TABLE otp_codes ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION generate_otp()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account text;
  v_recent integer;
  v_number bigint;
  v_code text;
BEGIN
  SELECT account_number INTO v_account
  FROM accounts WHERE pg_role_name = session_user;
  IF v_account IS NULL THEN
    RAISE EXCEPTION 'CALLER_ACCOUNT_NOT_FOUND';
  END IF;

  SELECT count(*) INTO v_recent FROM otp_codes
  WHERE account_number = v_account AND created_at > now() - interval '10 minutes';
  IF v_recent >= 5 THEN
    RAISE EXCEPTION 'OTP_RATE_LIMIT';
  END IF;

  UPDATE otp_codes SET used = true
  WHERE account_number = v_account AND used = false;

  v_number := abs((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32))::bigint) % 1000000;
  v_code := lpad(v_number::text, 6, '0');

  INSERT INTO otp_codes (account_number, code_hash, expires_at)
  VALUES (v_account, encode(digest(v_code, 'sha256'), 'hex'), now() + interval '5 minutes');

  RETURN v_code;
END;
$$;

REVOKE ALL ON FUNCTION generate_otp FROM PUBLIC;
GRANT EXECUTE ON FUNCTION generate_otp TO customer_base;

-- Verification d'un code, destinee au systeme qui le recoit (par exemple
-- un service de la banque). Le code est consomme : un second essai avec
-- le meme code echoue. Ce droit n'est PAS donne aux clients : il faut
-- l'accorder explicitement au role du service verificateur, par exemple
--   GRANT banqueparle_otp_verifier TO mon_service_banque;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'banqueparle_otp_verifier') THEN
    CREATE ROLE banqueparle_otp_verifier NOLOGIN;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION verify_otp(p_account text, p_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id bigint;
BEGIN
  SELECT id INTO v_id FROM otp_codes
  WHERE account_number = p_account
    AND used = false
    AND expires_at > now()
    AND code_hash = encode(digest(p_code, 'sha256'), 'hex')
  ORDER BY id DESC
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NULL THEN
    RETURN false;
  END IF;

  UPDATE otp_codes SET used = true WHERE id = v_id;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION verify_otp FROM PUBLIC;
GRANT EXECUTE ON FUNCTION verify_otp TO banqueparle_otp_verifier;

-- -----------------------------------------------------------------------
-- Mise a jour du nom du titulaire (gestion du profil). Le nom apparait
-- dans l'historique des correspondants, il doit donc rester coherent.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_owner_name(p_name text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_name IS NULL OR length(trim(p_name)) < 2 OR length(p_name) > 100 THEN
    RAISE EXCEPTION 'INVALID_NAME';
  END IF;
  UPDATE accounts SET owner_name = trim(p_name) WHERE pg_role_name = session_user;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CALLER_ACCOUNT_NOT_FOUND';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION update_owner_name FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_owner_name TO customer_base;

-- -----------------------------------------------------------------------
-- Profil complet dans la base.
--
-- Le nom est deja stocke (accounts.owner_name). Le telephone, la date de
-- naissance et le type de compte etaient uniquement sur le telephone ; ils
-- sont maintenant dans la base pour etre lus en ligne et synchronises. Les
-- anciens comptes ont ces colonnes vides : l'application les renseigne a
-- sa premiere synchronisation.
-- -----------------------------------------------------------------------
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS phone_number text;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS birth_date text;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS account_type text;

CREATE OR REPLACE FUNCTION get_profile()
RETURNS TABLE (
  p_account_number text,
  p_owner_name text,
  p_phone_number text,
  p_birth_date text,
  p_account_type text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT account_number, owner_name, phone_number, birth_date, account_type
  FROM accounts
  WHERE pg_role_name = session_user;
$$;

REVOKE ALL ON FUNCTION get_profile FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_profile TO customer_base;

CREATE OR REPLACE FUNCTION update_profile(
  p_phone text,
  p_birth text,
  p_type text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF length(coalesce(p_phone, '')) > 40
     OR length(coalesce(p_birth, '')) > 60
     OR length(coalesce(p_type, '')) > 60 THEN
    RAISE EXCEPTION 'INVALID_PROFILE';
  END IF;

  UPDATE accounts
  SET phone_number = nullif(trim(p_phone), ''),
      birth_date = nullif(trim(p_birth), ''),
      account_type = nullif(trim(p_type), '')
  WHERE pg_role_name = session_user;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CALLER_ACCOUNT_NOT_FOUND';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION update_profile FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_profile TO customer_base;
