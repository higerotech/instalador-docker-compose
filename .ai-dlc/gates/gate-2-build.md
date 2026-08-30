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

## Despliegue real en host destino

Evidencia: ejecución del 2026-08-30 desde la URL del repositorio en un host Ubuntu 24.04,
instalación completa sin intervención.

- [x] Instalación real verificada en **Ubuntu 24.04** sin errores, con systemd
- [x] `daemon.json` **creado con el perfil de endurecimiento** y daemon reiniciado sin fallo
- [x] Servicio docker **activo y habilitado en el arranque** (symlinks de systemd creados)
- [x] Driver de logs efectivo `json-file` con **rotación 10m × 3** confirmada por `docker info`
- [x] `docker compose version` operativo (Docker 29.7.2, Compose v5.5.0)
- [x] Smoke test `hello-world` ejecutado correctamente
- [x] Grupo `docker` concedido **solo por `--docker-group` explícito**, con la advertencia de ADR-0007 visible en la salida (T5)
- [x] Bitácora escrita en `/var/log/instalador-docker-compose.log`
- [ ] Instalación real verificada en **Debian 12** y **Debian 13**
- [ ] Instalación real verificada en **Ubuntu 22.04**
- [ ] **Verificación real del fingerprint GPG**: confirmar en la bitácora la línea `Fingerprint verificado` (se omite en `--dry-run`, y quedó fuera de la captura). Comprobar con:
      `sudo grep -i fingerprint /var/log/instalador-docker-compose.log`
- [ ] Prueba de convergencia: segunda ejecución sobre el host ya instalado no reinstala y respeta la configuración existente
- [ ] Aviso de UFW verificado en un host con UFW activo (T6, score 8.2)
- [ ] **Prueba negativa de integridad**: servir una llave que no coincida y confirmar salida con código 4 y host intacto → **diferida al Gate 3**, requiere montar un origen falso

## Seguridad de la construcción

- [x] gitleaks pinneado por versión y sha256 del tarball
- [x] `.gitattributes` fuerza LF en `*.sh` (un CRLF rompe el shebang en el host)
- [x] **Protección de rama `main`** activada en GitHub (ruleset `Protect-Main`) — ADR-0002
- [x] **Protección de tags `v*`** activada (ruleset `Protect-Tags`: no reescribibles ni borrables)
- [ ] logrotate de la bitácora desplegado (90 días, según `data-classification.md`)

## Decisiones pendientes de validación humana

- [ ] Confirmar si la advertencia de UFW basta o se añade una regla `DOCKER-USER` opt-in (`<TODO>` heredado de Gate 0)
- [ ] Confirmar si `--docker-version` debe pasar de opcional a obligatorio para la flota (ADR-0004)

**Estado Gate 2: CERRADO** (2026-08-30) — la implementación, sus 55 aserciones automatizadas y
el **despliegue real en un host Ubuntu 24.04** están verificados. El instalador hizo en un host
real exactamente lo que el diseño prometía: endureció el daemon, dejó el servicio activo, aplicó
la rotación de logs, concedió el grupo `docker` solo bajo petición explícita y dejó traza.

Se difieren al Gate 3, con decisión humana explícita y sin bloquear este gate:
- La prueba negativa del fingerprint GPG (requiere montar un origen falso).
- La cobertura del resto de la matriz de distribuciones (Debian 12/13, Ubuntu 22.04) en host real.
- La prueba de convergencia y la del aviso de UFW.

Queda pendiente de confirmación puntual la línea `Fingerprint verificado` en la bitácora del
host, que quedó fuera de la captura de la ejecución.
