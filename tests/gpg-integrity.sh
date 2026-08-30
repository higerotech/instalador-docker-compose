#!/usr/bin/env bash
#===============================================================================
# tests/gpg-integrity.sh — Pruebas del control de integridad de la cadena de
#                          suministro (RS01 / T3 / ADR-0003).
#
# La prueba positiva (que el instalador ACEPTA la llave correcta) ya está
# demostrada en host real. Lo que faltaba, y es lo que de verdad prueba un
# control de seguridad, es la prueba NEGATIVA: que RECHAZA una llave que no
# coincide con el fingerprint pinneado.
#
# Para ejercitar el camino real —curl sobre TLS, gpg, comparación de
# fingerprint— en lugar de simularlo, se levanta un origen HTTPS local que
# suplanta a download.docker.com:
#
#   1. Se genera una CA propia y un certificado para download.docker.com.
#   2. La CA se instala en el almacén de confianza del contenedor.
#   3. /etc/hosts apunta download.docker.com a 127.0.0.1.
#   4. Un servidor HTTPS local sirve /linux/<distro>/gpg.
#
# Es exactamente el escenario de amenaza T3: un atacante capaz de presentar un
# certificado válido para ese dominio. Si el instalador se limitara a confiar en
# TLS —como hace el procedimiento oficial de Docker— aquí instalaría la llave
# del atacante sin protestar.
#
# DEBE EJECUTARSE DENTRO DE UN CONTENEDOR DESECHABLE: modifica /etc/hosts,
# el almacén de CAs y /etc/apt.
#
#   docker run --rm -v "$PWD:/work" -w /work debian:12 bash tests/gpg-integrity.sh
#===============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${REPO_ROOT}/install-docker.sh"
WORK="/tmp/gpg-integrity"
SERVER_PID=""

if [[ ! -f /.dockerenv ]]; then
    echo "ERROR: esta prueba modifica /etc/hosts y el almacén de CAs." >&2
    echo "       Ejecútala dentro de un contenedor desechable." >&2
    exit 2
fi

PASS=0
FAIL=0
ok() { printf '\033[0;32m  PASS  %s\033[0m\n' "$*"; PASS=$((PASS + 1)); }
ko() { printf '\033[0;31m  FAIL  %s\033[0m\n' "$*"; FAIL=$((FAIL + 1)); }
info() { printf '\033[0;34m  ...   %s\033[0m\n' "$*"; }

cleanup() {
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
    return 0
}
trap cleanup EXIT

#--- Preparación del entorno ---------------------------------------------------
info "Instalando dependencias de la prueba..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq openssl ca-certificates curl gnupg python3 >/dev/null 2>&1 \
    || { echo "No se pudieron instalar las dependencias" >&2; exit 2; }

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

# El fingerprint que el instalador tiene pinneado, leído del propio script para
# que la prueba no se desincronice si algún día se rota la llave.
EXPECTED_FPR="$(grep -m1 'readonly DOCKER_GPG_FPR=' "$INSTALLER" | cut -d'"' -f2)"
info "Fingerprint pinneado en el instalador: ${EXPECTED_FPR}"

# La llave REAL se descarga ANTES de secuestrar el DNS, para la prueba positiva.
info "Descargando la llave real de Docker (antes de secuestrar el DNS)..."
curl -fsSL https://download.docker.com/linux/debian/gpg -o "${WORK}/real.asc" \
    || { echo "Sin salida a download.docker.com; no se puede ejecutar la prueba" >&2; exit 2; }

# Llave FALSA: la que serviría un atacante.
info "Generando una llave GPG falsa (la del atacante)..."
export GNUPGHOME="${WORK}/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
# --pinentry-mode loopback + --passphrase "" son obligatorios: sin ellos gpg falla
# con "Inappropriate ioctl for device" al no haber terminal donde pedir la clave,
# y la exportación devuelve un fichero VACÍO. La prueba seguiría pasando, pero
# estaría probando una llave vacía en lugar de la llave de un atacante.
gpg --batch --pinentry-mode loopback --passphrase "" \
    --quick-generate-key "Docker Release Falsa <fake@example.invalid>" \
    default default none >/dev/null 2>&1
gpg --armor --export "fake@example.invalid" > "${WORK}/fake.asc" 2>/dev/null

if [[ ! -s "${WORK}/fake.asc" ]]; then
    echo "La llave falsa se exportó vacía; la prueba no reproduciría la amenaza." >&2
    exit 2
fi

# El fingerprint de la falsa se extrae del fichero servido, con el mismo método
# que usa el instalador. Se hace así, y no listando el keyring del usuario, para
# medir exactamente lo que el instalador verá.
fpr_of() {
    local asc="$1" kr="${WORK}/kr-$$.gpg"
    rm -f "$kr" "${kr}~"
    gpg --no-default-keyring --keyring "$kr" --quiet --import "$asc" 2>/dev/null || true
    gpg --no-default-keyring --keyring "$kr" --with-colons --fingerprint 2>/dev/null \
        | awk -F: '/^fpr:/ {print $10; exit}'
    rm -f "$kr" "${kr}~"
}
FAKE_FPR="$(fpr_of "${WORK}/fake.asc")"
REAL_FPR="$(fpr_of "${WORK}/real.asc")"
info "Fingerprint de la llave falsa: ${FAKE_FPR:-<vacío>}"

# Sin estas guardas, un fingerprint vacío haría que `grep -q ""` casara con
# cualquier salida y la prueba pasaría de forma vacua: peor que no tenerla.
if [[ -z "$FAKE_FPR" || ${#FAKE_FPR} -ne 40 ]]; then
    echo "No se pudo extraer el fingerprint de la llave falsa; la prueba sería vacua." >&2
    exit 2
fi
if [[ "$REAL_FPR" != "$EXPECTED_FPR" ]]; then
    echo "La llave real descargada (${REAL_FPR}) no coincide con el pin (${EXPECTED_FPR})." >&2
    echo "O Docker rotó su llave, o hay un problema real de integridad. Revisar ADR-0003." >&2
    exit 2
fi
if [[ "$FAKE_FPR" == "$EXPECTED_FPR" ]]; then
    echo "La llave falsa coincide con la pinneada; la prueba no tendría sentido." >&2
    exit 2
fi

#--- Origen HTTPS que suplanta a download.docker.com ---------------------------
info "Generando CA y certificado para download.docker.com..."
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 1 \
    -subj "/CN=Test CA Suplantacion" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr \
    -subj "/CN=download.docker.com" >/dev/null 2>&1
printf 'subjectAltName=DNS:download.docker.com\n' > san.ext
openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out srv.crt -days 1 -extfile san.ext >/dev/null 2>&1

cp ca.crt /usr/local/share/ca-certificates/test-suplantacion.crt
update-ca-certificates >/dev/null 2>&1

info "Apuntando download.docker.com a 127.0.0.1..."
echo "127.0.0.1 download.docker.com" >> /etc/hosts

cat > "${WORK}/server.py" <<'EOF_PY'
import http.server
import ssl
import sys

KEY_FILE = sys.argv[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.endswith("/gpg"):
            with open(KEY_FILE, "rb") as fh:
                data = fh.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            # Cualquier otra ruta (metadatos del repositorio APT) no existe:
            # es lo que hace fallar a apt-get update en la prueba de rollback.
            self.send_error(404)

    def log_message(self, *args):
        pass


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(sys.argv[2], sys.argv[3])
httpd = http.server.HTTPServer(("127.0.0.1", 443), Handler)
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF_PY

start_server() {
    local key_file="$1"
    [[ -n "$SERVER_PID" ]] && { kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; }
    python3 "${WORK}/server.py" "$key_file" "${WORK}/srv.crt" "${WORK}/srv.key" &
    SERVER_PID=$!
    for _ in $(seq 1 25); do
        if curl -fsS --max-time 2 https://download.docker.com/linux/debian/gpg -o /dev/null 2>/dev/null; then
            return 0
        fi
        sleep 0.2
    done
    echo "El servidor de suplantación no respondió" >&2
    return 1
}

reset_host_state() {
    rm -f /etc/apt/keyrings/docker.asc
    rm -f /etc/apt/sources.list.d/docker.sources
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f "$1"
}

#===============================================================================
echo
echo "== Prueba 1 (NEGATIVA): una llave que no coincide debe ser rechazada =="
#===============================================================================
LOG1="${WORK}/negativa.log"
reset_host_state "$LOG1"
start_server "${WORK}/fake.asc" || exit 2

# Comprobación previa: el origen suplantado es indistinguible para curl, es
# decir, la única defensa que queda es el pin del fingerprint.
if curl -fsS https://download.docker.com/linux/debian/gpg -o "${WORK}/served.asc" 2>/dev/null; then
    ok "el origen suplantado supera la validación TLS (TLS por sí solo no protege)"
else
    ko "el origen suplantado no supera TLS; la prueba no reproduce la amenaza T3"
fi
if cmp -s "${WORK}/served.asc" "${WORK}/fake.asc"; then
    ok "download.docker.com sirve ahora la llave del atacante"
else
    ko "el servidor no está sirviendo la llave falsa"
fi

set +e
bash "$INSTALLER" --skip-smoke --log-file "$LOG1" >"${WORK}/out1.txt" 2>&1
RC1=$?
set -e

if [[ $RC1 -eq 4 ]]; then
    ok "el instalador aborta con código 4 (EX_INTEGRITY)"
else
    ko "esperado código 4, obtenido ${RC1}"
    tail -20 "${WORK}/out1.txt" | sed 's/^/        | /'
fi
if grep -q "NO coincide" "${WORK}/out1.txt"; then
    ok "informa de que el fingerprint no coincide"
else
    ko "no informa del fingerprint no coincidente"
fi
if grep -q "$EXPECTED_FPR" "${WORK}/out1.txt" && grep -q "$FAKE_FPR" "${WORK}/out1.txt"; then
    ok "muestra el fingerprint esperado y el obtenido, para poder diagnosticar"
else
    ko "no muestra ambos fingerprints"
fi
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    ok "NO instaló la llave del atacante en el keyring"
else
    ko "instaló la llave del atacante en /etc/apt/keyrings/docker.asc"
fi
if [[ ! -f /etc/apt/sources.list.d/docker.sources ]]; then
    ok "NO configuró el repositorio APT (el host queda intacto)"
else
    ko "configuró el repositorio pese a fallar la verificación"
fi
if ! dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q "^install ok installed$"; then
    ok "no instaló ningún paquete"
else
    ko "instaló docker-ce pese a la llave inválida"
fi
if grep -q "\[ERROR\]" "$LOG1" 2>/dev/null; then
    ok "el rechazo queda registrado en la bitácora (A09 / no repudio)"
else
    ko "el rechazo no quedó en la bitácora"
fi

#===============================================================================
echo
echo "== Prueba 2 (POSITIVA + ROLLBACK): la llave correcta se acepta, y un =="
echo "== repositorio que no resuelve se revierte sin romper APT (T10)      =="
#===============================================================================
LOG2="${WORK}/positiva.log"
reset_host_state "$LOG2"
start_server "${WORK}/real.asc" || exit 2

set +e
bash "$INSTALLER" --skip-smoke --log-file "$LOG2" >"${WORK}/out2.txt" 2>&1
RC2=$?
set -e

if grep -q "Fingerprint verificado: ${EXPECTED_FPR}" "${WORK}/out2.txt"; then
    ok "acepta la llave legítima y lo registra con el fingerprint completo"
else
    ko "no aceptó la llave legítima"
    tail -20 "${WORK}/out2.txt" | sed 's/^/        | /'
fi
if [[ $RC2 -ne 0 ]]; then
    ok "falla al no poder resolver el repositorio suplantado (código ${RC2})"
else
    ko "terminó en éxito con un repositorio que no existe"
fi
if grep -qi "Revirtiendo" "${WORK}/out2.txt"; then
    ok "activa el rollback del estado de APT"
else
    ko "no activó el rollback"
fi
if [[ ! -f /etc/apt/sources.list.d/docker.sources ]]; then
    ok "el rollback retiró docker.sources"
else
    ko "dejó un docker.sources que rompería todo apt-get del host"
fi
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    ok "el rollback retiró el keyring creado en esta ejecución"
else
    ko "dejó el keyring huérfano"
fi

info "Comprobando que apt-get del host sigue sano tras el fallo..."
if apt-get update -qq >/dev/null 2>&1; then
    ok "apt-get update sigue funcionando: el host no quedó inutilizado (T10)"
else
    ko "apt-get quedó roto tras el fallo del instalador"
fi

echo
echo "== ${PASS} pass · ${FAIL} fail =="
[[ $FAIL -eq 0 ]] || exit 1
