# AGENTS.md

## Alcance

Estas instrucciones se aplican a todo el repositorio RadioMix. El proyecto es
una aplicación Flutter multiplataforma con foco principal en Android.

## Estructura

- `lib/`: código Dart de la aplicación.
- `test/`: pruebas unitarias y de widgets.
- `assets/icon/`: icono usado en tiempo de ejecución.
- `assets/logo_options/`: propuestas de identidad visual.
- `assets/store/`: recursos gráficos para las fichas de las tiendas.
- `docs/`: documentación pública.
- `scripts/`: utilidades de ejecución y compilación Android.
- `memoria/`: notas internas locales; está ignorada y nunca debe versionarse.

## Seguridad y privacidad

- No añadas ni fuerces (`git add -f`) ningún archivo de `memoria/`.
- No versiones keystores, certificados, archivos `.env`, propiedades locales,
  credenciales de servicios ni claves API reales.
- Conserva únicamente ejemplos sin valores reales, como
  `android/keystore.properties.example`.
- Mantén fuera de Git los toolchains descargados (`.tools/`) y la configuración
  local de agentes o editores.
- Trata los backups XML generados por RadioMix como sensibles: pueden contener
  preferencias y credenciales de proveedores configuradas por el usuario.
- Antes de entregar cambios, revisa `git status --short`, los diffs y la lista
  de archivos rastreados para confirmar que no se incorporan datos privados.

## Flujo de trabajo

1. Instala dependencias con `flutter pub get`.
2. Formatea Dart con `dart format lib test`.
3. Ejecuta `flutter analyze` y `flutter test`.
4. Para Android, usa un JDK 17 o 21. Los scripts de `scripts/` seleccionan un
   JDK compatible mediante `RADIOMIX_JAVA_HOME`, `JAVA_HOME` o instalaciones
   habituales del sistema.
5. Para cambios de build Android, valida al menos:
   `./scripts/android_with_jdk.sh ./gradlew :app:processDebugMainManifest`.

## Criterios de implementación

- Mantén la separación actual entre pantallas, widgets, modelos y servicios.
- Reutiliza providers y servicios existentes antes de introducir estado global
  o clientes de red nuevos.
- Añade o actualiza pruebas cuando cambie el comportamiento.
- No edites archivos generados de Flutter; regénéralos con la herramienta que
  corresponda.
- Evita incluir rutas absolutas, datos de una máquina concreta o resultados de
  build en documentación pública.
