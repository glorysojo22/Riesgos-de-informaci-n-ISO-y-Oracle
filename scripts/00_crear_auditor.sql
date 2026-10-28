-- ============================================================
-- 00_crear_auditor.sql
-- Crea la cuenta de solo lectura del auditor externo.
-- Proyecto: Controles ISO 27001:2022 para la confidencialidad en Oracle
-- Ejecutar como SYSTEM conectado a la PDB XEPDB1.
-- ============================================================
SET VERIFY OFF

ACCEPT auditor_pwd PROMPT 'Contraseña para AUDITOR_EXT: ' HIDE

CREATE USER auditor_ext IDENTIFIED BY "&auditor_pwd";

-- SELECT_CATALOG_ROLE: leer vistas del diccionario (DBA_*, V$*)
-- AUDIT_VIEWER: leer los registros de auditoría unificada
-- Ninguno de los dos permite modificar datos ni configuración.
GRANT CREATE SESSION, SELECT_CATALOG_ROLE, AUDIT_VIEWER TO auditor_ext;

SELECT granted_role FROM dba_role_privs WHERE grantee = 'AUDITOR_EXT';
