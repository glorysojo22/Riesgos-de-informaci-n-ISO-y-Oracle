-- ============================================================
-- 01_verificacion_controles.sql
-- Batería de pruebas de configuración PT-00 a PT-15
-- Proyecto: Controles ISO 27001:2022 para la confidencialidad en Oracle
--
-- Ejecutar como AUDITOR_EXT (solo lectura) conectado a la PDB XEPDB1.
-- En SQL Developer: Ejecutar script (F5).
-- Genera el archivo de evidencia evidencia_verificacion.txt
--
-- Si una consulta falla con ORA-00942 por falta de privilegios,
-- ejecutarla con un usuario administrador y anotarlo en la evidencia.
-- ============================================================
SET LINESIZE 220
SET PAGESIZE 200
SET VERIFY OFF
SET FEEDBACK ON
SET TRIMSPOOL ON

-- Esquemas con información sensible (ajustar a tu laboratorio)
DEFINE esq1 = RRHH
DEFINE esq2 = FIN

SPOOL evidencia_verificacion.txt

PROMPT ============================================================
PROMPT PT-00 Ambiente de pruebas
PROMPT Esperado: versión, contenedor XEPDB1 y paquetes disponibles
PROMPT ============================================================
SELECT banner_full FROM v$version;

SELECT SYS_CONTEXT('USERENV', 'CON_NAME')     AS contenedor,
       SYS_CONTEXT('USERENV', 'SESSION_USER') AS usuario,
       SYSTIMESTAMP                           AS fecha_ejecucion
FROM dual;

SELECT owner, object_name AS paquete_disponible
FROM dba_objects
WHERE owner IN ('SYS', 'AUDSYS')
  AND object_type = 'PACKAGE'
  AND object_name IN ('DBMS_REDACT', 'DBMS_RLS', 'DBMS_PRIVILEGE_CAPTURE',
                      'DBMS_TSDP_MANAGE', 'DBMS_AUDIT_MGMT')
ORDER BY object_name;

SELECT parameter, value FROM v$option WHERE parameter = 'Unified Auditing';

PROMPT ============================================================
PROMPT PT-01 (CO-01, A5.12) Columnas sensibles etiquetadas
PROMPT Esperado: coinciden con el inventario documentado
PROMPT ============================================================
SELECT owner, table_name, column_name
FROM dba_col_comments
WHERE comments LIKE 'CLASIF:SENSIBLE%'
ORDER BY owner, table_name, column_name;

PROMPT ============================================================
PROMPT PT-02 (CO-02, A5.15) Privilegios directos a usuarios en esquemas sensibles
PROMPT Esperado: 0 filas
PROMPT ============================================================
SELECT p.grantee, p.owner, p.table_name, p.privilege
FROM dba_tab_privs p
JOIN dba_users u ON u.username = p.grantee
WHERE p.owner IN ('&esq1', '&esq2');

PROMPT ============================================================
PROMPT PT-03 (CO-03, A5.16) Cuentas abiertas sin acceso en 90 días
PROMPT Esperado: 0 filas (además, cruzar DBA_USERS con la planilla)
PROMPT ============================================================
-- Se excluyen los esquemas sin contraseña (NO AUTHENTICATION): nadie puede iniciar sesión con ellos.
SELECT username, account_status, last_login
FROM dba_users
WHERE oracle_maintained = 'N'
  AND authentication_type <> 'NONE'
  AND account_status = 'OPEN'
  AND (last_login IS NULL OR last_login < SYSTIMESTAMP - INTERVAL '90' DAY);

PROMPT ============================================================
PROMPT PT-04 (CO-04, A5.17) Cuentas abiertas con contraseña por defecto
PROMPT Esperado: 0 filas
PROMPT ============================================================
SELECT d.username, u.account_status
FROM dba_users_with_defpwd d
JOIN dba_users u ON u.username = d.username
WHERE u.account_status = 'OPEN';

PROMPT ============================================================
PROMPT PT-05 (CO-05, A5.18) Capturas de privilegios y privilegios no usados
PROMPT Esperado: al menos una captura; no usados revocados o justificados
PROMPT ============================================================
SELECT name, type, enabled FROM dba_priv_captures;

-- Resumen: el detalle de DBA_UNUSED_PRIVS ocupa decenas de miles de filas
-- (casi todas son vistas del diccionario de SELECT_CATALOG_ROLE).
PROMPT Privilegios de sistema no usados (cuentas propias)
SELECT DISTINCT capture, username, sys_priv
FROM dba_unused_privs
WHERE sys_priv IS NOT NULL
  AND username IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')
ORDER BY capture, username, sys_priv;

PROMPT Privilegios sobre objetos no usados, por cuenta y dueño (cuentas propias)
SELECT capture, username, object_owner, COUNT(*) AS no_usados
FROM dba_unused_privs
WHERE obj_priv IS NOT NULL
  AND username IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N')
GROUP BY capture, username, object_owner
ORDER BY capture, username, no_usados DESC;

PROMPT No usados sobre esquemas de negocio (RRHH, FIN). Esperado: 0 filas o justificados en el acta
SELECT capture, username, obj_priv, object_owner, object_name
FROM dba_unused_privs
WHERE object_owner IN ('RRHH','FIN');

PROMPT ============================================================
PROMPT PT-06 (CO-06, A5.33) Separación entre la administración de la base y la auditoría
PROMPT Esperado: 0 filas en la primera consulta, y al menos un responsable de auditoría
PROMPT           en la segunda que no tenga el rol DBA
PROMPT ============================================================
SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA' AND grantee <> 'SYS'
INTERSECT
SELECT grantee FROM dba_role_privs WHERE granted_role = 'AUDIT_ADMIN';

SELECT r.grantee AS responsable_auditoria,
       CASE WHEN EXISTS (SELECT 1 FROM dba_role_privs d
                         WHERE d.grantee = r.grantee AND d.granted_role = 'DBA')
            THEN 'SI' ELSE 'NO' END AS tiene_dba
FROM dba_role_privs r
WHERE r.granted_role = 'AUDIT_ADMIN'
  AND r.grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N');

PROMPT ============================================================
PROMPT PT-07 (CO-07, A8.2) Privilegios elevados
PROMPT Esperado: solo cuentas de la lista autorizada
PROMPT ============================================================
SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA';

SELECT grantee, privilege
FROM dba_sys_privs
WHERE privilege LIKE '%ANY%'
  AND grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N');

SELECT username, sysdba, sysoper FROM v$pwfile_users;

PROMPT ============================================================
PROMPT PT-08 (CO-08, A8.3) Políticas VPD en esquemas sensibles
PROMPT Esperado: todas con ENABLE = 'YES'
PROMPT ============================================================
SELECT object_owner, object_name, policy_name, enable
FROM dba_policies
WHERE object_owner IN ('&esq1', '&esq2');

PROMPT ============================================================
PROMPT PT-09 (CO-09, A8.5) Política de contraseñas por perfil
PROMPT Esperado: FAILED_LOGIN_ATTEMPTS <= 5, PASSWORD_LIFE_TIME <= 90,
PROMPT           función de verificación definida; 0 cuentas con perfil DEFAULT
PROMPT ============================================================
SELECT profile, resource_name, limit
FROM dba_profiles
WHERE resource_name IN ('FAILED_LOGIN_ATTEMPTS', 'PASSWORD_LIFE_TIME',
                        'PASSWORD_LOCK_TIME', 'PASSWORD_VERIFY_FUNCTION')
ORDER BY profile, resource_name;

SELECT username
FROM dba_users
WHERE oracle_maintained = 'N' AND profile = 'DEFAULT';

PROMPT ============================================================
PROMPT PT-10 (CO-10, A8.10) Objetos de esquemas sensibles en la papelera
PROMPT Esperado: 0 filas. Complementar en RMAN con: SHOW RETENTION POLICY;
PROMPT ============================================================
SELECT owner, original_name, droptime
FROM dba_recyclebin
WHERE owner IN ('&esq1', '&esq2');

PROMPT ============================================================
PROMPT PT-11 (CO-11, A8.11) Columnas sensibles sin política de redacción
PROMPT Esperado: 0 filas
PROMPT ============================================================
SELECT c.owner, c.table_name, c.column_name
FROM dba_col_comments c
WHERE c.comments LIKE 'CLASIF:SENSIBLE%'
  AND NOT EXISTS (SELECT 1
                  FROM redaction_columns r
                  WHERE r.object_owner = c.owner
                    AND r.object_name  = c.table_name
                    AND r.column_name  = c.column_name);

SELECT object_owner, object_name, policy_name, enable FROM redaction_policies;

PROMPT ============================================================
PROMPT PT-12 (CO-12, A8.12) Keystore, tablespaces cifrados y roles de exportación
PROMPT Esperado: STATUS = OPEN; ENCRYPTED = YES; roles solo en cuentas autorizadas
PROMPT ============================================================
SELECT wrl_type, status, wallet_type FROM v$encryption_wallet;

SELECT tablespace_name, encrypted
FROM dba_tablespaces
WHERE contents = 'PERMANENT'
  AND tablespace_name NOT IN ('SYSTEM', 'SYSAUX');

-- Solo cuentas propias (las de Oracle y los roles internos se omiten)
SELECT grantee, granted_role
FROM dba_role_privs
WHERE granted_role IN ('DATAPUMP_EXP_FULL_DATABASE', 'EXP_FULL_DATABASE', 'DBA')
  AND grantee IN (SELECT username FROM dba_users WHERE oracle_maintained = 'N');

PROMPT ============================================================
PROMPT PT-13 (CO-13, A8.13) Modo de archivado, último respaldo y piezas sin cifrar
PROMPT Esperado: ARCHIVELOG; respaldo de menos de 24 h; 0 piezas sin cifrar
PROMPT ============================================================
SELECT log_mode FROM v$database;

SELECT MAX(end_time) AS ultimo_respaldo
FROM v$rman_backup_job_details
WHERE status = 'COMPLETED';

SELECT COUNT(*) AS piezas_sin_cifrar
FROM v$backup_piece
WHERE encrypted = 'NO' AND status = 'A';

PROMPT ============================================================
PROMPT PT-14 (CO-14, A8.15) Políticas de auditoría habilitadas y eventos recientes
PROMPT Esperado: políticas de inicios fallidos y de tablas sensibles; eventos en 7 días
PROMPT ============================================================
SELECT policy_name, enabled_option, entity_name
FROM audit_unified_enabled_policies;

SELECT action_name, COUNT(*) AS eventos
FROM unified_audit_trail
WHERE event_timestamp > SYSTIMESTAMP - INTERVAL '7' DAY
GROUP BY action_name
ORDER BY eventos DESC;

PROMPT ============================================================
PROMPT PT-15 (CO-15, A8.20) Cifrado de la conexión actual
PROMPT Esperado: aparece un servicio de cifrado (por ejemplo AES256)
PROMPT Además revisar sqlnet.ora: SQLNET.ENCRYPTION_SERVER = REQUIRED,
PROMPT TCP.VALIDNODE_CHECKING = YES, TCP.INVITED_NODES
PROMPT ============================================================
SELECT network_service_banner
FROM v$session_connect_info
WHERE sid = SYS_CONTEXT('USERENV', 'SID');

SPOOL OFF
PROMPT Fin de la verificación. Evidencia guardada en evidencia_verificacion.txt
