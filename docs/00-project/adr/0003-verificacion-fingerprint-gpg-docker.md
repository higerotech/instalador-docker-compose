# ADR-0003: Verificar el fingerprint de la llave GPG de Docker antes de confiar en el repositorio

* **Estado:** accepted
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0003
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A03 Software Supply Chain Failures, A08 Software and Data Integrity Failures

## Contexto

El procedimiento oficial de Docker —y el script base del que parte este proyecto— descarga la
llave GPG así:

```bash
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
```

Y a continuación configura el repositorio con `Signed-By` apuntando a esa llave. El problema:
**no se verifica nada**. La única garantía es TLS. Cualquiera que pueda presentar un
certificado válido para ese dominio —una CA comprometida, un proxy corporativo de inspección
mal configurado, un DNS envenenado con un certificado emitido de forma fraudulenta— puede
entregar su propia llave. A partir de ese momento APT considerará legítimo todo paquete que ese
atacante firme, y `docker-ce` se instala como root.

Es la amenaza T3 del threat model: probabilidad baja, impacto máximo.

## Decisión

El instalador **pinnea el fingerprint** de la llave y aborta si no coincide:

```
DOCKER_GPG_FPR="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
```

La llave se descarga a un directorio temporal, se importa a un keyring desechable, se extrae su
fingerprint con `gpg --with-colons --fingerprint`, y **solo si coincide** se instala en
`/etc/apt/keyrings/`. Si no coincide, se sale con código `4` sin dejar rastro en el host.

### Procedencia del fingerprint

Docker **no publica el fingerprint en su documentación de instalación**, lo que obliga a
obtenerlo por verificación directa. El valor se estableció así el 2026-08-30:

```bash
curl -fsSL https://download.docker.com/linux/debian/gpg -o docker-debian.asc
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o docker-ubuntu.asc
gpg --show-keys --with-fingerprint --with-colons docker-debian.asc
```

Resultado, idéntico para ambos canales:

- Fingerprint primario: `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`
- UID: `Docker Release (CE deb) <docker@docker.com>`
- Subclave: `D3306A018370199E527AE7997EA0A9C3F273FCD8` (su id corto `7EA0A9C3F273FCD8` es el
  que aparece en los errores `NO_PUBKEY` habituales, lo que corrobora la identidad)
- `sha256` del fichero armored en esa fecha:
  `1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570`

**Se pinnea el fingerprint y no el sha256 del fichero** a propósito: el fichero armored puede
re-generarse legítimamente (añadir una subclave, cambiar el armor) sin que cambie la identidad
de la llave. Pinnear el hash produciría falsos positivos; pinnear el fingerprint no.

## Alternativas consideradas

| Opción | Pros | Contras | Riesgo de seguridad |
|---|---|---|---|
| **Pin del fingerprint** (elegida) | Detecta sustitución de llave; robusto ante re-armor | Si Docker rota la llave, falla toda la flota hasta actualizar el pin | Bajo |
| Confiar solo en TLS (procedimiento oficial) | Cero mantenimiento | Sin defensa ante CA comprometida o proxy de inspección | **Alto** (T3 sin mitigar) |
| Pin del `sha256` del fichero | Trivial de implementar | Falsos positivos ante cualquier re-armor legítimo; ruido que acabaría desactivándose | Medio |
| Empaquetar la llave dentro del script | No depende de la red | La llave crece el script y hay que actualizarlo en cada rotación; traslada el problema al canal del propio script | Medio |

## Consecuencias

- **Positivas:** T3 mitigada. El instalador falla de forma segura y ruidosa, que es el
  comportamiento correcto ante una posible manipulación de la cadena de suministro.
- **Negativas / deuda asumida:** se crea una **dependencia operativa**: una rotación de llave
  por parte de Docker deja la flota sin poder instalar hasta que se publique una versión nueva
  del instalador. Es un fallo cerrado (fail-closed) y se acepta conscientemente: preferimos no
  instalar a instalar confiando en una llave desconocida.
- **Negativas:** requiere `gnupg` en el host; se añade a las dependencias que instala el propio
  script.
- **Impacto en threat model:** T3 pasa de "sin control" a "mitigada con verificación
  automática". Introduce el riesgo operativo documentado arriba.

## Condiciones de revisión

- **Cualquier informe de que Docker ha rotado su llave de firma.** Procedimiento: repetir la
  verificación de procedencia de arriba, contrastar con el anuncio oficial de Docker, actualizar
  la constante, publicar versión PARCHE y avisar a los operadores.
- Revisión programada en cada release MENOR del instalador.
- Si Docker empieza a publicar el fingerprint en su documentación → citar esa fuente aquí.
