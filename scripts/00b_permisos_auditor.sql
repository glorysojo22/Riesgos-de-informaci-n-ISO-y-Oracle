-- ============================================================
-- 00b_permisos_auditor.sql
-- Completa los permisos de lectura de AUDITOR_EXT.
-- Proyecto: Controles ISO 27001:2022 para la confidencialidad en Oracle
--
-- SELECT_CATALOG_ROLE no incluye estas vistas, que usan PT-04 y PT-05.
-- Se otorga SELECT solo sobre ellas (mínimo privilegio), en lugar de
-- SELECT ANY DICTIONARY, que daría lectura a todo el diccionario.
--
-- Ejecutar como SYS con rol SYSDBA, conectado a la PDB XEPDB1
-- (en SQL Developer: usuario SYS, rol SYSDBA, servicio XEPDB1).
-- ============================================================
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS contenedor,
       SYS_CONTEXT('USERENV','SESSION_USER') AS usuario
FROM dual;

GRANT SELECT ON sys.dba_users_with_defpwd TO auditor_ext;   -- PT-04 (A5.17)
GRANT SELECT ON sys.dba_priv_captures     TO auditor_ext;   -- PT-05 (A5.18)
GRANT SELECT ON sys.dba_used_privs        TO auditor_ext;   -- PT-05 (A5.18)
GRANT SELECT ON sys.dba_unused_privs      TO auditor_ext;   -- PT-05 (A5.18)

SELECT owner, table_name, privilege
FROM dba_tab_privs
WHERE grantee = 'AUDITOR_EXT'
ORDER BY table_name;
