#!/usr/bin/env bash
#===============================================================================
# tests/run-all.sh — Ejecuta la suite completa local (la misma que corre en CI).
#
#   1. ShellCheck sobre el instalador y los tests.
#   2. Matriz dry-run en Debian 12/13 y Ubuntu 22.04/24.04 + distro no soportada.
#   3. Pruebas de fusión de daemon.json en contenedor desechable.
#   4. Integridad GPG: prueba negativa con origen suplantado, y rollback.
#   5. Instalación real, convergencia, bitácora, pin de versión y aviso de UFW.
#   6. Validación de los diagramas Mermaid de docs/.
#
# Las etapas 4 y 5 descargan paquetes reales: son las lentas.
#
# Uso: bash tests/run-all.sh
#===============================================================================

# Las funciones stage_* se invocan indirectamente: su nombre se pasa a run_stage, que las
# ejecuta con "$@". ShellCheck no resuelve esa indirección y lo señala con dos códigos
# distintos según la versión — SC2329 desde 0.11 y SC2317 en versiones anteriores — así que se
# desactivan ambos para que el análisis dé el mismo resultado en cualquier entorno.
# shellcheck disable=SC2329,SC2317

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Debe coincidir con SHELLCHECK_VERSION de .github/workflows/ci.yml.
SHELLCHECK_VERSION="v0.11.0"

export MSYS_NO_PATHCONV=1
if command -v cygpath >/dev/null 2>&1; then
    MOUNT_SRC="$(cygpath -m "$REPO_ROOT")"
else
    MOUNT_SRC="$REPO_ROOT"
fi

FAILED=()
run_stage() {
    local name="$1"
    shift
    echo
    printf '\033[0;34m===== %s =====\033[0m\n' "$name"
    if "$@"; then
        printf '\033[0;32m----- %s: OK -----\033[0m\n' "$name"
    else
        printf '\033[0;31m----- %s: FALLÓ -----\033[0m\n' "$name"
        FAILED+=("$name")
    fi
}

stage_shellcheck() {
    # Versión fijada: la de ubuntu-latest difiere y emite códigos distintos para el mismo
    # hallazgo, lo que produce verde en local y rojo en CI. CI usa esta misma imagen.
    docker run --rm -v "${MOUNT_SRC}:/work" -w /work "koalaman/shellcheck:${SHELLCHECK_VERSION}" \
        install-docker.sh tests/dry-run-matrix.sh tests/hardening-merge.sh \
        tests/gpg-integrity.sh tests/install-real.sh tests/run-all.sh
}

stage_gpg_integrity() {
    # Prueba negativa del control de cadena de suministro: levanta un origen HTTPS
    # que suplanta a download.docker.com. Necesita contenedor desechable.
    docker run --rm -v "${MOUNT_SRC}:/work" -w /work debian:12 \
        bash tests/gpg-integrity.sh
}

stage_install_real() {
    # Instalación real de paquetes, convergencia, bitácora, pin y aviso de UFW.
    # Es la etapa más lenta: descarga Docker de verdad.
    docker run --rm -v "${MOUNT_SRC}:/work" -w /work debian:12 \
        bash tests/install-real.sh
}

stage_dry_run() { bash tests/dry-run-matrix.sh; }

stage_hardening() {
    docker run --rm -v "${MOUNT_SRC}:/work" -w /work python:3.12-slim \
        bash tests/hardening-merge.sh
}

stage_mermaid() {
    if command -v python >/dev/null 2>&1; then
        python scripts/validate_mermaid.py docs
    else
        python3 scripts/validate_mermaid.py docs
    fi
}

command -v docker >/dev/null 2>&1 || { echo "Docker es necesario para la suite." >&2; exit 2; }

run_stage "ShellCheck" stage_shellcheck
run_stage "Matriz dry-run" stage_dry_run
run_stage "Fusión daemon.json" stage_hardening
run_stage "Integridad GPG (negativa + rollback)" stage_gpg_integrity
run_stage "Instalación real y convergencia" stage_install_real
run_stage "Diagramas Mermaid" stage_mermaid

echo
if [[ ${#FAILED[@]} -eq 0 ]]; then
    printf '\033[0;32m== Suite completa: TODO OK ==\033[0m\n'
    exit 0
fi
printf '\033[0;31m== Etapas fallidas: %s ==\033[0m\n' "${FAILED[*]}"
exit 1
