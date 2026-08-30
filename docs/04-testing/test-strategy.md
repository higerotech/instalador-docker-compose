# Estrategia de pruebas

* **Estado:** review
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 04-testing
* **Versión:** 0.2.0
* **Gate:** 3
* **Alcance de la suite:** `install-docker.sh` y sus efectos en el host
* **Ejecución local:** `bash tests/run-all.sh`

## La pirámide, adaptada a un instalador

La pirámide clásica no encaja tal cual: aquí no hay clases que instanciar ni servicios que
levantar. Lo que sí hay es un gradiente equivalente, del más barato y rápido al más caro y
lento:

| Nivel | Qué prueba | Herramienta | Dónde corre | Coste |
|---|---|---|---|---|
| **Estático** | Sintaxis, quoting, expansiones inseguras | `bash -n`, ShellCheck | CI + local | Segundos |
| **Unitario** | Funciones aisladas con salida determinista | `tests/hardening-merge.sh` | Contenedor `python:3.12-slim` | Segundos |
| **Integración** | El script completo contra un SO real | `tests/dry-run-matrix.sh` | Contenedores Debian/Ubuntu | ~1 min |
| **Contrato** | Códigos de salida y ficheros escritos | Aserciones en la matriz + `release.yml` | CI | Segundos |
| **Seguridad** | Secretos, integridad del artefacto | gitleaks, checksum del release | CI | Segundos |
| **Sistema (E2E)** | Instalación real con paquetes y systemd | Manual en VM | Gate 2 | Minutos, requiere VM |

La base es ancha y automatizada; la cúspide es manual **por una razón estructural, no por
pereza**: verificar la instalación real exige systemd, red hacia `download.docker.com` y un
host desechable. Los contenedores no ejecutan systemd, así que hay un techo que la
automatización actual no atraviesa. Está declarado abajo como brecha conocida.

## Alcance de las pruebas sobre la arquitectura

```mermaid
C4Component
    title Alcance de pruebas — que se ejerce de verdad y que se simula

    Boundary(scope_auto, "Cubierto por la suite automatizada", "test scope") {
        Component(argparse, "parse_args", "opciones", "14 opciones y 4 combinaciones invalidas")
        Component(preflight, "detect_os + check_supported", "preflight", "4 distribuciones reales mas una no soportada")
        Component(hardening, "apply_hardening", "endurecimiento", "6 escenarios de fusion, incluido JSON corrupto")
        Component(profile, "print_hardening_profile", "perfil", "Validez del JSON con y sin userns-remap")
        Component(rollback, "on_error + rollback_apt_state", "compensacion", "Verificado de forma indirecta por los codigos de salida")
    }

    Boundary(scope_manual, "Solo verificable en host real: Gate 2", "test scope") {
        Component(gpgverify, "install_gpg_key", "integridad", "Se omite en dry-run: requiere descarga real", $tags="mocked")
        Component(pkginstall, "install_docker_packages", "instalacion", "Requiere APT y red hacia Docker", $tags="mocked")
        Component(service, "enable_service + restart_daemon", "systemd", "Los contenedores no ejecutan systemd", $tags="mocked")
        Component(firewall, "firewall_advisory", "aviso UFW", "Requiere UFW activo en el host", $tags="mocked")
    }

    Rel(argparse, preflight, "Precede a", "")
    Rel(preflight, gpgverify, "Precede a", "")
    Rel(gpgverify, pkginstall, "Establece la confianza para", "")
    Rel(pkginstall, hardening, "Precede a", "")
    Rel(hardening, service, "Requiere reinicio via", "")

    UpdateElementStyle(gpgverify, $borderColor="#b30000", $fontColor="#b30000")
    UpdateElementStyle(service, $borderColor="#cccccc", $fontColor="#999999")
    UpdateElementStyle(pkginstall, $borderColor="#cccccc", $fontColor="#999999")
    UpdateElementStyle(firewall, $borderColor="#cccccc", $fontColor="#999999")
    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

*Caption — eje estructura, fase 04-testing: el límite entre lo que la suite ejerce de verdad y
lo que queda para el Gate 2. `install_gpg_key` se marca en rojo porque es el control de
seguridad más importante que **no** está cubierto automáticamente.*

## Pruebas de transición de estado

Las transiciones inválidas son las que cubren los escenarios de abuso: un instalador se rompe
en los caminos que nadie prueba.

```mermaid
stateDiagram-v2
    [*] --> SinDocker

    SinDocker --> Incompatible: distro no soportada (alpine) -- CUBIERTO exit 3
    SinDocker --> UsoInvalido: opcion desconocida -- CUBIERTO exit 2
    SinDocker --> UsoInvalido: flags excluyentes -- CUBIERTO exit 2
    SinDocker --> UsoInvalido: canal invalido -- CUBIERTO exit 2

    SinDocker --> Evaluado: preflight correcto -- CUBIERTO 4 imagenes
    Evaluado --> Comprometido: fingerprint no coincide -- BRECHA Gate 2
    Evaluado --> RepoConfigurado: llave verificada -- BRECHA Gate 2
    RepoConfigurado --> Revertido: apt-get update falla -- BRECHA Gate 2

    RepoConfigurado --> Instalado: paquetes instalados -- BRECHA Gate 2
    Instalado --> Endurecido: fusion sobre fichero nuevo -- CUBIERTO
    Instalado --> Endurecido: fusion respetando lo existente -- CUBIERTO
    Instalado --> Instalado: JSON corrupto, no se toca -- CUBIERTO
    Instalado --> Instalado: --no-hardening -- CUBIERTO

    Endurecido --> Verificado: comprobaciones posteriores -- BRECHA Gate 2
    Verificado --> [*]
    UsoInvalido --> [*]
    Incompatible --> [*]
    Comprometido --> [*]
    Revertido --> [*]
```

*Caption — eje comportamiento, fase 04-testing: las transiciones marcadas BRECHA son las que
requieren un host real. Todas las que se pueden automatizar hoy, lo están.*

## Trazabilidad requisito ↔ prueba

Cierra el círculo abierto en el `requirementDiagram` del PRD (Gate 0).

```mermaid
requirementDiagram
    requirement RF05 {
      id: RF05
      text: Endurecer daemon json por fusion no destructiva
      risk: high
      verifymethod: test
    }
    requirement RF08 {
      id: RF08
      text: El modo de ensayo no modifica el sistema
      risk: medium
      verifymethod: test
    }
    requirement RF01 {
      id: RF01
      text: Preflight aborta sin tocar el sistema si el host no es compatible
      risk: high
      verifymethod: test
    }
    requirement RS04 {
      id: RS04
      text: Ningun usuario entra al grupo docker sin peticion explicita
      risk: high
      verifymethod: test
    }
    requirement RS01 {
      id: RS01
      text: Verificar el fingerprint GPG antes de confiar en el repositorio
      risk: high
      verifymethod: demonstration
    }

    element PruebaFusionNoDestructiva {
      type: "prueba"
    }
    element PruebaJsonCorrupto {
      type: "prueba"
    }
    element PruebaMatrizDryRun {
      type: "prueba"
    }
    element PruebaDistroNoSoportada {
      type: "prueba"
    }
    element PruebaGrupoOptIn {
      type: "prueba"
    }
    element VerificacionGate2 {
      type: "prueba"
    }

    PruebaFusionNoDestructiva - verifies -> RF05
    PruebaJsonCorrupto - verifies -> RF05
    PruebaMatrizDryRun - verifies -> RF08
    PruebaDistroNoSoportada - verifies -> RF01
    PruebaGrupoOptIn - verifies -> RS04
    VerificacionGate2 - verifies -> RS01
```

*Caption — eje trazabilidad, fase 04-testing: cuatro de los cinco requisitos de riesgo alto
tienen prueba automatizada; RS01 queda con verificación por demostración en Gate 2.*

## Matriz OWASP Top 10:2025 × cobertura

| Riesgo | Aplica | Cómo se prueba | Estado |
|---|---|---|---|
| **A01** Broken Access Control | Sí (T5) | `dry-run-matrix.sh`: nadie entra al grupo sin `--docker-group` | ✅ Automatizado |
| **A02** Security Misconfiguration | Sí (T6, T7) | `hardening-merge.sh`: rotación de logs aplicada. Aviso de UFW: manual | ⚠️ Parcial |
| **A03** Software Supply Chain | Sí (T1, T2, T3, T9) | `release.yml` valida tag ↔ versión ↔ changelog. Fingerprint: Gate 2 | ⚠️ Parcial |
| **A04** Cryptographic Failures | Marginal | `curl --proto '=https' --tlsv1.2` en la descarga de la llave | ✅ Por construcción |
| **A05** Injection | Marginal | ShellCheck detecta expansiones sin comillas; sin entrada no confiable interpretada | ✅ Estático |
| **A06** Insecure Design | Sí | Threat model + ADRs revisadas en Gate 1 | ✅ Revisión |
| **A07** Identification/AuthN | No aplica | El instalador no autentica; delega en `sudo` | — |
| **A08** Data Integrity | Sí (T1, T2, T4) | `SHA256SUMS` en release; `main "$@"` revisado en PR | ⚠️ Parcial |
| **A09** Logging Failures | Sí (T11) | Bitácora implementada; **falta aserción automatizada** | ❌ Brecha |
| **A10** Exceptional Conditions | Sí (T4, T8, T10) | Códigos 2/3/4 verificados; JSON corrupto verificado | ✅ Automatizado |

## Estado actual de la suite

Ejecución del 2026-08-30 en Docker 29.5.2:

| Suite | Aserciones | Resultado |
|---|---|---|
| ShellCheck (`install-docker.sh` + 3 scripts de test) | — | Sin hallazgos |
| `dry-run-matrix.sh` (4 imágenes × 10 + alpine) | 41 | 41 pass · 0 fail |
| `hardening-merge.sh` | 14 | 14 pass · 0 fail |
| Validación Mermaid de `docs/` | 1 por diagrama | Todos válidos |

## Brechas conocidas y cómo se cierran

Se declaran de forma explícita porque un gate no se cierra ocultando lo que falta.

| Brecha | Impacto | Cómo se cierra | Gate |
|---|---|---|---|
| La verificación real del fingerprint GPG (RS01/T3) no se ejerce: `--dry-run` la omite | El control de seguridad más importante solo está revisado, no probado | Instalación real en VM + prueba negativa con una llave falsa servida localmente | 2 → 3 |
| systemd no se ejercita (enable, restart, `is-active`) | Los contenedores no lo ejecutan | Instalación real; opcionalmente imágenes con systemd o VM efímera en CI | 2 |
| La instalación real de paquetes no se prueba | El camino feliz principal | Instalación real en Debian 12 y 13 | 2 |
| Sin aserción sobre la bitácora (A09/T11) | No se verifica que se registre lo que se dice registrar | Añadir aserción en la instalación real: la bitácora contiene START, el fingerprint y END | 2 |
| `--docker-version` (pin) sin prueba | T9 mitigada pero no verificada | Prueba con una versión antigua conocida en VM | 3 |
| `--userns-remap` solo validado como JSON | Marcado experimental en el contrato | Prueba en VM antes de promoverlo a estable | 3 |
| Aviso de UFW sin prueba | T6, score 8.2 | VM con UFW activo; comprobar que aparece el aviso | 2 |

## Criterios de Gate 3

- [ ] Todas las brechas de la tabla anterior cerradas o reclasificadas con decisión humana.
- [ ] Prueba negativa de integridad: una llave GPG que no coincide **debe** producir código 4
      y dejar el host intacto.
- [ ] Instalación real verificada en Debian 12, Debian 13, Ubuntu 22.04 y Ubuntu 24.04.
- [ ] Prueba de convergencia: segunda ejecución sobre un host ya instalado no reinstala y
      respeta la configuración existente.
- [ ] Prueba de pin de versión con una versión no-última.
- [ ] CI en verde en las cinco tareas del workflow.
