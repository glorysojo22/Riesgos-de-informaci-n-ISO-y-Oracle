# 06 · Procedimientos de servidor

Controles que no se pueden aplicar desde una sesión normal de la PDB porque necesitan **SYSDBA**, **RMAN** o **editar archivos del servidor**. Se ejecutan después de `04_implementar_controles.sql` y antes de `03_pruebas_funcionales.sql`.

> **Antes de empezar:** estos pasos reinician la base de datos y cambian archivos de configuración. Hacelos en tu máquina de laboratorio, no en un servidor compartido, y anotá cada comando y su resultado: esa anotación es la evidencia de estos controles.
>
> Si alguna función no está disponible en tu edición de Oracle XE, la prueba PT-00 lo muestra. En ese caso, documentalo como limitación del laboratorio en lugar de omitirlo.

Rutas de ejemplo para Oracle XE 21c en Windows (`C:\app\<usuario>\product\21c\...`) y Linux (`/opt/oracle/...`). Ajustalas a tu instalación.

---

## 1. A8.13 · Modo ARCHIVELOG

Sin este modo, solo se puede restaurar al momento del último respaldo completo.

```sql
-- Como SYSDBA en el contenedor raíz (CDB$ROOT)
sqlplus / as sysdba

SELECT log_mode FROM v$database;          -- si dice NOARCHIVELOG, seguir
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
SELECT log_mode FROM v$database;          -- debe decir ARCHIVELOG
```

## 2. A8.13 y A8.10 · Respaldos RMAN cifrados y retención

```text
rman target /

CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;
CONFIGURE CONTROLFILE AUTOBACKUP ON;

# Cifrado con contraseña: no necesita TDE. Guardá la contraseña en un lugar seguro:
# sin ella el respaldo no se puede restaurar.
SET ENCRYPTION ON IDENTIFIED BY "<ClaveRespaldo>" ONLY;
BACKUP DATABASE PLUS ARCHIVELOG;

DELETE NOPROMPT OBSOLETE;                 # elimina lo que quedó fuera de la retención
SHOW RETENTION POLICY;
LIST BACKUP SUMMARY;
```

Si en el futuro configurás TDE (sección 3), podés usar `CONFIGURE ENCRYPTION FOR DATABASE ON;` en lugar de la contraseña.

La prueba **PF-08** valida que el respaldo se pueda restaurar:

```text
RESTORE DATABASE VALIDATE;
RESTORE ARCHIVELOG ALL VALIDATE;
```

## 3. A8.12 · Cifrado TDE de los datos en reposo (opcional)

Es el paso más delicado: si perdés la contraseña del keystore, los datos cifrados no se pueden recuperar. Hacé primero el respaldo de la sección 2.

```sql
-- 3.1 Como SYSDBA en CDB$ROOT: ubicación del keystore (requiere reinicio)
ALTER SYSTEM SET WALLET_ROOT = '<ruta>/admin/XE/wallet' SCOPE = SPFILE;
SHUTDOWN IMMEDIATE;
STARTUP;
ALTER SYSTEM SET TDE_CONFIGURATION = 'KEYSTORE_CONFIGURATION=FILE' SCOPE = BOTH;

-- 3.2 Crear y abrir el keystore, y crear la llave maestra
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE IDENTIFIED BY "<ClaveKeystore>";
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "<ClaveKeystore>" CONTAINER = ALL;
ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY "<ClaveKeystore>" WITH BACKUP CONTAINER = ALL;
ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE FROM KEYSTORE IDENTIFIED BY "<ClaveKeystore>";

-- 3.3 En la PDB: cifrar el tablespace de datos
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER TABLESPACE users ENCRYPTION ONLINE USING 'AES256' ENCRYPT;

-- 3.4 Verificar (es lo que revisa PT-12)
SELECT wrl_type, status, wallet_type FROM v$encryption_wallet;
SELECT tablespace_name, encrypted FROM dba_tablespaces;
```

## 4. A8.20 y A8.5 · Cifrado de red y equipos permitidos (`sqlnet.ora`)

Archivo: `<ORACLE_HOME>/network/admin/sqlnet.ora`. Hacé una copia antes de editarlo.

```text
# Cifrado obligatorio de las conexiones (A8.20)
SQLNET.ENCRYPTION_SERVER = REQUIRED
SQLNET.ENCRYPTION_TYPES_SERVER = (AES256)
SQLNET.CRYPTO_CHECKSUM_SERVER = REQUIRED
SQLNET.CRYPTO_CHECKSUM_TYPES_SERVER = (SHA256)

# Solo estos equipos pueden conectarse (A8.20)
TCP.VALIDNODE_CHECKING = YES
TCP.INVITED_NODES = (localhost, 127.0.0.1)

# Solo versiones seguras de contraseña (A8.5)
SQLNET.ALLOWED_LOGON_VERSION_SERVER = 12a
```

Después, reiniciar el listener y comprobar:

```text
lsnrctl stop
lsnrctl start
lsnrctl status
```

```sql
-- Desde una sesión nueva (es lo que revisa PT-15): debe aparecer "AES256 Encryption service adapter"
SELECT network_service_banner FROM v$session_connect_info
WHERE sid = SYS_CONTEXT('USERENV', 'SID');
```

> `TCP.INVITED_NODES` bloquea cualquier equipo que no esté en la lista. Si te conectás desde otra máquina o una máquina virtual, agregá su IP o no vas a poder entrar.

## 5. Registro como evidencia

Guardá en un archivo de texto (por ejemplo `evidencia_servidor.txt`) los comandos ejecutados, su resultado y la fecha, y adjuntalo a la evaluación en la pestaña Matriz junto con los demás archivos.
