import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../models/playable_item.dart';
import '../models/radio_station.dart';
import '../services/playback_coordinator_service.dart';
import '../services/radio_service.dart';
import '../widgets/fm_dial.dart';

enum _FMMode { hybrid, traditional, online }

class _FMOnlinePreset {
  const _FMOnlinePreset({
    required this.frequency,
    required this.name,
    required this.query,
  });

  final double frequency;
  final String name;
  final String query;
}

class FMScreen extends ConsumerStatefulWidget {
  const FMScreen({super.key});

  @override
  ConsumerState<FMScreen> createState() => _FMScreenState();
}

class _FMScreenState extends ConsumerState<FMScreen>
    with WidgetsBindingObserver {
  static const _platform = MethodChannel('com.radiomix.ralma/fm');
  static const _events = EventChannel('com.radiomix.ralma/fm_events');
  static const _onlinePresets = [
    _FMOnlinePreset(
      frequency: 88.2,
      name: 'Radio Nacional',
      query: 'Radio Nacional España',
    ),
    _FMOnlinePreset(
      frequency: 91.0,
      name: 'Europa FM',
      query: 'Europa FM España',
    ),
    _FMOnlinePreset(
      frequency: 93.9,
      name: 'Los 40',
      query: 'Los 40 España',
    ),
    _FMOnlinePreset(
      frequency: 98.0,
      name: 'Onda Cero',
      query: 'Onda Cero España',
    ),
    _FMOnlinePreset(
      frequency: 105.4,
      name: 'Cadena SER',
      query: 'Cadena SER España',
    ),
    _FMOnlinePreset(
      frequency: 106.3,
      name: 'COPE',
      query: 'COPE España',
    ),
  ];

  bool _headphonesConnected = false;
  bool _isCheckingAntenna = true;
  bool _isStartingOnline = false;
  _FMMode _mode = _FMMode.hybrid;
  double _currentFrequency = 95.5;
  StreamSubscription<bool>? _antennaSubscription;

  _FMOnlinePreset get _nearestOnlinePreset {
    return _onlinePresets.reduce((best, preset) {
      final bestDistance = (best.frequency - _currentFrequency).abs();
      final presetDistance = (preset.frequency - _currentFrequency).abs();
      return presetDistance < bestDistance ? preset : best;
    });
  }

  bool get _canUseTraditionalFM => _headphonesConnected;

  bool get _shouldShowFMView =>
      _mode != _FMMode.traditional || _canUseTraditionalFM;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForAntennaChanges();
    _checkHeadphones();
  }

  @override
  void dispose() {
    _antennaSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkHeadphones();
    }
  }

  void _listenForAntennaChanges() {
    _antennaSubscription = _events
        .receiveBroadcastStream()
        .map((event) => event == true)
        .listen((connected) {
      if (!mounted) return;
      setState(() {
        _headphonesConnected = connected;
        _isCheckingAntenna = false;
      });
    }, onError: (_) {});
  }

  Future<void> _checkHeadphones() async {
    setState(() {
      _isCheckingAntenna = true;
    });

    var connected = false;
    try {
      connected = await _platform
              .invokeMethod<bool>('isAntennaConnected')
              .timeout(const Duration(seconds: 1), onTimeout: () => false) ??
          false;
    } on PlatformException {
      connected = false;
    } on MissingPluginException {
      connected = false;
    }

    if (!mounted) return;
    setState(() {
      _headphonesConnected = connected;
      _isCheckingAntenna = false;
    });
  }

  void _onFrequencyChanged(double frequency) {
    setState(() {
      _currentFrequency = frequency;
    });
    HapticFeedback.lightImpact();
  }

  void _showHardwareMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Radio FM real requiere hardware y API del fabricante del dispositivo.',
        ),
      ),
    );
  }

  Future<void> _playOnlinePreset(_FMOnlinePreset preset) async {
    setState(() {
      _isStartingOnline = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final stations =
          await ref.read(radioServiceProvider).searchStations(preset.query);
      RadioStation? station;
      for (final candidate in stations) {
        if (candidate.streamUrl.trim().isNotEmpty) {
          station = candidate;
          break;
        }
      }

      if (!mounted) return;
      if (station == null) {
        messenger.showSnackBar(
          SnackBar(
            content:
                Text('No se encontró un stream online para ${preset.name}.'),
          ),
        );
        return;
      }

      final item = PlayableItem.fromRadioStation(
        RadioStation(
          id: 'fm_online_${preset.frequency}_${station.id}',
          name: '${preset.name} FM Online',
          streamUrl: station.streamUrl,
          favicon: station.favicon,
          country: station.country,
          language: station.language,
          tags: [...station.tags, 'FM online'],
          bitrate: station.bitrate,
        ),
      );

      await ref.read(playbackCoordinatorServiceProvider).playItem(
            item,
            messenger: messenger,
            successMessage:
                'Reproduciendo online: ${preset.name} (${preset.frequency.toStringAsFixed(1)} MHz)',
          );
    } finally {
      if (mounted) {
        setState(() {
          _isStartingOnline = false;
        });
      }
    }
  }

  void _tuneCurrentFrequency() {
    if (_mode == _FMMode.online) {
      _playOnlinePreset(_nearestOnlinePreset);
      return;
    }

    if (_mode == _FMMode.hybrid && !_canUseTraditionalFM) {
      _playOnlinePreset(_nearestOnlinePreset);
      return;
    }

    _showHardwareMessage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Modo FM'),
            SizedBox(width: 8),
            Chip(
              label: Text('Experimental', style: TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _shouldShowFMView ? _buildFMView() : _buildNoHeadphonesView(),
    );
  }

  Widget _buildModeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_FMMode>(
        segments: const [
          ButtonSegment(
            value: _FMMode.hybrid,
            icon: Icon(Icons.sync_alt),
            label: Text('Híbrido'),
          ),
          ButtonSegment(
            value: _FMMode.traditional,
            icon: Icon(Icons.settings_input_antenna),
            label: Text('FM'),
          ),
          ButtonSegment(
            value: _FMMode.online,
            icon: Icon(Icons.public),
            label: Text('Online'),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (selection) {
          setState(() {
            _mode = selection.first;
          });
        },
      ),
    );
  }

  Widget _buildNoHeadphonesView() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildModeSelector(),
                      const SizedBox(height: 32),
                      Icon(
                        Icons.headset_off,
                        size: 80,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Auriculares requeridos',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Conecta auriculares con cable para usarlos como antena FM tradicional.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: _isCheckingAntenna ? null : _checkHeadphones,
                        icon: Icon(
                            _isCheckingAntenna ? Icons.sync : Icons.refresh),
                        label: const Text('VERIFICAR ANTENA'),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withAlpha(40),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.withAlpha(80)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.settings_input_antenna,
                              color: Colors.amber,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'En modo híbrido puedes cambiar a online o conectar antena para FM real.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFMView() {
    final onlinePreset = _nearestOnlinePreset;
    final isOnlineRoute = _mode == _FMMode.online ||
        (_mode == _FMMode.hybrid && !_canUseTraditionalFM);
    final statusText = switch (_mode) {
      _FMMode.hybrid => _canUseTraditionalFM
          ? 'Híbrido: antena conectada'
          : 'Híbrido: online disponible',
      _FMMode.traditional => 'Antena conectada',
      _FMMode.online => 'Online',
    };
    final buttonLabel = switch (_mode) {
      _FMMode.hybrid =>
        _canUseTraditionalFM ? 'SINTONIZAR FM' : 'REPRODUCIR ONLINE',
      _FMMode.traditional => 'SINTONIZAR FM',
      _FMMode.online => 'REPRODUCIR ONLINE',
    };
    final buttonIcon =
        isOnlineRoute ? Icons.public : Icons.settings_input_antenna;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildModeSelector(),
        ),
        Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                'FM',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
              Text(
                '${_currentFrequency.toStringAsFixed(1)} MHz',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontFamily: 'monospace',
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                statusText,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
              if (isOnlineRoute) ...[
                const SizedBox(height: 8),
                Text(
                  'Online: ${onlinePreset.name} (${onlinePreset.frequency.toStringAsFixed(1)} MHz)',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: FMDial(
              frequency: _currentFrequency,
              onChanged: _onFrequencyChanged,
              minFrequency: 88.0,
              maxFrequency: 108.0,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              FilledButton.icon(
                onPressed: _isStartingOnline ? null : _tuneCurrentFrequency,
                icon: _isStartingOnline
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(buttonIcon),
                label: Text(buttonLabel),
              ),
              const SizedBox(height: 12),
              Text(
                isOnlineRoute
                    ? 'Desliza para elegir la frecuencia online más cercana'
                    : 'Desliza para seleccionar frecuencia',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
