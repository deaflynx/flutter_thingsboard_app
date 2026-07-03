import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/utils/services/location/i_location_service.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';
import 'package:thingsboard_app/utils/services/location/model/location_stream_settings.dart';
import 'package:thingsboard_app/utils/services/tb_client_service/i_tb_client_service.dart';

/// Phase 1a spike (see docs/superpowers/specs/2026-07-03-gps-tracking-design.md):
/// validates background/foreground live tracking and REST telemetry saves on
/// real devices before the production tracking service is built. Debug-only
/// entry point on the More page; throwaway UI by design.
class LiveTrackingSpikePage extends StatefulWidget {
  const LiveTrackingSpikePage({super.key});

  @override
  State<LiveTrackingSpikePage> createState() => _LiveTrackingSpikePageState();
}

class _SpikeEvent {
  _SpikeEvent(this.message, {this.isError = false}) : time = DateTime.now();

  final DateTime time;
  final String message;
  final bool isError;
}

class _LiveTrackingSpikePageState extends State<LiveTrackingSpikePage> {
  static const _maxEvents = 200;

  bool _backgroundMode = true;
  bool _saveTelemetry = true;

  StreamSubscription<LocationFix>? _subscription;
  Timer? _ticker;
  DateTime? _startedAt;
  int _fixCount = 0;
  int _savedCount = 0;
  int _saveErrorCount = 0;
  GeoPosition? _lastFix;
  final List<_SpikeEvent> _events = [];

  bool get _isRunning => _subscription != null;

  @override
  void dispose() {
    _ticker?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  void _start() {
    final settings = LocationStreamSettings(
      background:
          _backgroundMode
              ? const BackgroundTrackingConfig(
                notificationTitle: 'ThingsBoard live tracking',
                notificationText: 'Sharing phone location (spike)',
              )
              : null,
    );

    _startedAt = DateTime.now();
    _fixCount = 0;
    _savedCount = 0;
    _saveErrorCount = 0;
    _lastFix = null;
    _events.clear();
    _logEvent(
      'Started (${_backgroundMode ? 'background' : 'foreground'} mode, '
      'telemetry ${_saveTelemetry ? 'on' : 'off'})',
    );

    _subscription = getIt<ILocationService>()
        .positionStream(settings: settings)
        .listen(_onFix, onDone: _stop);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _subscription?.cancel();
    _subscription = null;
    _logEvent('Stopped');
    if (mounted) setState(() {});
  }

  void _onFix(LocationFix fix) {
    switch (fix) {
      case LocationSuccess(:final position):
        _fixCount++;
        _lastFix = position;
        _logEvent(
          '${position.latitude.toStringAsFixed(6)}, '
          '${position.longitude.toStringAsFixed(6)} '
          '(±${position.accuracy.toStringAsFixed(0)} m)',
        );
        if (_saveTelemetry) {
          unawaited(_saveFix(position));
        }
      case LocationServicesDisabled():
        _logEvent('Location services disabled', isError: true);
        _stop();
      case LocationPermissionDenied():
        _logEvent('Location permission denied', isError: true);
        _stop();
      case LocationPermissionDeniedForever():
        _logEvent('Location permission permanently denied', isError: true);
        _stop();
      case LocationFixError(:final message):
        _logEvent('Fix error: $message', isError: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveFix(GeoPosition position) async {
    try {
      final client = getIt<ITbClientService>().client;
      final userId = client.getAuthUser()?.userId;
      if (userId == null) {
        throw Exception('No authenticated user');
      }

      await client.getTelemetryControllerApi().saveEntityTelemetry(
        entityType: 'USER',
        entityId: userId,
        scope: 'ANY',
        body: jsonEncode({
          'ts': (position.timestamp ?? DateTime.now()).millisecondsSinceEpoch,
          'values': {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'gpsAccuracy': position.accuracy,
          },
        }),
      );
      _savedCount++;
    } catch (e) {
      _saveErrorCount++;
      _logEvent('Telemetry save failed: $e', isError: true);
    }
    if (mounted) setState(() {});
  }

  void _logEvent(String message, {bool isError = false}) {
    _events.insert(0, _SpikeEvent(message, isError: isError));
    if (_events.length > _maxEvents) {
      _events.removeLast();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GPS tracking spike')),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('Background tracking'),
            subtitle: const Text(
              'Foreground service on Android, background mode on iOS',
            ),
            value: _backgroundMode,
            onChanged:
                _isRunning
                    ? null
                    : (value) => setState(() => _backgroundMode = value),
          ),
          SwitchListTile(
            title: const Text('Save telemetry to my user entity'),
            subtitle: const Text('latitude / longitude / gpsAccuracy'),
            value: _saveTelemetry,
            onChanged:
                _isRunning
                    ? null
                    : (value) => setState(() => _saveTelemetry = value),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isRunning ? _stop : _start,
                    icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                    label: Text(_isRunning ? 'Stop' : 'Start'),
                  ),
                ),
              ],
            ),
          ),
          _StatsCard(
            isRunning: _isRunning,
            startedAt: _startedAt,
            fixCount: _fixCount,
            savedCount: _savedCount,
            saveErrorCount: _saveErrorCount,
            lastFix: _lastFix,
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[index];
                return ListTile(
                  dense: true,
                  leading: Text(
                    TimeOfDay.fromDateTime(event.time).format(context),
                  ),
                  title: Text(
                    event.message,
                    style:
                        event.isError
                            ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )
                            : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.isRunning,
    required this.startedAt,
    required this.fixCount,
    required this.savedCount,
    required this.saveErrorCount,
    required this.lastFix,
  });

  final bool isRunning;
  final DateTime? startedAt;
  final int fixCount;
  final int savedCount;
  final int saveErrorCount;
  final GeoPosition? lastFix;

  @override
  Widget build(BuildContext context) {
    final elapsed =
        startedAt == null ? null : DateTime.now().difference(startedAt!);
    final lastFixTime = lastFix?.timestamp;
    final lastFixAge =
        lastFixTime == null ? null : DateTime.now().difference(lastFixTime);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        [
          if (isRunning) 'RUNNING' else 'STOPPED',
          if (elapsed != null) 'elapsed: ${_format(elapsed)}',
          'fixes: $fixCount',
          'saved: $savedCount',
          if (saveErrorCount > 0) 'save errors: $saveErrorCount',
          if (lastFixAge != null) 'last fix: ${_format(lastFixAge)} ago',
        ].join(' · '),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
  }
}
