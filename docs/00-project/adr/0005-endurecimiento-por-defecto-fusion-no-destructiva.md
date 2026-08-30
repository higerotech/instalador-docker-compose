# ADR-0005: Endurecer el daemon por defecto, aplicándolo por fusión no destructiva

* **Estado:** accepted
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0005
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A02 Security Misconfiguration, A10 Mishandling of Exceptional Conditions

## Contexto

Docker recién instalado tiene un valor por defecto que causa incidentes reales de forma
rutinaria: **no rota los logs de los contenedores**. El driver `json-file` crece sin límite
hasta llenar el disco y tumbar el host entero, no solo el contenedor culpable (amenaza T7,
score 7.2 — la tercera más alta del modelo).

Pero aplicar configuración a `/etc/docker/daemon.json` tiene su propio riesgo, y es grave: si
el instalador se ejecuta en un host de producción que ya tiene `data-root` apuntando a otro
disco o `insecure-registries` configurado, sobrescribir ese fichero **tumba el daemon y con él
todos los contenedores en ejecución** (amenaza T8, score 6.8).

Las dos amenazas tiran en direcciones opuestas: endurecer exige escribir, no romper exige no
escribir.

## Decisión

**Se endurece por defecto, y se escribe mediante fusión no destructiva.**

Perfil aplicado, con la justificación de cada clave:

| Clave | Valor | Por qué |
|---|---|---|
| `log-driver` | `json-file` | Explícito, para que `log-opts` tenga efecto garantizado |
| `log-opts.max-size` | `10m` | Límite por fichero de log |
| `log-opts.max-file` | `3` | Máximo 30 MB por contenedor — mitiga T7 |
| `live-restore` | `true` | Los contenedores sobreviven al reinicio del daemon |
| `no-new-privileges` | `true` | Impide escalada vía binarios setuid dentro del contenedor |
| `default-ulimits.nofile` | `65536/65536` | Evita agotar descriptores del host |

Algoritmo de escritura:

1. Si `daemon.json` **no existe** → se escribe el perfil completo.
2. Si **existe** → copia de seguridad `daemon.json.bak.<UTC>`, y fusión con `python3`:
   - las claves del perfil que **faltan** se añaden;
   - las que **ya existen con otro valor** se **respetan** y se reportan al operador;
   - las claves ajenas al perfil (`data-root`, `insecure-registries`, …) **nunca se tocan**.
3. Con `--force-hardening` el perfil gana sobre las claves en conflicto (las ajenas se siguen
   preservando).
4. Si el JSON existente es **inválido** o la fusión falla → se restaura la copia y se continúa
   **sin endurecer**, avisando. Preferimos un host sin rotación de logs a un host sin daemon.
5. Si no hay `python3` → no se fusiona; se conserva el fichero intacto y se imprime el perfil
   para aplicarlo a mano.
6. Tras escribir, `systemctl restart docker`. Si el daemon no arranca, se informa de la ruta de
   la copia `.bak` y se sale con error.

**Se descartaron dos claves** que aparecen en muchas guías de hardening:

- `userland-proxy: false` — es una optimización de rendimiento, no un control de seguridad, y
  puede romper el acceso a puertos publicados en ciertas configuraciones de kernel.
- `icc: false` — rompe la comunicación entre contenedores en la red bridge por defecto, que es
  comportamiento del que dependen muchos `docker-compose.yml` existentes.

Incluirlas por defecto convertiría un instalador en una fuente de averías sutiles. Se
documentan en el runbook como ajustes opcionales conscientes.

## Alternativas consideradas

| Opción | Pros | Contras | Riesgo de seguridad |
|---|---|---|---|
| **Endurecer por defecto con fusión no destructiva** (elegida) | Mitiga T7 sin exponerse a T8; el operador conserva el control | Necesita `python3`; comportamiento algo más complejo de explicar | Bajo |
| Sobrescribir `daemon.json` siempre | Estado final predecible y homogéneo | Destruye configuración de hosts en producción | **Alto** (T8) |
| No tocar `daemon.json`; solo documentar | Cero riesgo de romper nada | T7 queda sin mitigar y es la amenaza que más incidentes causa | **Alto** (T7) |
| Endurecer solo con `--hardening` explícito | El operador decide | El valor por defecto es el que acaba aplicándose en el 90% de los hosts; un default inseguro es una decisión, no una neutralidad | Medio |
| Fusionar con `jq` | Herramienta natural para JSON | `jq` no viene instalado en Debian/Ubuntu base; habría que añadir una dependencia | Bajo |

## Consecuencias

- **Positivas:** T7 mitigada en todos los hosts nuevos. T8 mitigada en los existentes. La
  re-ejecución del instalador es segura sobre un host en producción, que es lo que hace útil el
  modo convergencia.
- **Negativas / deuda asumida:**
  - Se depende de `python3` para la fusión. Presente en instalaciones de servidor estándar,
    ausente en imágenes mínimas; se degrada de forma controlada.
  - Las copias `.bak.<timestamp>` **se acumulan** con cada fusión. No se purgan
    automáticamente a propósito; el runbook incluye el paso de limpieza.
  - `live-restore` es **incompatible con Swarm**. Aceptado: Swarm está fuera de alcance.
  - Un host cuyo operador ya había fijado `max-size: 1g` conservará ese valor y el instalador
    solo lo reportará. Es intencionado, pero significa que "endurecido" no implica "idéntico"
    en toda la flota.
- **Impacto en threat model:** mitiga T7 y T8, que juntas suman 14.0 de score DREAD.

## Condiciones de revisión

- Si algún host adopta Swarm → revisar `live-restore`.
- Si aparecen incidentes por `no-new-privileges` en cargas legítimas.
- Si `python3` deja de estar disponible en el parque → evaluar empaquetar un fusionador en awk.
