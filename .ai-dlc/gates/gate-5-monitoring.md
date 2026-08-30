# Gate 5 — Monitoring

Cierre de la Fase 06 y primer release productivo (`v1.0.0` de la documentación, `1.0.0` del
changelog). Marcar solo lo fundamentado (Human-in-the-Loop).

Detalle en `docs/06-monitoring/observability.md`.

## Diseño de observabilidad

- [x] Premisa declarada: **el instalador no emite telemetría**; la observabilidad es pull, no push
- [x] Ocho señales identificadas con su origen y qué amenaza detecta cada una
- [x] `sequenceDiagram` del flujo señal → acción, con sus cuatro ramas reales
- [x] `stateDiagram-v2` del ciclo de vida de un incidente, incluida la rama de reconstrucción
- [x] SLIs y SLOs definidos para un sistema de aprovisionamiento (corrección y homogeneidad, no disponibilidad)
- [x] `timeline` de roadmap con las dos caducidades declaradas (pin GPG y precios de ADR-0009)

## Implementación pendiente

- [ ] Inventario de la flota automatizado: versión de Docker, versión del instalador, hash de
      `daemon.json`, miembros del grupo `docker`
- [ ] Detección de deriva del perfil de endurecimiento con aviso al operador
- [ ] Escaneo periódico de puertos publicados en `0.0.0.0` (T6)
- [ ] Suscripción activa a los avisos de seguridad de Docker, con responsable asignado
- [ ] logrotate de la bitácora desplegado en toda la flota
- [ ] Proceso de incidentes ensayado al menos una vez

## Decisiones pendientes

- [ ] `<TODO>` Herramienta de inventario (Ansible ad-hoc, gestor de configuración o script
      propio). **Condiciona todos los criterios de implementación anteriores**: conviene
      resolverla primero.
- [ ] `<TODO>` Rotación de on-call. Hoy es Jeremi de facto, sin rotación formal.

## Revisiones con fecha de caducidad

- [ ] Reverificar el fingerprint GPG de Docker en cada release MENOR (ADR-0003)
- [ ] Reverificar los precios de la ADR-0009 antes del **2027-02-28**

**Estado Gate 5: ABIERTO** — el diseño de observabilidad está completo y es coherente con la
decisión de no emitir telemetría; la implementación depende de elegir la herramienta de
inventario.
