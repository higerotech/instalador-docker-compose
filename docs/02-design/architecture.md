# Diseño del Sistema — instalador-docker-compose

* **Estado:** approved
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 0.2.0
* **Gate:** 1
* **Estilo arquitectónico:** Script monolítico de un solo fichero, con separación interna por responsabilidad (puertos conceptuales) — ver ADR-0008
* **ADRs relacionadas:** ADR-0001 … ADR-0009

## Decisión estructural de partida

Este sistema tiene una restricción que domina el diseño: **debe poder ejecutarse con
`curl | sudo bash`**. Eso descarta cualquier arquitectura con módulos, librerías o ficheros
auxiliares, porque el intérprete solo recibe un flujo de texto. Todo debe caber en un fichero.

La respuesta no es renunciar a la separación de responsabilidades, sino aplicarla **dentro**
del fichero: cada responsabilidad es una función con una única razón de cambio, el estado
compartido son variables globales explícitas declaradas en un solo bloque, y el flujo de
orquestación vive únicamente en `main`. Es Clean Architecture reducida a lo que Bash permite:
`main` es el caso de uso, las funciones de preflight/repositorio/endurecimiento son los
adaptadores, y el "dominio" son las reglas de qué se considera un host soportado y un daemon
correctamente configurado.

## Contextos acotados (DDD)

| Bounded Context | Responsabilidad | Entidades núcleo |
|---|---|---|
| **Instalación** | Llevar el host desde "sin Docker" hasta "Docker operativo", de forma reversible ante fallo | Host destino, Instalación gobernada, Preflight |
| **Endurecimiento** | Converger `daemon.json` al perfil seguro sin destruir configuración del operador | Perfil de endurecimiento, Clave respetada |
| **Distribución** | Que el artefacto llegue íntegro y verificable al host | Artefacto de release, Tag inmutable, Ancla de integridad |

## Vista C4 — Container

```mermaid
C4Container
    title Container — instalador-docker-compose

    Person(operador, "Operador de infraestructura", "Ejecuta el instalador con sudo")

    System_Boundary(sistema, "instalador-docker-compose") {
        Container(script, "install-docker.sh", "Bash 5", "Fichero unico autocontenido: preflight, repositorio, paquetes, endurecimiento y verificacion")
        Container(release, "Artefacto de release", "Tag Git inmutable + SHA256SUMS", "Unidad de distribucion verificable publicada en GitHub Releases")
        Container(ci, "Pipeline de verificacion", "GitHub Actions", "ShellCheck, matriz en contenedores, fusion de daemon.json, gitleaks y Mermaid")
    }

    Boundary(host, "Host destino: estado gestionado por el instalador", "servidor Debian/Ubuntu") {
        ContainerDb(keyring, "Keyring de Docker", "GPG armored, 0644", "Llave cuyo fingerprint se verifica antes de instalarla")
        ContainerDb(sources, "docker.sources", "deb822, 0644", "Define repositorio, suite, canal y arquitectura")
        ContainerDb(daemonjson, "daemon.json", "JSON, 0644", "Perfil de endurecimiento fusionado de forma no destructiva")
        ContainerDb(bitacora, "Bitacora de instalacion", "texto plano, 0640", "Version, argumentos y resultado de cada ejecucion")
        Container(daemon, "Docker Engine", "dockerd + containerd + plugins", "Servicio gestionado por systemd")
    }

    System_Ext(github, "GitHub", "Repositorio, tags protegidos y releases")
    System_Ext(dockerrepo, "download.docker.com", "Llave GPG y paquetes firmados")

    Rel(operador, release, "Descarga y verifica el sha256", "HTTPS")
    Rel(operador, script, "Ejecuta como root con opciones explicitas", "sudo bash")
    Rel(ci, release, "Publica tras pasar las puertas de calidad", "GitHub Actions")
    Rel(release, github, "Se aloja en", "Git")
    Rel(script, dockerrepo, "Descarga la llave y verifica su fingerprint", "HTTPS + GPG")
    Rel(script, keyring, "Instala solo si el fingerprint coincide", "install -m 0644")
    Rel(script, sources, "Escribe y revierte ante fallo", "escritura atomica")
    Rel(script, daemonjson, "Fusiona el perfil respetando lo existente", "python3 json")
    Rel(script, bitacora, "Registra cada paso", "append")
    Rel(script, daemon, "Habilita, arranca y verifica", "systemctl")
    Rel(daemon, keyring, "APT valida las firmas con", "gpg")

    UpdateElementStyle(keyring, $borderColor="#b30000")
    UpdateElementStyle(release, $borderColor="#b30000")
    UpdateRelStyle(script, dockerrepo, $textColor="#b30000", $lineColor="#b30000")
    UpdateRelStyle(operador, script, $textColor="#b30000", $lineColor="#b30000")
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

*Caption — eje estructura, fase 02-design: el sistema son tres contenedores (script, artefacto,
pipeline); el cuarto bloque es el estado que el script deja en el host, y es lo que hay que
poder revertir.*

## Vista C4 — Component (interior de install-docker.sh)

```mermaid
C4Component
    title Component — interior de install-docker.sh

    Container_Boundary(script, "install-docker.sh") {
        Component(mainflow, "main", "funcion orquestadora", "Unico lugar con logica de flujo; invocada en la ultima linea del fichero")
        Component(argparse, "parse_args", "parseo de opciones", "Valida combinaciones excluyentes y devuelve codigo 2 ante uso invalido")
        Component(preflight, "detect_os + check_supported", "preflight", "Distribucion, codename, arquitectura y systemd; aborta sin tocar el sistema")
        Component(gpgverify, "install_gpg_key", "verificacion de integridad", "Descarga la llave, compara el fingerprint pinneado y solo entonces la instala")
        Component(reposetup, "configure_repo", "configuracion APT", "Escribe docker.sources en deb822 y retira el docker.list heredado")
        Component(pkginstall, "install_docker_packages", "instalacion", "Resuelve el pin de version con apt-cache madison e instala los cinco paquetes")
        Component(hardening, "apply_hardening", "endurecimiento", "Copia de seguridad y fusion no destructiva del perfil en daemon.json")
        Component(groups, "manage_docker_group", "control de acceso", "Pertenencia al grupo docker solo bajo peticion explicita")
        Component(verify, "verify_install", "verificacion posterior", "Binario, plugin compose, servicio activo y aviso de UFW")
        Component(rollback, "on_error + rollback_apt_state", "compensacion", "Trap ERR que retira el repositorio y el keyring creados en la ejecucion")
        Component(logger, "_log_line", "trazabilidad", "Bitacora con marca de tiempo, version y argumentos")
    }

    ContainerDb_Ext(daemonjson, "daemon.json", "JSON", "Configuracion del daemon en el host")
    System_Ext(dockerrepo, "download.docker.com", "Llave y paquetes firmados")

    Rel(mainflow, argparse, "Valida las opciones antes de nada", "")
    Rel(mainflow, preflight, "Decide si el host es compatible", "")
    Rel(mainflow, gpgverify, "Establece la confianza en el repositorio", "")
    Rel(mainflow, reposetup, "Configura APT", "")
    Rel(mainflow, pkginstall, "Instala los paquetes", "")
    Rel(mainflow, hardening, "Converge la configuracion", "")
    Rel(mainflow, groups, "Aplica el acceso solicitado", "")
    Rel(mainflow, verify, "Comprueba el resultado", "")
    Rel(gpgverify, dockerrepo, "Descarga y compara el fingerprint", "HTTPS")
    Rel(hardening, daemonjson, "Fusiona respetando lo existente", "python3")
    Rel(rollback, reposetup, "Revierte lo escrito si algo falla", "trap ERR")
    Rel(logger, mainflow, "Registra cada paso", "append")

    UpdateElementStyle(gpgverify, $borderColor="#b30000")
    UpdateElementStyle(groups, $borderColor="#b30000")
    UpdateElementStyle(rollback, $borderColor="#b30000")
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

*Caption — eje estructura, fase 02-design: los tres componentes marcados en rojo concentran los
controles de seguridad — confianza en el repositorio (RS01), control de acceso (RS04) y
recuperación ante fallo (RS07).*

## Flujos críticos (comportamiento)

```mermaid
sequenceDiagram
    autonumber
    actor OP as Operador
    participant GH as GitHub Releases
    participant SC as install-docker.sh
    participant DR as download.docker.com
    participant APT as APT del host
    participant DJ as daemon.json
    participant SD as systemd

    OP->>GH: descarga install-docker.sh y SHA256SUMS
    GH-->>OP: artefacto del tag inmutable
    OP->>OP: sha256sum -c SHA256SUMS
    Note over OP: Punto de decision humana:<br/>si no coincide, no se ejecuta
    OP->>SC: sudo bash install-docker.sh --docker-group jeremi

    SC->>SC: parse_args y require_root
    SC->>SC: detect_os y check_supported
    alt distribucion o arquitectura no soportada
        SC-->>OP: exit 3, host intacto
    end

    SC->>DR: GET /linux/debian/gpg
    DR-->>SC: llave publica
    SC->>SC: compara fingerprint con el pinneado
    alt fingerprint no coincide
        SC->>SC: rollback_apt_state
        SC-->>OP: exit 4, posible manipulacion
    end

    SC->>APT: escribe docker.sources y apt-get update
    alt el repositorio no resuelve
        SC->>SC: retira docker.sources y keyring
        SC-->>OP: exit 1, apt del host sigue funcionando
    end

    SC->>APT: install docker-ce docker-ce-cli containerd.io buildx compose
    APT->>DR: descarga paquetes y valida firmas
    SC->>SD: systemctl enable --now docker

    SC->>DJ: copia de seguridad y fusion del perfil
    Note over DJ: Las claves que el operador<br/>ya tenia se respetan
    SC->>SD: systemctl restart docker
    alt el daemon no arranca
        SC-->>OP: exit 1 y ruta de la copia .bak
    end

    SC->>SC: verify_install y aviso de UFW
    SC-->>OP: resumen, version y ruta de la bitacora
```

*Caption — eje comportamiento, fase 02-design: las cuatro ramas `alt` son el diseño real del
sistema. Un instalador se juzga por lo que hace cuando algo falla, no por el camino feliz.*

## Ciclo de vida del host destino

```mermaid
stateDiagram-v2
    [*] --> SinDocker

    SinDocker --> Evaluado: preflight
    Evaluado --> Incompatible: distro o arquitectura no soportada
    Incompatible --> [*]: exit 3, host intacto

    Evaluado --> ConfiandoRepo: fingerprint GPG verificado
    Evaluado --> Comprometido: fingerprint no coincide
    Comprometido --> [*]: exit 4, keyring retirado

    ConfiandoRepo --> RepoConfigurado: docker.sources escrito
    RepoConfigurado --> Revertido: apt-get update falla
    Revertido --> [*]: exit 1, apt del host sano

    RepoConfigurado --> Instalado: paquetes instalados y servicio activo
    Instalado --> Endurecido: perfil fusionado en daemon.json
    Endurecido --> Instalado: el daemon no arranca, se restaura la copia

    Endurecido --> Verificado: binario, compose y servicio comprobados
    Verificado --> Operativo: smoke test correcto u omitido
    Operativo --> Endurecido: re-ejecucion en modo convergencia
    Operativo --> [*]
```

*Caption — eje comportamiento, fase 02-design: `Operativo → Endurecido` es la arista que hace
que el script sea convergente y no solo idempotente; una re-ejecución sirve para algo.*

## Modelo de datos y dominio

```mermaid
erDiagram
    HOST ||--o{ INSTALACION : registra
    INSTALACION ||--|| ARTEFACTO : ejecuta
    INSTALACION ||--|| PERFIL_ENDURECIMIENTO : aplica
    INSTALACION ||--o{ PAQUETE : instala
    PERFIL_ENDURECIMIENTO ||--o{ CLAVE_RESPETADA : reporta

    HOST {
        string hostname
        string distro_id
        string codename
        string arquitectura
        bool tiene_systemd
    }
    INSTALACION {
        string marca_tiempo_utc
        string version_instalador
        string argumentos
        int codigo_salida
        bool modo_convergencia
    }
    ARTEFACTO {
        string tag
        string sha256
        string url_origen
    }
    PERFIL_ENDURECIMIENTO {
        string log_driver
        string max_size
        int max_file
        bool live_restore
        bool no_new_privileges
        string userns_remap
    }
    PAQUETE {
        string nombre
        string version_fijada
    }
    CLAVE_RESPETADA {
        string clave
        string valor_del_operador
    }
```

*Caption — eje estructura, fase 02-design: el modelo describe lo que una instalación deja
registrado. `CLAVE_RESPETADA` existe porque el sistema debe poder explicar qué **no** cambió.*

```mermaid
classDiagram
    class Opciones {
        +bool dryRun
        +bool doHardening
        +bool forceHardening
        +string dockerVersion
        +string canal
        +string usuarioGrupoDocker
        +string usernsRemap
        +validar() Resultado
    }
    class EntornoDetectado {
        +string distroId
        +string codename
        +string arquitectura
        +bool tieneSystemd
        +esSoportado() bool
    }
    class PerfilEndurecimiento {
        +map claves
        +aJson() string
    }
    class EstrategiaFusion {
        <<interface>>
        +fusionar(actual, deseado) Resultado
    }
    class FusionNoDestructiva {
        +fusionar(actual, deseado) Resultado
    }
    class FusionForzada {
        +fusionar(actual, deseado) Resultado
    }
    class ResultadoVerificacion {
        +string versionDocker
        +string versionCompose
        +bool servicioActivo
        +list avisos
    }

    Opciones --> EntornoDetectado
    Opciones --> PerfilEndurecimiento
    PerfilEndurecimiento --> EstrategiaFusion
    FusionNoDestructiva ..|> EstrategiaFusion
    FusionForzada ..|> EstrategiaFusion
    EntornoDetectado --> ResultadoVerificacion
```

*Caption — eje estructura, fase 02-design: la única abstracción con dos implementaciones reales
es la estrategia de fusión, que es exactamente donde `--force-hardening` cambia el
comportamiento. En Bash esto son dos ramas de `apply_hardening`, pero el contrato es este.*

## Contratos

El contrato de este sistema no es HTTP: es una **interfaz de línea de comandos** más el
conjunto de ficheros que escribe y los códigos de salida que devuelve. Está especificado
íntegramente en [`interfaces-contract.md`](interfaces-contract.md), que es el artefacto que
cierra el requisito de "contratos de API" del Gate 1.

Resumen de la superficie estable:

| Superficie | Elemento | Estabilidad |
|---|---|---|
| Entrada | 14 opciones de línea de comandos | SemVer: quitar o cambiar el significado de una opción es cambio MAYOR |
| Salida | Códigos 0–5 | Estable; añadir un código nuevo es cambio MENOR |
| Efecto | 4 rutas de fichero escritas | Estable; cambiar una ruta es cambio MAYOR |
| Entorno | `DEBIAN_FRONTEND`, `NEEDRESTART_MODE` fijados internamente | Detalle de implementación |

## Patrones de seguridad seleccionados (por amenaza DREAD priorizada)

| Amenaza | Patrón / Control | Implementación | OWASP |
|---|---|---|---|
| T5 (8.2) escalada vía grupo docker | Deny by default + consentimiento explícito | `--docker-group` obligatorio; advertencia en cada ejecución | A01 |
| T6 (8.2) bypass de UFW | Detección y aviso activo (no modificación silenciosa) | `firewall_advisory` consulta `ufw status` | A02 |
| T1 (7.6) manipulación en `main` | Artefacto inmutable + ancla de integridad | Tag SemVer + `SHA256SUMS` en la release | A03 / A08 |
| T7 (7.2) disco lleno por logs | Configuración segura por defecto | `log-opts max-size 10m, max-file 3` | A02 |
| T2 (6.8) reescritura de tag | Protección de rama y tags + verificación previa | Reglas del repositorio + procedimiento del runbook | A08 |
| T8 (6.8) destrucción de `daemon.json` | Backup + fusión no destructiva + restauración | `apply_hardening` con copia `.bak` y `python3` | A10 |
| T4 (6.6) ejecución truncada | Envoltura total en funciones | `main "$@"` como última línea | A10 |
| T10 (6.4) APT roto | Compensación transaccional | `trap ERR` → `rollback_apt_state` | A10 |
| T3 (6.0) llave suplantada | Pinning de fingerprint | Comparación contra `DOCKER_GPG_FPR`, exit 4 | A03 / A08 |
| T9 (6.0) deriva de versiones | Pin reproducible | `--docker-version` + `apt-cache madison` | A03 |
| T11 (5.2) repudio | Registro de auditoría | Bitácora `0640` con versión y argumentos | A09 |
