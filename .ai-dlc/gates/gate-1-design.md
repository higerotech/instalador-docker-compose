# Gate 1 — Design

Cierre de la Fase 02. Marcar solo lo fundamentado (Human-in-the-Loop).

- [x] Arquitectura definida con su restricción rectora (fichero único por `curl | bash`) — `docs/02-design/architecture.md`
- [x] Diagramas C4 Container y Component con límites de confianza y tags OWASP
- [x] Comportamiento documentado: sequence del flujo crítico (con sus 4 ramas de fallo) y stateDiagram del ciclo de vida del host
- [x] Modelo de dominio: erDiagram del estado de instalación y classDiagram de la configuración
- [x] Threat model STRIDE completo por componente — `docs/02-design/threat-model.md`
- [x] Amenazas priorizadas con DREAD (T1–T12), **todas con control trazable a ADR o requisito**
- [x] Contrato de interfaces (CLI, códigos de salida, ficheros escritos, política SemVer) — `docs/02-design/interfaces-contract.md`
- [x] ADRs de decisiones clave — `docs/00-project/adr/` (0001–0009, todas `accepted`)
- [x] **ADR de deployment placement con matriz PxD y precios verificados con fuente y fecha** — ADR-0009
- [x] Tabla de patrones de seguridad por amenaza DREAD priorizada — `architecture.md`
- [x] Riesgos aceptados documentados de forma explícita (4) — `threat-model.md`
- [x] Todos los diagramas Mermaid validados contra el parser oficial (24 bloques, 0 fallos)

**Estado Gate 1: CERRADO** (2026-08-30) — arquitectura, threat model STRIDE/DREAD, contrato de
interfaces y las nueve ADRs validados por Jeremi Alcala.

Decisiones estructurales que este gate deja fijadas:
- **ADR-0002**: distribución por tag inmutable + `SHA256SUMS`; `main` solo para pruebas.
- **ADR-0003**: pin del fingerprint GPG `9DC8…CD88`, verificado por descarga directa.
- **ADR-0005**: endurecimiento por defecto con fusión no destructiva.
- **ADR-0007**: grupo `docker` opt-in explícito; `$SUDO_USER` deliberadamente no se usa.
- **ADR-0008**: `main "$@"` como última línea — invariante del proyecto.

Residuos aceptados que **no** bloquean el gate pero deben vigilarse:
1. El operador puede saltarse la verificación de integridad (mitigación documental).
2. El pin del fingerprint caducará si Docker rota su llave (fallo seguro, dependencia operativa).
3. No hay firma GPG/Sigstore del artefacto: el checksum no protege ante cuenta comprometida.
4. `live-restore` es incompatible con Swarm (fuera de alcance).
