# Clasificación de Datos

* **Estado:** approved
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 00-project
* **Versión:** 0.1.0
* **Owner de datos (DPO):** Jeremi Alcala
* **Regulación aplicable:** Ninguna específica. GDPR aplica de forma marginal al nombre de usuario del operador registrado en la bitácora del host (dato personal de empleado).

Niveles: Público < Interno < Confidencial < Restringido.

**Principio rector del proyecto: el instalador no recolecta ni transmite nada.** No hay
telemetría, no hay llamada a casa, no hay identificador de host enviado a ningún servicio.
Todo el dato que se produce se queda en el host destino. Esto es una decisión de diseño, no
una omisión: reduce el alcance regulatorio a prácticamente cero y elimina toda una familia de
amenazas de fuga de información.

| Dato | Clasificación | Regulación | Cifrado en reposo | Cifrado en tránsito | Retención |
|---|---|---|---|---|---|
| Llave pública GPG de Docker (`/etc/apt/keyrings/docker.asc`) | Público | — | No aplica (es pública) | TLS 1.2+ hacia download.docker.com | Permanente mientras Docker esté instalado |
| Definición del repositorio APT (`/etc/apt/sources.list.d/docker.sources`) | Interno | — | Heredado del host | TLS 1.2+ | Permanente |
| Codename, arquitectura y `PRETTY_NAME` del host | Interno | — | Heredado del host | No sale del host | Vida del host |
| Nombre de usuario pasado a `--docker-group` | Interno | GDPR (dato de empleado) | Heredado del host | No sale del host | Vida del host |
| Bitácora `/var/log/instalador-docker-compose.log` | Interno | GDPR (contiene el usuario) | Heredado del host; permisos `0640` root | No sale del host | **90 días** vía logrotate (ver runbook) |
| `/etc/docker/daemon.json` | Interno | — | Heredado del host | No sale del host | Permanente |
| Copias `.bak` de `daemon.json` | Interno | — | Heredado del host | No sale del host | **Manual**: el operador las purga tras validar (ver runbook) |
| Logs de contenedores (`json-file`) | Depende de la carga del host | Depende de la carga | Heredado del host | No sale del host | 30 MB por contenedor (10 MB × 3) |
| Código fuente del instalador | Público | — | No aplica | TLS 1.2+ (GitHub) | Permanente |

## Decisiones de clasificación que conviene explicitar

1. **La bitácora es Interno, no Público**, aunque el repositorio sea público: registra qué
   servidor tiene qué versión y qué usuario tiene acceso al daemon. Es reconocimiento útil
   para un atacante. Por eso se crea con permisos `0640` y propietario root.

2. **Los logs de contenedor heredan la clasificación de la carga que corre encima.** El
   instalador fija la *rotación*, no el contenido. Si un proyecto desplegado en ese host
   escribe datos personales a stdout, esos logs son del nivel que corresponda a ese proyecto
   y su retención la define ese proyecto — este documento no puede cubrirlo por adelantado.
   Se deja explícito para que el ciclo AI-DLC de cada aplicación lo herede como requisito.

3. **`daemon.json` es Interno y no debe publicarse en tickets o pastes**: puede contener
   `insecure-registries` y `data-root`, que revelan topología interna.

4. **Las copias `.bak.<timestamp>` se acumulan.** Cada ejecución que fusiona crea una. No se
   purgan solas a propósito (son la red de seguridad ante un `daemon.json` roto), pero el
   runbook incluye el paso de limpieza tras validar la instalación.
