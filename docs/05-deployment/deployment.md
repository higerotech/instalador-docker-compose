# Despliegue: publicación del artefacto y despliegue en la flota

* **Estado:** draft
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 05-deployment
* **Versión:** 0.2.0
* **Gate:** 4
* **Entorno objetivo:** GitHub Releases (artefacto) · servidores base Debian/Ubuntu de Higerotech (consumo)
* **Estrategia de release:** tags SemVer inmutables + despliegue en olas por criticidad

En este proyecto "desplegar" tiene dos significados que conviene no mezclar:

1. **Publicar el artefacto** — cortar un tag y que GitHub Releases sirva el script con su
   checksum. Es automático y lo hace `release.yml`.
2. **Desplegar en la flota** — que cada servidor ejecute el instalador. Es manual y por olas,
   porque cada ejecución toca un host en producción.

## Topología (C4 Deployment)

```mermaid
C4Deployment
    title Deployment — del tag al host destino

    Deployment_Node(estacion, "Estacion del operador", "portatil o bastion") {
        Container(cli, "curl + sha256sum", "shell", "Descarga y verifica el artefacto antes de ejecutarlo")
    }

    Deployment_Node(github, "GitHub", "SaaS") {
        Deployment_Node(runner, "Runner de Actions", "ubuntu-latest efimero") {
            Container(ci, "Workflow CI", "GitHub Actions", "ShellCheck, matriz en contenedores, gitleaks, Mermaid")
            Container(rel, "Workflow Release", "GitHub Actions", "Valida tag y changelog, genera SHA256SUMS y publica")
        }
        Deployment_Node(releases, "GitHub Releases", "almacenamiento de artefactos") {
            Container(artefacto, "install-docker.sh + SHA256SUMS", "texto plano", "Artefacto inmutable del tag")
        }
    }

    Deployment_Node(host, "Host destino", "Debian 12/13 o Ubuntu 22.04/24.04") {
        Deployment_Node(systemd, "systemd", "gestor de servicios") {
            Container(dockerd, "dockerd", "Docker Engine", "Daemon endurecido segun daemon.json")
            Container(containerd, "containerd", "runtime", "Ejecuta los contenedores")
        }
        Deployment_Node(etc, "Estado de configuracion", "sistema de ficheros") {
            Container(cfg, "daemon.json, docker.sources, keyring", "ficheros", "Escritos por el instalador")
            Container(bitacora, "Bitacora de instalacion", "log 0640", "Traza de cada ejecucion")
        }
    }

    Deployment_Node(dockerinfra, "Infraestructura de Docker Inc", "SaaS") {
        Container(aptrepo, "download.docker.com", "repositorio APT", "Paquetes firmados y llave GPG")
    }

    Rel(ci, rel, "Debe pasar antes de publicar", "estado del workflow")
    Rel(rel, artefacto, "Publica con checksum", "GitHub API")
    Rel(cli, artefacto, "Descarga y verifica sha256", "HTTPS")
    Rel(cli, dockerd, "Ejecuta el instalador como root", "sudo bash")
    Rel(cli, cfg, "Escribe la configuracion", "sistema de ficheros")
    Rel(cli, aptrepo, "Instala paquetes firmados", "HTTPS + GPG")
    Rel(cli, bitacora, "Registra la ejecucion", "append")

    UpdateElementStyle(artefacto, $borderColor="#b30000")
    UpdateRelStyle(cli, artefacto, $textColor="#b30000", $lineColor="#b30000")
    UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="1")
```

*Caption — eje estructura, fase 05-deployment: la única frontera con control criptográfico real
está entre el artefacto publicado y la estación del operador; el resto es confianza en TLS más
la firma de APT.*

## Pipeline de publicación y ruta de reversión

```mermaid
flowchart TD
    PR[Pull request a main] --> G1{ShellCheck}
    G1 -- falla --> STOP1[Bloqueado: corregir el script]
    G1 -- pasa --> G2{Validacion Mermaid}
    G2 -- falla --> STOP2[Bloqueado: diagrama mal formado]
    G2 -- pasa --> G3{Matriz dry-run<br/>4 imagenes + alpine}
    G3 -- falla --> STOP3[Bloqueado: regresion de comportamiento]
    G3 -- pasa --> G4{Fusion de daemon.json}
    G4 -- falla --> STOP4[Bloqueado: riesgo de romper hosts]
    G4 -- pasa --> G5{gitleaks}
    G5 -- falla --> STOP5[Bloqueado: posible secreto]
    G5 -- pasa --> REV[Revision humana del PR]

    REV --> MERGE[Merge a main]
    MERGE --> BUMP[Subir SCRIPT_VERSION y cortar la seccion del CHANGELOG]
    BUMP --> TAG[git tag -a vX.Y.Z]
    TAG --> RW[Workflow Release]

    RW --> G6{El tag coincide con SCRIPT_VERSION}
    G6 -- no --> STOP6[Publicacion abortada]
    G6 -- si --> G7{Existe la seccion en CHANGELOG}
    G7 -- no --> STOP7[Publicacion abortada]
    G7 -- si --> SUMS[Generar SHA256SUMS]
    SUMS --> PUB[Publicar release con artefacto y checksum]

    PUB --> OLA1[Ola 1: host de laboratorio]
    OLA1 --> VER1{Verificacion posterior correcta}
    VER1 -- no --> RB[Reversion]
    VER1 -- si --> OLA2[Ola 2: hosts no criticos]
    OLA2 --> OLA3[Ola 3: hosts criticos]

    RB --> RB1[Retirar la release y despublicar el tag]
    RB1 --> RB2[Los hosts afectados: restaurar daemon.json desde .bak]
    RB2 --> RB3[Publicar version PARCHE con la correccion]
    RB3 --> RB4[Nunca reescribir un tag ya publicado: ADR-0002]
```

*Caption — eje comportamiento, fase 05-deployment: siete puertas antes de que un artefacto sea
descargable. La rama de reversión termina en la regla que sostiene ADR-0002 — un tag publicado
no se reescribe jamás; se publica uno nuevo.*

## Publicar una release sin mover el tag

GitHub **no registra un workflow hasta que llega a la rama por defecto**. Un tag empujado antes
de ese momento no dispara nunca su release, y es exactamente lo que ocurrió con `v0.2.0`. La
salida evidente —borrar el tag y volver a empujarlo— es justo lo que ADR-0002 prohíbe: un tag
publicado no se reescribe.

Por eso `release.yml` acepta disparo manual con el tag como entrada:

```bash
gh workflow run release.yml --ref main -f tag=v0.2.0
```

Se lanza **desde la rama por defecto** (de ahí sale la lógica del workflow, que es la única
versión que tiene `workflow_dispatch`) y hace checkout del **contenido del tag**, que es lo que
se publica y sobre lo que se calcula el `SHA256SUMS`. El tag no se toca.

El workflow además detecta los tags de hito documental: si el ref no contiene
`install-docker.sh` —como `v0.1.0`, que es solo requisitos— emite un aviso y termina sin
publicar artefacto, en vez de fallar.

## Inmutabilidad de los tags: cómo está impuesta y qué cuesta

ADR-0002 se apoya en que un tag publicado no se pueda reescribir. Eso dejó de ser una
convención y pasa a estar impuesto por el ruleset `Protect-Tags`:

| Elemento | Valor |
|---|---|
| Target | `tag`, sobre `refs/tags/v*` |
| Reglas | `deletion`, `non_fast_forward`, `update` |
| Actores con bypass | **ninguno** (`current_user_can_bypass: never`) |

Verificado con dos pruebas no destructivas: el borrado se rechaza con *Cannot delete this tag* y
un `--force` con *Cannot update this protected ref*. Crear tags nuevos sigue permitido, porque
no se añadió la regla `creation` — de lo contrario no se podría publicar ninguna versión.

**El coste de esto hay que conocerlo antes de necesitarlo.** Sin actores con bypass, *nadie*
—tampoco el propietario— puede borrar ni mover un tag `v*`. Un tag empujado por error (al commit
equivocado, o con un typo como `v0.20.0`) **es permanente**. Eso es exactamente lo que se
pretendía, pero implica dos cosas:

1. **La corrección de un tag erróneo no es borrarlo, es publicar el siguiente.** Si `v0.3.0`
   apunta a un commit equivocado, se abandona y se publica `v0.3.1`. El tag muerto se documenta
   en el `CHANGELOG.md` marcando la versión como `[YANKED]`, según Keep a Changelog.
2. **Solo si es imprescindible**, el propietario puede poner el ruleset en `evaluate` o añadirse
   como bypass temporalmente, corregir, y volver a `active` de inmediato. Debe quedar registrado
   como excepción: es una desviación consciente de ADR-0002, no un procedimiento normal.

```bash
# Consultar el estado del ruleset
gh api repos/higerotech/instalador-docker-compose/rulesets --jq '.[] | "\(.name)\t\(.target)\t\(.enforcement)"'
```

## Reversión: qué se puede y qué no

| Situación | Acción | Reversible |
|---|---|---|
| El artefacto publicado tiene un defecto y **nadie lo instaló aún** | Retirar la release, borrar el tag remoto, publicar PARCHE | Sí |
| El artefacto se instaló y **rompió el daemon** | Restaurar `daemon.json.bak.<ts>` en cada host afectado y reiniciar | Sí |
| El artefacto se instaló y **dejó `apt` roto** | No debería ocurrir (ADR-0008); si ocurre, §11 del runbook | Sí |
| El artefacto **instaló una versión errónea de Docker** | Desinstalar y reinstalar con `--docker-version` correcto | Sí, con parada de contenedores |
| Se añadió a alguien al grupo `docker` por error | `gpasswd -d <usuario> docker` + cerrar sus sesiones | Sí |
| Un tag comprometido **ya fue descargado y ejecutado** | **No reversible por el proyecto.** Es incidente de seguridad: reconstruir el host | **No** |

La última fila es el motivo de la existencia de ADR-0002 y del `SHA256SUMS`. Un instalador que
corre como root no tiene deshacer.

## Cutover: despliegue en la flota

```mermaid
gantt
    title Despliegue de una version nueva en la flota
    dateFormat YYYY-MM-DD
    section Preparacion
    Publicar release y checksum      :done, p1, 2026-09-01, 1d
    Revisar CHANGELOG con operadores :p2, after p1, 1d
    section Ola 1 laboratorio
    Instalar en host de pruebas      :crit, o1, after p2, 1d
    Verificacion completa y smoke    :o2, after o1, 1d
    section Ola 2 no criticos
    Instalar en hosts no criticos    :o3, after o2, 2d
    Observacion de 48 horas          :o4, after o3, 2d
    section Ola 3 criticos
    Ventana de mantenimiento         :crit, o5, after o4, 1d
    Instalar en hosts criticos       :crit, o6, after o5, 1d
    Verificacion final e inventario  :o7, after o6, 1d
    section Cierre
    Actualizar inventario de version :o8, after o7, 1d
    Purgar copias .bak validadas     :o9, after o8, 1d
```

*Caption — eje trazabilidad, fase 05-deployment: la observación de 48 horas entre la ola 2 y la
3 existe porque los efectos del endurecimiento (rotación de logs, `live-restore`) no se
manifiestan de inmediato, sino tras acumular actividad.*

## Criterios de Gate 4

- [ ] **Protección de rama `main` activada** en GitHub (sin push directo, PR obligatorio).
      Sin esto, ADR-0002 no se sostiene.
- [ ] **Protección de tags `v*`** activada (no se pueden reescribir ni borrar).
- [ ] Workflow `release.yml` ejecutado con éxito al menos una vez.
- [ ] `SHA256SUMS` publicado y verificado manualmente por un operador distinto del que publicó.
- [x] Disparo manual (`workflow_dispatch`) disponible para publicar un tag existente sin
      reescribirlo, y salida limpia en tags de hito documental sin instalador.
- [ ] Runbook validado ejecutándolo paso a paso en un host real.
- [ ] Ruta de reversión probada: restaurar `daemon.json` desde `.bak` en un host de pruebas.
- [ ] Inventario de la flota con versión de instalador y de Docker por host.
- [ ] `<TODO>` Definir quién es el aprobador de la ola 3 (hosts críticos).
