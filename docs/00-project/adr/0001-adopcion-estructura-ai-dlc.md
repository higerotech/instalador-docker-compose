# ADR-0001: Gobernar el proyecto con la estructura AI-DLC

* **Estado:** accepted
* **Fecha:** 2026-08-30
* **Decisores:** Jeremi Alcala
* **Fase AI-DLC:** 02-design
* **Versión:** 1.0.0
* **ID:** ADR-0001
* **Supersede / Superseded-by:** —
* **Controles OWASP afectados:** A06 Insecure Design

## Contexto

El proyecto es pequeño en líneas de código —un solo script— pero grande en consecuencias: lo
que produce se ejecuta como root en todos los servidores base de la organización. Un fallo de
diseño no se manifiesta como un bug en una pantalla, sino como una flota de servidores mal
configurada o comprometida.

La tentación en un proyecto de un fichero es no documentar nada. La pregunta real es si el
coste de la documentación se justifica cuando el artefacto es tan pequeño.

## Decisión

Se gobierna con AI-DLC completo: fases 00 a 06, gates con validación humana, diagramas de los
tres ejes inline, ADRs por decisión y `CHANGELOG.md` con SemVer.

El factor decisivo no es el tamaño del código sino **el radio de impacto y la dificultad de
revertir**. Un script de 500 líneas que corre como root en 20 servidores merece más rigor de
diseño que una aplicación de 50.000 líneas que corre en un contenedor sin privilegios.

Además, el threat model no es opcional aquí: sin él, controles como el pin del fingerprint GPG
(ADR-0003) o la envoltura en `main` (ADR-0008) sencillamente no se le ocurren a nadie mientras
escribe un instalador. Se descubren al enumerar amenazas, no al programar.

## Alternativas consideradas

| Opción | Pros | Contras | Riesgo de seguridad |
|---|---|---|---|
| **AI-DLC completo** (elegida) | Amenazas enumeradas antes de escribir; decisiones trazables; gates con firma humana | Documentación mayor que el código | Bajo |
| Solo README y comentarios | Coste mínimo | Los controles no se descubren; nadie sabe por qué el script hace lo que hace | Alto: T3, T4 y T8 no se habrían identificado |
| AI-DLC reducido a Gate 0 y 1 | Cubre requisitos y diseño | Sin fases 03–06 no hay estrategia de pruebas ni de release, que es donde vive T1/T2 | Medio |

## Consecuencias

- **Positivas:** los nueve controles de seguridad del threat model tienen origen trazable y
  prueba asociada. El repositorio sirve de plantilla para los siguientes componentes de
  infraestructura de Higerotech.
- **Negativas / deuda asumida:** mantener la documentación sincronizada con el script es
  trabajo continuo. Se mitiga derivando lo derivable (`repo-history.md` del historial real) y
  validando los diagramas en CI.
- **Impacto en threat model:** habilita el propio threat model. Sin esta decisión no existiría.
