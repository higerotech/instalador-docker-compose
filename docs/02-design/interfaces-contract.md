# Contrato de interfaces — install-docker.sh

* **Estado:** approved
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 0.2.0
* **Gate:** 1
* **Tipo de contrato:** CLI + efectos en el sistema de ficheros + códigos de salida

Este documento sustituye al contrato OpenAPI/AsyncAPI que pediría el Gate 1: el sistema no
expone una API de red, pero sí tiene una superficie pública estable que otros scripts y
runbooks van a consumir. Todo lo listado aquí está sujeto a SemVer.

## 1. Invocación

```bash
sudo bash install-docker.sh [opciones]
curl -fsSL <url-del-tag>/install-docker.sh | sudo bash -s -- [opciones]
```

Al usar la tubería, las opciones **deben** ir tras `-s --`. Sin eso, `bash` interpreta los
argumentos como propios y el script los recibe vacíos.

El script es **no interactivo por diseño**: nunca lee de la entrada estándar. Cuando se ejecuta
con `curl | bash`, la entrada estándar es el propio script, así que cualquier `read` corrompería
la ejecución.

## 2. Opciones

| Opción | Argumento | Por defecto | Estabilidad | Descripción |
|---|---|---|---|---|
| `--dry-run` | — | desactivado | Estable | Muestra todas las acciones sin modificar el sistema. |
| `--docker-version` | versión (`27.1.1`) | última del canal | Estable | Fija la versión de `docker-ce` y `docker-ce-cli`. |
| `--channel` | `stable` \| `test` | `stable` | Estable | Componente del repositorio APT de Docker. |
| `--docker-group` | usuario | ninguno | Estable | Añade el usuario al grupo `docker`. **Equivale a concederle root.** |
| `--no-docker-group` | — | activo | Estable | Explicita que no se añade a nadie. Excluyente con el anterior. |
| `--no-hardening` | — | desactivado | Estable | No escribe `daemon.json`. |
| `--force-hardening` | — | desactivado | Estable | Sobrescribe las claves del perfil ya presentes. |
| `--userns-remap` | usuario (opcional) | desactivado | Experimental | Activa `userns-remap`; `default` si se omite el valor. |
| `--skip-smoke` | — | desactivado | Estable | Omite el contenedor `hello-world`. |
| `--codename` | codename | autodetectado | Estable | Fuerza la suite del repositorio APT. |
| `--distro` | `debian` \| `ubuntu` | autodetectado | Estable | Fuerza el repositorio de Docker (derivados). |
| `--log-file` | ruta | `/var/log/instalador-docker-compose.log` | Estable | Ruta de la bitácora. |
| `--quiet` | — | desactivado | Estable | Solo advertencias y errores en la salida estándar. |
| `--version` | — | — | Estable | Imprime `install-docker.sh <versión>` y termina con 0. |
| `--help`, `-h` | — | — | Estable | Imprime la ayuda y termina con 0. |

**Combinaciones inválidas** (devuelven código 2):

- `--docker-group` junto con `--no-docker-group`.
- `--channel` con un valor distinto de `stable` o `test`.
- `--distro` con un valor distinto de `debian` o `ubuntu`.
- Cualquier opción no reconocida.
- `--docker-version`, `--docker-group` o `--codename` sin argumento.

## 3. Códigos de salida

| Código | Nombre | Significado | ¿El host queda modificado? |
|---|---|---|---|
| `0` | OK | Instalación completada y verificada | Sí, en el estado deseado |
| `1` | FAIL | Error genérico (fallo de APT, daemon que no arranca, usuario inexistente) | Parcialmente; se aplica rollback de APT si procede |
| `2` | USAGE | Uso inválido: opción desconocida o combinación incompatible | **No** |
| `3` | UNSUPPORTED | Distribución, codename o arquitectura no soportados | **No** |
| `4` | INTEGRITY | El fingerprint de la llave GPG no coincide con el esperado | **No** (el keyring creado se retira) |
| `5` | VERIFY | La instalación terminó pero la verificación posterior falló | Sí; requiere diagnóstico manual |

**Garantía de seguridad del contrato:** los códigos `2`, `3` y `4` implican que el host quedó
sin tocar. Es lo que permite ejecutar el instalador en un servidor de producción sin miedo a
que un error de tecleo deje el `apt` roto.

## 4. Efectos en el sistema de ficheros

| Ruta | Modo | Propietario | Cuándo se escribe | Reversible ante fallo |
|---|---|---|---|---|
| `/etc/apt/keyrings/docker.asc` | `0644` | root | Tras verificar el fingerprint | Sí, si se creó en esta ejecución |
| `/etc/apt/sources.list.d/docker.sources` | `0644` | root | Tras instalar la llave | Sí, si se creó en esta ejecución |
| `/etc/apt/sources.list.d/docker.list` | — | — | **Se elimina** si existe (formato heredado) | No |
| `/etc/docker/daemon.json` | `0644` | root | Al aplicar el endurecimiento | Sí, vía copia `.bak` |
| `/etc/docker/daemon.json.bak.<UTC>` | copia del original | root | Antes de cada fusión sobre un fichero existente | — |
| `/var/log/instalador-docker-compose.log` | `0640` | root | Durante toda la ejecución | No (es la traza) |

**No se escribe nada más.** El script no toca `/etc/ssh`, ni el firewall, ni `sysctl`, ni
ficheros de usuario. Es una restricción de diseño, no un olvido.

## 5. Variables de entorno

| Variable | Dirección | Uso |
|---|---|---|
| `DEBIAN_FRONTEND=noninteractive` | Fijada por el script | Evita diálogos de `debconf` durante APT |
| `NEEDRESTART_MODE=a` | Fijada por el script | Evita el prompt de `needrestart` en Debian 12+ |
| `SUDO_USER` | Leída | **No se usa para añadir al grupo docker.** Se documenta explícitamente: la versión base del proyecto lo hacía de forma automática y eso es justo la amenaza T5 |
| `EUID` | Leída | Comprobación de root |

## 6. Formato de la bitácora

Una línea por evento, en UTC e ISO 8601:

```
2026-08-30T14:22:01Z [START] install-docker.sh 1.0.0 — argumentos: --docker-group jeremi
2026-08-30T14:22:01Z [INFO] Sistema: Debian GNU/Linux 12 (bookworm) · repo=debian · codename=bookworm · arch=amd64
2026-08-30T14:22:03Z [INFO] Fingerprint verificado: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 (Docker Release CE deb)
2026-08-30T14:23:40Z [WARN] Añadiendo 'jeremi' al grupo 'docker': equivale a concederle root sin sudo (ADR-0007)
2026-08-30T14:23:45Z [END] Finalizado correctamente.
```

Niveles: `START`, `STEP`, `INFO`, `WARN`, `ERROR`, `END`. El formato es estable: cualquier
parser externo puede apoyarse en el prefijo de marca de tiempo y el nivel entre corchetes.

## 7. Perfil de endurecimiento aplicado

Contenido que el instalador converge en `daemon.json` (las claves ausentes se añaden; las
presentes se respetan salvo `--force-hardening`):

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "no-new-privileges": true,
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Soft": 65536, "Hard": 65536 }
  }
}
```

Con `--userns-remap` se añade además `"userns-remap": "<usuario>"`.

## 8. Política de compatibilidad

| Cambio | Impacto SemVer |
|---|---|
| Eliminar una opción o cambiar su significado | **MAYOR** |
| Cambiar una ruta de fichero escrita | **MAYOR** |
| Cambiar el significado de un código de salida existente | **MAYOR** |
| Cambiar un valor por defecto del perfil de endurecimiento | **MAYOR** (altera hosts ya instalados en la siguiente convergencia) |
| Añadir una opción nueva | MENOR |
| Añadir un código de salida nuevo | MENOR |
| Añadir una clave nueva al perfil | MENOR |
| Corregir un fallo sin alterar la superficie | PARCHE |
