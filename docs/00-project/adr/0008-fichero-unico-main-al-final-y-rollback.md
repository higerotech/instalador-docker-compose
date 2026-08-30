# ADR-0008: Fichero único con `main "$@"` en la última línea y rollback compensatorio

* **Estado:** accepted
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0008
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A10 Mishandling of Exceptional Conditions, A08 Software and Data Integrity Failures

## Contexto

Cuando se ejecuta `curl … | sudo bash`, el intérprete **no recibe un fichero: recibe un flujo**.
Bash lee, interpreta y ejecuta a medida que le llegan bytes. Si la conexión se corta a mitad —
red inestable, proxy que cierra, o un atacante que interrumpe deliberadamente— bash **ya ha
ejecutado todo lo que había leído hasta ese punto** y termina como si el script hubiera
acabado.

En el script base, escrito como una secuencia lineal de comandos, un corte justo después de
configurar el repositorio pero antes de instalar dejaría el host con el `docker.sources`
escrito y sin Docker. Peor: un corte en mitad de la línea de `apt-get remove` de paquetes
conflictivos podría ejecutar una eliminación parcial.

Esta es la amenaza **T4** (score 6.6). Y su vecina, **T10** (6.4): incluso sin truncamiento, si
`apt-get update` falla porque el codename no existe, el host queda con un repositorio inválido
que hace fallar **todas** las operaciones de APT posteriores, incluidas las actualizaciones de
seguridad.

## Decisión

Dos mecanismos complementarios.

### 1. Envoltura total en funciones

Todo el cuerpo ejecutable vive dentro de funciones. La **única sentencia ejecutable a nivel
superior es la última línea del fichero**:

```bash
main "$@"
```

Con esto, una descarga truncada define funciones que nunca se invocan y el script termina sin
efecto alguno. Es la diferencia entre "media instalación" y "ninguna instalación", y no cuesta
nada implementarla.

La estructura de un solo fichero es obligatoria: `curl | bash` no puede resolver `source` de
ficheros vecinos. La separación de responsabilidades se mantiene con funciones de una sola
razón de cambio y estado global declarado en un único bloque (ver `architecture.md`).

### 2. Rollback compensatorio del estado de APT

Un `trap ERR` invoca `rollback_apt_state`, que retira **solo lo que esa ejecución creó**:

- `docker.sources`, si no existía antes.
- `/etc/apt/keyrings/docker.asc`, si no existía antes.
- Restaura `daemon.json` desde la copia `.bak` si la fusión quedó a medias.

El rastreo se hace con banderas (`SOURCES_CREATED`, `KEYRING_CREATED`) puestas antes de
escribir, de modo que una re-ejecución sobre un host ya configurado **no borra** ficheros
legítimos preexistentes.

La garantía resultante está codificada en el contrato de interfaces: **los códigos de salida
2, 3 y 4 dejan el host sin tocar**.

## Alternativas consideradas

| Opción | Pros | Contras | Riesgo de seguridad |
|---|---|---|---|
| **Funciones + `main "$@"` + trap ERR** (elegida) | Neutraliza T4 con coste cero; rollback acotado a lo creado | Requiere disciplina: cualquier línea suelta a nivel superior rompe la garantía | Bajo |
| Script lineal (base de partida) | Más fácil de leer de arriba abajo | T4 y T10 sin mitigar | **Alto** |
| Descargar a fichero y luego ejecutar | Elimina el truncamiento de raíz | Rompe el `curl \| bash` de una línea, que es el requisito del producto | Bajo |
| Comprobar un marcador al final del script | Detecta truncamiento | Requiere leerse a sí mismo; frágil con la tubería | Medio |
| Rollback completo con snapshot del sistema | Reversión total | Desproporcionado; requiere LVM o btrfs | Bajo |

## Consecuencias

- **Positivas:** T4 neutralizada por construcción. T10 mitigada: un fallo no deja el `apt` del
  host roto, que es el peor daño colateral posible de un instalador (bloquearía las
  actualizaciones de seguridad del servidor).
- **Negativas / deuda asumida:**
  - **La garantía es frágil ante el mantenimiento**: basta con que alguien añada una línea
    ejecutable fuera de una función para perderla. Se protege con revisión en PR y se
    documenta aquí como invariante del proyecto.
  - El rollback no cubre lo ocurrido *después* de instalar paquetes: si `apt-get install`
    tiene éxito y falla el endurecimiento, Docker queda instalado. Es correcto — desinstalar
    Docker automáticamente sería más destructivo que dejarlo.
  - El `trap ERR` no se dispara en todos los contextos de Bash (subshells, comandos en
    condicionales). Se compensa comprobando explícitamente los puntos críticos.
- **Impacto en threat model:** controles principales de T4 y T10 (13.0 de score combinado).

## Condiciones de revisión

- Si el script crece hasta hacer inviable el fichero único → reevaluar la distribución
  (por ejemplo, un `.tar.gz` verificado en vez de un `curl | bash`), lo que exigiría revisar
  también ADR-0002.
- Si se añaden pasos que modifiquen el host antes de la instalación de paquetes → ampliar
  `rollback_apt_state`.
