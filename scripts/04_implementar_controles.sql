-- ============================================================
-- 04_implementar_controles.sql
-- Implementa los controles de ISO/IEC 27001:2022 que se pueden
-- automatizar dentro de la base de datos (fase "Hacer" del PHVA).
-- Proyecto: Controles ISO 27001:2022 para la confidencialidad en Oracle
--
-- Ejecutar como SYSTEM conectado a la PDB XEPDB1, con
-- "Ejecutar script (F5)" en SQL Developer o en SQL*Plus.
-- Requisitos: 00_crear_auditor.sql y 02_datos_prueba.sql ejecutados.
-- Genera el archivo evidencia_implementacion.txt
--
-- Se puede ejecutar más de una vez: cada sección elimina lo que
-- creó antes de volver a crearlo.
--
-- Si VPD o Data Redaction fallan con PLS-00201 (el paquete no se reconoce),
-- ejecutar una vez como SYSDBA, en XEPDB1:
--   GRANT EXECUTE ON sys.dbms_rls TO system;
--   GRANT EXECUTE ON sys.dbms_redact TO system;
--
-- Controles que NO están aquí porque necesitan SYSDBA, RMAN o
-- archivos del servidor (ver 06_procedimientos_servidor.md):
--   A8.12 cifrado TDE · A8.13 ARCHIVELOG y respaldos cifrados
--   A8.10 retención de RMAN · A8.5 y A8.20 parámetros de sqlnet.ora
-- ============================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET FEEDBACK ON
SET LINESIZE 200
SET PAGESIZE 100
WHENEVER SQLERROR CONTINUE

DEFINE svc = localhost:1521/XEPDB1

PROMPT Las contraseñas nuevas deben tener al menos 9 caracteres, con 2 mayúsculas,
PROMPT 2 minúsculas, 2 números y 2 caracteres especiales (ORA12C_STRONG_VERIFY_FUNCTION).
PROMPT No uses el símbolo ampersand en las contraseñas.
ACCEPT system_pwd   PROMPT 'Contraseña de SYSTEM: ' HIDE
ACCEPT admin_bd_pwd PROMPT 'Contraseña nueva para ADMIN_BD (DBA operativo): ' HIDE
ACCEPT audit_pwd    PROMPT 'Contraseña nueva para AUDITOR_SEG (responsable de auditoría): ' HIDE

SPOOL evidencia_implementacion.txt
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS contenedor,
       SYS_CONTEXT('USERENV','SESSION_USER') AS usuario,
       SYSTIMESTAMP AS fecha_implementacion
FROM dual;

PROMPT ============================================================
PROMPT [A8.5 / A5.17] Perfil de contraseñas PERFIL_FUNCIONARIO
PROMPT ============================================================
-- La función ORA12C_STRONG_VERIFY_FUNCTION la crea Oracle al instalar.
SELECT object_name, status FROM dba_objects
WHERE owner = 'SYS' AND object_name = 'ORA12C_STRONG_VERIFY_FUNCTION';

BEGIN
  EXECUTE IMMEDIATE 'CREATE PROFILE perfil_funcionario LIMIT
      FAILED_LOGIN_ATTEMPTS    3
      PASSWORD_LOCK_TIME       1
      PASSWORD_LIFE_TIME       90
      PASSWORD_GRACE_TIME      7
      PASSWORD_REUSE_MAX       5
      PASSWORD_REUSE_TIME      365
      PASSWORD_VERIFY_FUNCTION ora12c_strong_verify_function
      IDLE_TIME                15';
  DBMS_OUTPUT.PUT_LINE('Perfil PERFIL_FUNCIONARIO creado.');
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE = -2379 THEN  -- el perfil ya existe: se actualizan sus límites
    EXECUTE IMMEDIATE 'ALTER PROFILE perfil_funcionario LIMIT
        FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 1 PASSWORD_LIFE_TIME 90
        PASSWORD_GRACE_TIME 7 PASSWORD_REUSE_MAX 5 PASSWORD_REUSE_TIME 365
        PASSWORD_VERIFY_FUNCTION ora12c_strong_verify_function IDLE_TIME 15';
    DBMS_OUTPUT.PUT_LINE('Perfil PERFIL_FUNCIONARIO actualizado.');
  ELSE RAISE; END IF;
END;
/

PROMPT ============================================================
PROMPT [A5.33 / A8.2] Separación de funciones: DBA operativo y responsable de auditoría
PROMPT ============================================================
-- ADMIN_BD administra cuentas y objetos, pero su rol NO incluye privilegios
-- de auditoría ni GRANT ANY ROLE/PRIVILEGE (con eso podría darse AUDIT_ADMIN).
-- Limitación: ALTER USER le permite cambiar contraseñas de otras cuentas;
-- en producción esto se cierra con Oracle Database Vault.
BEGIN EXECUTE IMMEDIATE 'DROP ROLE rol_dba_operativo'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE ROLE rol_dba_operativo;
GRANT CREATE SESSION, CREATE USER, ALTER USER, DROP USER,
      CREATE ROLE, CREATE PROFILE, ALTER PROFILE,
      CREATE TABLESPACE, ALTER TABLESPACE
TO rol_dba_operativo;
GRANT SELECT_CATALOG_ROLE TO rol_dba_operativo;

BEGIN EXECUTE IMMEDIATE 'DROP USER admin_bd CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE USER admin_bd IDENTIFIED BY "&admin_bd_pwd" PROFILE perfil_funcionario;
GRANT rol_dba_operativo TO admin_bd;

BEGIN EXECUTE IMMEDIATE 'DROP USER auditor_seg CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE USER auditor_seg IDENTIFIED BY "&audit_pwd" PROFILE perfil_funcionario;
GRANT CREATE SESSION, AUDIT_ADMIN, AUDIT_VIEWER TO auditor_seg;

PROMPT ============================================================
PROMPT [A5.15] Acceso a RRHH solo mediante roles por función
PROMPT ============================================================
BEGIN EXECUTE IMMEDIATE 'DROP ROLE rol_rrhh'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE ROLE rol_rrhh;
GRANT SELECT ON rrhh.empleados TO rol_rrhh;
-- El rol se otorga a las personas que lo necesitan; las pruebas
-- funcionales lo otorgan a PRUEBA_TI y PRUEBA_CONTA durante PF-03.

-- Revocar privilegios de objeto otorgados directamente a usuarios o a PUBLIC
-- en los esquemas sensibles (después deben pasar por un rol).
DECLARE
  n PLS_INTEGER := 0;
BEGIN
  FOR p IN (SELECT DISTINCT tp.grantee, tp.owner, tp.table_name, tp.privilege
            FROM dba_tab_privs tp
            WHERE tp.owner IN ('RRHH','FIN')
              AND (tp.grantee = 'PUBLIC'
                   OR tp.grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N'))) LOOP
    EXECUTE IMMEDIATE 'REVOKE ' || p.privilege || ' ON "' || p.owner || '"."' || p.table_name || '" FROM ' ||
                      CASE WHEN p.grantee = 'PUBLIC' THEN 'PUBLIC' ELSE '"' || p.grantee || '"' END;
    DBMS_OUTPUT.PUT_LINE('Revocado: ' || p.privilege || ' ON ' || p.owner || '.' || p.table_name || ' FROM ' || p.grantee);
    n := n + 1;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(n || ' privilegios directos revocados.');
END;
/

PROMPT ============================================================
PROMPT [A8.5 / A5.16] Asignar PERFIL_FUNCIONARIO a las cuentas
PROMPT ============================================================
-- 1) Cuentas del proyecto: siempre.
BEGIN
  FOR u IN (SELECT username FROM dba_users
            WHERE username IN ('AUDITOR_EXT','ADMIN_BD','AUDITOR_SEG','PRUEBA_TI','PRUEBA_CONTA')
              AND profile <> 'PERFIL_FUNCIONARIO') LOOP
    EXECUTE IMMEDIATE 'ALTER USER "' || u.username || '" PROFILE perfil_funcionario';
    DBMS_OUTPUT.PUT_LINE('Perfil asignado a ' || u.username);
  END LOOP;
END;
/

-- 2) Otras cuentas propias (por ejemplo, de otros cursos): se pregunta antes.
-- Con PERFIL_FUNCIONARIO, una contraseña con más de 90 días vence y Oracle pide
-- cambiarla en el siguiente inicio de sesión, y la cuenta se bloquea tras 3 intentos fallidos.
SELECT username, profile, account_status, last_login
FROM dba_users
WHERE oracle_maintained = 'N'
  AND authentication_type <> 'NONE'
  AND profile <> 'PERFIL_FUNCIONARIO'
  AND username NOT IN ('AUDITOR_EXT','ADMIN_BD','AUDITOR_SEG','PRUEBA_TI','PRUEBA_CONTA')
ORDER BY username;

PROMPT Si respondés N, estas cuentas quedan con el perfil DEFAULT y PT-09 lo va a mostrar:
PROMPT documentalas como excepción en la evaluación.
ACCEPT perfil_otras PROMPT '¿Asignar PERFIL_FUNCIONARIO también a las cuentas listadas? (S/N): '
DECLARE
  n PLS_INTEGER := 0;
BEGIN
  IF UPPER('&perfil_otras') = 'S' THEN
    FOR u IN (SELECT username FROM dba_users
              WHERE oracle_maintained = 'N' AND authentication_type <> 'NONE'
                AND profile <> 'PERFIL_FUNCIONARIO'
                AND username NOT IN ('AUDITOR_EXT','ADMIN_BD','AUDITOR_SEG','PRUEBA_TI','PRUEBA_CONTA')) LOOP
      EXECUTE IMMEDIATE 'ALTER USER "' || u.username || '" PROFILE perfil_funcionario';
      DBMS_OUTPUT.PUT_LINE('Perfil asignado a ' || u.username); n := n + 1;
    END LOOP;
  END IF;
  DBMS_OUTPUT.PUT_LINE(n || ' cuentas adicionales pasaron a PERFIL_FUNCIONARIO.');
END;
/

PROMPT ============================================================
PROMPT [A5.17] Bloquear cuentas abiertas con contraseña por defecto
PROMPT ============================================================
DECLARE
  n PLS_INTEGER := 0;
BEGIN
  FOR u IN (SELECT d.username FROM dba_users_with_defpwd d
            JOIN dba_users u ON u.username = d.username
            WHERE u.account_status = 'OPEN') LOOP
    EXECUTE IMMEDIATE 'ALTER USER "' || u.username || '" ACCOUNT LOCK';
    DBMS_OUTPUT.PUT_LINE('Bloqueada: ' || u.username);
    n := n + 1;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(n || ' cuentas con contraseña por defecto bloqueadas.');
END;
/

PROMPT ============================================================
PROMPT [A5.16] Cuentas abiertas sin uso en 90 días
PROMPT ============================================================
-- Se excluyen las cuentas que crean los scripts del proyecto.
SELECT username, account_status, last_login, created
FROM dba_users
WHERE oracle_maintained = 'N'
  AND authentication_type <> 'NONE'
  AND account_status = 'OPEN'
  AND (last_login IS NULL OR last_login < SYSTIMESTAMP - INTERVAL '90' DAY)
  AND username NOT IN ('AUDITOR_EXT','AUDITOR_SEG','ADMIN_BD','PRUEBA_TI','PRUEBA_CONTA');

PROMPT Revisá la lista anterior. Si alguna cuenta la usás para otros trabajos, respondé N.
ACCEPT bloquear_inactivas PROMPT '¿Bloquear las cuentas listadas? (S/N): '
DECLARE
  n PLS_INTEGER := 0;
BEGIN
  IF UPPER('&bloquear_inactivas') = 'S' THEN
    FOR u IN (SELECT username FROM dba_users
              WHERE oracle_maintained = 'N' AND authentication_type <> 'NONE' AND account_status = 'OPEN'
                AND (last_login IS NULL OR last_login < SYSTIMESTAMP - INTERVAL '90' DAY)
                AND username NOT IN ('AUDITOR_EXT','AUDITOR_SEG','ADMIN_BD','PRUEBA_TI','PRUEBA_CONTA')) LOOP
      EXECUTE IMMEDIATE 'ALTER USER "' || u.username || '" ACCOUNT LOCK';
      DBMS_OUTPUT.PUT_LINE('Bloqueada: ' || u.username);
      n := n + 1;
    END LOOP;
  END IF;
  DBMS_OUTPUT.PUT_LINE(n || ' cuentas inactivas bloqueadas.');
END;
/

PROMPT ============================================================
PROMPT [A8.2] Privilegios elevados en cuentas propias
PROMPT ============================================================
-- Lista de autorizadas: ninguna cuenta propia debe tener el rol DBA ni privilegios ANY.
SELECT grantee, granted_role AS privilegio FROM dba_role_privs
WHERE granted_role = 'DBA'
  AND grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')
UNION ALL
SELECT grantee, privilege FROM dba_sys_privs
WHERE privilege LIKE '%ANY%'
  AND grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N');

PROMPT Si alguna de estas cuentas la usás para otros trabajos, respondé N y documentá la excepción.
ACCEPT revocar_elevados PROMPT '¿Revocar el rol DBA y los privilegios ANY listados? (S/N): '
DECLARE
  n PLS_INTEGER := 0;
BEGIN
  IF UPPER('&revocar_elevados') = 'S' THEN
    FOR r IN (SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA'
              AND grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')) LOOP
      EXECUTE IMMEDIATE 'REVOKE DBA FROM "' || r.grantee || '"';
      DBMS_OUTPUT.PUT_LINE('Revocado DBA de ' || r.grantee); n := n + 1;
    END LOOP;
    FOR p IN (SELECT grantee, privilege FROM dba_sys_privs WHERE privilege LIKE '%ANY%'
              AND grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')) LOOP
      EXECUTE IMMEDIATE 'REVOKE ' || p.privilege || ' FROM "' || p.grantee || '"';
      DBMS_OUTPUT.PUT_LINE('Revocado ' || p.privilege || ' de ' || p.grantee); n := n + 1;
    END LOOP;
  END IF;
  DBMS_OUTPUT.PUT_LINE(n || ' privilegios elevados revocados.');
END;
/

PROMPT ============================================================
PROMPT [A8.12] Roles de exportación masiva en cuentas propias
PROMPT ============================================================
SELECT grantee, granted_role FROM dba_role_privs
WHERE granted_role IN ('DATAPUMP_EXP_FULL_DATABASE','EXP_FULL_DATABASE')
  AND grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N');
DECLARE
  n PLS_INTEGER := 0;
BEGIN
  FOR r IN (SELECT grantee, granted_role FROM dba_role_privs
            WHERE granted_role IN ('DATAPUMP_EXP_FULL_DATABASE','EXP_FULL_DATABASE')
              AND grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')) LOOP
    EXECUTE IMMEDIATE 'REVOKE ' || r.granted_role || ' FROM "' || r.grantee || '"';
    DBMS_OUTPUT.PUT_LINE('Revocado ' || r.granted_role || ' de ' || r.grantee); n := n + 1;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(n || ' roles de exportación revocados.');
END;
/

PROMPT ============================================================
PROMPT [A8.3] Virtual Private Database: cada usuario ve solo su departamento
PROMPT ============================================================
-- Tabla de asignación usuario -> departamento (la lee la función, no el usuario).
BEGIN EXECUTE IMMEDIATE 'DROP TABLE rrhh.usuarios_departamento PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE TABLE rrhh.usuarios_departamento (
  usuario      VARCHAR2(128) PRIMARY KEY,
  departamento VARCHAR2(10)  NOT NULL
);
INSERT INTO rrhh.usuarios_departamento VALUES ('PRUEBA_TI',    'TI');
INSERT INTO rrhh.usuarios_departamento VALUES ('PRUEBA_CONTA', 'CONTA');
COMMIT;

-- Función de política: devuelve el filtro que Oracle agrega a cada consulta.
CREATE OR REPLACE FUNCTION rrhh.vpd_departamento (
  p_esquema IN VARCHAR2,
  p_objeto  IN VARCHAR2
) RETURN VARCHAR2
AS
  v_usuario VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
  v_depto   VARCHAR2(10);
BEGIN
  IF v_usuario IN ('SYS', 'SYSTEM') THEN
    RETURN NULL;                       -- administración: sin filtro
  END IF;
  SELECT departamento INTO v_depto
  FROM rrhh.usuarios_departamento
  WHERE usuario = v_usuario;
  RETURN 'departamento = ''' || v_depto || '''';
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN '1 = 0';                    -- usuario sin departamento asignado: no ve filas
END;
/

BEGIN
  BEGIN
    DBMS_RLS.DROP_POLICY('RRHH', 'EMPLEADOS', 'PF_DEPARTAMENTO');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  DBMS_RLS.ADD_POLICY(
    object_schema   => 'RRHH',
    object_name     => 'EMPLEADOS',
    policy_name     => 'PF_DEPARTAMENTO',
    function_schema => 'RRHH',
    policy_function => 'VPD_DEPARTAMENTO',
    statement_types => 'SELECT, UPDATE, DELETE');
  DBMS_OUTPUT.PUT_LINE('Política VPD PF_DEPARTAMENTO creada.');
END;
/

PROMPT ============================================================
PROMPT [A8.11] Data Redaction: cédula parcial y salario oculto
PROMPT ============================================================
BEGIN
  BEGIN
    DBMS_REDACT.DROP_POLICY(object_schema => 'RRHH', object_name => 'EMPLEADOS', policy_name => 'RED_EMPLEADOS');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  -- Salario: redacción total (los números se muestran como 0)
  DBMS_REDACT.ADD_POLICY(
    object_schema => 'RRHH',
    object_name   => 'EMPLEADOS',
    policy_name   => 'RED_EMPLEADOS',
    column_name   => 'SALARIO',
    function_type => DBMS_REDACT.FULL,
    expression    => '1=1');
  -- Cédula: se muestran solo los últimos 4 dígitos (1-1111-1111 -> *-****-1111)
  DBMS_REDACT.ALTER_POLICY(
    object_schema          => 'RRHH',
    object_name            => 'EMPLEADOS',
    policy_name            => 'RED_EMPLEADOS',
    action                 => DBMS_REDACT.ADD_COLUMN,
    column_name            => 'CEDULA',
    function_type          => DBMS_REDACT.REGEXP,
    regexp_pattern         => '^(\d)-(\d{4})-(\d{4})$',
    regexp_replace_string  => '*-****-\3',
    regexp_position        => 1,
    regexp_occurrence      => 0,
    regexp_match_parameter => 'i');
  DBMS_OUTPUT.PUT_LINE('Política de redacción RED_EMPLEADOS creada.');
END;
/

PROMPT ============================================================
PROMPT [A8.10] Purgar la papelera de reciclaje de los esquemas sensibles
PROMPT ============================================================
DECLARE
  n PLS_INTEGER := 0;
BEGIN
  FOR o IN (SELECT owner, object_name, original_name FROM dba_recyclebin
            WHERE owner IN ('RRHH','FIN') AND type = 'TABLE') LOOP
    EXECUTE IMMEDIATE 'PURGE TABLE "' || o.owner || '"."' || o.object_name || '"';
    DBMS_OUTPUT.PUT_LINE('Purgada: ' || o.owner || '.' || o.original_name); n := n + 1;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(n || ' tablas purgadas de la papelera.');
END;
/

PROMPT ============================================================
PROMPT [A5.18] Iniciar la captura de privilegios (análisis de privilegios)
PROMPT ============================================================
-- Registra qué privilegios se usan mientras corren las pruebas.
-- 05_cerrar_revision_privilegios.sql la detiene y genera el resultado.
BEGIN
  BEGIN DBMS_PRIVILEGE_CAPTURE.DISABLE_CAPTURE('CAP_REVISION'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DBMS_PRIVILEGE_CAPTURE.DROP_CAPTURE('CAP_REVISION');    EXCEPTION WHEN OTHERS THEN NULL; END;
  DBMS_PRIVILEGE_CAPTURE.CREATE_CAPTURE(
    name        => 'CAP_REVISION',
    description => 'Revisión periódica de privilegios (A5.18)',
    type        => DBMS_PRIVILEGE_CAPTURE.G_DATABASE);
  DBMS_PRIVILEGE_CAPTURE.ENABLE_CAPTURE('CAP_REVISION');
  DBMS_OUTPUT.PUT_LINE('Captura CAP_REVISION activa.');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('No se pudo iniciar la captura: ' || SQLERRM);
  DBMS_OUTPUT.PUT_LINE('Verificá que SYSTEM tenga el rol CAPTURE_ADMIN.');
END;
/

PROMPT ============================================================
PROMPT [A8.15 / A5.33] Políticas de auditoría (las crea AUDITOR_SEG, no el DBA)
PROMPT ============================================================
CONNECT auditor_seg/"&audit_pwd"@&svc
SET SERVEROUTPUT ON SIZE UNLIMITED
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

CONNECT system/"&system_pwd"@&svc

PROMPT ============================================================
PROMPT Resumen de lo implementado
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
PROMPT Implementación terminada. Evidencia guardada en evidencia_implementacion.txt
PROMPT Siguiente paso: 06_procedimientos_servidor.md (SYSDBA) y luego 03_pruebas_funcionales.sql
