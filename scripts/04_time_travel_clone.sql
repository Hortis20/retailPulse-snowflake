-- =============================================================================
-- RetailPulse – 04_time_travel_clone.sql
-- Étape 5 : Time Travel et Zero-Copy Clone
--   - mise à jour simulée de FACT_SALES, lecture de l'état antérieur, restauration exacte
--   - clone de RETAIL_DB en RETAIL_DB_DEV, sans dupliquer le stockage
-- Prérequis : 03_automation.sql
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE RETAIL_WH;

-- -----------------------------------------------------------------------------
-- 1. Time Travel
-- -----------------------------------------------------------------------------
-- Mise à jour simulée : +10 % sur les commandes françaises
UPDATE RETAIL_DB.ANALYTICS.FACT_SALES
SET total_amount = total_amount * 1.10
WHERE country = 'FR';

SET update_id = LAST_QUERY_ID();   -- identifiant de l'UPDATE, à capturer juste après

-- Comparaison : état actuel / état juste avant l'UPDATE
SELECT 'apres' AS etat, SUM(total_amount) AS ca_france
FROM RETAIL_DB.ANALYTICS.FACT_SALES
WHERE country = 'FR'
UNION ALL
SELECT 'avant', SUM(total_amount)
FROM RETAIL_DB.ANALYTICS.FACT_SALES BEFORE(STATEMENT => $update_id)
WHERE country = 'FR';

-- Autres syntaxes : AT(TIMESTAMP => '2026-10-13 15:00:00'::TIMESTAMP_LTZ), AT(OFFSET => -300)

-- Restauration exacte : on reprend les montants du passé (diviser par 1,10 créerait des écarts d'arrondi)
UPDATE RETAIL_DB.ANALYTICS.FACT_SALES f
SET total_amount = avant.total_amount
FROM (
  SELECT transaction_id, total_amount
  FROM RETAIL_DB.ANALYTICS.FACT_SALES BEFORE(STATEMENT => $update_id)
) avant
WHERE f.transaction_id = avant.transaction_id
  AND f.country = 'FR';

-- -----------------------------------------------------------------------------
-- 2. Zero-Copy Clone : environnement de développement
--    Le clone pointe vers les mêmes micro-partitions : aucun stockage supplémentaire
--    tant qu'il n'est pas modifié. Les tasks clonées sont suspendues.
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS RETAIL_DB_DEV CLONE RETAIL_DB;

-- Démonstration d'indépendance : modification du clone uniquement
DELETE FROM RETAIL_DB_DEV.ANALYTICS.FACT_SALES WHERE country = 'FR';

SELECT 'prod' AS env, COUNT(*) AS nb FROM RETAIL_DB.ANALYTICS.FACT_SALES
UNION ALL
SELECT 'dev',  COUNT(*)             FROM RETAIL_DB_DEV.ANALYTICS.FACT_SALES;
