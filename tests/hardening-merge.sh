#!/usr/bin/env bash
#===============================================================================
# tests/hardening-merge.sh — Pruebas de la fusión de /etc/docker/daemon.json
#
# Verifica el control que mitiga T8 (destrucción de la configuración de un host en
# producción): la fusión debe ser NO DESTRUCTIVA por defecto y respetar las claves
# que el operador ya había escrito.
#
# DEBE EJECUTARSE DENTRO DE UN CONTENEDOR DESECHABLE: escribe en /etc/docker.
#   docker run --rm -v "$PWD:/work" -w /work python:3.12-slim bash tests/hardening-merge.sh
#
# El wrapper tests/run-all.sh lo lanza así automáticamente.
#===============================================================================

# SC2034 (variable sin usar) se desactiva para todo el fichero a propósito: QUIET, DRY_RUN,
# DO_HARDENING, FORCE_HARDENING y USERNS_REMAP son las variables globales que consumen las
# funciones cargadas con `source` desde install-docker.sh. ShellCheck no puede seguir un
# `source` de ruta dinámica, así que las ve como asignaciones muertas cuando en realidad son
# la forma de fijar el escenario de cada prueba.
# shellcheck disable=SC2034

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="/tmp/install-docker.lib.sh"

if [[ ! -f /.dockerenv ]]; then
    echo "ERROR: esta prueba escribe en /etc/docker. Ejecútala dentro de un contenedor." >&2
    exit 2
fi

PASS=0
FAIL=0
ok() { printf '\033[0;32m  PASS  %s\033[0m\n' "$*"; PASS=$((PASS + 1)); }
ko() { printf '\033[0;31m  FAIL  %s\033[0m\n' "$*"; FAIL=$((FAIL + 1)); }

# Carga el script sin su última línea (`main "$@"`) para poder invocar funciones sueltas.
sed '$d' "${REPO_ROOT}/install-docker.sh" >"$LIB"
# shellcheck disable=SC1090
source "$LIB"

QUIET=1
DRY_RUN=0
DO_HARDENING=1

json_get() { python3 -c "import json,sys; print(json.load(open('/etc/docker/daemon.json')).get(sys.argv[1]))" "$1"; }

echo "== Perfil de endurecimiento: validez del JSON =="

USERNS_REMAP=""
if print_hardening_profile | python3 -m json.tool >/dev/null 2>&1; then
    ok "el perfil por defecto es JSON válido"
else
    ko "el perfil por defecto NO es JSON válido"
    print_hardening_profile | sed 's/^/        | /'
fi

USERNS_REMAP="default"
if print_hardening_profile | python3 -m json.tool >/dev/null 2>&1; then
    ok "el perfil con --userns-remap es JSON válido"
else
    ko "el perfil con --userns-remap NO es JSON válido"
    print_hardening_profile | sed 's/^/        | /'
fi
if print_hardening_profile | grep -q '"userns-remap": "default"'; then
    ok "el perfil con --userns-remap incluye la clave userns-remap"
else
    ko "falta la clave userns-remap en el perfil"
fi
USERNS_REMAP=""

echo
echo "== Creación cuando no existe daemon.json =="
rm -rf /etc/docker
mkdir -p /etc/docker
apply_hardening >/dev/null 2>&1
if [[ -f /etc/docker/daemon.json ]] && python3 -m json.tool </etc/docker/daemon.json >/dev/null 2>&1; then
    ok "crea un daemon.json válido cuando no existe"
else
    ko "no creó un daemon.json válido"
fi
if [[ "$(json_get log-driver)" == "json-file" ]]; then
    ok "aplica la rotación de logs (mitigación de T7)"
else
    ko "no aplicó log-driver json-file"
fi

echo
echo "== Fusión NO destructiva sobre configuración existente (T8) =="
cat >/etc/docker/daemon.json <<'EOF_EXISTING'
{
  "log-driver": "syslog",
  "insecure-registries": ["registry.interno.local:5000"],
  "data-root": "/mnt/datos/docker"
}
EOF_EXISTING

FORCE_HARDENING=0
apply_hardening >/dev/null 2>&1

if [[ "$(json_get log-driver)" == "syslog" ]]; then
    ok "respeta log-driver que el operador ya había definido"
else
    ko "SOBRESCRIBIÓ log-driver del operador (ahora: $(json_get log-driver))"
fi
if [[ "$(json_get data-root)" == "/mnt/datos/docker" ]]; then
    ok "preserva claves ajenas al perfil (data-root)"
else
    ko "perdió data-root del operador"
fi
if [[ "$(json_get insecure-registries)" == *"registry.interno.local:5000"* ]]; then
    ok "preserva insecure-registries del operador"
else
    ko "perdió insecure-registries del operador"
fi
if [[ "$(json_get live-restore)" == "True" ]]; then
    ok "añade las claves del perfil que faltaban (live-restore)"
else
    ko "no añadió live-restore"
fi
if ls /etc/docker/daemon.json.bak.* >/dev/null 2>&1; then
    ok "deja copia de seguridad previa a la fusión"
else
    ko "no dejó copia de seguridad"
fi

echo
echo "== --force-hardening sí sobrescribe =="
rm -f /etc/docker/daemon.json.bak.*
cat >/etc/docker/daemon.json <<'EOF_EXISTING2'
{ "log-driver": "syslog", "data-root": "/mnt/datos/docker" }
EOF_EXISTING2
FORCE_HARDENING=1
apply_hardening >/dev/null 2>&1
if [[ "$(json_get log-driver)" == "json-file" ]]; then
    ok "--force-hardening sobrescribe la clave en conflicto"
else
    ko "--force-hardening no sobrescribió log-driver"
fi
if [[ "$(json_get data-root)" == "/mnt/datos/docker" ]]; then
    ok "--force-hardening sigue preservando claves ajenas al perfil"
else
    ko "--force-hardening destruyó data-root"
fi

echo
echo "== JSON corrupto: no se destruye, se restaura =="
FORCE_HARDENING=0
printf '{ esto no es json valido' >/etc/docker/daemon.json
apply_hardening >/dev/null 2>&1
if [[ "$(cat /etc/docker/daemon.json)" == "{ esto no es json valido" ]]; then
    ok "ante un daemon.json corrupto conserva el original sin tocarlo"
else
    ko "modificó un daemon.json corrupto (contenido: $(cat /etc/docker/daemon.json))"
fi

echo
echo "== --no-hardening no toca nada =="
printf '{"log-driver":"syslog"}' >/etc/docker/daemon.json
DO_HARDENING=0
apply_hardening >/dev/null 2>&1
if [[ "$(json_get log-driver)" == "syslog" ]]; then
    ok "--no-hardening deja daemon.json intacto"
else
    ko "--no-hardening modificó daemon.json"
fi

echo
echo "== ${PASS} pass · ${FAIL} fail =="
[[ $FAIL -eq 0 ]] || exit 1
