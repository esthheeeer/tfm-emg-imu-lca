# Análisis electromiográfico y cinemático tras reconstrucción de LCA

Código del Trabajo Fin de Máster de Esther Rego Falagán
(Máster en Ingeniería para la Discapacidad y la Rehabilitación, URJC, 2026/2027).

## Qué hace este código
Procesa señales de EMG de superficie e IMU registradas durante las tareas
sit-to-stand y step-up, calcula la actividad muscular normalizada (%MVC),
el rango de movimiento (ROM) de cadera y rodilla y el índice de simetría
límbica (LSI), y genera las figuras de la memoria.

## Requisitos
- MATLAB R2025b con Signal Processing Toolbox.
- Sistema de adquisición: OT Bioelettronica Due+ Pro (OT BioLab).

## Estructura del repositorio
```
P1/   scripts del paciente 1  [P1.m]
P2/   ...
...
P8/
```

## Datos de entrada
Los datos de los participantes no se incluyen por protección de datos
(Reglamento UE 2016/679 y LO 3/2018). Para ejecutar el código hay que
colocar los archivos de cada paciente en su carpeta `PX/`.

Formato de los archivos (exportación de OT BioLab, `.csv`):
- 3 líneas de cabecera, separador `;` y coma decimal.
- Columna 1: tiempo (s). Frecuencia de muestreo: 2000 Hz.
- Columnas 2–49: señales de EMG e IMU. [Tabla: columna → señal/músculo/lado]
- Nombres de archivo: [p. ej. `ED18.csv` = tarea ..., `ei..`, `S..`, MVC ...]

## Ejecución
1. Coloca los archivos del paciente en `PX/`.
2. Abre MATLAB, sitúate en la carpeta `PX/` y ejecuta `[PX.m]`.
3. Genera: variables, tablas, figuras y se guardan en la misma carpeta y las figuras se guardan en la carpeta dentro de la otra de PX_figuras.
4. Repite para cada paciente (P1–P8).

## Cita
Rego Falagán, E. (2026). *Análisis electromiográfico y cinemático en pacientes
tras reconstrucción de ligamento cruzado anterior* [TFM]. Universidad Rey Juan Carlos.

## Licencia
MIT
