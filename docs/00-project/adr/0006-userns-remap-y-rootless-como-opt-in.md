# ADR-0006: `userns-remap` y Docker rootless quedan como opt-in, no como valor por defecto

* **Estado:** accepted
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0006
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A01 Broken Access Control, A06 Insecure Design

## Contexto

La escalada de privilegios desde un contenedor hacia el host (relacionada con la amenaza T5) se
mitiga de raíz con dos mecanismos que Docker ofrece:

- **`userns-remap`**: el `root` de dentro del contenedor se mapea a un UID sin privilegios del
  host. Un escape del contenedor aterriza como usuario normal.
- **Docker rootless**: el daemon completo corre como usuario no privilegiado.

Ambos son claramente más seguros que la configuración estándar. La pregunta no es si son
mejores en abstracto, sino si activarlos por defecto en un instalador de propósito general es
la decisión correcta.

## Decisión

**Ninguno de los dos se activa por defecto.** `userns-remap` se ofrece como `--userns-remap`
(marcado *experimental* en el contrato de interfaces); rootless queda fuera del alcance de esta
versión.

El motivo es que ambos **rompen cosas que funcionan**, de forma no obvia:

`userns-remap`:
- Los volúmenes existentes quedan con propietario incorrecto: un `bind mount` de datos previos
  se vuelve ilegible para el contenedor.
- Es incompatible con `--network host`, `--pid host` y con contenedores privilegiados.
- Las imágenes ya descargadas se re-descargan a un `data-root` distinto por espacio de nombres.

Rootless:
- No puede publicar puertos por debajo de 1024 sin configuración adicional.
- Rendimiento de red degradado (slirp4netns / pasta).
- Requiere `systemd --user`, linger habilitado y subuid/subgid configurados.
- Cambia la ruta del socket, lo que rompe cualquier automatización que asuma
  `/var/run/docker.sock`.

Un instalador cuyo valor es "un comando y el servidor queda listo" no puede introducir por
defecto un cambio que deja al operador depurando permisos de volúmenes. **El default seguro
tiene que ser también el default que funciona**, o el operador dejará de usar el instalador y
volverá a instalar a mano — que es peor resultado de seguridad que no haber endurecido nada.

En su lugar, T5 se ataca por la vía que no rompe nada: no meter a nadie en el grupo `docker`
salvo petición explícita (ADR-0007).

## Alternativas consideradas

| Opción | Pros | Contras | Riesgo de seguridad |
|---|---|---|---|
| **Ambos opt-in** (elegida) | El instalador sigue siendo predecible; disponible para quien lo necesite | La mayoría de hosts no tendrá aislamiento de espacio de nombres de usuario | Medio, mitigado por ADR-0007 |
| `userns-remap` por defecto | Mitigación fuerte de escape de contenedor | Rompe volúmenes existentes y `--network host`; incidentes garantizados en re-ejecución sobre hosts en uso | Bajo en seguridad, **alto en disponibilidad** |
| Rootless por defecto | La mitigación más fuerte | Rompe puertos < 1024, red y ruta del socket; incompatible con el parque actual | Bajo en seguridad, **muy alto en disponibilidad** |
| No ofrecerlos en absoluto | Menos superficie de opciones | Quien necesita el aislamiento tendría que salirse del instalador | Medio |

## Consecuencias

- **Positivas:** el instalador es seguro de ejecutar sobre hosts que ya tienen cargas
  corriendo, que es el requisito de convergencia. La opción está disponible para hosts nuevos
  con requisitos altos.
- **Negativas / deuda asumida:** el parque queda sin aislamiento de espacio de nombres de
  usuario. El residuo de T5 se acepta apoyándose en ADR-0007 y en el hecho de que el acceso al
  host ya está restringido a operadores con `sudo`.
- **`--userns-remap` está marcado experimental**: no está cubierto por la matriz de pruebas
  automatizadas más allá de la validez del JSON generado. Un operador que lo use debe validarlo
  en un host de pruebas antes.
- **Impacto en threat model:** T5 no se elimina; se contiene con ADR-0007. Queda registrado
  como residuo consciente.

## Condiciones de revisión

- Si un host pasa a ejecutar cargas de terceros o multi-tenant → rootless deja de ser opcional.
- Si Docker rootless resuelve la limitación de puertos privilegiados y el coste de red baja.
- Si se produce cualquier incidente de escape de contenedor en la flota.
