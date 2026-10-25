-- =============================================================================
-- RetailPulse – 03_automation.sql
-- Étape 4 : CDC (stream) et automatisation (task)
--   - stream APPEND_ONLY sur la table brute : uniquement les nouvelles lignes insérées
--   - task horaire qui insère le contenu du stream dans FACT_SALES
--   - démonstration avec l'arrivée du lot 2
-- Prérequis : 02_transformation.sql (le stream doit être créé APRÈS le chargement initial)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Droit d'exécuter des tasks (seul ACCOUNTADMIN peut l'accorder)
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
USE WAREHOUSE RETAIL_WH;

-- -----------------------------------------------------------------------------
-- 2. Stream : ne contient que les insertions postérieures à sa création
-- -----------------------------------------------------------------------------
CREATE STREAM IF NOT EXISTS RETAIL_DB.STAGING.RAW_TRANSACTIONS_STREAM
  ON TABLE RETAIL_DB.STAGING.RAW_TRANSACTIONS
  APPEND_ONLY = TRUE;

-- -----------------------------------------------------------------------------
-- 3. Task : toutes les heures, seulement si le stream contient des données
--    (sinon l'exécution est sautée sans démarrer le warehouse)
--    Le stream est consommé par l'INSERT : chaque ligne n'est traitée qu'une fois.
-- -----------------------------------------------------------------------------
CREATE TASK IF NOT EXISTS RETAIL_DB.STAGING.TSK_LOAD_FACT_SALES
  WAREHOUSE = RETAIL_WH
  SCHEDULE  = '60 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('RETAIL_DB.STAGING.RAW_TRANSACTIONS_STREAM')
AS
  INSERT INTO RETAIL_DB.ANALYTICS.FACT_SALES
    (transaction_id, customer_id, country, event_timestamp,
     nb_types_produit, nb_articles, total_amount)
  SELECT
    t.raw_data:transaction_id::STRING                  AS transaction_id,
    t.raw_data:customer_info.id::STRING                AS customer_id,
    t.raw_data:customer_info.country::STRING           AS country,
    t.raw_data:event_timestamp::TIMESTAMP_NTZ          AS event_timestamp,
    COUNT(DISTINCT f.value:sku)                        AS nb_types_produit,
    COALESCE(SUM(f.value:quantity::NUMBER), 0)         AS nb_articles,
    t.raw_data:total_amount::NUMBER(10,2)              AS total_amount
  FROM RETAIL_DB.STAGING.RAW_TRANSACTIONS_STREAM t,
       LATERAL FLATTEN(INPUT => t.raw_data:items, OUTER => TRUE) f
  WHERE t.METADATA$ACTION = 'INSERT'
  GROUP BY transaction_id, customer_id, country, event_timestamp, total_amount;

-- Une task est créée suspendue : activation
ALTER TASK RETAIL_DB.STAGING.TSK_LOAD_FACT_SALES RESUME;

-- -----------------------------------------------------------------------------
-- 4. Démonstration : arrivée du lot 2
--    Déposer sales_2026_10_v2.json dans le stage, chemin lot_02, puis :
-- -----------------------------------------------------------------------------
COPY INTO RETAIL_DB.STAGING.RAW_TRANSACTIONS (raw_data, source_file, file_row_num)
FROM (
  SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
  FROM @RETAIL_DB.STAGING.RAW_STAGE/lot_02/
);

-- Le stream contient maintenant uniquement le lot 2 (150 lignes)
SELECT COUNT(*) AS lignes_en_attente FROM RETAIL_DB.STAGING.RAW_TRANSACTIONS_STREAM;

-- Exécution immédiate, sans attendre l'heure planifiée
EXECUTE TASK RETAIL_DB.STAGING.TSK_LOAD_FACT_SALES;

-- Suivi de l'exécution (attendre state = SUCCEEDED)
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(RETAIL_DB.INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'TSK_LOAD_FACT_SALES'))
ORDER BY scheduled_time DESC;
