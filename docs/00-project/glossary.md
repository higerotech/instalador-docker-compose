# Glosario / Lenguaje Ubicuo (DDD)

* **Estado:** approved
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 00-project
* **Versión:** 0.1.0
* **Contextos acotados:** Instalación · Endurecimiento · Distribución

Tres contextos acotados, con vocabularios que no deben mezclarse:

- **Instalación** — lo que ocurre *en el host destino*: detectar, instalar, verificar.
- **Endurecimiento** — la configuración *del daemon* que el instalador converge.
- **Distribución** — cómo el artefacto *llega* al host: tags, checksums, releases.

| Término | Definición | Contexto acotado |
|---|---|---|
| **Host destino** | Servidor Debian/Ubuntu sobre el que se ejecuta el instalador. Es el agregado raíz del contexto de Instalación. | Instalación |
| **Operador** | Persona con `sudo` en el host destino que ejecuta el instalador. Único actor humano del sistema. | Instalación |
| **Instalación gobernada** | Ejecución completa del instalador: preflight → repositorio → paquetes → endurecimiento → verificación. Se distingue de una instalación manual en que es reproducible y deja traza. | Instalación |
| **Preflight** | Conjunto de comprobaciones previas a modificar el sistema: root, distribución, codename, arquitectura, systemd. Si falla, el host queda intacto. | Instalación |
| **Convergencia** | Comportamiento en re-ejecución: si Docker ya está instalado no se reinstala, pero sí se revisa y aplica la configuración. Es lo que hace el script idempotente sin ser inútil. | Instalación |
| **Rollback de estado APT** | Retirada del `docker.sources` y del keyring creados en la ejecución cuando esta falla antes de instalar. Evita dejar el `apt-get` del host roto. | Instalación |
| **Codename** | Nombre en clave de la versión de la distribución (`bookworm`, `trixie`, `noble`). Determina la suite del repositorio APT de Docker. | Instalación |
| **Bitácora de instalación** | Fichero `/var/log/instalador-docker-compose.log` con marca de tiempo, versión del instalador, argumentos y resultado. Evidencia de no repudio. | Instalación |
| **Perfil de endurecimiento** | Conjunto de claves de `daemon.json` que el instalador considera configuración segura por defecto: rotación de logs, `live-restore`, `no-new-privileges`, `default-ulimits`. | Endurecimiento |
| **Fusión no destructiva** | Estrategia de escritura de `daemon.json`: se añaden las claves del perfil que faltan y se **respeta** el valor que el operador ya hubiera puesto, salvo `--force-hardening`. | Endurecimiento |
| **Clave respetada** | Clave del perfil que existía ya en `daemon.json` con otro valor y por tanto no se tocó. Se reporta al operador al terminar. | Endurecimiento |
| **Grupo docker** | Grupo Unix cuya pertenencia da acceso al socket del daemon y por tanto **equivale a root** en el host. Por eso su asignación es opt-in. | Endurecimiento |
| **Bypass de UFW** | Comportamiento de Docker por el que sus reglas de publicación de puertos se insertan antes que las de UFW, dejando expuesto un puerto que el firewall cree denegado. | Endurecimiento |
| **Artefacto de release** | El fichero `install-docker.sh` publicado en un tag concreto, junto a su `SHA256SUMS`. Unidad inmutable de distribución. | Distribución |
| **Tag inmutable** | Etiqueta Git `vX.Y.Z` protegida contra reescritura. Es la URL canónica que se recomienda en el `curl`. | Distribución |
| **Ancla de integridad** | El `SHA256SUMS` publicado en la release, que permite al operador verificar el script **antes** de ejecutarlo como root. | Distribución |
| **Canal** | Componente del repositorio APT de Docker: `stable` (por defecto) o `test`. No confundir con el canal de distribución del propio instalador. | Distribución |
| **Ejecución truncada** | Fallo en el que la descarga del script se corta a mitad y el intérprete ejecuta un fragmento. Neutralizada envolviendo todo en funciones e invocando `main` en la última línea. | Distribución |
