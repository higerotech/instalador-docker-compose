# Gate 2 — Build (implementación y despliegue real)

Cierre de la Fase 03. Marcar solo lo fundamentado (Human-in-the-Loop).

## Implementación

- [x] `install-docker.sh` 0.2.0 implementado con los controles de las ADRs 0002–0008
- [x] ShellCheck sin hallazgos sobre el instalador y los tres scripts de prueba
- [x] Matriz dry-run en contenedores reales: **41 aserciones, 41 pass** (Debian 12/13, Ubuntu 22.04/24.04, alpine)
- [x] Pruebas de fusión de `daemon.json`: **14 aserciones, 14 pass** (incluye JSON corrupto y `--force-hardening`)
- [x] CI con cinco tareas: ShellCheck, Mermaid, matriz en contenedores (incluida distro no soportada), fusión de daemon.json y gitleaks
- [x] Workflow de release que valida tag ↔ `SCRIPT_VERSION` ↔ `CHANGELOG.md` antes de publicar
- [x] Runbook de instalación y operación — `docs/03-implementation/deployment-runbook.md`
- [x] `repo-history.md` regenerado desde el historial real tras el primer commit y tag (`v0.1.0` = `465801f`, `v0.2.0` = `f674f5f`)

## Despliegue real en host destino (pendiente — requiere VM)

- [ ] Instalación real verificada en **Debian 12** sin errores, con systemd
- [ ] Instalación real verificada en **Debian 13**
- [ ] Instalación real verificada en **Ubuntu 22.04** y **24.04**
- [ ] **Verificación real del fingerprint GPG** (se omite en `--dry-run`): comprobar que la llave descargada coincide con el pin
- [ ] **Prueba negativa de integridad**: servir una llave que no coincida y confirmar salida con código 4 y host intacto
- [ ] Prueba de convergencia: segunda ejecución sobre host ya instalado no reinstala y respeta la configuración existente
- [ ] Aserción de bitácora: contiene `START`, el fingerprint verificado y `END` (cierra la brecha A09/T11)
- [ ] Aviso de UFW verificado en un host con UFW activo (T6, score 8.2)
- [ ] `docker compose version` operativo y smoke test `hello-world` correcto

## Seguridad de la construcción

- [x] gitleaks pinneado por versión y sha256 del tarball
- [x] `.gitattributes` fuerza LF en `*.sh` (un CRLF rompe el shebang en el host)
- [ ] **Protección de rama `main`** activada en GitHub — sin esto ADR-0002 no se sostiene
- [ ] **Protección de tags `v*`** activada (no reescribibles)
- [ ] logrotate de la bitácora desplegado (90 días, según `data-classification.md`)

## Decisiones pendientes de validación humana

- [ ] Confirmar si la advertencia de UFW basta o se añade una regla `DOCKER-USER` opt-in (`<TODO>` heredado de Gate 0)
- [ ] Confirmar si `--docker-version` debe pasar de opcional a obligatorio para la flota (ADR-0004)

**Estado Gate 2: ABIERTO** — la implementación y su verificación automatizada están completas
(55 aserciones en verde); falta el despliegue real en host con systemd, que es donde se ejercen
los controles que `--dry-run` no puede tocar.
