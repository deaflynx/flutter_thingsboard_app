import 'dart:async';

import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_location_tracking_service.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/i_live_tracking_remote.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';
import 'package:thingsboard_app/utils/services/location/i_location_service.dart';
import 'package:thingsboard_app/utils/services/location/model/geo_position.dart';
import 'package:thingsboard_app/utils/services/location/model/location_fix.dart';
import 'package:thingsboard_app/utils/services/location/model/location_stream_settings.dart';

class LiveLocationTrackingService implements ILiveLocationTrackingService {
  LiveLocationTrackingService({
    required ILocationService locationService,
    required ILiveTrackingRemote remote,
    required TbLogger logger,
    // Android notification strings are OS-level, set once at construction;
    // English defaults are acceptable for v1 (the locator can later pass
    // localized strings without touching this class).
    this.backgroundConfig = const BackgroundTrackingConfig(
      notificationTitle: 'ThingsBoard',
      notificationText: 'Live location tracking is active',
    ),
  }) : _locationService = locationService,
       _remote = remote,
       _log = logger;

  final ILocationService _locationService;
  final ILiveTrackingRemote _remote;
  final TbLogger _log;
  final BackgroundTrackingConfig backgroundConfig;

  final _sessionController = StreamController<LiveTrackingSession?>.broadcast();
  LiveTrackingSession? _session;
  StreamSubscription<LocationFix>? _subscription;
  Timer? _maxDurationTimer;

  @override
  LiveTrackingSession? get session => _session;

  @override
  Stream<LiveTrackingSession?> get sessionStream => _sessionController.stream;

  @override
  Future<void> start(LiveTrackingConfig config) async {
    await stop();
    _setSession(
      LiveTrackingSession(
        config: config,
        status: LiveTrackingStatus.tracking,
        startedAt: DateTime.now(),
      ),
    );
    await _writeStatusAttributes({
      'gpsActive': true,
      if (config.trackedBy != null) 'gpsTrackedBy': config.trackedBy,
    });
    _subscribe(config);
    final maxDuration = config.maxDurationMinutes;
    if (maxDuration != null) {
      _maxDurationTimer = Timer(Duration(minutes: maxDuration), stop);
    }
  }

  @override
  Future<void> stop() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _cancelSubscription();
    if (_session != null) {
      await _writeStatusAttributes({'gpsActive': false});
      _setSession(null);
    }
  }

  @override
  Future<void> pause() async {
    final current = _session;
    if (current == null || current.status != LiveTrackingStatus.tracking) {
      return;
    }
    _cancelSubscription();
    _setSession(current.copyWith(status: LiveTrackingStatus.paused));
    await _writeStatusAttributes({'gpsActive': false});
  }

  @override
  Future<void> resume() async {
    final current = _session;
    if (current == null || current.status != LiveTrackingStatus.paused) {
      return;
    }
    _setSession(
      current.copyWith(status: LiveTrackingStatus.tracking, lastError: null),
    );
    await _writeStatusAttributes({'gpsActive': true});
    _subscribe(current.config);
  }

  void _subscribe(LiveTrackingConfig config) {
    _subscription = _locationService
        .positionStream(
          settings: LocationStreamSettings(
            accuracy: config.accuracy,
            distanceFilterMeters: config.distanceFilterMeters ?? 0,
            interval:
                config.intervalSeconds != null
                    ? Duration(seconds: config.intervalSeconds!)
                    : null,
            background: backgroundConfig,
          ),
        )
        .listen(_onFix);
  }

  Future<void> _onFix(LocationFix fix) async {
    final current = _session;
    if (current == null) {
      return;
    }
    switch (fix) {
      case LocationSuccess(:final position):
        _setSession(
          current.copyWith(fixCount: current.fixCount + 1, lastFix: position),
        );
        await _saveFix(current.config, position);
      case LocationServicesDisabled():
        await _pauseWithError('Location services are disabled.');
      case LocationPermissionDenied():
        await _pauseWithError('Location permission denied.');
      case LocationPermissionDeniedForever():
        await _pauseWithError('Location permission permanently denied.');
      case LocationFixError(:final message):
        _setSession(_session?.copyWith(lastError: message));
    }
  }

  Future<void> _saveFix(LiveTrackingConfig config, GeoPosition position) async {
    final values = <String, dynamic>{
      config.latitudeKey: position.latitude,
      config.longitudeKey: position.longitude,
      if (config.includeMetadata) ...{
        'gpsAccuracy': position.accuracy,
        if (position.altitude != null) 'gpsAltitude': position.altitude,
        if (position.speed != null) 'gpsSpeed': position.speed,
        if (position.heading != null) 'gpsHeading': position.heading,
      },
    };
    final ts = (position.timestamp ?? DateTime.now()).millisecondsSinceEpoch;
    try {
      await _remote.saveTelemetry(config.target, ts, values);
      final attributes = <String, dynamic>{
        if (config.mirrorToAttributes) ...values,
        if (config.writeStatusAttributes) 'gpsLastUpdateTime': ts,
      };
      if (attributes.isNotEmpty) {
        await _remote.saveAttributes(config.target, attributes);
      }
      final current = _session;
      if (current != null) {
        _setSession(current.copyWith(savedCount: current.savedCount + 1));
      }
    } catch (e, s) {
      _log.error('LiveLocationTrackingService: save failed', e, s);
      final current = _session;
      if (current != null) {
        _setSession(
          current.copyWith(
            saveErrorCount: current.saveErrorCount + 1,
            lastError: e.toString(),
          ),
        );
      }
    }
  }

  Future<void> _pauseWithError(String message) async {
    final current = _session;
    if (current == null) {
      return;
    }
    _cancelSubscription();
    _setSession(
      current.copyWith(status: LiveTrackingStatus.paused, lastError: message),
    );
    await _writeStatusAttributes({'gpsActive': false});
  }

  /// Fire-and-forget teardown: [StreamSubscription.cancel] detaches the
  /// listener synchronously, so awaiting its completion would only gate on the
  /// plugin's native teardown — which we don't need to block session state on.
  void _cancelSubscription() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  Future<void> _writeStatusAttributes(Map<String, dynamic> attributes) async {
    final config = _session?.config;
    if (config == null || !config.writeStatusAttributes) {
      return;
    }
    try {
      await _remote.saveAttributes(config.target, attributes);
    } catch (e, s) {
      _log.error('LiveLocationTrackingService: status attributes failed', e, s);
    }
  }

  void _setSession(LiveTrackingSession? session) {
    _session = session;
    _sessionController.add(session);
  }
}
