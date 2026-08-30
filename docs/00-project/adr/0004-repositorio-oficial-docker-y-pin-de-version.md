# ADR-0004: Instalar desde el repositorio APT oficial de Docker, con pin de versión opcional

* **Estado:** accepted
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0004
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A03 Software Supply Chain Failures

## Contexto

Hay tres formas habituales de poner Docker en un Debian, y no son equivalentes:

1. `apt install docker.io` — el paquete de la distribución. Va por detrás en versiones, no
   incluye el plugin Compose v2, y su ciclo de vida lo marca Debian, no Docker.
2. `curl -fsSL https://get.docker.com | sh` — el script de conveniencia oficial. Docker mismo
   desaconseja usarlo en producción: no es idempotente, no permite fijar versión y ejecuta
   lógica opaca como root.
3. El repositorio APT oficial de Docker — lo que documenta Docker para producción.

Además, el proyecto necesita que 20 servidores tengan la *misma* versión (amenaza T9, deriva de
versiones), y `apt install docker-ce` instala siempre la última.

## Decisión

**Repositorio APT oficial de Docker**, en formato **deb822** (`docker.sources`), con canal
seleccionable (`stable` por defecto, `test` disponible) y **pin de versión opcional**.

El formato deb822 es el que documenta Docker actualmente (verificado en
`docs.docker.com/engine/install/{debian,ubuntu}/` el 2026-08-30) y sustituye al antiguo
`docker.list` de una línea. El instalador **retira el `docker.list` heredado** si lo encuentra,
para evitar tener el mismo repositorio declarado dos veces —lo que produce avisos de APT y, si
divergen, comportamiento impredecible.

El pin se expresa en la forma que usa el operador (`--docker-version 27.1.1`) y el script lo
traduce a la cadena real del paquete con `apt-cache madison`, porque la versión de Debian es
`5:27.1.1-1~debian.12~bookworm` y nadie debería tener que escribir eso. Si la versión no
existe, falla mostrando las cinco más recientes disponibles en lugar de un error de APT opaco.

Codenames y arquitecturas soportados se validan contra una lista verificada, pero **una
discrepancia solo produce advertencia, no error**: Docker publica repositorios para codenames
nuevos antes de que esta lista se actualice, y bloquear ahí convertiría el instalador en un
obstáculo. Si el repositorio realmente no existe, `apt-get update` falla y el rollback actúa.

## Alternativas consideradas

| Opción | Pros | Contras | Riesgo de seguridad |
|---|---|---|---|
| **Repositorio oficial + deb822 + pin** (elegida) | Versiones al día; Compose v2 incluido; actualizable con `apt upgrade`; reproducible | Requiere configurar llave y repositorio | Bajo |
| `apt install docker.io` | Un comando; mantenido por Debian | Versiones retrasadas; sin Compose v2; no es lo que Docker soporta | Medio: parches de seguridad más lentos |
| `get.docker.com` | Un comando | No idempotente; sin pin de versión; lógica opaca ejecutada como root; desaconsejado por Docker para producción | **Alto**: es exactamente el antipatrón que este proyecto sustituye |
| Binarios estáticos desde tarball | Sin dependencia de APT | Sin actualizaciones automáticas; hay que gestionar systemd a mano | Medio: los parches quedan a cargo del operador |

## Consecuencias

- **Positivas:** los hosts reciben parches de seguridad de Docker por el flujo normal de
  `apt upgrade`. T9 mitigada cuando se usa el pin. El formato deb822 alinea el proyecto con la
  documentación vigente.
- **Negativas / deuda asumida:**
  - El pin es **opcional**, no obligatorio. Un operador que lo omita seguirá introduciendo
    deriva. Se documenta en el runbook como práctica recomendada para la flota.
  - En modo convergencia (Docker ya instalado) `--docker-version` se ignora y se advierte:
    cambiar de versión exige desinstalar primero. Es deliberado — un downgrade silencioso de
    `docker-ce` puede dejar contenedores inutilizables.
- **Impacto en threat model:** mitiga T9. Introduce la dependencia de `download.docker.com`
  como origen de paquetes, cuya confianza queda cubierta por ADR-0003.

## Condiciones de revisión

- Si Docker abandona el formato deb822 o cambia la estructura del repositorio.
- Si aparece un codename nuevo de Debian/Ubuntu → actualizar las listas verificadas.
- Si la deriva de versiones persiste pese al pin opcional → evaluar hacerlo obligatorio.
