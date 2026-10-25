-- =============================================================================
-- RetailPulse – 99_teardown.sql
-- Nettoyage complet du projet. IRRÉVERSIBLE au-delà de la période de Time Travel.
-- Exécuter instruction par instruction, en vérifiant chaque nom.
-- =============================================================================

USE ROLE SYSADMIN;

-- 1. Arrêter l'automatisation
ALTER TASK IF EXISTS RETAIL_DB.STAGING.TSK_LOAD_FACT_SALES SUSPEND;

-- 2. Supprimer le clone, puis la base (schémas, tables, stage, stream, task inclus)
DROP DATABASE IF EXISTS RETAIL_DB_DEV;
DROP DATABASE IF EXISTS RETAIL_DB;
-- Récupérable pendant la période de rétention : UNDROP DATABASE RETAIL_DB;

-- 3. Supprimer le warehouse
DROP WAREHOUSE IF EXISTS RETAIL_WH;

-- 4. Supprimer le rôle et le privilège de tasks
USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS ANALYST_ROLE;

USE ROLE ACCOUNTADMIN;
REVOKE EXECUTE TASK ON ACCOUNT FROM ROLE SYSADMIN;
