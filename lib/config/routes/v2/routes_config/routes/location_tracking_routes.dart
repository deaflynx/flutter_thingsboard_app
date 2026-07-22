import 'package:go_router/go_router.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/view/live_tracking_session_page.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/view/live_tracking_spike_page.dart';

class LocationTrackingRoutes {
  static const liveTrackingSpike = '/liveTrackingSpike';
  static const liveTrackingSession = '/liveTrackingSession';
}

final List<GoRoute> locationTrackingRoutes = [
  GoRoute(
    path: LocationTrackingRoutes.liveTrackingSpike,
    builder: (context, state) {
      return const LiveTrackingSpikePage();
    },
  ),
  GoRoute(
    path: LocationTrackingRoutes.liveTrackingSession,
    builder: (context, state) {
      return const LiveTrackingSessionPage();
    },
  ),
];
