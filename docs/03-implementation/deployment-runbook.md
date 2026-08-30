# Runbook de instalación y operación

* **Estado:** review
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 03-implementation
* **Versión:** 0.2.0
* **Gate:** 2
* **Rama principal:** main
* **Estrategia de branching:** trunk-based con tags SemVer

Procedimiento operativo para instalar, verificar, endurecer y revertir. Todo lo que aparece
aquí como comando está pensado para copiarse tal cual en el host destino.

## 1. Antes de empezar

| Requisito | Comprobación |
|---|---|
| Debian 11/12/13 o Ubuntu 22.04/24.04/26.04 | `cat /etc/os-release` |
| Arquitectura soportada | `dpkg --print-architecture` → `amd64`, `arm64`, `armhf`, `ppc64el` (`s390x` solo Ubuntu) |
| Acceso root | `sudo -v` |
| Salida HTTPS | `curl -fsI https://download.docker.com/linux/debian/gpg` |
| systemd activo | `test -d /run/systemd/system && echo ok` |

## 2. Instalación verificada (procedimiento recomendado)

Este es el flujo que se debe usar en producción. Verifica el artefacto **antes** de concederle
root:

```bash
V=v1.0.0
B="https://github.com/higerotech/instalador-docker-compose/releases/download/$V"

curl -fsSLO "$B/install-docker.sh"
curl -fsSLO "$B/SHA256SUMS"

sha256sum -c SHA256SUMS          # DEBE decir: install-docker.sh: La suma coincide
less install-docker.sh           # revisión humana antes de dar root

sudo bash install-docker.sh --docker-group "$USER"
```

Si `sha256sum -c` falla: **no ejecutes el script**. Es la señal de T1/T2. Vuelve a descargar; si
persiste, avisa al mantenedor antes de seguir.

## 3. Instalación rápida (tag inmutable)

Para hosts de laboratorio o aprovisionamiento automatizado donde ya se confía en el canal:

```bash
curl -fsSL https://raw.githubusercontent.com/higerotech/instalador-docker-compose/v1.0.0/install-docker.sh \
  | sudo bash -s -- --docker-group "$USER"
```

**Usa siempre la URL del tag, nunca la de `main`** (ADR-0002). Los argumentos deben ir tras
`-s --`; sin eso el script no los recibe.

## 4. Ensayo previo

```bash
sudo bash install-docker.sh --dry-run
```

Imprime cada acción sin modificar nada. Útil para revisar qué codename detectó y qué perfil de
endurecimiento aplicaría antes de tocar un host de producción.

## 5. Flota homogénea

Para que 20 servidores queden con la misma versión:

```bash
sudo bash install-docker.sh --docker-version 27.1.1 --skip-smoke --quiet
```

Si la versión no existe, el script falla mostrando las cinco disponibles. Consulta el catálogo
completo con:

```bash
apt-cache madison docker-ce | awk '{print $3}' | head -20
```

**Nota:** sobre un host donde Docker ya está instalado, `--docker-version` se ignora (modo
convergencia). Para cambiar de versión hay que desinstalar primero — ver §11.

## 6. Verificación tras instalar

```bash
docker --version
docker compose version
systemctl is-active docker
systemctl is-enabled docker

# El endurecimiento se aplicó
docker info --format '{{.LoggingDriver}}'
sudo cat /etc/docker/daemon.json

# La bitácora registró la ejecución
sudo tail -20 /var/log/instalador-docker-compose.log

# Prueba funcional
docker run --rm hello-world
```

Salida esperada del `daemon.json` en un host limpio:

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "no-new-privileges": true,
  "default-ulimits": { "nofile": { "Name": "nofile", "Soft": 65536, "Hard": 65536 } }
}
```

## 7. El bypass de UFW (amenaza T6) — acción requerida

**Esto es lo que más incidentes causa en la práctica y el instalador no puede arreglarlo por
ti.** Docker inserta sus reglas de publicación de puertos en la cadena `DOCKER` de iptables
*antes* de que se evalúen las de UFW. Consecuencia:

```bash
sudo ufw enable
sudo ufw deny 5432
docker run -d -p 5432:5432 postgres    # ← EXPUESTO A INTERNET pese al ufw deny
```

Hay dos soluciones. Usa la primera siempre que puedas.

### Opción A (preferida): publicar solo en loopback

```bash
docker run -d -p 127.0.0.1:5432:5432 postgres
```

En `compose.yaml`:

```yaml
services:
  db:
    ports:
      - "127.0.0.1:5432:5432"
```

El puerto queda accesible solo desde el host. Para exponerlo, un proxy inverso o un túnel
delante. Es la opción correcta en el 90% de los casos y no requiere tocar el firewall.

### Opción B: filtrar en la cadena DOCKER-USER

Cuando el servicio tenga que ser accesible desde fuera pero solo para ciertas redes:

```bash
# Sustituye eth0 por tu interfaz pública y 10.0.0.0/8 por tu red de confianza
sudo iptables -I DOCKER-USER -i eth0 -s 10.0.0.0/8 -j RETURN
sudo iptables -I DOCKER-USER -i eth0 -j DROP

# Persistir entre reinicios
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

`DOCKER-USER` se evalúa antes que las reglas generadas por Docker, así que sí tiene efecto. El
orden importa: la regla `RETURN` debe insertarse **después** del `DROP` para acabar por encima
de él.

Verifica el resultado desde fuera del host, nunca desde el propio host:

```bash
nmap -Pn -p 5432 <ip-publica>     # desde otra máquina
```

## 8. Rotación de la bitácora

La bitácora crece unas pocas líneas por ejecución, pero conviene acotarla. Crea
`/etc/logrotate.d/instalador-docker-compose`:

```
/var/log/instalador-docker-compose.log {
    monthly
    rotate 3
    compress
    missingok
    notifempty
    create 0640 root root
}
```

Retiene 90 días, conforme a `data-classification.md`.

## 9. Limpieza de copias de daemon.json

Cada fusión sobre un `daemon.json` existente deja una copia. No se purgan solas de forma
deliberada: son la red de seguridad. Tras validar que el daemon funciona:

```bash
ls -l /etc/docker/daemon.json.bak.*
sudo rm /etc/docker/daemon.json.bak.<timestamp>   # solo las ya validadas
```

## 10. Ajustes opcionales conscientes

Estos **no** se aplican por defecto (ADR-0005) porque pueden romper cargas existentes. Aplícalos
solo si entiendes el efecto en tu host:

| Ajuste | Efecto | Riesgo |
|---|---|---|
| `"userland-proxy": false` | Menor consumo por puerto publicado | Puede romper el acceso a puertos publicados desde el propio host en algunos kernels |
| `"icc": false` | Aísla contenedores en la red bridge por defecto | Rompe `docker-compose.yml` que dependan de la comunicación por bridge por defecto |
| `--userns-remap` | El root del contenedor no es root del host | Rompe permisos de volúmenes existentes; incompatible con `--network host` |

Tras editar `daemon.json` a mano:

```bash
sudo python3 -m json.tool /etc/docker/daemon.json   # valida el JSON ANTES de reiniciar
sudo systemctl restart docker
systemctl is-active docker
```

## 11. Diagnóstico

### El daemon no arranca tras el endurecimiento

```bash
journalctl -u docker -n 50 --no-pager
sudo python3 -m json.tool /etc/docker/daemon.json     # ¿JSON válido?
ls -l /etc/docker/daemon.json.bak.*                   # restaura la copia más reciente
sudo cp /etc/docker/daemon.json.bak.<timestamp> /etc/docker/daemon.json
sudo systemctl restart docker
```

### `apt-get update` falla tras una ejecución interrumpida

El rollback debería haberlo evitado (ADR-0008). Si aun así ocurre:

```bash
sudo rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
sudo apt-get update
```

### Salida con código 4 — fingerprint no coincide

**No lo ignores ni lo rodees.** Significa que la llave servida por `download.docker.com` no es
la esperada. Puede ser:

1. Docker rotó su llave → hay que actualizar el pin del instalador (ADR-0003).
2. Un proxy de inspección TLS en la red está sustituyendo la llave.
3. Un ataque real a la cadena de suministro.

Verifica manualmente antes de decidir:

```bash
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --show-keys --with-fingerprint
```

Contrasta con el anuncio oficial de Docker. Si la llave cambió legítimamente, abre una issue en
el repositorio del instalador; no edites la constante en el host.

### El smoke test falla pero todo lo demás está bien

Es no fatal por diseño: normalmente indica falta de salida hacia `registry-1.docker.io`
(proxy, firewall de salida). Verifica con `docker info` y la conectividad.

## 12. Desinstalación y reversión

```bash
# Detener y eliminar paquetes
sudo systemctl stop docker
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Eliminar el repositorio y la llave
sudo rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc

# Configuración (revisa antes: /var/lib/docker contiene TODAS las imágenes y volúmenes)
sudo rm -f /etc/docker/daemon.json
sudo rm -rf /var/lib/docker /var/lib/containerd

# Grupo docker, si se creó
sudo groupdel docker

sudo apt-get update
```

> `rm -rf /var/lib/docker` **destruye todos los volúmenes, imágenes y contenedores** del host.
> Haz copia de lo que necesites antes.

## 13. Actualización de Docker

El instalador configuró el repositorio oficial, así que las actualizaciones son las normales
del sistema:

```bash
sudo apt-get update && sudo apt-get upgrade docker-ce docker-ce-cli containerd.io
```

Para volver a aplicar el endurecimiento tras una actualización (modo convergencia):

```bash
sudo bash install-docker.sh --skip-smoke
```

No reinstala nada: revisa `daemon.json`, informa de las claves respetadas y verifica el estado.
