# Gate 0 — Requirements

Cierre de la Fase 01. Marcar solo lo fundamentado (Human-in-the-Loop).

- [x] Charter con visión, alcance y no-scope explícito — `docs/00-project/charter.md`
- [x] Glosario / lenguaje ubicuo con tres contextos acotados — `docs/00-project/glossary.md`
- [x] Datos clasificados — `docs/00-project/data-classification.md` (sin PII de clientes; GDPR marginal por el usuario en la bitácora; **retención de bitácora: 90 días**, decisión humana)
- [x] PRD con requisitos funcionales RF01–RF12 — `docs/01-requirements/instalacion-docker-endurecida.md`
- [x] Escenarios negativos / de abuso documentados (**10 escenarios**, EA1–EA10)
- [x] Requisitos de seguridad RS01–RS08 mapeados a OWASP ASVS L2 y Top 10:2025
- [x] Threat assessment inicial: amenazas T1–T12 identificadas y priorizadas en cuadrante DREAD
- [x] Diagramas de evidencia: mindmap de alcance · journey · requirementDiagram · DFD + quadrant
- [x] Decisiones de alcance confirmadas por humano (2026-08-30): **instalador + hardening del daemon**, **repositorio público**, **distribución por tag SemVer + checksum**

**Estado Gate 0: CERRADO** (2026-08-30) — alcance, clasificación de datos, 10 escenarios de
abuso, requisitos de seguridad OWASP ASVS L2 y threat assessment T1–T12 validados por Jeremi
Alcala al aprobar las tres decisiones materiales del alcance.

Quedan visibles como `<TODO>` para el Gate 2, sin bloquear este gate:
- Confirmar si la advertencia de UFW basta o hace falta una regla `DOCKER-USER` opt-in.
- Desplegar la política de logrotate de la bitácora (propuesta: 90 días).
