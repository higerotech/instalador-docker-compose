# ADR-0002: Distribuir por tag SemVer inmutable con checksum publicado, en repositorio público

* **Estado:** accepted
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0002
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A03 Software Supply Chain Failures, A08 Software and Data Integrity Failures, A02 Security Misconfiguration

## Contexto

El caso de uso que motiva el proyecto es `curl … | sudo bash`: un comando que se pega en la
consola de un servidor recién creado. Eso significa que **el contenido que devuelva una URL se
ejecutará con privilegios totales**, sin revisión previa, en cada host.

Las amenazas T1 (commit malicioso en `main`) y T2 (reescritura de un tag) del threat model
nacen exactamente aquí. Y hay una decisión previa que las condiciona: si el repositorio es
privado, el `curl` necesita un token, que acabaría incrustado en la línea de comandos y por
tanto en `~/.bash_history` del servidor (T12).

Origen: requisitos RS02 y RS08 del PRD `DOCKER-INSTALL-001`.

## Decisión

Tres decisiones acopladas:

1. **Repositorio público.** Elimina T12 por completo: no hay credencial que filtrar porque no
   hace falta ninguna. El contenido es un instalador; no hay nada que proteger por oscuridad.
   Además hace gratuito e ilimitado GitHub Actions (ver ADR-0009).

2. **La URL canónica apunta a un tag inmutable**, nunca a `main`:
   `…/instalador-docker-compose/v0.2.0/install-docker.sh`. `main` se documenta explícitamente
   como "solo para pruebas". Un commit malicioso en `main` no alcanza a quien sigue las
   instrucciones publicadas.

3. **Cada release publica `SHA256SUMS`** junto al script, y el README presenta *primero* el
   flujo verificado (descargar, comprobar, ejecutar) y solo después el atajo de una línea. El
   `release.yml` valida además que el tag coincida con `SCRIPT_VERSION` y que exista la entrada
   correspondiente en el `CHANGELOG.md`, de modo que no se pueda publicar una release
   incoherente.

## Alternativas consideradas

| Opción | Pros | Contras | Riesgo de seguridad |
|---|---|---|---|
| **Tag inmutable + SHA256SUMS, `main` como conveniencia** (elegida) | Ancla de integridad verificable; no rompe el one-liner; coste cero | Requiere disciplina de tagging y protección de tags | Bajo |
| Solo `raw` de `main` | Máxima simplicidad; siempre la última versión | Un commit o un force-push llega a producción en el siguiente `curl`; sin ancla verificable | **Alto** (T1 sin mitigar) |
| Solo tags + verificación obligatoria documentada | Máxima integridad | Rompe el `curl \| bash` que justifica el proyecto; el operador buscará el atajo por su cuenta | Bajo, pero se incumple el objetivo del producto |
| Repositorio privado con token en la URL | "Menos expuesto" | El token queda en el historial del shell de cada servidor; Actions limitado a 2.000 min/mes | **Alto** (T12) |
| Firma GPG o Sigstore del artefacto | Protege incluso ante cuenta comprometida | Exige gestión de claves y que el operador tenga la clave pública; desproporcionado hoy | Muy bajo |

## Consecuencias

- **Positivas:** T1 se reduce a un residuo aceptable; T12 desaparece; el operador tiene una
  forma real de auditar antes de conceder root; CI gratuito.
- **Negativas / deuda asumida:**
  - El `SHA256SUMS` protege el tránsito, **no** protege contra una cuenta de GitHub
    comprometida que publique una release nueva y legítima con código malicioso. Ese residuo se
    acepta hoy (ver riesgo aceptado 3 del threat model).
  - Publicar una versión exige cortar tag y esperar al workflow; ya no basta con empujar a
    `main`.
  - Es obligatorio activar **protección de rama sobre `main` y protección de tags `v*`** en la
    configuración de GitHub. Sin eso, la decisión 2 no vale nada. Es criterio de Gate 4.
- **Impacto en threat model:** mitiga T1 y T2; elimina T12. Introduce dependencia operativa de
  la disciplina de tagging.

## Condiciones de revisión

- Si el instalador pasa a distribuirse fuera de Higerotech → evaluar firma Sigstore/cosign.
- Si se detecta cualquier acceso no autorizado a la cuenta de GitHub → rotar y reevaluar.
- Si GitHub cambia el modelo de precios o de acceso a `raw.githubusercontent.com`.
