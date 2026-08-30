# Gate 3 — Testing

Cierre de la Fase 04. Marcar solo lo fundamentado (Human-in-the-Loop).

Detalle y justificación de cada nivel en `docs/04-testing/test-strategy.md`.

## Cobertura conseguida — 108 aserciones automatizadas

- [x] Nivel estático: ShellCheck sin hallazgos (fijado a `v0.11.0`, verificado también contra 0.9.0)
- [x] Nivel unitario: perfil de endurecimiento y fusión de `daemon.json` — 14 aserciones
- [x] Nivel integración: matriz en 4 distribuciones + distro no soportada — 41 aserciones
- [x] Nivel seguridad: `gpg-integrity.sh` — 15 aserciones
- [x] Nivel sistema: `install-real.sh` — 38 aserciones
- [x] Nivel contrato: códigos de salida 0–4 verificados; ficheros escritos y no escritos
- [x] `requirementDiagram` con relaciones `verifies` — cierra el círculo abierto en Gate 0
- [x] Matriz OWASP Top 10:2025 × cobertura, con los huecos declarados

## Controles de seguridad con su ruta de fallo ejercida

Lo que distingue este gate del anterior: no basta con que el control exista, hay que provocar
la situación que debe rechazar.

- [x] **RS01 / T3 — prueba negativa del fingerprint GPG.** Origen HTTPS con CA propia que
      suplanta `download.docker.com` y sirve una llave de atacante bien formada. El instalador
      sale con código 4, no instala el keyring, no configura el repositorio y lo registra.
- [x] **T10 — rollback del estado de APT.** Fallo provocado *después* de escribir en el host:
      se retiran repositorio y keyring, y `apt-get update` del host sigue funcionando.
      **Esta prueba encontró que el control estaba roto** (ver abajo).
- [x] **T9 — pin de versión.** Una versión inexistente no se instala y se listan las disponibles.
- [x] **T8 — fusión no destructiva.** Con y sin `python3`, incluida la ruta degradada que no
      estaba ni declarada como brecha.
- [x] **T6 — aviso de bypass de UFW**, con doble de prueba.
- [x] **T11 — bitácora**: formato del contrato, fingerprint, argumentos y END.
- [x] Toda amenaza con score DREAD ≥ 6.0 tiene una prueba automatizada que ejerce su control
      (10 de 10).

## Defecto encontrado por este gate

- [x] **El rollback de T10 no funcionaba.** `set -euo pipefail` sin la `E`: bash no hereda la
      trampa `ERR` dentro de funciones, y como todo el script vive en funciones (ADR-0008),
      `on_error` nunca se ejecutaba. Corregido en **1.0.1** con `set -eEuo pipefail`.
      El threat model y ADR-0008 daban el control por implementado; lo estaba en el código y no
      en la práctica. Ambos documentos corregidos con una nota explícita, no en silencio.

## Pendiente

- [ ] Instalación real en la **matriz completa** en host con systemd: Debian 13 y Ubuntu 22.04
      (Debian 12 en la suite, Ubuntu 24.04 verificado a mano en Gate 2)
- [ ] systemd ejercitado en CI: `enable`, `restart`, `is-active` — requiere VM efímera
- [ ] Smoke test (`docker run hello-world`) en la suite — requiere daemon en marcha
- [ ] `--userns-remap` con daemon real, antes de promoverlo de experimental a estable
- [ ] Rutas de fallo de `apply_hardening` con daemon real (un `daemon.json` válido que impida
      arrancar debería restaurarse desde la copia)
- [ ] CI en verde en las siete tareas del workflow

**Estado Gate 3: ABIERTO** — la parte que dependía de **poder provocar fallos** está cerrada, y
es la que aportó valor real: encontró el único defecto del proyecto. Lo que queda depende de
disponer de una VM con systemd en CI, que es logística de infraestructura y no diseño de
pruebas.
