#!/usr/bin/env bash
#===============================================================================
# tests/dry-run-matrix.sh — Matriz de verificación del instalador en contenedores
#
# Ejecuta install-docker.sh en modo --dry-run sobre imágenes Debian/Ubuntu reales
# y comprueba el comportamiento observable: detección de SO, códigos de salida y
# rutas de error. Cubre el nivel "integración" de la pirámide (docs/04-testing/).
#
# LO QUE ESTA MATRIZ NO CUBRE (honestidad de alcance — ver docs/04-testing/test-strategy.md):
#   - La instalación real de paquetes desde download.docker.com.
#   - systemd (los contenedores no lo ejecutan): enable/restart del servicio.
#   - La verificación real del fingerprint GPG (se omite en --dry-run).
#   Eso se valida en el despliegue real del Gate 2 (deployment-runbook.md).
#
# Uso:
#   bash tests/dry-run-matrix.sh
#===============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

# En Git Bash / MSYS hay que desactivar la conversión de rutas de Docker Desktop.
export MSYS_NO_PATHCONV=1
if command -v cygpath >/dev/null 2>&1; then
    MOUNT_SRC="$(cygpath -m "$REPO_ROOT")"
else
    MOUNT_SRC="$REPO_ROOT"
fi

IMAGES=(debian:12 debian:13 ubuntu:22.04 ubuntu:24.04)

PASS=0
FAIL=0
SKIP=0

green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }

in_container() {
    local image="$1"
    shift
    docker run --rm -v "${MOUNT_SRC}:/work" -w /work "$image" "$@" 2>&1
}

# assert_exit <descripción> <código esperado> <imagen> <argumentos...>
assert_exit() {
    local desc="$1" expected="$2" image="$3"
    shift 3
    local out actual
    out="$(in_container "$image" bash install-docker.sh "$@")"
    actual=$?
    if [[ $actual -eq $expected ]]; then
        green "  PASS  ${desc} (exit ${actual})"
        PASS=$((PASS + 1))
    else
        red "  FAIL  ${desc} — esperado exit ${expected}, obtenido ${actual}"
        printf '%s\n' "$out" | sed 's/^/        | /' | tail -15
        FAIL=$((FAIL + 1))
    fi
}

# assert_output <descripción> <patrón> <imagen> <argumentos...>
assert_output() {
    local desc="$1" pattern="$2" image="$3"
    shift 3
    local out
    out="$(in_container "$image" bash install-docker.sh "$@")"
    if grep -qE "$pattern" <<<"$out"; then
        green "  PASS  ${desc}"
        PASS=$((PASS + 1))
    else
        red "  FAIL  ${desc} — no se encontró /${pattern}/ en la salida"
        printf '%s\n' "$out" | sed 's/^/        | /' | tail -15
        FAIL=$((FAIL + 1))
    fi
}

echo "== Matriz dry-run de ${REPO_ROOT} =="
command -v docker >/dev/null 2>&1 || { red "Docker no disponible; no se puede ejecutar la matriz."; exit 2; }

for image in "${IMAGES[@]}"; do
    echo
    echo "-- ${image} --"
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        if ! docker pull -q "$image" >/dev/null 2>&1; then
            yellow "  SKIP  ${image} no descargable (sin red o tag inexistente)"
            SKIP=$((SKIP + 1))
            continue
        fi
    fi

    assert_exit "dry-run completo termina en éxito" 0 "$image" --dry-run --skip-smoke
    assert_output "detecta el codename del sistema" 'codename=[a-z]+' "$image" --dry-run --skip-smoke
    assert_output "no modifica el sistema (todo marcado dry-run)" '\[dry-run\]' "$image" --dry-run --skip-smoke
    assert_output "el perfil de endurecimiento incluye rotación de logs" 'max-size' "$image" --dry-run --skip-smoke
    assert_exit "opción desconocida devuelve uso inválido" 2 "$image" --dry-run --opcion-inexistente
    assert_exit "--channel inválido devuelve uso inválido" 2 "$image" --dry-run --channel produccion
    assert_exit "--docker-group + --no-docker-group es excluyente" 2 "$image" --dry-run --docker-group root --no-docker-group
    assert_exit "--help termina en éxito" 0 "$image" --help
    assert_output "advierte de la ausencia de systemd" 'systemd no está activo' "$image" --dry-run --skip-smoke
    assert_output "el grupo docker es opt-in explícito" "Ningún usuario añadido al grupo" "$image" --dry-run --skip-smoke
done

echo
echo "-- alpine (distribución no soportada) --"
if docker pull -q alpine:latest >/dev/null 2>&1; then
    out="$(docker run --rm -v "${MOUNT_SRC}:/work" -w /work alpine:latest sh -c 'apk add --no-cache bash >/dev/null 2>&1 && bash install-docker.sh --dry-run' 2>&1)"
    rc=$?
    if [[ $rc -eq 3 ]]; then
        green "  PASS  distribución no soportada devuelve exit 3"
        PASS=$((PASS + 1))
    else
        red "  FAIL  esperado exit 3 en alpine, obtenido ${rc}"
        printf '%s\n' "$out" | sed 's/^/        | /' | tail -10
        FAIL=$((FAIL + 1))
    fi
else
    yellow "  SKIP  alpine no descargable"
    SKIP=$((SKIP + 1))
fi

echo
echo "== ${PASS} pass · ${FAIL} fail · ${SKIP} skip =="
[[ $FAIL -eq 0 ]] || exit 1
