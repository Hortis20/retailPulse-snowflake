-- =============================================================================
-- RetailPulse – 00_setup.sql
-- Étape 1 : infrastructure et sécurité
--   - warehouse RETAIL_WH, base RETAIL_DB, schémas STAGING et ANALYTICS
--   - rôle ANALYST_ROLE en lecture seule sur ANALYTICS
-- À exécuter EN ENTIER, depuis la première ligne (le USE ROLE fixe le propriétaire).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Objets : créés avec SYSADMIN, qui en devient propriétaire
-- -----------------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS RETAIL_WH
  WAREHOUSE_SIZE      = 'XSMALL'   -- 1 crédit/heure : largement suffisant pour ce volume
  AUTO_SUSPEND        = 60         -- s'éteint après 60 s d'inactivité (facturation minimale de 60 s)
  AUTO_RESUME         = TRUE       -- se rallume seul à la requête suivante (indispensable pour la task)
  INITIALLY_SUSPENDED = TRUE       -- ne consomme rien à la création
  COMMENT             = 'Warehouse du projet RetailPulse';

USE WAREHOUSE RETAIL_WH;

CREATE DATABASE IF NOT EXISTS RETAIL_DB;
CREATE SCHEMA   IF NOT EXISTS RETAIL_DB.STAGING;    -- données brutes, jamais modifiées
CREATE SCHEMA   IF NOT EXISTS RETAIL_DB.ANALYTICS;  -- données transformées, exposées aux analystes

-- -----------------------------------------------------------------------------
-- 2. Sécurité : gérée avec SECURITYADMIN
-- -----------------------------------------------------------------------------
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS ANALYST_ROLE
  COMMENT = 'Lecture seule sur RETAIL_DB.ANALYTICS';

GRANT ROLE ANALYST_ROLE TO ROLE SYSADMIN;   -- rattachement à la hiérarchie des rôles

-- La chaîne d'accès : warehouse -> base -> schéma
GRANT USAGE ON WAREHOUSE RETAIL_WH           TO ROLE ANALYST_ROLE;
GRANT USAGE ON DATABASE  RETAIL_DB           TO ROLE ANALYST_ROLE;
GRANT USAGE ON SCHEMA    RETAIL_DB.ANALYTICS TO ROLE ANALYST_ROLE;

-- La lecture : tables existantes ET futures (FACT_SALES est créée plus tard)
GRANT SELECT ON ALL TABLES    IN SCHEMA RETAIL_DB.ANALYTICS TO ROLE ANALYST_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RETAIL_DB.ANALYTICS TO ROLE ANALYST_ROLE;

-- Attribution du rôle à l'utilisateur : nom exact renvoyé par SELECT CURRENT_USER();
-- (guillemets obligatoires si le nom contient un caractère spécial, comme un point)
GRANT ROLE ANALYST_ROLE TO USER "<NOM_UTILISATEUR>";

USE ROLE SYSADMIN;
