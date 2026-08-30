# Índice de diagramas

* **Estado:** approved
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 0.2.0

Mapa de todos los diagramas del proyecto: qué pregunta responde cada uno, en qué eje vive y
dónde está.

**Este índice no contiene diagramas, solo enlaces.** Cada diagrama vive *inline* junto al
artefacto que lo justifica, y solo existe una copia de cada uno. Duplicar el C4 Context aquí y
en el PRD garantizaría que uno de los dos quedase obsoleto.

## Eje estructura — ¿qué existe?

| Diagrama | Pregunta que responde | Fase | Ubicación |
|---|---|---|---|
| `C4Context` | ¿Qué es el sistema, quién lo usa y de qué depende? | 01 | [PRD](../01-requirements/instalacion-docker-endurecida.md#contexto-del-sistema-c4-context) |
| `C4Container` | ¿De qué piezas se compone y qué estado deja en el host? | 02 | [architecture.md](../02-design/architecture.md#vista-c4--container) |
| `C4Component` | ¿Cómo está organizado el interior del script? | 02 | [architecture.md](../02-design/architecture.md#vista-c4--component-interior-de-install-dockersh) |
| `erDiagram` | ¿Qué registra una instalación? | 02 | [architecture.md](../02-design/architecture.md#modelo-de-datos-y-dominio) |
| `classDiagram` | ¿Cuál es el modelo de configuración y dónde varía el comportamiento? | 02 | [architecture.md](../02-design/architecture.md#modelo-de-datos-y-dominio) |
| `C4Component` (test scope) | ¿Qué se ejerce de verdad y qué se simula? | 04 | [test-strategy.md](../04-testing/test-strategy.md#alcance-de-las-pruebas-sobre-la-arquitectura) |
| `C4Deployment` | ¿Dónde corre cada cosa, del tag al host? | 05 | [deployment.md](../05-deployment/deployment.md#topología-c4-deployment) |

## Eje comportamiento — ¿cómo fluye en el tiempo?

| Diagrama | Pregunta que responde | Fase | Ubicación |
|---|---|---|---|
| DFD inicial (`flowchart`) | ¿Por dónde cruzan los datos los límites de confianza? | 01 | [PRD](../01-requirements/instalacion-docker-endurecida.md#diagrama-de-flujo-de-datos-dfd-inicial) |
| DFD con 4 límites (`flowchart`) | ¿Qué alimenta el análisis STRIDE? | 02 | [threat-model.md](../02-design/threat-model.md#diagrama-de-flujo-de-datos-dfd-con-límites-de-confianza) |
| `sequenceDiagram` | ¿En qué orden ocurre una instalación y qué pasa cuando falla? | 02 | [architecture.md](../02-design/architecture.md#flujos-críticos-comportamiento) |
| `stateDiagram-v2` | ¿Cuál es el ciclo de vida del host destino? | 02 | [architecture.md](../02-design/architecture.md#ciclo-de-vida-del-host-destino) |
| `stateDiagram-v2` (transiciones) | ¿Qué transiciones están cubiertas por pruebas? | 04 | [test-strategy.md](../04-testing/test-strategy.md#pruebas-de-transición-de-estado) |
| `flowchart` (pipeline) | ¿Qué puertas atraviesa un artefacto antes de publicarse, y cómo se revierte? | 05 | [deployment.md](../05-deployment/deployment.md#pipeline-de-publicación-y-ruta-de-reversión) |
| `sequenceDiagram` (observabilidad) | ¿Cómo viaja una señal hasta la acción del operador? | 06 | [observability.md](../06-monitoring/observability.md#flujo-de-una-señal-hasta-la-acción) |
| `stateDiagram-v2` (incidente) | ¿Cómo se resuelve un incidente? | 06 | [observability.md](../06-monitoring/observability.md#ciclo-de-vida-de-un-incidente) |

## Eje trazabilidad / plan — ¿por qué y si se cumple?

| Diagrama | Pregunta que responde | Fase | Ubicación |
|---|---|---|---|
| `mindmap` | ¿Cuál es el alcance, quiénes son los actores y qué riesgos hay? | 00 | [charter.md](../00-project/charter.md#mapa-mental-del-alcance) |
| `journey` | ¿Dónde están los puntos de dolor del operador? | 01 | [PRD](../01-requirements/instalacion-docker-endurecida.md#journey-del-usuario) |
| `requirementDiagram` (satisfies) | ¿Qué componente satisface cada requisito? | 01 | [PRD](../01-requirements/instalacion-docker-endurecida.md#trazabilidad-de-requisitos) |
| `quadrantChart` (DREAD inicial) | ¿Qué amenazas priorizar? | 01 | [PRD](../01-requirements/instalacion-docker-endurecida.md#amenazas-priorizadas-dread-inicial) |
| `quadrantChart` (DREAD tras diseño) | ¿Siguen igual las prioridades tras diseñar los controles? | 02 | [threat-model.md](../02-design/threat-model.md#amenazas-priorizadas-dread) |
| `quadrantChart` (PxD) | ¿Dónde desplegar el artefacto según performance por dólar? | 02 | [ADR-0009](../00-project/adr/0009-placement-distribucion-y-cd.md) |
| `requirementDiagram` (verifies) | ¿Qué prueba verifica cada requisito? | 04 | [test-strategy.md](../04-testing/test-strategy.md#trazabilidad-requisito--prueba) |
| `gantt` | ¿En qué orden se despliega en la flota? | 05 | [deployment.md](../05-deployment/deployment.md#cutover-despliegue-en-la-flota) |
| `timeline` | ¿Cuál es el roadmap y qué caduca cuándo? | 06 | [observability.md](../06-monitoring/observability.md#roadmap) |
| `gitGraph` | ¿Cómo evolucionó el repositorio? | 03 | [repo-history.md](../03-implementation/repo-history.md) — derivado del historial real |

## Validación

Todos los bloques Mermaid se validan contra el parser oficial, en local y en CI:

```bash
python scripts/validate_mermaid.py docs
```

Un diagrama mal formado renderiza una caja de error en GitHub, así que la tarea
`docs-mermaid` del workflow bloquea el merge.

## Convenciones aplicadas

- **IDs estables entre diagramas**: `script`, `dockerrepo`, `daemonjson` designan lo mismo en
  todas las vistas, para poder seguir un elemento del Context al Deployment.
- **Rojo (`#b30000`) solo para superficies con control de seguridad**, nunca decorativo.
- **Gris (`#cccccc`)** para lo simulado o fuera de alcance en diagramas de pruebas.
- **Cada `Rel` lleva verbo y tecnología**: una relación sin protocolo a nivel Container es un
  olvido, no un estilo.
- **Caption obligatorio** bajo cada diagrama, indicando eje y fase, y diciendo qué hay que
  mirar. Un diagrama sin caption obliga al lector a adivinar por qué está ahí.
