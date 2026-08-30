# Gate 4 — Deployment

Cierre de la Fase 05. Marcar solo lo fundamentado (Human-in-the-Loop).

Detalle en `docs/05-deployment/deployment.md`.

## Pipeline y artefacto

- [x] Pipeline de publicación diseñado con siete puertas previas a que el artefacto sea descargable
- [x] `release.yml` valida tag ↔ `SCRIPT_VERSION` ↔ entrada en `CHANGELOG.md`
- [x] `SHA256SUMS` generado y publicado automáticamente con cada release
- [x] Diagrama C4 Deployment de la topología completa
- [x] Ruta de reversión documentada, con la lista explícita de lo que **no** es reversible
- [ ] Workflow `release.yml` ejecutado con éxito al menos una vez
- [ ] `SHA256SUMS` verificado manualmente por alguien distinto de quien publicó

## Controles de repositorio (bloqueantes para ADR-0002)

- [ ] **Protección de rama `main`**: sin push directo, PR obligatorio, CI en verde requerido
- [ ] **Protección de tags `v*`**: no reescribibles ni borrables
- [ ] Revisión obligatoria de PR antes de merge

> Sin estos tres controles, la mitigación de T1 y T2 que sostiene ADR-0002 no existe: un tag
> "inmutable" que se puede reescribir no es una ancla de integridad.

## Despliegue en la flota

- [x] Estrategia de olas definida (laboratorio → no críticos → críticos) con `gantt` de cutover
- [ ] Runbook validado ejecutándolo paso a paso en un host real
- [ ] Ruta de reversión probada: restaurar `daemon.json` desde `.bak` en un host de pruebas
- [ ] Inventario de la flota con versión de instalador y de Docker por host
- [ ] `<TODO>` Definir quién aprueba la ola 3 (hosts críticos)

**Estado Gate 4: ABIERTO** — el diseño del pipeline y la estrategia de release están completos;
faltan la primera ejecución real del workflow y, sobre todo, activar las protecciones de rama y
tags en GitHub.
