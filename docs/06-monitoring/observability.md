# Observabilidad y respuesta a incidentes

* **Estado:** draft
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 06-monitoring
* **Versión:** 0.2.0
* **Gate:** 5
* **SLOs (ref):** ver tabla de SLIs/SLOs de este documento
* **On-call:** `<TODO>` definir rotación; hoy es Jeremi

## Premisa: el instalador no observa nada, y es deliberado

El instalador **no envía telemetría**. No hay ping a un servidor de estadísticas, ni
identificador de host, ni contador de instalaciones. Es una decisión de diseño registrada en
`data-classification.md`: elimina toda una familia de amenazas de fuga y deja el alcance
regulatorio en prácticamente cero.

La consecuencia es que la observabilidad de este sistema **no es push, es pull**: el estado
vive distribuido en los hosts y hay que ir a buscarlo. Eso condiciona todo lo que sigue.

## Qué se observa y dónde vive

| Señal | Dónde vive | Cómo se recoge | Qué detecta |
|---|---|---|---|
| Resultado de cada instalación | `/var/log/instalador-docker-compose.log` en cada host | `ssh` + `tail`, o el gestor de configuración | Instalaciones fallidas, quién recibió acceso al grupo docker |
| Versión de Docker por host | `docker --version` | Inventario periódico | Deriva de versiones (T9) |
| Versión del instalador aplicada | Línea `START` de la bitácora | Inventario periódico | Hosts con versión antigua del instalador |
| Deriva de `daemon.json` | `/etc/docker/daemon.json` | Comparación contra el perfil esperado | Endurecimiento revertido a mano |
| Ocupación de disco por logs | `du -sh /var/lib/docker/containers` | Métrica del host | Que la rotación funciona (T7) |
| Puertos publicados en `0.0.0.0` | `docker ps --format` / `ss -tlnp` | Escaneo periódico | Exposición no intencionada (T6) |
| Avisos de seguridad de Docker | Docker Security Advisories | Suscripción | CVEs que exijan actualizar |
| Miembros del grupo docker | `getent group docker` | Inventario periódico | Concesiones de root no registradas (T5) |

## Flujo de una señal hasta la acción

```mermaid
sequenceDiagram
    autonumber
    participant CRON as Inventario periodico
    participant HOST as Hosts de la flota
    participant INV as Inventario consolidado
    participant OP as Operador
    participant REPO as Repositorio del instalador

    CRON->>HOST: recoge version de docker, daemon.json y grupo docker
    HOST-->>CRON: estado actual
    CRON->>INV: consolida el estado de la flota
    INV->>INV: compara contra el estado esperado

    alt deriva de version detectada
        INV->>OP: hosts fuera de la version objetivo
        OP->>HOST: reinstala con --docker-version fijado
    end

    alt endurecimiento revertido
        INV->>OP: daemon.json no coincide con el perfil
        OP->>HOST: ejecuta el instalador en modo convergencia
    end

    alt puerto publicado en 0.0.0.0 inesperado
        INV->>OP: exposicion potencial, amenaza T6
        OP->>HOST: republica en loopback o aplica regla DOCKER-USER
    end

    alt CVE relevante de Docker
        OP->>REPO: abre issue y evalua nueva version fijada
        REPO-->>OP: release con la version corregida
        OP->>HOST: despliegue por olas segun fase 05
    end
```

*Caption — eje comportamiento, fase 06-monitoring: las cuatro ramas son los únicos motivos por
los que este sistema genera trabajo operativo. Tres de ellas terminan re-ejecutando el
instalador, que es justo lo que el modo convergencia habilita.*

## Ciclo de vida de un incidente

```mermaid
stateDiagram-v2
    [*] --> Detectado

    Detectado --> Triado: se clasifica el tipo
    Triado --> FalloInstalacion: un host no completo la instalacion
    Triado --> DerivaConfiguracion: el estado no coincide con el esperado
    Triado --> IncidenteSeguridad: sospecha de artefacto manipulado
    Triado --> DefectoInstalador: el fallo se reproduce en varios hosts

    FalloInstalacion --> Diagnosticado: bitacora y journalctl
    Diagnosticado --> Mitigado: runbook seccion 11
    Mitigado --> Cerrado

    DerivaConfiguracion --> Convergido: re-ejecutar el instalador
    Convergido --> Cerrado

    IncidenteSeguridad --> Contenido: aislar el host y revocar accesos
    Contenido --> Reconstruido: el host se reconstruye desde cero
    Reconstruido --> PostMortem
    note right of Reconstruido
        Un instalador que corrio como root
        no tiene deshacer: se reconstruye
    end note

    DefectoInstalador --> Reproducido: anadir caso a la suite
    Reproducido --> Corregido: version PARCHE publicada
    Corregido --> PostMortem

    PostMortem --> NuevoRequisito: alimenta la fase 01 del siguiente ciclo
    PostMortem --> Cerrado
    NuevoRequisito --> [*]
    Cerrado --> [*]
```

*Caption — eje comportamiento, fase 06-monitoring: la rama de incidente de seguridad termina en
reconstrucción, no en limpieza. La de defecto termina siempre añadiendo un caso a la suite —
es el bucle 06 → 01 de la metodología.*

## SLIs y SLOs

Estos objetivos son de un sistema de aprovisionamiento, no de un servicio en línea: no hay
disponibilidad que medir, hay **corrección y homogeneidad**.

| SLI | SLO | Ventana | Cómo se mide |
|---|---|---|---|
| Instalaciones que terminan con código 0 | ≥ 98% | Trimestre | Bitácoras de la flota |
| Hosts con la versión de Docker objetivo | 100% | Mensual | Inventario |
| Hosts con el perfil de endurecimiento íntegro | 100% | Mensual | Comparación de `daemon.json` |
| Hosts con puertos publicados en `0.0.0.0` sin justificar | 0 | Mensual | Escaneo |
| Miembros del grupo docker no registrados en bitácora | 0 | Trimestre | `getent` vs bitácoras |
| Tiempo desde CVE crítico de Docker hasta flota actualizada | ≤ 7 días | Por evento | Fecha del aviso vs inventario |

## Roadmap

```mermaid
timeline
    title Evolucion del instalador
    Q3 2026 : Gate 0 y Gate 1 cerrados : Script 0.2.0 con endurecimiento : Suite de 55 aserciones
    Q4 2026 : Gate 2 con despliegue real verificado : Prueba negativa del fingerprint GPG : Inventario de flota automatizado
    Q1 2027 : Gate 3 y Gate 4 : Proteccion de ramas y tags : Deteccion de deriva de daemon.json
    Q2 2027 : Evaluacion de rootless para hosts multi tenant : Revision del pin GPG y de precios de la ADR 0009
```

*Caption — eje trazabilidad, fase 06-monitoring: la revisión del pin GPG y de los precios de la
ADR-0009 aparecen en el roadmap porque ambos tienen fecha de caducidad declarada.*

## Criterios de Gate 5

- [ ] Inventario de la flota automatizado (versión de Docker, versión del instalador, hash de
      `daemon.json`, miembros del grupo docker).
- [ ] Detección de deriva del perfil de endurecimiento con alerta al operador.
- [ ] Suscripción activa a los avisos de seguridad de Docker con responsable asignado.
- [ ] Proceso de incidentes documentado y ensayado al menos una vez.
- [ ] Rotación de la bitácora (logrotate) desplegada en toda la flota.
- [ ] `<TODO>` Definir la rotación de on-call.
- [ ] `<TODO>` Decidir la herramienta de inventario (Ansible ad-hoc, gestor de configuración o
      script propio) — condiciona el resto de criterios.
