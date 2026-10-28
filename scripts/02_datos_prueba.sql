-- ============================================================
-- 02_datos_prueba.sql
-- Crea el esquema sensible de ejemplo y los usuarios de prueba
-- que usan las pruebas funcionales (03_pruebas_funcionales.sql).
-- Proyecto: Controles ISO 27001:2022 para la confidencialidad en Oracle
-- Ejecutar como SYSTEM conectado a la PDB XEPDB1.
-- Los datos son ficticios. Las contraseñas son solo de laboratorio.
-- ============================================================

-- Esquema sin contraseña: nadie puede iniciar sesión como RRHH
CREATE USER rrhh NO AUTHENTICATION QUOTA UNLIMITED ON users;

CREATE TABLE rrhh.empleados (
  id           NUMBER        PRIMARY KEY,
  nombre       VARCHAR2(60)  NOT NULL,
  cedula       VARCHAR2(12)  NOT NULL,
  salario      NUMBER(12,2)  NOT NULL,
  departamento VARCHAR2(10)  NOT NULL
);

INSERT INTO rrhh.empleados VALUES (1, 'Ana Rojas',    '1-1111-1111',  950000, 'TI');
INSERT INTO rrhh.empleados VALUES (2, 'Luis Mora',    '2-2222-2222', 1200000, 'TI');
INSERT INTO rrhh.empleados VALUES (3, 'Carla Solis',  '3-3333-3333',  870000, 'CONTA');
INSERT INTO rrhh.empleados VALUES (4, 'Diego Vargas', '4-4444-4444', 1050000, 'CONTA');
COMMIT;

-- Clasificación de columnas sensibles (A5.12)
COMMENT ON COLUMN rrhh.empleados.cedula  IS 'CLASIF:SENSIBLE';
COMMENT ON COLUMN rrhh.empleados.salario IS 'CLASIF:SENSIBLE';

-- Usuarios de prueba, uno por departamento
CREATE USER prueba_ti    IDENTIFIED BY "PR##lab2026";
CREATE USER prueba_conta IDENTIFIED BY "PR##lab2026";
GRANT CREATE SESSION TO prueba_ti, prueba_conta;

SELECT * FROM rrhh.empleados ORDER BY id;
