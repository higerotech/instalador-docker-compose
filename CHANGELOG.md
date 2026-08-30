# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

Convención de corte por gate: Gate 0 → `0.1.0`, Gate 1 → `0.2.0`, Gate 2 → `0.3.0`,
Gate 3 → `0.4.0`, Gate 4 → `0.5.0`, Gate 5 → `1.0.0` (primer release productivo).

## [Unreleased]

Pendiente para `0.2.0` (cierre del Gate 1): arquitectura C4, threat model STRIDE/DREAD, ADRs,
contrato de interfaces e implementación del instalador.

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

[Unreleased]: https://github.com/higerotech/instalador-docker-compose/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/higerotech/instalador-docker-compose/releases/tag/v0.1.0
