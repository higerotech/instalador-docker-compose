#!/usr/bin/env bash
#===============================================================================
# install-docker.sh — Instalación gobernada y endurecida de Docker Engine
#                     + Compose plugin en Debian / Ubuntu.
#
# Proyecto: higerotech/instalador-docker-compose  (metodología AI-DLC)
# Contrato de interfaz: docs/02-design/interfaces-contract.md
#
# Uso local:
#   sudo bash install-docker.sh [opciones]
#
# Uso remoto (versión inmutable — RECOMENDADO):
#   curl -fsSL https://raw.githubusercontent.com/higerotech/instalador-docker-compose/v0.2.0/install-docker.sh \
#     | sudo bash -s -- --docker-group "$USER"
#
# Uso remoto con verificación de integridad (máxima garantía — ADR-0002):
#   V=v0.2.0; B=https://github.com/higerotech/instalador-docker-compose/releases/download/$V
#   curl -fsSLO "$B/install-docker.sh" && curl -fsSLO "$B/SHA256SUMS"
#   sha256sum -c SHA256SUMS && sudo bash install-docker.sh
#
# NOTA DE SEGURIDAD (T4/RS03): todo el cuerpo vive dentro de funciones y la única
# sentencia ejecutable es `main "$@"` en la última línea. Si la descarga se trunca
# a mitad, bash no ejecuta un script incompleto: nunca llega a invocar main.
#===============================================================================

set -euo pipefail

readonly SCRIPT_NAME="install-docker.sh"
readonly SCRIPT_VERSION="0.2.0"

# Fingerprint de la llave "Docker Release (CE deb) <docker@docker.com>" (RS01/T3).
# Verificado el 2026-08-30 descargando la llave desde download.docker.com y ejecutando
# `gpg --show-keys --with-fingerprint`; idéntica para los canales debian y ubuntu.
# Procedimiento de re-verificación: docs/00-project/adr/0003-verificacion-fingerprint-gpg-docker.md
readonly DOCKER_GPG_FPR="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

readonly KEYRING_PATH="/etc/apt/keyrings/docker.asc"
readonly SOURCES_PATH="/etc/apt/sources.list.d/docker.sources"
readonly LEGACY_LIST_PATH="/etc/apt/sources.list.d/docker.list"
readonly DAEMON_JSON="/etc/docker/daemon.json"
readonly DEFAULT_LOG_FILE="/var/log/instalador-docker-compose.log"

readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
readonly CONFLICTING_PACKAGES=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)

# Codenames y arquitecturas con repositorio publicado por Docker.
# Verificado en docs.docker.com/engine/install/{debian,ubuntu}/ el 2026-08-30.
readonly DEBIAN_CODENAMES="bullseye bookworm trixie"
readonly UBUNTU_CODENAMES="jammy noble resolute"
readonly DEBIAN_ARCHS="amd64 armhf arm64 ppc64el"
readonly UBUNTU_ARCHS="amd64 armhf arm64 s390x ppc64el"

# Códigos de salida (contrato estable — ver interfaces-contract.md).
readonly EX_OK=0 EX_FAIL=1 EX_USAGE=2 EX_UNSUPPORTED=3 EX_INTEGRITY=4 EX_VERIFY=5

#--- Estado global -------------------------------------------------------------
DRY_RUN=0
DO_HARDENING=1
FORCE_HARDENING=0
USERNS_REMAP=""
DOCKER_GROUP_USER=""
NO_DOCKER_GROUP=0
DOCKER_VERSION=""
CHANNEL="stable"
CODENAME_OVERRIDE=""
DISTRO_OVERRIDE=""
SKIP_SMOKE=0
QUIET=0
LOG_FILE="$DEFAULT_LOG_FILE"
ORIGINAL_ARGS=""

DISTRO_ID=""
CODENAME=""
ARCH=""
PRETTY_OS=""
KEYRING_CREATED=0
SOURCES_CREATED=0
DAEMON_JSON_BACKUP=""

#--- Salida --------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    NC=$'\033[0m'
else
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi

_log_line() {
    # Bitácora auditable de la instalación (RS06/T11 — OWASP A09).
    [[ $DRY_RUN -eq 1 ]] && return 0
    [[ -n "$LOG_FILE" ]] || return 0
    printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >>"$LOG_FILE" 2>/dev/null || true
}

info() { [[ $QUIET -eq 1 ]] || echo "${GREEN}[INFO]${NC} $*"; _log_line INFO "$*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*" >&2; _log_line WARN "$*"; }
step() { [[ $QUIET -eq 1 ]] || echo "${BLUE}[==>]${NC} $*"; _log_line STEP "$*"; }
fail() { echo "${RED}[ERROR]${NC} $*" >&2; _log_line ERROR "$*"; }
die() { local code="$1"; shift; fail "$*"; exit "$code"; }

usage() {
    cat <<'USAGE'
install-docker.sh — instalación gobernada y endurecida de Docker Engine + Compose

USO
  sudo bash install-docker.sh [opciones]
  curl -fsSL <url-del-tag>/install-docker.sh | sudo bash -s -- [opciones]

OPCIONES
  --dry-run                 Muestra lo que haría sin modificar el sistema.
  --docker-version VER      Fija la versión de Docker Engine (ej. 27.1.1). Por
                            defecto instala la última del canal.
  --channel CANAL           Canal del repositorio: stable (por defecto) | test.
  --docker-group USUARIO    Añade USUARIO al grupo 'docker'. OPT-IN explícito:
                            equivale a concederle root en el host (ADR-0007).
  --no-docker-group         No añade a nadie al grupo docker (comportamiento por
                            defecto si no se pasa --docker-group).
  --no-hardening            No escribe /etc/docker/daemon.json.
  --force-hardening         Sobrescribe claves ya presentes en daemon.json (por
                            defecto se respeta la configuración existente).
  --userns-remap [USUARIO]  Activa userns-remap ('default' si se omite). Rompe
                            permisos de volúmenes existentes: ver ADR-0006.
  --skip-smoke              Omite el contenedor de prueba hello-world.
  --codename NOMBRE         Fuerza el codename del repositorio APT.
  --distro debian|ubuntu    Fuerza el repositorio de Docker a usar (derivados).
  --log-file RUTA           Bitácora (por defecto /var/log/instalador-docker-compose.log).
  --quiet                   Solo advertencias y errores.
  --version                 Muestra la versión del instalador y sale.
  --help                    Esta ayuda.

CÓDIGOS DE SALIDA
  0 éxito · 1 error · 2 uso inválido · 3 SO/arquitectura no soportada
  4 fallo de verificación de integridad (GPG) · 5 fallo de verificación posterior
USAGE
}

#--- Manejo de errores y rollback (RS07/T10 — OWASP A10) -----------------------
on_error() {
    local exit_code=$?
    local line="$1"
    fail "Fallo en la línea ${line} (código ${exit_code}). Revirtiendo cambios parciales de APT..."
    rollback_apt_state
    _log_line ERROR "Instalación abortada."
    exit "$exit_code"
}

rollback_apt_state() {
    # Un docker.sources apuntando a un repositorio inexistente rompe TODO apt-get
    # posterior del host. Si fallamos antes de instalar, no dejamos rastro.
    if [[ $SOURCES_CREATED -eq 1 && -f "$SOURCES_PATH" ]]; then
        warn "Eliminando ${SOURCES_PATH} creado en esta ejecución."
        rm -f "$SOURCES_PATH"
    fi
    if [[ $KEYRING_CREATED -eq 1 && -f "$KEYRING_PATH" ]]; then
        warn "Eliminando ${KEYRING_PATH} creado en esta ejecución."
        rm -f "$KEYRING_PATH"
    fi
    if [[ -n "$DAEMON_JSON_BACKUP" && -f "$DAEMON_JSON_BACKUP" ]]; then
        warn "Restaurando ${DAEMON_JSON} desde ${DAEMON_JSON_BACKUP}."
        mv -f "$DAEMON_JSON_BACKUP" "$DAEMON_JSON"
    fi
}

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${BLUE}[dry-run]${NC} $*"
        return 0
    fi
    "$@"
}

apt_get() {
    # Lock::Timeout evita el fallo por unattended-upgrades corriendo en paralelo.
    run env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get -o DPkg::Lock::Timeout=300 "$@"
}

#--- Parseo de opciones --------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --docker-version)
                DOCKER_VERSION="${2:-}"
                [[ -n "$DOCKER_VERSION" ]] || die $EX_USAGE "--docker-version requiere un valor."
                shift ;;
            --channel)
                CHANNEL="${2:-}"
                shift ;;
            --docker-group)
                DOCKER_GROUP_USER="${2:-}"
                [[ -n "$DOCKER_GROUP_USER" ]] || die $EX_USAGE "--docker-group requiere un usuario."
                shift ;;
            --no-docker-group) NO_DOCKER_GROUP=1 ;;
            --no-hardening) DO_HARDENING=0 ;;
            --force-hardening) FORCE_HARDENING=1 ;;
            --userns-remap)
                if [[ "${2:-}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                    USERNS_REMAP="$2"
                    shift
                else
                    USERNS_REMAP="default"
                fi ;;
            --skip-smoke) SKIP_SMOKE=1 ;;
            --codename)
                CODENAME_OVERRIDE="${2:-}"
                [[ -n "$CODENAME_OVERRIDE" ]] || die $EX_USAGE "--codename requiere un valor."
                shift ;;
            --distro)
                DISTRO_OVERRIDE="${2:-}"
                shift ;;
            --log-file)
                LOG_FILE="${2:-}"
                shift ;;
            --quiet) QUIET=1 ;;
            --version) echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"; exit $EX_OK ;;
            --help | -h) usage; exit $EX_OK ;;
            *) usage >&2; die $EX_USAGE "Opción desconocida: $1" ;;
        esac
        shift
    done

    [[ "$CHANNEL" == "stable" || "$CHANNEL" == "test" ]] \
        || die $EX_USAGE "--channel debe ser 'stable' o 'test' (recibido: '${CHANNEL}')."
    [[ -z "$DISTRO_OVERRIDE" || "$DISTRO_OVERRIDE" == "debian" || "$DISTRO_OVERRIDE" == "ubuntu" ]] \
        || die $EX_USAGE "--distro debe ser 'debian' o 'ubuntu'."
    if [[ -n "$DOCKER_GROUP_USER" && $NO_DOCKER_GROUP -eq 1 ]]; then
        die $EX_USAGE "--docker-group y --no-docker-group son mutuamente excluyentes."
    fi
}

#--- Preflight -----------------------------------------------------------------
require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] \
        || die $EX_FAIL "Debe ejecutarse como root. Usa: sudo bash ${SCRIPT_NAME}"
}

init_log() {
    [[ $DRY_RUN -eq 1 ]] && return 0
    [[ -n "$LOG_FILE" ]] || return 0
    local dir
    dir="$(dirname "$LOG_FILE")"
    if ! mkdir -p "$dir" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
        warn "No se puede escribir la bitácora en ${LOG_FILE}; se continúa sin ella."
        LOG_FILE=""
        return 0
    fi
    chmod 0640 "$LOG_FILE" 2>/dev/null || true
    _log_line START "${SCRIPT_NAME} ${SCRIPT_VERSION} — argumentos: ${ORIGINAL_ARGS:-<ninguno>}"
}

detect_os() {
    [[ -f /etc/os-release ]] || die $EX_UNSUPPORTED "No se puede detectar el SO (/etc/os-release no existe)."
    # shellcheck disable=SC1091
    . /etc/os-release

    PRETTY_OS="${PRETTY_NAME:-${NAME:-desconocido}}"
    local detected="${ID:-}"

    if [[ -n "$DISTRO_OVERRIDE" ]]; then
        DISTRO_ID="$DISTRO_OVERRIDE"
    elif [[ "$detected" == "debian" || "$detected" == "ubuntu" ]]; then
        DISTRO_ID="$detected"
    else
        # Derivados (Raspberry Pi OS, LMDE, Mint, Pop!_OS…): Docker no publica un
        # repositorio propio; hay que decir explícitamente sobre qué base mapear.
        local like=" ${ID_LIKE:-} "
        case "$like" in
            *" ubuntu "*) DISTRO_ID="ubuntu" ;;
            *" debian "*) DISTRO_ID="debian" ;;
            *) die $EX_UNSUPPORTED "Distribución no soportada: '${detected}'. Este instalador cubre Debian y Ubuntu." ;;
        esac
        warn "Distribución derivada detectada ('${detected}'); se usará el repositorio de ${DISTRO_ID}."
        warn "Si el codename no coincide con el de la base, pásalo con --codename."
    fi

    if [[ -n "$CODENAME_OVERRIDE" ]]; then
        CODENAME="$CODENAME_OVERRIDE"
    elif [[ "$DISTRO_ID" == "ubuntu" ]]; then
        CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    else
        CODENAME="${VERSION_CODENAME:-}"
    fi
    [[ -n "$CODENAME" ]] \
        || die $EX_UNSUPPORTED "No se pudo determinar el codename del sistema. Indícalo con --codename."

    ARCH="$(dpkg --print-architecture)"
    info "Sistema: ${PRETTY_OS} · repo=${DISTRO_ID} · codename=${CODENAME} · arch=${ARCH}"
}

check_supported() {
    local valid_codenames valid_archs
    if [[ "$DISTRO_ID" == "ubuntu" ]]; then
        valid_codenames="$UBUNTU_CODENAMES"
        valid_archs="$UBUNTU_ARCHS"
    else
        valid_codenames="$DEBIAN_CODENAMES"
        valid_archs="$DEBIAN_ARCHS"
    fi

    case " $valid_archs " in
        *" $ARCH "*) ;;
        *) die $EX_UNSUPPORTED "Arquitectura '${ARCH}' sin repositorio Docker para ${DISTRO_ID} (soportadas: ${valid_archs})." ;;
    esac

    case " $valid_codenames " in
        *" $CODENAME "*) ;;
        *)
            # No abortamos: Docker publica codenames nuevos antes de que se actualice
            # esta lista. Advertimos y dejamos que apt-get update sea el juez.
            warn "'${CODENAME}' no está en la lista de codenames verificados para ${DISTRO_ID} (${valid_codenames})."
            warn "Se intentará igualmente; si el repositorio no existe, apt-get update fallará y se revertirá."
            ;;
    esac
}

has_systemd() { [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; }

#--- Instalación ---------------------------------------------------------------
remove_conflicting_packages() {
    step "Revisando paquetes conflictivos (distribuciones no oficiales de Docker)..."
    local pkg
    local present=()
    for pkg in "${CONFLICTING_PACKAGES[@]}"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed$"; then
            present+=("$pkg")
        fi
    done
    if [[ ${#present[@]} -eq 0 ]]; then
        info "No hay paquetes conflictivos instalados."
        return 0
    fi
    warn "Se eliminarán: ${present[*]}"
    apt_get remove -y "${present[@]}"
}

install_prereqs() {
    step "Instalando dependencias (ca-certificates, curl, gnupg)..."
    apt_get update -qq
    apt_get install -y -qq ca-certificates curl gnupg
}

install_gpg_key() {
    step "Descargando y verificando la llave GPG oficial de Docker..."
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${BLUE}[dry-run]${NC} descargaría https://download.docker.com/linux/${DISTRO_ID}/gpg y verificaría el fingerprint ${DOCKER_GPG_FPR}"
        return 0
    fi

    local tmp
    tmp="$(mktemp -d)"

    if ! curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
        "https://download.docker.com/linux/${DISTRO_ID}/gpg" -o "${tmp}/docker.asc"; then
        rm -rf "$tmp"
        die $EX_INTEGRITY "No se pudo descargar la llave GPG de Docker."
    fi

    # RS01/T3: la llave solo se considera confiable si su fingerprint coincide con el
    # pinneado. Sin esta comprobación, un espejo malicioso o un MITM con una CA
    # comprometida podría hacer que APT aceptara paquetes arbitrarios como legítimos.
    local fprs
    gpg --no-default-keyring --keyring "${tmp}/kr.gpg" --quiet --import "${tmp}/docker.asc" 2>/dev/null || true
    fprs="$(gpg --no-default-keyring --keyring "${tmp}/kr.gpg" --with-colons --fingerprint 2>/dev/null \
        | awk -F: '/^fpr:/ {print $10}')"

    if ! grep -qx "$DOCKER_GPG_FPR" <<<"$fprs"; then
        fail "El fingerprint de la llave de Docker NO coincide con el esperado."
        fail "  esperado: ${DOCKER_GPG_FPR}"
        fail "  obtenido: $(tr '\n' ' ' <<<"$fprs")"
        rm -rf "$tmp"
        die $EX_INTEGRITY "Abortando: posible manipulación del canal de distribución (OWASP A03/A08)."
    fi
    info "Fingerprint verificado: ${DOCKER_GPG_FPR} (Docker Release CE deb)."

    install -m 0755 -d /etc/apt/keyrings
    [[ -f "$KEYRING_PATH" ]] || KEYRING_CREATED=1
    install -m 0644 "${tmp}/docker.asc" "$KEYRING_PATH"
    rm -rf "$tmp"
}

configure_repo() {
    step "Configurando el repositorio APT de Docker (formato deb822)..."
    if [[ -f "$LEGACY_LIST_PATH" ]]; then
        warn "Encontrado ${LEGACY_LIST_PATH} heredado; se retira para evitar un repositorio duplicado."
        run rm -f "$LEGACY_LIST_PATH"
    fi
    [[ -f "$SOURCES_PATH" ]] || SOURCES_CREATED=1

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${BLUE}[dry-run]${NC} escribiría ${SOURCES_PATH} → URIs=https://download.docker.com/linux/${DISTRO_ID} Suites=${CODENAME} Components=${CHANNEL} Architectures=${ARCH}"
    else
        cat >"$SOURCES_PATH" <<EOF_SOURCES
# Generado por ${SCRIPT_NAME} ${SCRIPT_VERSION} el $(date -u +%Y-%m-%dT%H:%M:%SZ)
Types: deb
URIs: https://download.docker.com/linux/${DISTRO_ID}
Suites: ${CODENAME}
Components: ${CHANNEL}
Architectures: ${ARCH}
Signed-By: ${KEYRING_PATH}
EOF_SOURCES
        chmod 0644 "$SOURCES_PATH"
    fi
    apt_get update -qq
}

resolve_version_string() {
    # Traduce "27.1.1" a la cadena real del paquete (5:27.1.1-1~debian.12~bookworm).
    local pkg="$1"
    local wanted="$2"
    local resolved
    resolved="$(apt-cache madison "$pkg" 2>/dev/null | awk '{print $3}' | grep -m1 -F "$wanted" || true)"
    if [[ -z "$resolved" ]]; then
        fail "La versión '${wanted}' no está disponible para ${pkg} en ${DISTRO_ID}/${CODENAME}."
        fail "Versiones disponibles (5 más recientes):"
        apt-cache madison "$pkg" 2>/dev/null | awk '{print "  " $3}' | head -5 >&2 || true
        die $EX_FAIL "Ajusta --docker-version o quítalo para instalar la última."
    fi
    printf '%s' "$resolved"
}

install_docker_packages() {
    step "Instalando Docker Engine, CLI, containerd, buildx y compose-plugin..."
    if [[ -n "$DOCKER_VERSION" ]]; then
        # Pin reproducible entre servidores (RF04/T9 — OWASP A03).
        local ver_ce ver_cli
        ver_ce="$(resolve_version_string docker-ce "$DOCKER_VERSION")"
        ver_cli="$(resolve_version_string docker-ce-cli "$DOCKER_VERSION")"
        info "Fijando docker-ce=${ver_ce}"
        apt_get install -y -qq \
            "docker-ce=${ver_ce}" "docker-ce-cli=${ver_cli}" \
            containerd.io docker-buildx-plugin docker-compose-plugin
    else
        apt_get install -y -qq "${DOCKER_PACKAGES[@]}"
    fi
}

enable_service() {
    if ! has_systemd; then
        warn "systemd no está activo (contenedor, chroot o WSL sin systemd)."
        warn "El servicio no se habilita automáticamente. Arráncalo con: service docker start"
        return 0
    fi
    step "Habilitando e iniciando el servicio Docker..."
    run systemctl enable --now docker
}

#--- Endurecimiento del daemon (RS05/T7/T8 — OWASP A02) ------------------------
# Perfil por defecto y su justificación:
#   log-driver + log-opts  rotación 10 MB × 3 → un contenedor ruidoso no llena el
#                          disco y tumba el host (T7). Docker NO rota por defecto.
#   live-restore           los contenedores sobreviven al reinicio del daemon
#                          (incompatible con Swarm — ver ADR-0005).
#   no-new-privileges      impide escalada vía binarios setuid dentro del contenedor.
#   default-ulimits nofile evita el agotamiento de descriptores del host.
print_hardening_profile() {
    echo '{'
    echo '  "log-driver": "json-file",'
    echo '  "log-opts": {'
    echo '    "max-size": "10m",'
    echo '    "max-file": "3"'
    echo '  },'
    echo '  "live-restore": true,'
    echo '  "no-new-privileges": true,'
    if [[ -n "$USERNS_REMAP" ]]; then
        printf '  "userns-remap": "%s",\n' "$USERNS_REMAP"
    fi
    echo '  "default-ulimits": {'
    echo '    "nofile": {'
    echo '      "Name": "nofile",'
    echo '      "Soft": 65536,'
    echo '      "Hard": 65536'
    echo '    }'
    echo '  }'
    echo '}'
}

merge_hardening_with_python() {
    # Fusión no destructiva: por defecto gana lo que el operador ya tenía escrito;
    # con --force-hardening gana el perfil. Nunca se pierde la configuración previa.
    FORCE_HARDENING="$FORCE_HARDENING" USERNS_REMAP="$USERNS_REMAP" \
        python3 - "$DAEMON_JSON" <<'EOF_PY'
import json
import os
import sys

path = sys.argv[1]
force = os.environ.get("FORCE_HARDENING") == "1"

desired = {
    "log-driver": "json-file",
    "log-opts": {"max-size": "10m", "max-file": "3"},
    "live-restore": True,
    "no-new-privileges": True,
    "default-ulimits": {"nofile": {"Name": "nofile", "Soft": 65536, "Hard": 65536}},
}
userns = os.environ.get("USERNS_REMAP") or ""
if userns:
    desired["userns-remap"] = userns

try:
    with open(path, encoding="utf-8") as fh:
        current = json.load(fh)
except (OSError, json.JSONDecodeError) as exc:
    print("no se pudo leer %s: %s" % (path, exc), file=sys.stderr)
    sys.exit(3)

if not isinstance(current, dict):
    print("la raiz de %s no es un objeto JSON" % path, file=sys.stderr)
    sys.exit(3)

applied = []
skipped = []
for key, value in desired.items():
    if key in current and not force:
        if current[key] != value:
            skipped.append(key)
        continue
    current[key] = value
    applied.append(key)

with open(path, "w", encoding="utf-8") as fh:
    json.dump(current, fh, indent=2, ensure_ascii=False)
    fh.write("\n")

print("APPLIED %s" % (",".join(applied) if applied else "-"))
print("SKIPPED %s" % (",".join(skipped) if skipped else "-"))
EOF_PY
}

apply_hardening() {
    if [[ $DO_HARDENING -eq 0 ]]; then
        warn "Endurecimiento omitido por --no-hardening: sin rotación de logs (riesgo de disco lleno, T7)."
        return 0
    fi
    step "Aplicando perfil de endurecimiento en ${DAEMON_JSON}..."

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${BLUE}[dry-run]${NC} fusionaría en ${DAEMON_JSON}:"
        print_hardening_profile | sed 's/^/[dry-run]   /'
        return 0
    fi

    mkdir -p /etc/docker

    if [[ ! -f "$DAEMON_JSON" ]]; then
        print_hardening_profile >"$DAEMON_JSON"
        chmod 0644 "$DAEMON_JSON"
        info "daemon.json creado con el perfil de endurecimiento."
        restart_daemon
        return 0
    fi

    # T8: nunca pisar la configuración de un host en producción.
    DAEMON_JSON_BACKUP="${DAEMON_JSON}.bak.$(date -u +%Y%m%d%H%M%S)"
    cp -p "$DAEMON_JSON" "$DAEMON_JSON_BACKUP"
    info "Copia de seguridad previa: ${DAEMON_JSON_BACKUP}"

    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 no disponible: no se puede fusionar el JSON existente de forma segura."
        warn "Se conserva ${DAEMON_JSON} intacto. Aplica este perfil a mano:"
        print_hardening_profile | sed 's/^/  /' >&2
        DAEMON_JSON_BACKUP=""
        return 0
    fi

    local merge_out
    if ! merge_out="$(merge_hardening_with_python)"; then
        warn "No se pudo fusionar ${DAEMON_JSON} (JSON inválido o error de escritura)."
        warn "Restaurando la copia de seguridad y continuando sin endurecer."
        mv -f "$DAEMON_JSON_BACKUP" "$DAEMON_JSON"
        DAEMON_JSON_BACKUP=""
        return 0
    fi

    local applied skipped
    applied="$(awk '/^APPLIED /{print substr($0, 9)}' <<<"$merge_out")"
    skipped="$(awk '/^SKIPPED /{print substr($0, 9)}' <<<"$merge_out")"
    info "Claves aplicadas: ${applied}"
    if [[ -n "$skipped" && "$skipped" != "-" ]]; then
        warn "Claves respetadas por existir ya con otro valor: ${skipped}"
        warn "Usa --force-hardening si quieres que el perfil las sobrescriba."
    fi
    DAEMON_JSON_BACKUP=""
    restart_daemon
}

restart_daemon() {
    has_systemd || return 0
    step "Reiniciando el daemon para aplicar la configuración..."
    if ! run systemctl restart docker; then
        fail "El daemon no arrancó tras aplicar ${DAEMON_JSON}."
        fail "Diagnostica con: journalctl -u docker -n 50 --no-pager"
        die $EX_FAIL "Revisa ${DAEMON_JSON} (o restaura la copia .bak) y reintenta."
    fi
}

#--- Grupo docker (RS04/T5 — OWASP A01) ----------------------------------------
manage_docker_group() {
    if [[ $NO_DOCKER_GROUP -eq 1 || -z "$DOCKER_GROUP_USER" ]]; then
        info "Ningún usuario añadido al grupo 'docker' (usa 'sudo docker', o --docker-group USUARIO)."
        info "Pertenecer al grupo 'docker' equivale a acceso root en el host — ver ADR-0007."
        return 0
    fi
    if ! id -u "$DOCKER_GROUP_USER" >/dev/null 2>&1; then
        die $EX_FAIL "El usuario '${DOCKER_GROUP_USER}' no existe en este host."
    fi
    warn "Añadiendo '${DOCKER_GROUP_USER}' al grupo 'docker': equivale a concederle root sin sudo (ADR-0007)."
    run usermod -aG docker "$DOCKER_GROUP_USER"
    info "Hecho. '${DOCKER_GROUP_USER}' debe cerrar sesión y volver a entrar (o ejecutar 'newgrp docker')."
}

#--- Verificación --------------------------------------------------------------
firewall_advisory() {
    # T6: Docker inserta sus reglas en la cadena DOCKER de iptables/nftables ANTES que
    # las de UFW. Un `-p 5432:5432` queda expuesto a Internet aunque `ufw deny` lo niegue.
    command -v ufw >/dev/null 2>&1 || return 0
    ufw status 2>/dev/null | grep -qi '^Status: active' || return 0
    warn "UFW está activo: Docker NO respeta sus reglas para los puertos publicados."
    warn "Publica sobre loopback ('-p 127.0.0.1:8080:8080') o filtra en la cadena DOCKER-USER."
    warn "Receta completa en docs/03-implementation/deployment-runbook.md."
}

verify_install() {
    step "Verificando la instalación..."
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "${BLUE}[dry-run]${NC} verificaría docker --version, docker compose version y el estado del daemon"
        return 0
    fi

    command -v docker >/dev/null 2>&1 || die $EX_VERIFY "El binario 'docker' no está disponible tras la instalación."

    local dv cv
    dv="$(docker --version 2>/dev/null)" || die $EX_VERIFY "'docker --version' falló."
    cv="$(docker compose version 2>/dev/null)" || die $EX_VERIFY "El plugin 'docker compose' no está disponible."
    info "$dv"
    info "$cv"

    if has_systemd; then
        systemctl is-active --quiet docker \
            || die $EX_VERIFY "El servicio docker no está activo. Diagnostica: journalctl -u docker -n 50 --no-pager"
        info "Servicio docker activo y habilitado en el arranque."
    fi

    if [[ $DO_HARDENING -eq 1 && -f "$DAEMON_JSON" ]]; then
        local driver
        driver="$(docker info --format '{{.LoggingDriver}}' 2>/dev/null || echo desconocido)"
        info "Driver de logs efectivo: ${driver} (rotación 10m × 3 según ${DAEMON_JSON})."
    fi

    firewall_advisory
}

smoke_test() {
    if [[ $SKIP_SMOKE -eq 1 || $DRY_RUN -eq 1 ]]; then
        info "Smoke test omitido."
        return 0
    fi
    step "Ejecutando contenedor de prueba (hello-world)..."
    if docker run --rm hello-world >/dev/null 2>&1; then
        info "✔ El daemon ejecuta contenedores correctamente."
    else
        # No es fatal: puede fallar por red, proxy o registry sin que la instalación esté mal.
        warn "El contenedor de prueba falló. La instalación puede seguir siendo válida."
        warn "Comprueba la salida hacia registry-1.docker.io y revisa: systemctl status docker"
    fi
}

#--- Idempotencia --------------------------------------------------------------
already_installed() {
    dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q "^install ok installed$"
}

#--- main ----------------------------------------------------------------------
main() {
    ORIGINAL_ARGS="$*"
    parse_args "$@"
    require_root
    init_log
    trap 'on_error $LINENO' ERR

    info "${SCRIPT_NAME} ${SCRIPT_VERSION}"
    [[ $DRY_RUN -eq 1 ]] && warn "MODO DRY-RUN: no se modificará el sistema."

    detect_os
    check_supported

    if already_installed; then
        # Convergencia, no cortocircuito: si Docker ya está instalado seguimos aplicando
        # el perfil de endurecimiento y el grupo, que es lo que puede haber cambiado.
        info "docker-ce ya está instalado: $(docker --version 2>/dev/null || echo 'versión no disponible')"
        info "Modo convergencia: se revisa la configuración, no se reinstala."
        [[ -n "$DOCKER_VERSION" ]] \
            && warn "--docker-version se ignora en convergencia; desinstala primero para cambiar de versión."
    else
        remove_conflicting_packages
        install_prereqs
        install_gpg_key
        configure_repo
        install_docker_packages
        enable_service
    fi

    apply_hardening
    manage_docker_group
    verify_install
    smoke_test

    trap - ERR
    info "✔ Instalación completada."
    [[ -n "$LOG_FILE" ]] && info "Bitácora: ${LOG_FILE}"
    _log_line END "Finalizado correctamente."
    return $EX_OK
}

main "$@"
