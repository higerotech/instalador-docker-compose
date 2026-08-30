# ADR-0007: La pertenencia al grupo `docker` es opt-in explícito, nunca automática

* **Estado:** accepted
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0007
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A01 Broken Access Control

## Contexto

El script base del que parte este proyecto hacía esto al final:

```bash
TARGET_USER="${SUDO_USER:-}"
if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
    usermod -aG docker "$TARGET_USER"
fi
```

Es el comportamiento que aparece en casi todos los tutoriales, y es cómodo: el operador puede
usar `docker` sin `sudo` inmediatamente. También es, de forma silenciosa, **una concesión de
privilegios de root permanente**.

Pertenecer al grupo `docker` da acceso de escritura al socket del daemon. Con eso, cualquier
miembro del grupo puede hacer:

```bash
docker run -v /:/host -it debian chroot /host
```

y obtener una shell de root en el host. Sin `sudo`, sin contraseña, sin quedar registrado en
`auth.log` como una elevación de privilegios. Es la amenaza **T5**, con score DREAD **8.2** —
la más alta del modelo, empatada con T6.

Lo relevante no es que el mecanismo sea conocido —está documentado por Docker—, sino que el
script lo aplicaba **por inferencia** (`$SUDO_USER`) y no por decisión. Nadie escribió "concede
root a este usuario"; simplemente ocurrió.

## Decisión

El instalador **no añade a nadie al grupo `docker` salvo que se le pida por nombre**:

```bash
sudo bash install-docker.sh --docker-group jeremi
```

- `$SUDO_USER` **no se lee** para este propósito. Está documentado explícitamente en el
  contrato de interfaces para que quede constancia de que es una omisión deliberada.
- Cuando se usa la opción, el script emite una **advertencia en cada ejecución**: "equivale a
  concederle root sin sudo (ADR-0007)".
- Cuando no se usa, el script **informa** de que nadie fue añadido y recuerda que la
  pertenencia equivale a root, para que la decisión sea consciente en ambas direcciones.
- Si el usuario indicado no existe, se aborta con error en vez de crearlo.
- La advertencia queda registrada en la bitácora, lo que da traza de quién recibió el acceso y
  cuándo (mitiga parcialmente T11).

## Alternativas consideradas

| Opción | Pros | Contras | Riesgo de seguridad |
|---|---|---|---|
| **Opt-in por nombre con advertencia** (elegida) | La concesión de root es un acto explícito y trazable | Un paso más para el operador que quiere comodidad | Bajo |
| Añadir `$SUDO_USER` automáticamente (script base) | Cero fricción | Concede root de facto sin decisión; invisible en la revisión posterior | **Alto** (T5 sin mitigar) |
| No permitirlo en absoluto | Elimina T5 del instalador | El operador lo hará a mano con `usermod`, sin advertencia ni traza: el riesgo se mueve, no desaparece | Medio |
| Añadir y luego avisar | Comodidad más información | El aviso llega cuando el cambio ya está hecho; nadie deshace un `usermod` tras leer un warning | Alto |

## Consecuencias

- **Positivas:** T5 pasa de ocurrir por defecto a requerir una decisión escrita. Queda traza en
  la bitácora del host. El operador que no pasa la opción usa `sudo docker`, que sí queda
  registrado en los logs de autenticación.
- **Negativas / deuda asumida:**
  - Fricción real: quien quiera comodidad tiene que escribir la opción. Es intencionado —
    la fricción está puesta exactamente en el punto donde se concede root.
  - El riesgo no se elimina: un operador puede seguir ejecutando `usermod -aG docker` por su
    cuenta. El instalador no puede impedirlo; solo puede no hacerlo en su nombre.
  - No se ofrece `sudo docker` sin contraseña como alternativa cómoda, porque tendría
    exactamente el mismo efecto con más pasos.
- **Impacto en threat model:** control principal de T5 (score 8.2). El residuo se documenta en
  ADR-0006, donde se explica por qué no se acompaña de `userns-remap` por defecto.

## Condiciones de revisión

- Si el host pasa a tener usuarios que no deban ser root → evaluar rootless (ADR-0006) o
  acceso al daemon vía socket con proxy de autorización.
- Si se detecta que operadores están ejecutando `usermod -aG docker` a mano de forma habitual →
  el control no está funcionando; revisar el enfoque.
