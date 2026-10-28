-- ============================================================
-- 04b_completar_separacion_funciones.sql
-- Completa la parte de 04_implementar_controles.sql que falló en la
-- primera ejecución (25/10/2026):
--   * ADMIN_BD y AUDITOR_SEG no se crearon (ORA-28003: la contraseña
--     no cumplía ORA12C_STRONG_VERIFY_FUNCTION).
--   * Por eso falló la conexión como AUDITOR_SEG (ORA-01017) y no se
--     creó la política de auditoría POL_RRHH_LECTURA.
--   * La reconexión como SYSTEM falló (ORA-01017) y no se generó el
--     resumen final.
-- El resto de 04 sí se aplicó y no se repite aquí.
--
-- Ejecutar como SYSTEM conectado a la PDB XEPDB1, con F5.
-- Genera tres archivos de evidencia, uno por conexión, porque SQL Developer
-- cierra el SPOOL cuando el script cambia de usuario con CONNECT:
--   evidencia_implementacion_parte2a.txt  (SYSTEM crea las cuentas)
--   evidencia_implementacion_parte2b.txt  (AUDITOR_SEG crea la política)
--   evidencia_implementacion_parte2c.txt  (SYSTEM, resumen final)
-- La salida completa también queda en el panel "Salida de Script".
--
-- Contraseñas: al menos 9 caracteres, con 2 mayúsculas, 2 minúsculas,
-- 2 números y 2 caracteres especiales. Usá especiales como # $ _ ! %
-- NO uses: &  @  /  "  ni espacios (rompen la sustitución o el CONNECT).
-- ============================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET FEEDBACK ON
SET LINESIZE 200
SET PAGESIZE 100
WHENEVER SQLERROR CONTINUE

DEFINE svc = localhost:1521/XEPDB1

PROMPT Contraseñas: 9+ caracteres, 2 mayúsculas, 2 minúsculas, 2 números y 2 especiales (# $ _ ! %).
PROMPT No uses ampersand, arroba, barra, comillas ni espacios.
ACCEPT system_pwd   PROMPT 'Contraseña ACTUAL de SYSTEM (la que usás para conectarte): ' HIDE
ACCEPT admin_bd_pwd PROMPT 'Contraseña nueva para ADMIN_BD (DBA operativo): ' HIDE
ACCEPT audit_pwd    PROMPT 'Contraseña nueva para AUDITOR_SEG (responsable de auditoría): ' HIDE

SPOOL evidencia_implementacion_parte2a.txt
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS contenedor,
       SYS_CONTEXT('USERENV','SESSION_USER') AS usuario,
       SYSTIMESTAMP AS fecha_implementacion
FROM dual;

PROMPT ============================================================
PROMPT [A5.33 / A8.2] Crear ADMIN_BD (DBA operativo) y AUDITOR_SEG (auditoría)
PROMPT ============================================================
BEGIN EXECUTE IMMEDIATE 'DROP USER admin_bd CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE USER admin_bd IDENTIFIED BY "&admin_bd_pwd" PROFILE perfil_funcionario;
GRANT rol_dba_operativo TO admin_bd;

BEGIN EXECUTE IMMEDIATE 'DROP USER auditor_seg CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE USER auditor_seg IDENTIFIED BY "&audit_pwd" PROFILE perfil_funcionario;
GRANT CREATE SESSION, AUDIT_ADMIN, AUDIT_VIEWER TO auditor_seg;

-- Si alguna de las dos no se creó, se detiene aquí para no repetir el error.
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username IN ('ADMIN_BD','AUDITOR_SEG');
  IF n < 2 THEN
    DBMS_OUTPUT.PUT_LINE('*** Falta crear ADMIN_BD o AUDITOR_SEG: revisá la contraseña y volvé a ejecutar 04b. ***');
  ELSE
    DBMS_OUTPUT.PUT_LINE('ADMIN_BD y AUDITOR_SEG creadas.');
  END IF;
END;
/

PROMPT ============================================================
PROMPT [A8.15 / A5.33] Políticas de auditoría (las crea AUDITOR_SEG, no el DBA)
PROMPT ============================================================
SPOOL OFF
CONNECT auditor_seg/"&audit_pwd"@&svc
SET SERVEROUTPUT ON SIZE UNLIMITED
SPOOL evidencia_implementacion_parte2b.txt
SELECT SYS_CONTEXT('USERENV','SESSION_USER') AS usuario_que_crea_la_politica FROM dual;
BEGIN
  BEGIN EXECUTE IMMEDIATE 'NOAUDIT POLICY pol_rrhh_lectura'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'DROP AUDIT POLICY pol_rrhh_lectura'; EXCEPTION WHEN OTHERS THEN NULL; END;
  EXECUTE IMMEDIATE 'CREATE AUDIT POLICY pol_rrhh_lectura
                       ACTIONS SELECT ON rrhh.empleados,
                               UPDATE ON rrhh.empleados,
                               DELETE ON rrhh.empleados';
  EXECUTE IMMEDIATE 'AUDIT POLICY pol_rrhh_lectura';
  DBMS_OUTPUT.PUT_LINE('Política POL_RRHH_LECTURA habilitada.');
  BEGIN
    EXECUTE IMMEDIATE 'AUDIT POLICY ora_logon_failures WHENEVER NOT SUCCESSFUL';
    DBMS_OUTPUT.PUT_LINE('Política ORA_LOGON_FAILURES habilitada.');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ORA_LOGON_FAILURES: ' || SQLERRM || ' (si ya estaba habilitada, no es un problema).');
  END;
END;
/
SELECT policy_name, enabled_option, entity_name, success, failure
FROM audit_unified_enabled_policies
WHERE policy_name IN ('POL_RRHH_LECTURA','ORA_LOGON_FAILURES');

SPOOL OFF
CONNECT system/"&system_pwd"@&svc
SET SERVEROUTPUT ON SIZE UNLIMITED
SPOOL evidencia_implementacion_parte2c.txt

PROMPT ============================================================
PROMPT Resumen de lo implementado (04 + 04b)
PROMPT ============================================================
SELECT username, profile, account_status FROM dba_users
WHERE oracle_maintained = 'N' ORDER BY username;
SELECT grantee, granted_role FROM dba_role_privs
WHERE granted_role IN ('ROL_RRHH','ROL_DBA_OPERATIVO','AUDIT_ADMIN','DBA')
  AND grantee NOT IN ('SYS') ORDER BY granted_role, grantee;
SELECT object_owner, object_name, policy_name, enable FROM dba_policies WHERE object_owner = 'RRHH';
SELECT object_owner, object_name, column_name, function_type FROM redaction_columns WHERE object_owner = 'RRHH';
SELECT name, type, enabled FROM dba_priv_captures;

SPOOL OFF
PROMPT Listo. Evidencia en evidencia_implementacion_parte2a, 2b y 2c (.txt)
