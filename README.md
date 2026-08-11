# RadioMix

Aplicacion Flutter para radio online y podcasts con reproduccion en segundo plano, favoritos, suscripciones, descargas offline y backup local.

## Estado actual

- Proyecto Flutter multiplataforma con foco practico en Android
- Reproduccion en segundo plano con `just_audio` + `audio_service`
- Persistencia local con `SharedPreferences`
- Descarga de episodios a almacenamiento interno
- Backup y restauracion en XML

Version de la app: `1.6.5+5`

Fecha de esta documentacion: 2026-08-11

## Funcionalidades

- Buscar emisoras online
- Reproducir radios en streaming
- Guardar radios favoritas
- Anadir emisoras personalizadas manualmente
- Buscar podcasts
- Suscribirse a podcasts
- Cargar episodios desde RSS
- Continuar reproduccion desde el ultimo progreso guardado
- Descargar episodios para reproduccion offline
- Gestionar volumen y buffer de audio
- Exportar e importar backup local
- Controles multimedia del sistema en Android

## Limitaciones conocidas

- La pantalla FM es experimental y actualmente no usa hardware FM real
- El backup no incluye los archivos descargados de podcasts
- `README.md` describe el estado actual observado en codigo, no un roadmap cerrado de producto

## Stack

- Flutter `3.44.9`
- Dart `3.12.2`
- Material 3
- Riverpod
- just_audio
- audio_service
- audio_session
- http
- xml
- shared_preferences
- path_provider
- file_picker
- share_plus

## Estructura del proyecto

```text
lib/
  main.dart
  models/
  screens/
  services/
  widgets/
assets/
  icon/
  logo_options/
  store/
docs/
scripts/
android/
ios/
macos/
linux/
windows/
web/
test/
```

Archivos clave:

- `lib/main.dart`: arranque de app, tema y bootstrap de audio
- `lib/screens/home_screen.dart`: shell principal con navegacion
- `lib/screens/player_screen.dart`: reproductor central
- `lib/screens/search_screen.dart`: busqueda de radios y podcasts
- `lib/screens/favorites_screen.dart`: favoritos y suscripciones
- `lib/screens/podcast_detail_screen.dart`: detalle y episodios de podcast
- `lib/screens/settings_screen.dart`: ajustes, backup y limpieza de descargas
- `lib/services/audio_player_service.dart`: servicio central de audio
- `lib/services/app_audio_handler.dart`: integracion con controles del sistema

## Arquitectura resumida

La app sigue una arquitectura ligera por capas:

- UI: pantallas y widgets Flutter
- Estado: Riverpod + estado local con `setState`
- Servicios: audio, radio, podcasts, progreso, descargas y backup
- Datos locales: `SharedPreferences` + filesystem
- Integraciones externas: Radio Browser, iTunes Search, RSS y streams de audio

Las notas operativas y las pautas internas para agentes se guardan en la
carpeta local `memoria/`, excluida expresamente de Git.

Documentación pública:

- [Política de privacidad](./docs/privacy_policy.html)

## Requisitos de desarrollo

- Flutter SDK compatible con la version actual del proyecto
- Android SDK para build Android
- Xcode para targets Apple
- Entorno con acceso a internet para buscar radios, podcasts y reproducir streams remotos

## Instalacion

```bash
flutter pub get
```

## Ejecucion

```bash
flutter run
```

Para Android se necesita JDK 17 o 21. Los scripts seleccionan un JDK compatible
desde `RADIOMIX_JAVA_HOME`, `JAVA_HOME`, `.tools/jdk-21` (solo local) o las
ubicaciones habituales del sistema:

```bash
./scripts/android_with_jdk.sh flutter run
./scripts/android_with_jdk.sh ./gradlew :app:assembleDebug
./scripts/android_run.sh
./scripts/android_build_apk.sh
./scripts/android_build_appbundle.sh
./scripts/android_build_apk_split.sh
```

## Verificaciones basicas

```bash
flutter analyze
flutter test
./scripts/android_with_jdk.sh ./gradlew :app:processDebugMainManifest
```

Última validación local (2026-08-11): análisis sin incidencias, `52` pruebas
correctas y procesamiento del manifest Android completado.

## Configuracion Android de firma

El proyecto soporta firma release mediante:

- `android/keystore.properties`
- o variables de entorno `RADIOMIX_*`

Archivo de ejemplo:

- `android/keystore.properties.example`

Claves esperadas:

- `storeFile`
- `storePassword`
- `keyAlias`
- `keyPassword`

Variables equivalentes:

- `RADIOMIX_STORE_FILE`
- `RADIOMIX_STORE_PASSWORD`
- `RADIOMIX_KEY_ALIAS`
- `RADIOMIX_KEY_PASSWORD`

Si no hay configuracion release completa, el build de release cae a debug signing.

## Persistencia local

Claves observadas en `SharedPreferences`:

- `theme_mode`
- `favorite_stations`
- `podcast_subscriptions`
- `podcast_downloads`
- `audio_buffer_seconds`
- `recent_stations`
- `playback_progress_<stationId>`

Archivos locales:

- episodios descargados: `Documents/podcasts`
- backup exportado: XML temporal compartido desde la app

## APIs y fuentes externas

Radio:

- `https://de1.api.radio-browser.info/json/stations/search`
- `https://de1.api.radio-browser.info/json/stations/topvote/10`

Podcasts:

- `https://itunes.apple.com/search`
- RSS del feed de cada podcast

## Audio y reproduccion

El pipeline de audio reutiliza el mismo servicio para radios y podcasts.

Puntos clave:

- `AudioPlayerService` posee el `AudioPlayer`
- `AppAudioHandler` publica metadata y controles del sistema
- Los podcasts habilitan seek, progreso y reanudacion
- Las radios usan play/pause/stop sin barra de progreso

## Backup y restauracion

El backup exporta:

- radios favoritas
- podcasts suscritos
- progreso de reproduccion
- preferencias de usuario y proveedores configurados
- metadata de descargas, sin rutas ni archivos de audio

Los backups pueden contener credenciales de proveedores introducidas por el
usuario y deben tratarse como archivos sensibles.

## Seguridad y notas operativas

- Android mantiene `android:usesCleartextTraffic="true"`
- `android.keystore`, `android/keystore.properties`, archivos de entorno y
  credenciales están excluidos de Git
- `.tools/`, `.claude/` y `memoria/` son exclusivamente locales
- nunca se deben forzar archivos ignorados al preparar una publicación

## Testing actual

La suite incluye pruebas de modelos, servicios, persistencia, backup, audio,
búsqueda, coordinación de reproducción y widgets principales. La referencia
válida es siempre el resultado de `flutter test` en el commit que se publique.

## Mejoras recomendadas

Resumen corto:

1. aumentar cobertura de pruebas
2. unificar inyeccion de dependencias con Riverpod
3. extraer backup y datos a capas mas limpias
4. endurecer configuracion Android

El roadmap público debe mantenerse en los issues del repositorio. Las notas de
trabajo privadas permanecen en `memoria/` y no forman parte de los commits.
