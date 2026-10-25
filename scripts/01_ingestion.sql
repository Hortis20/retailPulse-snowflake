-- =============================================================================
-- RetailPulse – 01_ingestion.sql
-- Étape 2 : ingestion des fichiers JSON
--   - format de fichier JSON Lines, stage interne, table brute VARIANT
--   - chargement du lot 1 (juillet -> septembre 2026) avec COPY INTO
-- Prérequis : 00_setup.sql
-- Les fichiers du lot 1 sont déposés dans le stage via Snowsight
-- (Ingestion > Add Data > Load files into a Stage), chemin lot_01.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE RETAIL_WH;

-- -----------------------------------------------------------------------------
-- 1. Format de fichier : JSON Lines (un objet JSON indépendant par ligne)
-- -----------------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS RETAIL_DB.STAGING.FF_JSON
  TYPE       = JSON
  MULTI_LINE = FALSE   -- chaque ligne est lue indépendamment : une ligne tronquée n'avale pas la suivante
  COMMENT    = 'JSON Lines des événements de vente';

-- -----------------------------------------------------------------------------
-- 2. Stage interne (sans URL = interne, stockage géré par Snowflake)
-- -----------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS RETAIL_DB.STAGING.RAW_STAGE
  FILE_FORMAT = RETAIL_DB.STAGING.FF_JSON
  DIRECTORY   = (ENABLE = TRUE)              -- index des fichiers, utilisé par Snowsight
  ENCRYPTION  = (TYPE = 'SNOWFLAKE_SSE')     -- chiffrement côté serveur (non modifiable après création)
  COMMENT     = 'Fichiers JSON des ventes RetailPulse';

-- -----------------------------------------------------------------------------
-- 3. Table brute : le JSON tel que reçu + colonnes de lignage
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RETAIL_DB.STAGING.RAW_TRANSACTIONS (
  raw_data      VARIANT,                                    -- l'événement JSON complet
  source_file   STRING,                                     -- fichier d'origine
  file_row_num  NUMBER,                                     -- ligne dans ce fichier
  loaded_at     TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- date de chargement
);

-- -----------------------------------------------------------------------------
-- 4. Chargement du lot 1
--    COPY INTO mémorise les fichiers déjà chargés (64 jours) : relancé, il les ignore.
-- -----------------------------------------------------------------------------
COPY INTO RETAIL_DB.STAGING.RAW_TRANSACTIONS (raw_data, source_file, file_row_num)
FROM (
  SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
  FROM @RETAIL_DB.STAGING.RAW_STAGE/lot_01/
);
