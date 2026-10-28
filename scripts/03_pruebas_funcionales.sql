-- ============================================================
-- 03_pruebas_funcionales.sql
-- Pruebas funcionales PF-01 a PF-07 (PF-08 se ejecuta en RMAN)
-- Proyecto: Controles ISO 27001:2022 para la confidencialidad en Oracle
--
-- Requisitos:
--   1. 00_crear_auditor.sql y 02_datos_prueba.sql ejecutados.
--   2. Controles implementados con 04_implementar_controles.sql: perfil
--      PERFIL_FUNCIONARIO, rol ROL_RRHH, políticas de redacción, VPD y
--      auditoría sobre RRHH.EMPLEADOS, y las cuentas separadas ADMIN_BD
--      (DBA operativo) y AUDITOR_SEG (responsable de auditoría).
--   Si un control no está implementado, su prueba falla: ese resultado es la
--   evidencia del estado "No cumple".
--
-- Ejecutar en SQL*Plus: cd a la carpeta, sqlplus /nolog, @03_pruebas_funcionales.sql
-- (SQL Developer pierde el SPOOL con tantos CONNECT y deja el archivo vacío).
-- Genera el archivo de evidencia evidencia_funcional.txt
-- ============================================================
WHENEVER SQLERROR CONTINUE
SET VERIFY OFF
SET FEEDBACK ON
SET LINESIZE 200
SET PAGESIZE 100

DEFINE svc = localhost:1521/XEPDB1

ACCEPT admin_pwd    PROMPT 'Contraseña de SYSTEM: '      HIDE
ACCEPT auditor_pwd  PROMPT 'Contraseña de AUDITOR_EXT: ' HIDE
ACCEPT admin_bd_pwd PROMPT 'Contraseña de ADMIN_BD: '    HIDE
ACCEPT audit_pwd    PROMPT 'Contraseña de AUDITOR_SEG: ' HIDE

SPOOL evidencia_funcional.txt

PROMPT ============================================================
PROMPT PF-01 (A8.5) Bloqueo de la cuenta tras intentos fallidos
PROMPT ============================================================
-- SQL Developer detiene el script si hay dos CONNECT fallidos seguidos
-- (la hoja queda sin conexión). Por eso, después de cada intento fallido
-- se vuelve a conectar como SYSTEM. Eso no reinicia el contador de
-- intentos de PRUEBA_LOCK: ese contador es de la cuenta, no de la sesión.
CONNECT system/"&admin_pwd"@&svc
-- Limpieza de una ejecución anterior, si la hubo
BEGIN EXECUTE IMMEDIATE 'DROP USER prueba_lock CASCADE';  EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP USER prueba_debil CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE USER prueba_lock IDENTIFIED BY "PR##lab2026" PROFILE perfil_funcionario;
GRANT CREATE SESSION TO prueba_lock;

PROMPT Cuatro intentos con contraseña incorrecta (FAILED_LOGIN_ATTEMPTS = 3)
PROMPT Esperado: ORA-01017 en los primeros; la cuenta queda bloqueada al tercero
PROMPT Intento 1
CONNECT prueba_lock/clave_incorrecta@&svc
CONNECT system/"&admin_pwd"@&svc
PROMPT Intento 2
CONNECT prueba_lock/clave_incorrecta@&svc
CONNECT system/"&admin_pwd"@&svc
PROMPT Intento 3
CONNECT prueba_lock/clave_incorrecta@&svc
CONNECT system/"&admin_pwd"@&svc
PROMPT Intento 4
CONNECT prueba_lock/clave_incorrecta@&svc
CONNECT system/"&admin_pwd"@&svc

PROMPT Intento con la contraseña correcta. Esperado: ORA-28000 (cuenta bloqueada)
CONNECT prueba_lock/"PR##lab2026"@&svc
CONNECT system/"&admin_pwd"@&svc

PROMPT Estado de la cuenta. Esperado: LOCKED(TIMED)
SELECT username, account_status, lock_date, profile
FROM dba_users WHERE username = 'PRUEBA_LOCK';

PROMPT ============================================================
PROMPT PF-02 (A5.17) Rechazo de una contraseña débil
PROMPT Esperado: ORA-28003 (no cumple la función de verificación)
PROMPT ============================================================
CONNECT system/"&admin_pwd"@&svc
CREATE USER prueba_debil IDENTIFIED BY "abc123" PROFILE perfil_funcionario;

PROMPT ============================================================
PROMPT PF-03 (A5.15) Acceso a datos sensibles solo mediante rol
PROMPT ============================================================
CONNECT prueba_ti/"PR##lab2026"@&svc
PROMPT Sin rol. Esperado: ORA-00942
SELECT COUNT(*) FROM rrhh.empleados;

CONNECT system/"&admin_pwd"@&svc
GRANT rol_rrhh TO prueba_ti, prueba_conta;

CONNECT prueba_ti/"PR##lab2026"@&svc
PROMPT Con rol. Esperado: la consulta devuelve un conteo
SELECT COUNT(*) FROM rrhh.empleados;

PROMPT ============================================================
PROMPT PF-04 (A8.11) Enmascaramiento de columnas sensibles
PROMPT Esperado: CEDULA y SALARIO aparecen redactados (por ejemplo SALARIO = 0)
PROMPT ============================================================
SELECT nombre, cedula, salario FROM rrhh.empleados;

PROMPT ============================================================
PROMPT PF-05 (A8.3) Filtrado de filas con VPD
PROMPT ============================================================
PROMPT PRUEBA_TI. Esperado: solo filas del departamento TI
SELECT departamento, COUNT(*) AS filas
FROM rrhh.empleados
GROUP BY departamento;

CONNECT prueba_conta/"PR##lab2026"@&svc
PROMPT PRUEBA_CONTA. Esperado: solo filas del departamento CONTA
SELECT departamento, COUNT(*) AS filas
FROM rrhh.empleados
GROUP BY departamento;

PROMPT ============================================================
PROMPT PF-06 (A8.15) La auditoría registra la lectura de datos sensibles
PROMPT Esperado: aparecen las consultas de PRUEBA_TI y PRUEBA_CONTA
PROMPT ============================================================
CONNECT auditor_ext/"&auditor_pwd"@&svc
SELECT event_timestamp, dbusername, action_name, object_name
FROM unified_audit_trail
WHERE object_schema = 'RRHH'
  AND dbusername IN ('PRUEBA_TI', 'PRUEBA_CONTA')
  AND event_timestamp > SYSTIMESTAMP - INTERVAL '1' HOUR
ORDER BY event_timestamp DESC;

PROMPT ============================================================
PROMPT PF-07 (A5.33) Separación de funciones entre el DBA y la auditoría
PROMPT ============================================================
PROMPT Paso 1: el DBA operativo (ADMIN_BD) intenta manipular la auditoría.
PROMPT Las políticas de prueba no usan tablas de RRHH: así el error solo puede venir
PROMPT de la falta del privilegio AUDIT_ADMIN y no de que ADMIN_BD no vea la tabla (ORA-00942).
CONNECT admin_bd/"&admin_bd_pwd"@&svc
PROMPT 1a. Crear una política. Esperado: ORA-01031 (privilegios insuficientes)
CREATE AUDIT POLICY pol_prueba_segregacion ACTIONS LOGON;
PROMPT 1b. Desactivar la política que protege RRHH. Esperado: ORA-01031
NOAUDIT POLICY pol_rrhh_lectura;
PROMPT Si alguna de las dos líneas anteriores no dio error, el DBA puede alterar la auditoría: NO CUMPLE.

PROMPT Paso 2: el responsable de auditoría (AUDITOR_SEG) sí puede hacerlo.
PROMPT Esperado: la política se crea y luego se elimina sin errores.
CONNECT auditor_seg/"&audit_pwd"@&svc
BEGIN EXECUTE IMMEDIATE 'DROP AUDIT POLICY pol_prueba_segregacion'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE AUDIT POLICY pol_prueba_segregacion ACTIONS LOGON;
DROP AUDIT POLICY pol_prueba_segregacion;
PROMPT POL_RRHH_LECTURA debe seguir habilitada (el DBA no pudo desactivarla)
SELECT policy_name, enabled_option, success, failure
FROM audit_unified_enabled_policies WHERE policy_name = 'POL_RRHH_LECTURA';

CONNECT system/"&admin_pwd"@&svc

PROMPT ============================================================
PROMPT Limpieza de la prueba
PROMPT ============================================================
REVOKE rol_rrhh FROM prueba_ti, prueba_conta;
DROP USER prueba_lock CASCADE;
-- PRUEBA_DEBIL solo existe si PF-02 falló (la contraseña débil fue aceptada)
BEGIN EXECUTE IMMEDIATE 'DROP USER prueba_debil CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

SPOOL OFF

PROMPT ============================================================
PROMPT PF-08 (A8.13) se ejecuta en RMAN (rman target /):
PROMPT   RESTORE DATABASE VALIDATE;
PROMPT   RESTORE ARCHIVELOG ALL VALIDATE;
PROMPT Esperado: termina sin errores
PROMPT ============================================================
