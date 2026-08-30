# Gate 3 — Testing

Cierre de la Fase 04. Marcar solo lo fundamentado (Human-in-the-Loop).

Detalle y justificación de cada nivel en `docs/04-testing/test-strategy.md`.

## Cobertura ya conseguida

- [x] Nivel estático: ShellCheck sin hallazgos + `bash -n`
- [x] Nivel unitario: perfil de endurecimiento y fusión de `daemon.json` (14 aserciones)
- [x] Nivel integración: matriz en 4 distribuciones reales + distro no soportada (41 aserciones)
- [x] Nivel contrato: códigos de salida 0, 2 y 3 verificados; ficheros no escritos en dry-run
- [x] Nivel seguridad: gitleaks en CI; validación tag ↔ versión ↔ changelog en release
- [x] `requirementDiagram` con relaciones `verifies` — cierra el círculo abierto en Gate 0
- [x] Matriz OWASP Top 10:2025 × cobertura, con los huecos declarados

## Brechas que este gate debe cerrar

- [ ] **Prueba negativa del fingerprint GPG** (RS01/T3): una llave que no coincide produce
      código 4 y deja el host intacto. Es el control de seguridad más importante y hoy solo
      está revisado, no probado.
- [ ] systemd ejercitado: `enable`, `restart`, `is-active` en host real o VM efímera en CI
- [ ] Instalación real de paquetes probada (camino feliz principal)
- [ ] Aserción automatizada sobre la bitácora (cierra la brecha A09/T11)
- [ ] Prueba de `--docker-version` con una versión no-última (verifica T9)
- [ ] Prueba de `--userns-remap` en VM antes de promoverlo de experimental a estable
- [ ] Prueba del aviso de UFW con UFW activo (T6)
- [ ] Prueba de convergencia sobre host con Docker ya instalado

## Criterios de salida

- [ ] Toda amenaza con score DREAD ≥ 6.0 tiene al menos una prueba automatizada que ejerce su
      control (hoy: 7 de 10)
- [ ] Suite completa en verde en CI en las cinco tareas
- [ ] Ninguna brecha de la tabla de `test-strategy.md` sin cerrar o sin reclasificar por
      decisión humana explícita

**Estado Gate 3: ABIERTO** — la base de la pirámide está automatizada y en verde; la cúspide
depende del despliegue real del Gate 2, del que este gate es continuación natural.
