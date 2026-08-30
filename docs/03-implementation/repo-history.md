# Historial de implementación — instalador-docker-compose

* **Estado:** draft
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 03-implementation
* **Versión:** 0.2.0
* **Gate:** 2
* **Rama principal:** main
* **Estrategia de branching:** trunk-based con tags SemVer

## Documentación viva: este archivo se genera, no se escribe

El `gitGraph` de esta fase **no se redacta a mano**: se deriva del historial real del
repositorio. Escribirlo a mano garantiza que se desincronice del árbol de commits en la primera
semana, y un diagrama de trazabilidad que miente es peor que no tenerlo.

Regenera tras cada merge o tag:

```bash
python scripts/gitgraph_from_log.py . --branch main \
  --out docs/03-implementation/repo-history.md
```

El script emite el grafo Mermaid (commits, ramas, merges y tags) más la bitácora fiel de
commits. Tras generarlo, vuelve a anteponer esta cabecera de metadatos y la tabla de
trazabilidad de abajo.

## Estado actual

> **Pendiente del primer commit.** En el momento de redactar esta documentación el árbol de
> trabajo está completo pero el repositorio local aún no tiene historial, así que no hay nada
> que derivar. Este es el punto exacto del checklist del Gate 2 que queda abierto:
> *"`repo-history.md` regenerado desde el historial real tras el primer commit y tag"*.

Secuencia prevista para el arranque:

```bash
git init -b main
git remote add origin https://github.com/higerotech/instalador-docker-compose.git

git add .
git commit -m "feat: instalador gobernado de Docker con AI-DLC (Gate 0 y Gate 1)"

# Corte de versión al cerrar los gates ya validados
git tag -a v0.1.0 -m "Gate 0 — Requirements"
git tag -a v0.2.0 -m "Gate 1 — Design + implementación"

git push -u origin main --follow-tags
```

Al empujar `v0.2.0`, `release.yml` verificará que el tag coincide con `SCRIPT_VERSION` y que
existe la sección `## [0.2.0]` en el `CHANGELOG.md`, generará el `SHA256SUMS` y publicará la
release.

## Trazabilidad tag ↔ versión ↔ decisión

| Tag | Versión CHANGELOG | Gate | ADR / artefacto que lo motiva |
|---|---|---|---|
| `v0.1.0` | 0.1.0 | Gate 0 — Requirements | Charter, glosario, clasificación de datos, PRD DOCKER-INSTALL-001 |
| `v0.2.0` | 0.2.0 | Gate 1 — Design | ADR-0001 … ADR-0009, threat model STRIDE/DREAD, contrato CLI, `install-docker.sh` 0.2.0 |
| `v0.3.0` | *(pendiente)* | Gate 2 — Build | Verificación real en host con systemd, prueba negativa del fingerprint GPG |
| `v0.4.0` | *(pendiente)* | Gate 3 — Testing | Cierre de las brechas de `test-strategy.md` |
| `v0.5.0` | *(pendiente)* | Gate 4 — Deployment | Protecciones de rama y tags, primera release publicada |
| `v1.0.0` | *(pendiente)* | Gate 5 — Monitoring | Inventario de flota y proceso de incidentes ensayado |

## Invariantes de implementación que la revisión de PR debe proteger

Estas tres propiedades son controles de seguridad que viven en la *estructura* del código, no
en una línea concreta. Un refactor descuidado las elimina sin que ninguna prueba falle:

1. **`main "$@"` es la última línea del fichero y la única sentencia ejecutable de nivel
   superior.** Añadir cualquier comando fuera de una función rompe la mitigación de T4
   (ADR-0008).
2. **`$SUDO_USER` no se usa para conceder acceso al grupo `docker`.** Es una omisión
   deliberada, no un olvido (ADR-0007).
3. **`rollback_apt_state` solo retira lo que la ejecución actual creó**, según las banderas
   `SOURCES_CREATED` y `KEYRING_CREATED`. Retirar incondicionalmente destruiría configuración
   legítima al re-ejecutar (ADR-0008).
