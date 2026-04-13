# Ejercicio nº2
Segundo ejercicio práctico de PLSQL para la asignatura de Aplicaciones de Bases de Datos

Hecho por: *Adrián Zamora Sánchez*/*azs1004@alu.ubu.es*

## Descripción
En este ejercicio se desarrolla un sistema básico de gestión de matrículas de cursos en Oracle PL/SQL.

Se han creado los siguientes procedimientos:

- **matricular_alumno**: realiza la matrícula de un alumno, comprobando existencia, estado de la edición, plazas disponibles y posible lista de espera.
- **ancelar_matricula**: cancela una matrícula y, si procede, promociona automáticamente a un alumno en espera.
- **registrar_pago**: registra el pago de una matrícula validando estado, importe y duplicidades.

También se incluyen tests automáticos para comprobar casos correctos, errores esperados de cada procedimiento, así como un test de integración de todo el sistema.
