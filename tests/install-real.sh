#!/usr/bin/env bash
#===============================================================================
# tests/install-real.sh — Instalación real de paquetes, convergencia, bitácora,
#                         pin de versión y aviso de UFW.
#
# Instala Docker de verdad desde download.docker.com dentro de un contenedor
# desechable. Cubre las brechas de Gate 3 que `--dry-run` no puede tocar.
#
# LO QUE SIGUE SIN CUBRIR, y hay que saberlo: el contenedor no ejecuta systemd,
# así que `enable_service` y `restart_daemon` no se ejercitan aquí (el script las
# omite con aviso). Eso quedó verificado en el host real del Gate 2.
#
# DEBE EJECUTARSE DENTRO DE UN CONTENEDOR DESECHABLE: instala paquetes y escribe
# en /etc.
#
#   docker run --rm -v "$PWD:/work" -w /work debian:12 bash tests/install-real.sh
#===============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${REPO_ROOT}/install-docker.sh"
WORK="/tmp/install-real"

if [[ ! -f /.dockerenv ]]; then
    echo "ERROR: esta prueba instala paquetes y escribe en /etc." >&2
    echo "       Ejecútala dentro de un contenedor desechable." >&2
    exit 2
fi

PASS=0
FAIL=0
ok() { printf '\033[0;32m  PASS  %s\033[0m\n' "$*"; PASS=$((PASS + 1)); }
ko() { printf '\033[0;31m  FAIL  %s\033[0m\n' "$*"; FAIL=$((FAIL + 1)); }
info() { printf '\033[0;34m  ...   %s\033[0m\n' "$*"; }

rm -rf "$WORK"
mkdir -p "$WORK"

EXPECTED_FPR="$(grep -m1 'readonly DOCKER_GPG_FPR=' "$INSTALLER" | cut -d'"' -f2)"

#===============================================================================
echo "== Prueba 1: pin de una versión inexistente falla de forma útil (T9) =="
#===============================================================================
# Se ejecuta ANTES de instalar: el pin solo se resuelve cuando hay que instalar,
# no en modo convergencia.
LOG1="${WORK}/pin.log"
set +e
bash "$INSTALLER" --docker-version 99.99.99 --skip-smoke --log-file "$LOG1" >"${WORK}/pin.txt" 2>&1
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
    ok "una versión inexistente no se instala (código ${RC})"
else
    ko "aceptó una versión inexistente"
fi
if grep -q "no está disponible" "${WORK}/pin.txt"; then
    ok "explica que la versión pedida no está disponible"
else
    ko "no explica el motivo del fallo"
    tail -15 "${WORK}/pin.txt" | sed 's/^/        | /'
fi
if grep -q "Versiones disponibles" "${WORK}/pin.txt"; then
    ok "lista las versiones disponibles en lugar de un error opaco de APT"
else
    ko "no lista las versiones disponibles"
fi
if ! dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q "^install ok installed$"; then
    ok "no instaló nada al fallar el pin"
else
    ko "instaló docker-ce pese a fallar el pin"
fi

#===============================================================================
echo
echo "== Prueba 2: instalación real completa desde el repositorio oficial =="
#===============================================================================
LOG2="${WORK}/install.log"
info "Instalando Docker de verdad (puede tardar)..."
set +e
bash "$INSTALLER" --skip-smoke --log-file "$LOG2" >"${WORK}/install.txt" 2>&1
RC=$?
set -e

if [[ $RC -eq 0 ]]; then
    ok "la instalación real termina en éxito (código 0)"
else
    ko "la instalación real falló con código ${RC}"
    tail -25 "${WORK}/install.txt" | sed 's/^/        | /'
fi
if command -v docker >/dev/null 2>&1; then
    ok "el binario docker queda disponible: $(docker --version 2>/dev/null)"
else
    ko "no hay binario docker tras instalar"
fi
if docker compose version >/dev/null 2>&1; then
    ok "el plugin compose queda disponible: $(docker compose version 2>/dev/null)"
else
    ko "el plugin compose no está disponible"
fi
for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed$"; then
        ok "paquete instalado: ${pkg}"
    else
        ko "falta el paquete ${pkg}"
    fi
done

echo
info "Estado que deja en el host"
if [[ -f /etc/apt/keyrings/docker.asc ]]; then
    ok "keyring instalado en /etc/apt/keyrings/docker.asc"
else
    ko "no instaló el keyring"
fi
if grep -q "^Signed-By: /etc/apt/keyrings/docker.asc" /etc/apt/sources.list.d/docker.sources 2>/dev/null; then
    ok "docker.sources en formato deb822 y firmado por el keyring verificado"
else
    ko "docker.sources ausente o mal formado"
fi
if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
    ko "quedó un docker.list heredado (repositorio duplicado)"
else
    ok "no hay docker.list heredado"
fi
# Ojo: la imagen base NO trae python3, y eso es deliberado — permite ejercitar la
# ruta degradada de apply_hardening más abajo. La validez del JSON se comprueba
# en la prueba 3b, una vez instalado python3.
for clave in '"log-driver": "json-file"' '"max-size": "10m"' '"live-restore": true' '"no-new-privileges": true'; do
    if grep -q "$clave" /etc/docker/daemon.json 2>/dev/null; then
        ok "perfil de endurecimiento aplicado: ${clave}"
    else
        ko "falta en daemon.json: ${clave}"
    fi
done

echo
info "Bitácora (A09 / T11) — cierra la brecha declarada en test-strategy"
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[START\] ' "$LOG2"; then
    ok "registra START con el formato del contrato (UTC ISO 8601 + nivel)"
else
    ko "no registra START con el formato especificado"
fi
if grep -q "\[INFO\] Fingerprint verificado: ${EXPECTED_FPR}" "$LOG2"; then
    ok "registra el fingerprint verificado completo (evidencia de RS01)"
else
    ko "no registra el fingerprint verificado"
fi
if grep -q "\[END\] Finalizado correctamente" "$LOG2"; then
    ok "registra END al terminar correctamente"
else
    ko "no registra END"
fi
if grep -q "argumentos:" "$LOG2"; then
    ok "registra los argumentos de la invocación (no repudio)"
else
    ko "no registra los argumentos"
fi

#===============================================================================
echo
echo "== Prueba 3a: convergencia sin python3 — degradación controlada (T8) =="
#===============================================================================
# La imagen base no trae python3. Con un daemon.json ya existente, el instalador
# no puede fusionar de forma segura: debe CONSERVARLO intacto y avisar, nunca
# escribir a ciegas. Esta ruta no estaba cubierta por ninguna prueba.
SUM_ANTES="$(sha256sum /etc/docker/daemon.json | cut -d' ' -f1)"
set +e
bash "$INSTALLER" --skip-smoke --log-file "${WORK}/nopy.log" >"${WORK}/nopy.txt" 2>&1
RC=$?
set -e

if [[ $RC -eq 0 ]]; then
    ok "la re-ejecución sin python3 termina en éxito"
else
    ko "falló con código ${RC}"
    tail -20 "${WORK}/nopy.txt" | sed 's/^/        | /'
fi
if grep -q "python3 no disponible" "${WORK}/nopy.txt"; then
    ok "avisa de que no puede fusionar sin python3"
else
    ko "no avisó de la ausencia de python3"
fi
if [[ "$(sha256sum /etc/docker/daemon.json | cut -d' ' -f1)" == "$SUM_ANTES" ]]; then
    ok "conserva daemon.json intacto en vez de escribir a ciegas"
else
    ko "modificó daemon.json sin poder fusionar de forma segura"
fi
if ls /etc/docker/daemon.json.bak.* >/dev/null 2>&1; then
    ok "deja copia de seguridad antes de intentar la fusión"
else
    ko "no dejó copia de seguridad"
fi

#===============================================================================
echo
echo "== Prueba 3b: convergencia con python3 — no reinstala y respeta al operador =="
#===============================================================================
info "Instalando python3 (dependencia de la prueba, no del producto)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 >/dev/null 2>&1

if python3 -m json.tool /etc/docker/daemon.json >/dev/null 2>&1; then
    ok "el daemon.json que escribió el instalador es JSON válido"
else
    ko "daemon.json no es JSON válido"
    sed 's/^/        | /' /etc/docker/daemon.json
fi

rm -f /etc/docker/daemon.json.bak.*
LOG3="${WORK}/converge.log"
# Marca de configuración propia del operador: debe sobrevivir a la convergencia.
python3 - <<'EOF_PY'
import json
p = "/etc/docker/daemon.json"
d = json.load(open(p))
d["data-root"] = "/mnt/datos/docker"
json.dump(d, open(p, "w"), indent=2)
EOF_PY

set +e
bash "$INSTALLER" --skip-smoke --log-file "$LOG3" >"${WORK}/converge.txt" 2>&1
RC=$?
set -e

if [[ $RC -eq 0 ]]; then
    ok "la re-ejecución termina en éxito"
else
    ko "la re-ejecución falló con código ${RC}"
    tail -20 "${WORK}/converge.txt" | sed 's/^/        | /'
fi
if grep -q "Modo convergencia" "${WORK}/converge.txt"; then
    ok "entra en modo convergencia en vez de reinstalar"
else
    ko "no entró en modo convergencia"
fi
if ! grep -q "Instalando Docker Engine" "${WORK}/converge.txt"; then
    ok "no vuelve a instalar los paquetes"
else
    ko "reinstaló los paquetes"
fi
if grep -q '"data-root": "/mnt/datos/docker"' /etc/docker/daemon.json; then
    ok "la convergencia preserva la configuración propia del operador (T8)"
else
    ko "la convergencia destruyó data-root del operador"
fi
if grep -q "ya está instalado" "${WORK}/converge.txt"; then
    ok "informa de la versión ya presente"
else
    ko "no informa de la versión presente"
fi

echo
info "Convergencia con --docker-version: debe avisar de que se ignora"
set +e
bash "$INSTALLER" --docker-version 27.1.1 --skip-smoke --log-file "${WORK}/conv2.log" >"${WORK}/conv2.txt" 2>&1
set -e
if grep -q "se ignora en convergencia" "${WORK}/conv2.txt"; then
    ok "avisa de que --docker-version se ignora en convergencia (ADR-0004)"
else
    ko "no avisa de que --docker-version se ignora"
fi

#===============================================================================
echo
echo "== Prueba 4: aviso del bypass de UFW (T6, score DREAD 8.2) =="
#===============================================================================
# Se sustituye ufw por un doble de prueba: lo que se verifica es la lógica del
# aviso, no ufw. Montar un cortafuegos real en un contenedor no aportaría nada.
cat > /usr/local/bin/ufw <<'EOF_UFW'
#!/bin/sh
[ "$1" = "status" ] && echo "Status: active" && exit 0
exit 0
EOF_UFW
chmod +x /usr/local/bin/ufw

set +e
bash "$INSTALLER" --skip-smoke --log-file "${WORK}/ufw.log" >"${WORK}/ufw.txt" 2>&1
set -e

if grep -q "UFW está activo" "${WORK}/ufw.txt"; then
    ok "detecta UFW activo y avisa"
else
    ko "no avisó pese a UFW activo"
    tail -15 "${WORK}/ufw.txt" | sed 's/^/        | /'
fi
if grep -q "NO respeta sus reglas" "${WORK}/ufw.txt"; then
    ok "explica que Docker no respeta las reglas de UFW"
else
    ko "no explica el motivo del aviso"
fi
if grep -q "127.0.0.1" "${WORK}/ufw.txt"; then
    ok "ofrece la mitigación concreta (publicar en loopback)"
else
    ko "no ofrece mitigación"
fi

rm -f /usr/local/bin/ufw
set +e
bash "$INSTALLER" --skip-smoke --log-file "${WORK}/noufw.log" >"${WORK}/noufw.txt" 2>&1
set -e
if ! grep -q "UFW está activo" "${WORK}/noufw.txt"; then
    ok "no avisa cuando UFW no está presente"
else
    ko "avisa de UFW sin haber UFW"
fi

echo
echo "== ${PASS} pass · ${FAIL} fail =="
[[ $FAIL -eq 0 ]] || exit 1
