# instalador-docker-compose

Instalador **gobernado y endurecido** de Docker Engine + plugin Compose para servidores base
Debian y Ubuntu. Un solo fichero, ejecutable por `curl`, que verifica la cadena de suministro
antes de instalar, aplica un perfil de configuración segura sin destruir lo que ya hubiera en
el host, y deja traza de lo que hizo.

## Instalación

### Verificada (recomendada en producción)

Comprueba el artefacto **antes** de concederle root:

```bash
V=v0.2.0
B="https://github.com/higerotech/instalador-docker-compose/releases/download/$V"

curl -fsSLO "$B/install-docker.sh"
curl -fsSLO "$B/SHA256SUMS"
sha256sum -c SHA256SUMS

sudo bash install-docker.sh --docker-group "$USER"
```

### Directa (tag inmutable)

```bash
curl -fsSL https://raw.githubusercontent.com/higerotech/instalador-docker-compose/v0.2.0/install-docker.sh \
  | sudo bash -s -- --docker-group "$USER"
```

> Usa siempre la URL de un **tag**, nunca la de `main`. `main` es la rama de desarrollo y solo
> debe usarse para pruebas ([ADR-0002](docs/00-project/adr/0002-distribucion-tag-inmutable-y-checksum.md)).
> Con la tubería, los argumentos van tras `-s --`.

### Ensayo, sin tocar el sistema

```bash
sudo bash install-docker.sh --dry-run
```

## Qué hace, y por qué así

| Comportamiento | Motivo |
|---|---|
| **Verifica el fingerprint de la llave GPG** de Docker antes de instalarla; aborta con código 4 si no coincide | El procedimiento oficial solo confía en TLS. Una CA comprometida o un proxy de inspección podrían hacer que APT aceptara paquetes falsificados ([ADR-0003](docs/00-project/adr/0003-verificacion-fingerprint-gpg-docker.md)) |
| **Rota los logs de contenedor** (10 MB × 3) por defecto | Docker no rota `json-file`: un contenedor ruidoso llena el disco y tumba el host entero |
| **Fusiona `daemon.json` sin destruir** lo existente, con copia de seguridad | Ejecutarlo en un host de producción con `data-root` o `insecure-registries` propios no debe tumbar el daemon ([ADR-0005](docs/00-project/adr/0005-endurecimiento-por-defecto-fusion-no-destructiva.md)) |
| **No añade a nadie al grupo `docker`** salvo `--docker-group USUARIO` | Pertenecer al grupo equivale a root sin `sudo`. El script base lo hacía automáticamente con `$SUDO_USER`; aquí es una decisión explícita y trazada ([ADR-0007](docs/00-project/adr/0007-grupo-docker-opt-in-explicito.md)) |
| **Todo el cuerpo vive en funciones**, con `main "$@"` como última línea | Una descarga truncada de `curl \| bash` ejecutaría medio script. Así no ejecuta nada ([ADR-0008](docs/00-project/adr/0008-fichero-unico-main-al-final-y-rollback.md)) |
| **Revierte el repositorio APT** si falla antes de instalar | Un `docker.sources` inválido rompe todas las actualizaciones de seguridad del host |
| **Converge en vez de cortocircuitar** si Docker ya está instalado | Re-ejecutarlo sirve para aplicar configuración, no solo para salir con un aviso |
| **Advierte del bypass de UFW** | Docker publica puertos saltándose UFW; es la causa de exposición accidental más común |
| **No envía telemetría** | Nada sale del host. Decisión de diseño, no omisión |

Opciones completas: `bash install-docker.sh --help` y
[contrato de interfaces](docs/02-design/interfaces-contract.md).

## Estado de los gates

| Gate | Fase | Estado |
|---|---|---|
| 0 | Requirements | ✅ cerrado (0.1.0) |
| 1 | Design | ✅ cerrado (0.2.0) |
| 2 | Build / despliegue real | 🚧 abierto — implementación y pruebas en verde; falta verificación en host con systemd |
| 3 | Testing | 🚧 abierto |
| 4 | Deployment | 🚧 abierto — faltan protecciones de rama y tags |
| 5 | Monitoring | 🚧 abierto |

Checklists en [`.ai-dlc/gates/`](.ai-dlc/gates/).

## Estructura

```
install-docker.sh       el instalador (fichero único, es el producto)
LICENSE                 GPL-3.0
.ai-dlc/                gates (checklists HITL) y plantillas de artefactos
.github/workflows/      ci.yml (5 tareas) y release.yml (publica con SHA256SUMS)
docs/
  00-project/           charter, glosario, clasificación de datos y las 9 ADRs
  01-requirements/      PRD con escenarios de abuso y trazabilidad ASVS (Gate 0)
  02-design/            arquitectura C4, threat model STRIDE/DREAD, contrato CLI (Gate 1)
  03-implementation/    runbook de instalación y operación, historial del repo
  04-testing/           estrategia de pruebas y brechas declaradas
  05-deployment/        pipeline de publicación y despliegue en olas
  06-monitoring/        observabilidad, SLOs y respuesta a incidentes
  architecture/         índice de todos los diagramas por eje y fase
scripts/                validate_mermaid.py, gitgraph_from_log.py
tests/                  suite: matriz en contenedores + fusión de daemon.json
```

## Pruebas

```bash
bash tests/run-all.sh      # ShellCheck + matriz + fusión + Mermaid (requiere Docker)
```

Estado en la última ejecución (2026-08-30): **ShellCheck sin hallazgos · 41/41 en la matriz de
contenedores · 14/14 en las pruebas de fusión · 24/24 diagramas válidos**.

Lo que la suite **no** cubre está declarado en
[docs/04-testing/test-strategy.md](docs/04-testing/test-strategy.md): la verificación real del
fingerprint GPG, systemd y la instalación real de paquetes requieren un host con systemd y se
cierran en el Gate 2.

## Distribuciones soportadas

| Distribución | Codenames | Arquitecturas |
|---|---|---|
| Debian | bullseye (11), bookworm (12), trixie (13) | amd64, armhf, arm64, ppc64el |
| Ubuntu | jammy (22.04), noble (24.04), resolute (26.04) | amd64, armhf, arm64, s390x, ppc64el |

Verificado en `docs.docker.com` el 2026-08-30. Derivados (Raspberry Pi OS, LMDE, Mint) mediante
`--distro` y `--codename`.

## Qué NO se versiona

- `SHA256SUMS` — lo genera el workflow de release en cada tag.
- Cualquier secreto, `.env`, clave o certificado. El repositorio es público
  ([ADR-0002](docs/00-project/adr/0002-distribucion-tag-inmutable-y-checksum.md)) y gitleaks lo
  verifica en cada push.

## Licencia

[GNU General Public License v3.0](LICENSE).

Implicación práctica para quien lo reutilice: si distribuyes una versión modificada de
`install-docker.sh` —dentro de una imagen, un repositorio interno o un producto—, debes
publicar el código modificado bajo la misma licencia. Usarlo tal cual para aprovisionar tus
propios servidores no impone ninguna obligación.

## Metodología

Proyecto gobernado con **AI-DLC**: cada fase produce documentación con diagramas Mermaid inline
en los tres ejes (estructura, comportamiento, trazabilidad) y cierra con un gate validado por
humano. Versionado según [Keep a Changelog + SemVer](CHANGELOG.md): Gate 0 → `0.1.0`,
Gate 1 → `0.2.0`, Gate 2 → `0.3.0`, … Gate 5 → `1.0.0`.

Los diagramas se validan en CI: un bloque Mermaid mal formado no llega a `main`.
