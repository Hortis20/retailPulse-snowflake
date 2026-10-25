-- =============================================================================
-- RetailPulse – 05_tests.sql
-- Requêtes de contrôle et d'exploration, étape par étape.
-- Version améliorée de RetailPulseWorkSheet.sql (feuille de travail d'origine) :
-- les tests y sont structurés par étape pour s'y retrouver rapidement.
-- Cette feuille ne modifie AUCUNE donnée : elle peut être rejouée à tout moment.
-- Les créations d'objets sont dans les scripts 00 à 04.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE RETAIL_WH;

-- =============================================================================
-- ÉTAPE 1 – INFRASTRUCTURE ET SÉCURITÉ
-- =============================================================================

-- Contexte de session
SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_DATABASE();

-- Warehouse : état, taille, arrêt automatique, propriétaire
SHOW WAREHOUSES LIKE 'RETAIL_WH';

-- Schémas : propriétaire attendu = SYSADMIN
SHOW SCHEMAS IN DATABASE RETAIL_DB;

-- Droits du rôle analyste (actuels et sur les tables futures)
SHOW GRANTS TO ROLE ANALYST_ROLE;
SHOW FUTURE GRANTS IN SCHEMA RETAIL_DB.ANALYTICS;

-- Test du rôle analyste : rôles secondaires DÉSACTIVÉS, sinon on teste la somme de tous ses rôles
USE ROLE ANALYST_ROLE;
USE SECONDARY ROLES NONE;
SELECT CURRENT_ROLE(), CURRENT_SECONDARY_ROLES();               -- attendu : ANALYST_ROLE, liste vide

SELECT COUNT(*) FROM RETAIL_DB.ANALYTICS.FACT_SALES;             -- attendu : autorisé
SELECT COUNT(*) FROM RETAIL_DB.STAGING.RAW_TRANSACTIONS;         -- attendu : erreur (aucun droit sur STAGING)
DELETE FROM RETAIL_DB.ANALYTICS.FACT_SALES WHERE 1 = 0;          -- attendu : erreur de privilège
                                                                 -- (WHERE 1 = 0 : ne supprimerait rien même si autorisé)
USE SECONDARY ROLES ALL;
USE ROLE SYSADMIN;

-- =============================================================================
-- ÉTAPE 2 – INGESTION
-- =============================================================================

-- Fichiers présents dans le stage
LIST @RETAIL_DB.STAGING.RAW_STAGE;

-- Lecture directe des fichiers, sans les charger
SELECT METADATA$FILENAME,          -- le fichier d'où vient la ligne
       METADATA$FILE_ROW_NUMBER,   -- le numéro de la ligne dans ce fichier
       $1
FROM @RETAIL_DB.STAGING.RAW_STAGE/lot_01/
LIMIT 5;

-- Historique des chargements (la mémoire du COPY INTO)
SELECT file_name, status, row_count, row_parsed, first_error_message, last_load_time
FROM TABLE(RETAIL_DB.INFORMATION_SCHEMA.COPY_HISTORY(
     TABLE_NAME => 'RETAIL_DB.STAGING.RAW_TRANSACTIONS',
     START_TIME => DATEADD('day', -14, CURRENT_TIMESTAMP())
   ))
ORDER BY last_load_time, file_name;

-- Lignes chargées par fichier (attendu : 300 par fichier du lot 1, 150 pour le lot 2)
SELECT source_file, COUNT(*) AS nb_lignes
FROM RETAIL_DB.STAGING.RAW_TRANSACTIONS
GROUP BY source_file
ORDER BY source_file;

-- =============================================================================
-- ÉTAPE 3 – TRANSFORMATION
-- =============================================================================

-- Exploration : lecture par chemin dans le VARIANT
SELECT
  raw_data:transaction_id                        AS transaction_id_brut,   -- VARIANT (avec guillemets)
  raw_data:transaction_id::STRING                AS transaction_id,        -- STRING
  raw_data:customer_info.id::STRING              AS customer_id,
  raw_data:customer_info.country::STRING         AS country,
  raw_data:customer_info.email::STRING           AS email,
  raw_data:total_amount::NUMBER(10,2)            AS total_amount,
  raw_data:event_timestamp::TIMESTAMP_NTZ        AS event_timestamp,
  raw_data:items[0].sku::STRING                  AS premier_sku,
  raw_data:items[1].sku::STRING                  AS second_sku,            -- NULL si un seul article
  ARRAY_SIZE(raw_data:items)                     AS nb_lignes_articles,
  raw_data:customer_info.COUNTRY::STRING         AS pays_mauvaise_casse    -- NULL : clés sensibles à la casse
FROM RETAIL_DB.STAGING.RAW_TRANSACTIONS
ORDER BY transaction_id
LIMIT 10;

-- Exploration : une ligne par article avec LATERAL FLATTEN
SELECT
  t.raw_data:transaction_id::STRING    AS transaction_id,
  f.index                              AS position,
  f.value                              AS article_brut,
  f.value:sku::STRING                  AS sku,
  f.value:quantity::NUMBER             AS quantity,
  f.value:unit_price::NUMBER(10,2)     AS unit_price
FROM RETAIL_DB.STAGING.RAW_TRANSACTIONS t,
     LATERAL FLATTEN(INPUT => t.raw_data:items) f
WHERE t.raw_data:transaction_id::STRING = 'TX-000001';

-- Contrôle : montant recalculé à partir des articles = total_amount du JSON
-- (attendu : aucune ligne)
SELECT
  t.raw_data:transaction_id::STRING                                   AS transaction_id,
  COUNT(*)                                                            AS nb_lignes_articles,
  SUM(f.value:quantity::NUMBER)                                       AS nb_articles,
  SUM(f.value:quantity::NUMBER * f.value:unit_price::NUMBER(10,2))    AS montant_recalcule,
  montant_recalcule - t.raw_data:total_amount::NUMBER(10,2)           AS diff_total_amount
FROM RETAIL_DB.STAGING.RAW_TRANSACTIONS t,
     LATERAL FLATTEN(INPUT => t.raw_data:items) f
GROUP BY transaction_id, t.raw_data:total_amount::NUMBER(10,2)
HAVING diff_total_amount <> 0;

-- Test du piège du tableau vide : sans OUTER la commande disparaît, avec OUTER elle est gardée
WITH test AS (
  SELECT PARSE_JSON('{"transaction_id": "TX-TEST", "items": []}') AS raw_data
)
SELECT 'sans OUTER' AS cas, COUNT(*) AS nb_lignes
FROM test t, LATERAL FLATTEN(INPUT => t.raw_data:items) f
UNION ALL
SELECT 'avec OUTER', COUNT(*)
FROM test t, LATERAL FLATTEN(INPUT => t.raw_data:items, OUTER => TRUE) f;

-- Rapprochement : totaux de FACT_SALES
-- attendu après le lot 1 : 900 / 900 / 2 253 / 3 147 / 178 191,30
-- attendu après le lot 2 : 1 050 / 1 050 / 2 628 / 3 645 / 204 909,10
SELECT
  COUNT(*)                           AS nb_commandes,
  COUNT(DISTINCT transaction_id)     AS nb_commandes_distinctes,
  SUM(nb_types_produit)              AS total_lignes_articles,
  SUM(nb_articles)                   AS total_articles,
  SUM(total_amount)                  AS chiffre_affaires
FROM RETAIL_DB.ANALYTICS.FACT_SALES;

-- =============================================================================
-- ÉTAPE 4 – STREAM ET TASK
-- =============================================================================

-- Contenu du stream (attendu après passage de la task : 0)
SELECT COUNT(*) FROM RETAIL_DB.STAGING.RAW_TRANSACTIONS_STREAM;
SELECT SYSTEM$STREAM_HAS_DATA('RETAIL_DB.STAGING.RAW_TRANSACTIONS_STREAM');

-- État de la task (colonne state : started = active, suspended = arrêtée)
SHOW TASKS IN SCHEMA RETAIL_DB.STAGING;

-- Historique des exécutions de la task
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(RETAIL_DB.INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'TSK_LOAD_FACT_SALES'))
ORDER BY scheduled_time DESC;

-- Vagues d'insertion dans FACT_SALES (attendu : 900 puis 150)
SELECT DATE_TRUNC('minute', inserted_at) AS insertion, COUNT(*) AS nb_commandes
FROM RETAIL_DB.ANALYTICS.FACT_SALES
GROUP BY 1
ORDER BY 1;

-- =============================================================================
-- ÉTAPE 5 – TIME TRAVEL ET CLONE
-- =============================================================================

-- Indépendance du clone (attendu : prod 1 050, dev 527)
SELECT 'prod' AS env, COUNT(*) AS nb, SUM(total_amount) AS ca FROM RETAIL_DB.ANALYTICS.FACT_SALES
UNION ALL
SELECT 'dev', COUNT(*), SUM(total_amount) FROM RETAIL_DB_DEV.ANALYTICS.FACT_SALES;

-- Tasks du clone (attendu : suspended)
SHOW TASKS IN DATABASE RETAIL_DB_DEV;

-- Audit : historique des requêtes qui ont modifié FACT_SALES
SELECT query_id, query_type, query_text, role_name, execution_status, start_time
FROM TABLE(RETAIL_DB.INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 1000))
WHERE query_text ILIKE '%ANALYTICS.FACT_SALES%'
  AND query_type IN ('INSERT', 'UPDATE', 'DELETE')
ORDER BY start_time;
