-- ============================================================
-- 05_cerrar_revision_privilegios.sql
-- Detiene la captura de privilegios CAP_REVISION y genera el resultado
-- que consulta la prueba PT-05 (control A5.18, derechos de acceso).
-- Proyecto: Controles ISO 27001:2022 para la confidencialidad en Oracle
--
-- Ejecutar como SYSTEM conectado a la PDB XEPDB1, DESPUÉS de
-- 03_pruebas_funcionales.sql y ANTES de la verificación final con
-- 01_verificacion_controles.sql.
-- Genera el archivo evidencia_revision_privilegios.txt
-- Recomendado ejecutarlo en SQL*Plus (sqlplus system@localhost:1521/XEPDB1),
-- porque SQL Developer a veces deja el archivo del SPOOL vacío.
-- ============================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 200
SET FEEDBACK ON
WHENEVER SQLERROR CONTINUE

SPOOL evidencia_revision_privilegios.txt
SELECT SYSTIMESTAMP AS fecha_revision FROM dual;

-- Se puede ejecutar más de una vez: si la captura ya estaba detenida,
-- solo se vuelve a generar el resultado.
BEGIN
  BEGIN
    DBMS_PRIVILEGE_CAPTURE.DISABLE_CAPTURE('CAP_REVISION');
    DBMS_OUTPUT.PUT_LINE('Captura CAP_REVISION detenida.');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('La captura ya estaba detenida (' || SQLERRM || ').');
  END;
  DBMS_PRIVILEGE_CAPTURE.GENERATE_RESULT('CAP_REVISION');
  DBMS_OUTPUT.PUT_LINE('Resultado de CAP_REVISION generado.');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('No se pudo generar el resultado: ' || SQLERRM);
END;
/

PROMPT Estado de la captura. Esperado: ENABLED = N
SELECT name, type, enabled FROM dba_priv_captures WHERE name = 'CAP_REVISION';

PROMPT ============================================================
PROMPT Privilegios usados durante la captura (cuentas propias)
PROMPT ============================================================
SELECT DISTINCT username, sys_priv, obj_priv, object_owner, object_name
FROM dba_used_privs
WHERE capture = 'CAP_REVISION'
  AND username IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')
ORDER BY username, sys_priv, obj_priv;

PROMPT ============================================================
PROMPT Privilegios de SISTEMA otorgados que NO se usaron (candidatos a revocar)
PROMPT ROLENAME queda vacío en capturas de tipo DATABASE: el rol de origen se ve en DBA_ROLE_PRIVS.
PROMPT ============================================================
COLUMN username FORMAT A15
COLUMN sys_priv FORMAT A28
COLUMN rolename FORMAT A25
COLUMN object_owner FORMAT A15
SELECT DISTINCT username, sys_priv, NVL(rolename, '(no informado)') AS rolename
FROM dba_unused_privs
WHERE capture = 'CAP_REVISION' AND sys_priv IS NOT NULL
  AND username IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')
ORDER BY username, sys_priv;

PROMPT ============================================================
PROMPT Privilegios sobre OBJETOS que NO se usaron, resumidos por cuenta, rol y dueño
PROMPT (el detalle objeto por objeto ocupa miles de filas: casi todo viene de
PROMPT  SELECT_CATALOG_ROLE, que da lectura a las vistas del diccionario)
PROMPT ============================================================
SELECT username, NVL(rolename, '(no informado)') AS rolename, object_owner,
       COUNT(DISTINCT obj_priv || '.' || object_name) AS privilegios_no_usados
FROM dba_unused_privs
WHERE capture = 'CAP_REVISION' AND obj_priv IS NOT NULL
  AND username IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')
GROUP BY username, NVL(rolename, '(no informado)'), object_owner
ORDER BY username, privilegios_no_usados DESC;

PROMPT Privilegios sobre objetos de esquemas de NEGOCIO no usados (RRHH, FIN). Revisar uno por uno:
SELECT DISTINCT username, obj_priv, object_owner, object_name, NVL(rolename, '(no informado)') AS rolename
FROM dba_unused_privs
WHERE capture = 'CAP_REVISION' AND object_owner IN ('RRHH','FIN')
  AND username IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')
ORDER BY username, object_owner, object_name;

PROMPT ============================================================
PROMPT Acta de revisión de privilegios
PROMPT Para cada privilegio no usado, decidir: revocar o justificar.
PROMPT Registrar la decisión en el acta (fecha, responsable, decisión)
PROMPT y adjuntarla como evidencia de PT-05 en la evaluación.
PROMPT ============================================================

SPOOL OFF
