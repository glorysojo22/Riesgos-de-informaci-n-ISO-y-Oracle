# Controles ISO/IEC 27001:2022 para la confidencialidad en la administración de bases de datos

**Artefacto en línea:** https://glorysojo22.github.io/Riesgos-de-informaci-n-ISO-y-Oracle/

Proyecto del curso **Administración de Bases de Datos** · Escuela de Informática, Universidad Nacional · II Ciclo 2026
Profesor: Johnny Villalobos Murillo · Estudiante: **Gloriana Sojo Pereira**

El proyecto analiza la confidencialidad de una base de datos Oracle a partir de las tareas del DBA. Relaciona cinco riesgos de confidencialidad con doce tareas, controles del Anexo A de ISO/IEC 27001:2022 y quince controles observables por un auditor externo. Los controles se implementaron y evaluaron en **Oracle Database 21c Express Edition** (base `XEPDB1`).

## Resultado

| Evaluación | Tipo | Fecha | RC | Semáforo |
|---|---|---|---|---|
| Tres Patitos · XEPDB1 | Simulada | 23/10/2026 | 53,5 % | Amarillo |
| Tres Patitos · XEPDB1 | Simulada | 23/11/2026 | 76,4 % | Verde |
| Laboratorio UNA · XEPDB1 | **Real**, antes de implementar | 25/10/2026 | **8,8 %** | Rojo |
| Laboratorio UNA · XEPDB1 | **Real**, después de implementar | 27/10/2026 | **86,6 %** | Verde |

RC (riesgo de confidencialidad controlado) = Σ(CSk · Wk) / ΣWk, donde CSk vale 1 si el control cumple (nivel 3-4), 0,5 si es parcial (nivel 2) y 0 si no cumple (nivel 0-1), y Wk es el valor I×P del riesgo más alto que atiende el control.

La empresa **Tres Patitos es ficticia**: sus evaluaciones son simulaciones solicitadas por el curso.

## Contenido

```
index.html                Redirige al artefacto (dirección principal de GitHub Pages)
artefacto/index.html      Artefacto web
informe/                  Informe final en PDF y declaración jurada de uso de IA
scripts/                  Scripts SQL de verificación, implementación y pruebas
evidencias/real/          Salidas reales de los scripts en Oracle 21c XE
evidencias/simulada/      Evaluaciones simuladas de Tres Patitos
```

## Cómo funciona el artefacto

El artefacto abre con las cuatro evaluaciones de la tabla de resultados ya cargadas, con sus criterios, evidencias y archivos adjuntos. Cada persona que lo abre puede registrar evaluaciones nuevas en la pestaña **Matriz**. Esas evaluaciones se guardan **solo en su propio navegador** (`localStorage`): no se comparten con otras personas ni modifican el repositorio. Si se borran los datos del navegador, el artefacto vuelve a las cuatro evaluaciones originales.

También se puede abrir sin conexión, con doble clic en `artefacto/index.html`.

## Orden de ejecución de los scripts

| Paso | Script | Conectado como | Genera |
|---|---|---|---|
| 1 | `00_crear_auditor.sql` | SYSTEM en XEPDB1 | Cuenta de solo lectura AUDITOR_EXT |
| 2 | `00b_permisos_auditor.sql` | SYS como SYSDBA en XEPDB1 | Lectura de las vistas de PT-04 y PT-05 |
| 3 | `02_datos_prueba.sql` | SYSTEM | Esquema RRHH con datos ficticios |
| 4 | `01_verificacion_controles.sql` | AUDITOR_EXT | `evidencia_verificacion.txt` (evaluación inicial) |
| 5 | `04_implementar_controles.sql` | SYSTEM | `evidencia_implementacion.txt` |
| 5b | `04b_completar_separacion_funciones.sql` | SYSTEM | Solo si el paso 5 no pudo crear ADMIN_BD y AUDITOR_SEG |
| 6 | `06_procedimientos_servidor.md` | SYSDBA, RMAN, sqlnet.ora | Respaldo cifrado, retención y cifrado de red |
| 7 | `03_pruebas_funcionales.sql` | SQL*Plus: `sqlplus /nolog` | `evidencia_funcional.txt` (PF-01 a PF-07) |
| 8 | PF-08 en RMAN | `rman target /` | Validación de la restauración |
| 9 | `05_cerrar_revision_privilegios.sql` | SYSTEM en SQL*Plus | `evidencia_revision_privilegios.txt` |
| 10 | `01_verificacion_controles.sql` | AUDITOR_EXT | Evaluación final |

Recomendaciones:

- Ejecutar los scripts que cambian de usuario (`03`) o que generan reportes largos en **SQL\*Plus**. SQL Developer puede dejar vacío el archivo del `SPOOL`.
- Las contraseñas nuevas deben cumplir `ORA12C_STRONG_VERIFY_FUNCTION`: 9 o más caracteres, con 2 mayúsculas, 2 minúsculas, 2 números y 2 caracteres especiales. No usar `&`, `@`, `/` ni comillas.
- **Ejecutar `04` solo en una base de laboratorio**: bloquea cuentas y revoca privilegios.

## Seguridad del repositorio

- Ningún script guarda contraseñas reales: todas se piden al ejecutar con `ACCEPT ... HIDE`.
- La contraseña `PR##lab2026` de las cuentas de prueba es ficticia y solo existe en el laboratorio.
- En `evidencias/real/evidencia_servidor.txt` la clave del respaldo RMAN está ocultada.
- A los archivos de evidencia se les quitaron los espacios en blanco del final de cada línea, que SQL*Plus agrega hasta completar el ancho de línea. El contenido no cambió.

## Referencias principales

- ISO/IEC 27001:2022 e ISO/IEC 27002:2022.
- Oracle Database 21c: Security Guide, Advanced Security Guide, Backup and Recovery User's Guide.
- Ley n.° 8968 de Protección de la Persona frente al Tratamiento de sus Datos Personales (Costa Rica).

La lista completa, en formato APA 7, está en el informe.

## Uso de inteligencia artificial

El proyecto se desarrolló con apoyo de Claude (Anthropic). El detalle de cada uso y su validación está en la declaración jurada de `informe/`.
