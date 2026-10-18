# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

Convención de corte por gate: Gate 0 → `0.1.0`, Gate 1 → `0.2.0`, Gate 2 → `0.3.0`,
Gate 3 → `0.4.0`, Gate 4 → `0.5.0`, Gate 5 → `1.0.0`.

**Esta convención dejó de aplicarse en `1.0.0`**, publicada al cerrar el Gate 2 en lugar del
Gate 5. El motivo está razonado en la entrada de esa versión: a partir de ella manda la
estabilidad del contrato público del instalador, no el avance por gates. Los Gates 3 a 5
avanzan como versiones `1.x`.

## [Unreleased]

Pendiente para el Gate 3: prueba negativa del fingerprint GPG, cobertura del resto de la matriz
de distribuciones en host real, prueba de convergencia y verificación del aviso de UFW.

### Seguridad

- **RS01 / T3 verificado en producción.** La bitácora del host Ubuntu 24.04 registra
  `2026-08-30T21:50:24Z [INFO] Fingerprint verificado: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88`.
  Contrastado contra la constante `DOCKER_GPG_FPR` de `v1.0.0` y contra la llave viva de
  `download.docker.com`: los tres coinciden. El control de cadena de suministro más importante
  del instalador deja de estar solo revisado y pasa a estar demostrado en un host real. Queda la
  prueba **negativa** (que una llave no coincidente produzca código 4) para el Gate 3.

### Cambiado

- Gate 2 cerrado **sin reservas**; trazabilidad de T3 y T11 actualizada en el threat model y
  brechas de `test-strategy.md` reclasificadas al Gate 3.
- Gate 4: marcado el `release.yml` ejecutado con éxito (`v1.0.0`) y la cadena artefacto ↔ tag ↔
  checksum verificada end-to-end. Sigue abierta la verificación por un **segundo operador**,
  que por definición no puede hacer quien publicó.

## [1.0.0] - 2026-08-30

Cierre del **Gate 2 — Build**, con el instalador verificado en un host real. Primer release
estable de la herramienta.

**Sobre el salto a `1.0.0`.** El corte por gate habría dado `0.3.0`. Se publica `1.0.0` como
desviación consciente de esa convención: SemVer mayor no mide madurez de proceso sino
**estabilidad del contrato público**, y el del instalador —14 opciones, 6 códigos de salida y
4 rutas de fichero— está especificado en `docs/02-design/interfaces-contract.md`, congelado y
ahora verificado en un host real. Los Gates 3 a 5 siguen abiertos y avanzarán como versiones
`1.x`: son madurez operativa, no cambios de contrato. A partir de aquí, cualquier cambio
incompatible de ese contrato exige `2.0.0`.

### Añadido

- **Verificación en host real (Ubuntu 24.04)**, evidencia que cierra el Gate 2: instalación
  completa sin intervención, `daemon.json` creado con el perfil de endurecimiento, daemon
  reiniciado sin fallo, servicio activo y habilitado en el arranque, driver `json-file` con
  rotación 10m × 3 efectiva, Docker 29.7.2 y Compose v5.5.0 operativos, smoke test `hello-world`
  correcto y bitácora escrita.
- Confirmado en esa ejecución que el grupo `docker` **solo** se concede con `--docker-group`
  explícito y que la advertencia de ADR-0007 aparece en la salida (control de T5, la amenaza de
  mayor score del modelo).
- `docs/03-implementation/repo-history.md` regenerado desde el historial real con
  `scripts/gitgraph_from_log.py`: `gitGraph` derivado, bitácora fiel de commits y tabla de
  trazabilidad tag ↔ commit ↔ versión ↔ gate. Cierra el ítem correspondiente del Gate 2.
- Sección de licencia en el `README.md` (GPL-3.0, heredada del commit inicial del repositorio)
  con la implicación práctica para quien redistribuya una versión modificada.
- **`release.yml` admite disparo manual** (`workflow_dispatch`) con el tag como entrada:
  `gh workflow run release.yml --ref main -f tag=vX.Y.Z`. Necesario porque GitHub no registra
  un workflow hasta que llega a la rama por defecto, de modo que un tag empujado antes nunca
  dispara su release; reescribir el tag para forzarlo violaría ADR-0002. El workflow hace
  checkout del contenido del tag sin tocarlo, y los tags de hito documental sin instalador
  terminan con aviso en lugar de fallar.

### Seguridad

- **Inmutabilidad de los tags impuesta por configuración**, no solo por convención: ruleset
  `Protect-Tags` sobre `refs/tags/v*` con `deletion`, `non_fast_forward` y `update`, sin actores
  con bypass. Es el control que faltaba para que la mitigación de T2 de ADR-0002 fuera real.
  Verificado con pruebas no destructivas: borrado y `--force` rechazados. Documentado en
  `docs/05-deployment/deployment.md` el coste operativo: un tag erróneo es permanente y se
  corrige publicando el siguiente, no borrándolo.

### Corregido

- **ShellCheck fijado a `v0.11.0` en CI y en local.** El binario preinstalado en
  `ubuntu-latest` es de otra versión y señala el mismo hallazgo con un código distinto
  (`SC2317` en lugar de `SC2329`), lo que producía verde en local y rojo en CI. Ahora ambos
  ejecutan la misma imagen y `tests/run-all.sh` desactiva los dos códigos, verificado contra
  las versiones 0.9.0 y 0.11.0.

## [0.2.0] - 2026-08-30

Cierre del **Gate 1 — Design**, e implementación del instalador.

### Añadido

- `install-docker.sh` 0.2.0: instalación gobernada y endurecida de Docker Engine + Compose.
  14 opciones, 6 códigos de salida, modo convergencia, `--dry-run` y bitácora auditable.
- `docs/02-design/architecture.md`: C4 Container y Component, secuencia del flujo crítico con
  sus cuatro ramas de fallo, ciclo de vida del host destino, modelo ER del estado de instalación
  y diagrama de clases de la configuración.
- `docs/02-design/threat-model.md`: DFD con cuatro límites de confianza, STRIDE por componente,
  amenazas T1–T12 priorizadas con DREAD y trazadas a control, y cuatro riesgos aceptados
  documentados.
- `docs/02-design/interfaces-contract.md`: contrato CLI completo (opciones, códigos de salida,
  ficheros escritos, formato de bitácora y política de compatibilidad SemVer).
- ADR-0001 (adopción de AI-DLC), ADR-0002 (distribución por tag inmutable + checksum, repositorio
  público), ADR-0003 (verificación del fingerprint GPG), ADR-0004 (repositorio oficial de Docker
  y pin de versión), ADR-0005 (endurecimiento por fusión no destructiva), ADR-0006 (userns-remap
  y rootless como opt-in), ADR-0007 (grupo docker opt-in), ADR-0008 (fichero único con `main`
  al final y rollback), ADR-0009 (placement de distribución y CD con matriz PxD).
- Fases 03–06: runbook de instalación y operación, estrategia de pruebas con brechas declaradas,
  pipeline de publicación con despliegue en olas, y diseño de observabilidad con SLOs.
- Suite de pruebas: `tests/dry-run-matrix.sh` (41 aserciones en Debian 12/13, Ubuntu 22.04/24.04
  y alpine), `tests/hardening-merge.sh` (14 aserciones sobre la fusión de `daemon.json`) y
  `tests/run-all.sh`.
- CI (`.github/workflows/ci.yml`) con cinco tareas: ShellCheck, validación Mermaid, matriz
  dry-run en contenedores (incluida la distribución no soportada), fusión de `daemon.json` y
  gitleaks (pinneado por versión y sha256). Los contenedores se lanzan con `docker run` desde
  el runner, no con `container:`, porque `actions/checkout` no funciona dentro de Alpine.
- Release (`.github/workflows/release.yml`): valida que el tag coincida con `SCRIPT_VERSION` y
  que exista la entrada en este changelog antes de generar `SHA256SUMS` y publicar.
- Checklists de los gates 2 a 5 en `.ai-dlc/gates/`.

### Seguridad

- Pin del fingerprint de la llave GPG de Docker `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`,
  verificado por descarga directa el 2026-08-30. Una llave que no coincida aborta con código 4
  sin modificar el host (mitiga T3).
- El grupo `docker` ya **no** se concede automáticamente a `$SUDO_USER`: requiere
  `--docker-group USUARIO` explícito, con advertencia y registro en bitácora (mitiga T5).
- Todo el cuerpo del script vive en funciones, con `main "$@"` como única sentencia ejecutable
  de nivel superior: una descarga truncada no ejecuta una instalación parcial (mitiga T4).
- Rollback del estado de APT ante fallo previo a la instalación: el host nunca queda con un
  repositorio inválido que bloquee sus actualizaciones de seguridad (mitiga T10).
- Rotación de logs de contenedor por defecto (10 MB × 3), `live-restore`, `no-new-privileges` y
  `default-ulimits` (mitiga T7).
- Fusión no destructiva de `daemon.json` con copia de seguridad previa; un JSON corrupto se
  conserva intacto (mitiga T8).
- Aviso activo cuando UFW está habilitado, por el bypass de puertos publicados (mitiga T6).

### Cambiado

- Formato del repositorio APT: `docker.sources` (deb822) en lugar de `docker.list`, conforme a
  la documentación vigente de Docker. El `docker.list` heredado se retira si existe.
- Artefactos de la fase 02 promovidos a `approved`; Gate 1 cerrado.

## [0.1.0] - 2026-08-30

Cierre del **Gate 0 — Requirements**.

### Añadido

- Scaffolding AI-DLC: estructura de fases 00–06, gate 0 (`.ai-dlc/gates/`) y plantillas de
  artefactos (`.ai-dlc/templates/`).
- `docs/00-project/charter.md`: visión, alcance con no-scope explícito, mindmap de alcance,
  restricciones, métricas de éxito y siete riesgos de alto nivel.
- `docs/00-project/glossary.md`: lenguaje ubicuo con tres contextos acotados (Instalación,
  Endurecimiento, Distribución).
- `docs/00-project/data-classification.md`: nueve categorías de dato, retención de bitácora de
  90 días y la premisa de que el instalador no recolecta ni transmite nada.
- `docs/01-requirements/instalacion-docker-endurecida.md` (DOCKER-INSTALL-001, ASVS L2):
  RF01–RF12, RS01–RS08, **10 escenarios de abuso**, C4 Context, journey del operador,
  trazabilidad de requisitos, DFD inicial y cuadrante DREAD con T1–T12.
- Validador de Mermaid vendorizado (`scripts/validate_mermaid.py`) y `.gitattributes` que fuerza
  LF en `*.sh` (un CRLF rompe el shebang en el host destino).
- Higiene del repositorio: `.gitignore` y `.gitleaks.toml` sin allowlists.

### Decisiones de alcance (validadas por humano)

- Alcance: **instalador + endurecimiento del daemon**. Desplegar stacks compose queda fuera.
- Visibilidad: **repositorio público** — elimina la filtración de token en el historial del shell.
- Distribución: **tag SemVer inmutable + checksum**, con `main` documentado solo para pruebas.

[Unreleased]: https://github.com/higerotech/instalador-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/higerotech/instalador-docker-compose/compare/v0.2.0...v1.0.0
[0.2.0]: https://github.com/higerotech/instalador-docker-compose/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/higerotech/instalador-docker-compose/releases/tag/v0.1.0
