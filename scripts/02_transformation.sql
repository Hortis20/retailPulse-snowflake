-- =============================================================================
-- RetailPulse – 02_transformation.sql
-- Étape 3 : extraction du JSON et alimentation de ANALYTICS.FACT_SALES
--   - une ligne par commande
--   - nb_types_produit : nombre de produits différents (COUNT DISTINCT sku)
--   - nb_articles      : nombre total d'articles = somme des quantités (choix documenté)
-- Prérequis : 01_ingestion.sql
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE RETAIL_WH;

-- -----------------------------------------------------------------------------
-- 1. Table de faits
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RETAIL_DB.ANALYTICS.FACT_SALES (
  transaction_id     STRING,
  customer_id        STRING,
  country            STRING,
  event_timestamp    TIMESTAMP_NTZ,                             -- heure de la vente, telle qu'envoyée
  nb_types_produit   INT,
  nb_articles        INT,
  total_amount       NUMBER(10,2),                              -- type exact pour un montant (jamais FLOAT)
  inserted_at        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()  -- instant d'insertion
);

-- -----------------------------------------------------------------------------
-- 2. Chargement initial (lot 1)
--    ATTENTION : à exécuter UNE SEULE FOIS sur une table vide.
--    Un INSERT ... SELECT n'a pas de mémoire : relancé, il dupliquerait toutes les commandes.
--    Les arrivées suivantes sont traitées par le stream et la task (03_automation.sql).
-- -----------------------------------------------------------------------------
INSERT INTO RETAIL_DB.ANALYTICS.FACT_SALES
  (transaction_id, customer_id, country, event_timestamp,
   nb_types_produit, nb_articles, total_amount)
SELECT
  t.raw_data:transaction_id::STRING                  AS transaction_id,
  t.raw_data:customer_info.id::STRING                AS customer_id,
  t.raw_data:customer_info.country::STRING           AS country,
  t.raw_data:event_timestamp::TIMESTAMP_NTZ          AS event_timestamp,
  COUNT(DISTINCT f.value:sku)                        AS nb_types_produit,   -- 0 si aucun article
  COALESCE(SUM(f.value:quantity::NUMBER), 0)         AS nb_articles,        -- 0 si aucun article
  t.raw_data:total_amount::NUMBER(10,2)              AS total_amount
FROM RETAIL_DB.STAGING.RAW_TRANSACTIONS t,
     LATERAL FLATTEN(INPUT => t.raw_data:items, OUTER => TRUE) f   -- OUTER : garde les commandes sans article
GROUP BY transaction_id, customer_id, country, event_timestamp, total_amount;
