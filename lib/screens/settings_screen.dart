import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';
import '../services/backup_service.dart';
import '../services/app_network_error.dart';
import '../services/podcast_download_service.dart';
import '../services/radio_service.dart';
import '../services/podcast_service.dart';

final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isBackupLoading = false;
  bool _isRestoreLoading = false;

  void _showInfoMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() {
      _isBackupLoading = true;
    });

    try {
      final backupService = ref.read(backupServiceProvider);
      final backupFile = await backupService.createBackupFile();
      final backup = await backupService.loadBackupFromPath(backupFile.path);

      // Compartir archivo de backup
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backupFile.path)],
          text: 'Backup de Radio Mix',
          subject: 'Backup Radio Mix ${backup.timestamp.toLocal()}',
        ),
      );

      _showInfoMessage('Backup XML creado. Guarda el archivo compartido.');
    } catch (error) {
      _showErrorMessage(
        'Error al crear backup: ${describeAppError(error)}',
      );
    } finally {
      setState(() {
        _isBackupLoading = false;
      });
    }
  }

  Future<void> _restoreBackup() async {
    setState(() {
      _isRestoreLoading = true;
    });

    try {
      // Seleccionar archivo
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml', 'json', 'txt'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.first.path;
      if (filePath == null || filePath.isEmpty) {
        throw const FormatException(
            'No se pudo acceder al archivo seleccionado');
      }

      final backup = await ref.read(backupServiceProvider).loadBackupFromPath(
            filePath,
          );
      if (!mounted) return;

      // Confirmar restauración
      final shouldRestore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restaurar backup'),
          content: Text(
            'Fecha del backup: ${backup.timestamp.toLocal()}\n'
            'Radios: ${backup.favoriteStations.length}\n'
            'Podcasts: ${backup.subscribedPodcasts.length}\n'
            'Progresos: ${backup.playbackProgress.length}\n\n'
            'Esto reemplazará tus datos actuales. ¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('RESTAURAR'),
            ),
          ],
        ),
      );

      if (shouldRestore != true) return;

      await ref.read(backupServiceProvider).restoreBackup(backup);
      _showInfoMessage('Backup restaurado correctamente');
    } catch (error) {
      _showErrorMessage(
        'Error al restaurar backup: ${describeAppError(error)}',
      );
    } finally {
      setState(() {
        _isRestoreLoading = false;
      });
    }
  }

  void _showRadioProviderSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Proveedor de búsqueda de radio',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.radio),
                title: const Text('Radio Browser'),
                subtitle:
                    const Text('Directorio global de radios (sin API key)'),
                trailing:
                    ref.watch(activeRadioProviderIdProvider) == 'radio_browser'
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                onTap: () async {
                  await ref
                      .read(activeRadioProviderIdProvider.notifier)
                      .setProvider('radio_browser');
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.radio),
                title: const Text('Radio Garden'),
                subtitle: const Text(
                    '~40k estaciones por todo el mundo (sin API key)'),
                trailing:
                    ref.watch(activeRadioProviderIdProvider) == 'radio_garden'
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                onTap: () async {
                  await ref
                      .read(activeRadioProviderIdProvider.notifier)
                      .setProvider('radio_garden');
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.radio),
                title: const Text('SHOUTcast'),
                subtitle: const Text('Directorio SHOUTcast (requiere API key)'),
                trailing:
                    ref.watch(activeRadioProviderIdProvider) == 'shoutcast'
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                onTap: () async {
                  await ref
                      .read(activeRadioProviderIdProvider.notifier)
                      .setProvider('shoutcast');
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showPodcastProviderSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Proveedor de búsqueda de podcasts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.podcasts),
                title: const Text('iTunes / Apple Podcasts'),
                subtitle: const Text('Directorio de Apple (sin API key)'),
                trailing: ref.watch(activePodcastProviderIdProvider) == 'itunes'
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await ref
                      .read(activePodcastProviderIdProvider.notifier)
                      .setProvider('itunes');
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.podcasts),
                title: const Text('gPodder'),
                subtitle:
                    const Text('Directorio abierto de podcasts (sin API key)'),
                trailing:
                    ref.watch(activePodcastProviderIdProvider) == 'gpodder'
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                onTap: () async {
                  await ref
                      .read(activePodcastProviderIdProvider.notifier)
                      .setProvider('gpodder');
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.podcasts),
                title: const Text('Podcast Index'),
                subtitle: const Text('Directorio abierto (requiere API key)'),
                trailing: ref.watch(activePodcastProviderIdProvider) ==
                        'podcast_index'
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await ref
                      .read(activePodcastProviderIdProvider.notifier)
                      .setProvider('podcast_index');
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showApiKeyDialog({
    required String title,
    required String currentValue,
    required String hint,
    required Future<void> Function(String) onSave,
    bool obscure = false,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await onSave(controller.text.trim());
    }
    controller.dispose();
  }

  String _getThemeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Sistema';
      case ThemeMode.light:
        return 'Claro';
      case ThemeMode.dark:
        return 'Oscuro';
    }
  }

  IconData _getThemeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.brightness_auto;
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final downloadSizeAsync = ref.watch(totalDownloadSizeProvider);
    final packageInfoAsync = ref.watch(packageInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          // Sección: Apariencia
          _buildSectionHeader('Apariencia'),

          // Tema
          ListTile(
            leading: Icon(_getThemeIcon(themeMode)),
            title: const Text('Tema'),
            subtitle: Text(_getThemeName(themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemeSelector(context),
          ),

          const Divider(),

          // Sección: Fuentes de búsqueda
          _buildSectionHeader('Fuentes de búsqueda'),

          // Proveedor de radio
          ListTile(
            leading: const Icon(Icons.radio),
            title: const Text('Proveedor de radio'),
            subtitle: Text(switch (ref.watch(activeRadioProviderIdProvider)) {
              'shoutcast' => 'SHOUTcast',
              'radio_garden' => 'Radio Garden',
              _ => 'Radio Browser',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showRadioProviderSelector(),
          ),

          // API Key SHOUTcast (solo visible si está seleccionado)
          if (ref.watch(activeRadioProviderIdProvider) == 'shoutcast')
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text('API Key SHOUTcast'),
              subtitle: Text(
                ref.watch(shoutcastApiKeyProvider).isEmpty
                    ? 'Sin configurar — obtén una en shoutcast.com/Developer'
                    : '••••••${ref.watch(shoutcastApiKeyProvider).length > 6 ? ref.watch(shoutcastApiKeyProvider).substring(ref.watch(shoutcastApiKeyProvider).length - 4) : ''}',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _showApiKeyDialog(
                title: 'API Key SHOUTcast',
                currentValue: ref.read(shoutcastApiKeyProvider),
                hint: 'Pega aquí tu API key',
                onSave: (v) =>
                    ref.read(shoutcastApiKeyProvider.notifier).setKey(v),
              ),
            ),

          // Proveedor de podcasts
          ListTile(
            leading: const Icon(Icons.podcasts),
            title: const Text('Proveedor de podcasts'),
            subtitle: Text(switch (ref.watch(activePodcastProviderIdProvider)) {
              'podcast_index' => 'Podcast Index',
              'gpodder' => 'gPodder',
              _ => 'iTunes / Apple Podcasts',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPodcastProviderSelector(),
          ),

          // API Key / Secret Podcast Index (solo visible si está seleccionado)
          if (ref.watch(activePodcastProviderIdProvider) ==
              'podcast_index') ...[
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text('API Key Podcast Index'),
              subtitle: Text(
                ref.watch(podcastIndexApiKeyProvider).isEmpty
                    ? 'Sin configurar — obtén una en api.podcastindex.org'
                    : '••••${ref.watch(podcastIndexApiKeyProvider).length > 4 ? ref.watch(podcastIndexApiKeyProvider).substring(ref.watch(podcastIndexApiKeyProvider).length - 4) : ''}',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _showApiKeyDialog(
                title: 'API Key Podcast Index',
                currentValue: ref.read(podcastIndexApiKeyProvider),
                hint: 'Pega aquí tu API key',
                onSave: (v) =>
                    ref.read(podcastIndexApiKeyProvider.notifier).setKey(v),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('API Secret Podcast Index'),
              subtitle: Text(
                ref.watch(podcastIndexApiSecretProvider).isEmpty
                    ? 'Sin configurar'
                    : '••••••••',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _showApiKeyDialog(
                title: 'API Secret Podcast Index',
                currentValue: ref.read(podcastIndexApiSecretProvider),
                hint: 'Pega aquí tu API secret',
                onSave: (v) =>
                    ref.read(podcastIndexApiSecretProvider.notifier).setKey(v),
                obscure: true,
              ),
            ),
          ],

          const Divider(),

          // Sección: Backup
          _buildSectionHeader('Backup y Restauración'),

          // Crear backup
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Crear backup'),
            subtitle: const Text('Guarda tus radios, podcasts y progresos'),
            trailing: _isBackupLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share),
            onTap: _isBackupLoading ? null : _createBackup,
          ),

          // Restaurar backup
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restaurar backup'),
            subtitle: const Text('Carga un archivo de backup'),
            trailing: _isRestoreLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            onTap: _isRestoreLoading ? null : _restoreBackup,
          ),

          const Divider(),

          // Sección: Descargas
          _buildSectionHeader('Descargas de Podcasts'),

          // Tamaño total de descargas
          downloadSizeAsync.when(
            data: (size) {
              final sizeStr = _formatFileSize(size);
              return ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('Espacio usado'),
                subtitle: Text('$sizeStr en descargas'),
              );
            },
            loading: () => const ListTile(
              leading: Icon(Icons.storage),
              title: Text('Espacio usado'),
              subtitle: Text('Calculando...'),
            ),
            error: (_, __) => const ListTile(
              leading: Icon(Icons.storage),
              title: Text('Espacio usado'),
              subtitle: Text('No disponible'),
            ),
          ),

          // Borrar descargas antiguas
          Builder(
            builder: (BuildContext itemContext) {
              return ListTile(
                leading: const Icon(Icons.delete_sweep),
                title: const Text('Borrar descargas antiguas'),
                subtitle: const Text('Selecciona el periodo a borrar'),
                onTap: () {
                  final RenderBox button =
                      itemContext.findRenderObject() as RenderBox;
                  final RenderBox overlay = Navigator.of(itemContext)
                      .overlay!
                      .context
                      .findRenderObject() as RenderBox;
                  final RelativeRect position = RelativeRect.fromRect(
                    Rect.fromPoints(
                      button.localToGlobal(button.size.bottomLeft(Offset.zero),
                          ancestor: overlay),
                      button.localToGlobal(button.size.bottomRight(Offset.zero),
                          ancestor: overlay),
                    ),
                    Offset.zero & overlay.size,
                  );

                  showMenu<int>(
                    context: itemContext,
                    position: position,
                    // Use a BoxConstraints to force the menu to have the same width as the button
                    constraints: BoxConstraints(
                      minWidth: button.size.width,
                      maxWidth: button.size.width,
                    ),
                    items: const [
                      PopupMenuItem(
                        value: 7,
                        child: Text('Hace 7 días'),
                      ),
                      PopupMenuItem(
                        value: 15,
                        child: Text('Hace 15 días'),
                      ),
                      PopupMenuItem(
                        value: 30,
                        child: Text('Hace 30 días'),
                      ),
                    ],
                  ).then((days) {
                    if (days != null) {
                      _showDeleteDownloadsDialog(days);
                    }
                  });
                },
              );
            },
          ),

          // Borrar todas las descargas
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Borrar todas las descargas'),
            subtitle: const Text('Eliminar todos los episodios descargados'),
            onTap: () => _showDeleteAllDownloadsDialog(),
          ),

          const Divider(),

          // Sección: Información
          _buildSectionHeader('Información'),

          packageInfoAsync.when(
            data: (packageInfo) {
              final buildNumber = packageInfo.buildNumber;
              final versionStr = buildNumber.isNotEmpty
                  ? '${packageInfo.version}+$buildNumber'
                  : packageInfo.version;
              return ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Versión'),
                subtitle: Text(versionStr),
              );
            },
            loading: () => const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Versión'),
              subtitle: Text('Cargando...'),
            ),
            error: (_, __) => const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Versión'),
              subtitle: Text('No disponible'),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Desarrollado con Flutter'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  void _showThemeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Seleccionar tema',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.brightness_auto),
                title: const Text('Sistema'),
                subtitle: const Text('Sigue la configuración del dispositivo'),
                trailing: ref.watch(themeModeProvider) == ThemeMode.system
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await ref
                      .read(themeModeProvider.notifier)
                      .setTheme(ThemeMode.system);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.light_mode),
                title: const Text('Claro'),
                subtitle: const Text('Tema claro siempre'),
                trailing: ref.watch(themeModeProvider) == ThemeMode.light
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await ref
                      .read(themeModeProvider.notifier)
                      .setTheme(ThemeMode.light);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.dark_mode),
                title: const Text('Oscuro'),
                subtitle: const Text('Tema oscuro siempre'),
                trailing: ref.watch(themeModeProvider) == ThemeMode.dark
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  await ref
                      .read(themeModeProvider.notifier)
                      .setTheme(ThemeMode.dark);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDeleteDownloadsDialog(int daysOld) async {
    final count = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar descargas antiguas'),
        content: Text(
            '¿Deseas borrar los episodios descargados hace más de $daysOld días?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 1),
            child: const Text('BORRAR'),
          ),
        ],
      ),
    );

    if (count != null) {
      final deletedCount = await ref
          .read(podcastDownloadServiceProvider)
          .deleteOldDownloads(daysOld);
      if (mounted) {
        ref.invalidate(totalDownloadSizeProvider);
        setState(() {});
        _showInfoMessage('Se eliminaron $deletedCount episodios');
      }
    }
  }

  Future<void> _showDeleteAllDownloadsDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar todas las descargas'),
        content: const Text(
            '¿Estás seguro de que deseas eliminar TODOS los episodios descargados? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('BORRAR TODO'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(podcastDownloadServiceProvider).deleteAllDownloads();
      if (mounted) {
        ref.invalidate(totalDownloadSizeProvider);
        setState(() {});
        _showInfoMessage('Se eliminaron todas las descargas');
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
