import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/radio_station.dart';
import '../services/audio_player_service.dart';
import '../services/podcast_subscription_service.dart';
import '../services/radio_service.dart';
import 'player_screen.dart';
import 'search_screen.dart';
import 'favorites_screen.dart';
import 'fm_screen.dart';
import 'settings_screen.dart';
import '../widgets/mini_player.dart';

// Notifier para saber en qué sub-tab está FavoritesScreen (0=Radios, 1=Podcasts)
class FavoritesTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void setTab(int index) => state = index;
}

final favoritesTabProvider =
    NotifierProvider<FavoritesTabNotifier, int>(FavoritesTabNotifier.new);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const PlayerScreen(),
      const SearchScreen(),
      const FavoritesScreen(),
      const FMScreen(),
    ];
  }

  void _showBufferDialog() {
    final service = ref.read(audioPlayerServiceProvider);
    int tempBuffer = service.bufferSeconds;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Buffer de audio'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Retraso: $tempBuffer segundos',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Un buffer mayor mejora la estabilidad pero añade retraso.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: tempBuffer.toDouble(),
                    min: 0, // Ajustado a 0 para divisiones exactas
                    max: 120,
                    divisions: 12, // Cada 10 segundos
                    label: '${tempBuffer}s',
                    onChanged: (value) {
                      setDialogState(() {
                        tempBuffer =
                            value == 0 ? 2 : value.round(); // Mínimo 2s
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('2s',
                            style: Theme.of(context).textTheme.bodySmall),
                        Text('30s',
                            style: Theme.of(context).textTheme.bodySmall),
                        Text('60s',
                            style: Theme.of(context).textTheme.bodySmall),
                        Text('90s',
                            style: Theme.of(context).textTheme.bodySmall),
                        Text('120s',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCELAR'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    service.setBufferDuration(tempBuffer);
                  },
                  child: const Text('APLICAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddStationDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final logoController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Añadir emisora personalizada'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    hintText: 'Mi Radio Favorita',
                    prefixIcon: Icon(Icons.radio),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL del stream *',
                    hintText: 'https://stream.ejemplo.com/radio.mp3',
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: logoController,
                  decoration: const InputDecoration(
                    labelText: 'URL del logo (opcional)',
                    hintText: 'https://ejemplo.com/logo.png',
                    prefixIcon: Icon(Icons.image),
                  ),
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCELAR'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final url = urlController.text.trim();
                final logo = logoController.text.trim();

                if (name.isEmpty || url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('El nombre y la URL son obligatorios'),
                    ),
                  );
                  return;
                }

                final station = RadioStation(
                  id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  streamUrl: url,
                  favicon: logo.isNotEmpty ? logo : null,
                  country: 'Personalizada',
                  isFavorite: true,
                );

                Navigator.pop(dialogContext);
                _addCustomStation(station);
              },
              child: const Text('AÑADIR'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addCustomStation(RadioStation station) async {
    final service = ref.read(radioServiceProvider);
    await service.addFavorite(station);
    ref.invalidate(favoriteStationsProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${station.name} añadida a favoritos')),
    );
  }

  Future<bool> _onWillPop() async {
    // Si no estamos en la pestaña Home (índice 0), volver a Home
    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
      });
      return false; // No salir de la app
    }
    // Si estamos en Home, permitir salir
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await _onWillPop();
        if (shouldPop) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Radio Mix'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.speed),
              tooltip: 'Buffer de audio',
              onPressed: _showBufferDialog,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Configuración',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
            if (_currentIndex != 0) const MiniPlayer(),
          ],
        ),
        floatingActionButton:
            _currentIndex == 2 && ref.watch(favoritesTabProvider) == 0
                ? FloatingActionButton.extended(
                    onPressed: _showAddStationDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir radio'),
                  )
                : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
            if (index == 2) {
              ref.invalidate(favoriteStationsProvider);
              ref.invalidate(podcastSubscriptionsProvider);
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.play_circle_outline),
              selectedIcon: Icon(Icons.play_circle_fill),
              label: 'Reproductor',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Buscar',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline),
              selectedIcon: Icon(Icons.favorite),
              label: 'Favoritos',
            ),
            NavigationDestination(
              icon: Icon(Icons.radio_outlined),
              selectedIcon: Icon(Icons.radio),
              label: 'FM',
            ),
          ],
        ),
      ),
    );
  }
}
