import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/provider/live_tracking_provider.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';

class LiveTrackingSessionPage extends ConsumerWidget {
  const LiveTrackingSessionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(liveTrackingProvider).session;
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).liveTrackingSessionTitle)),
      body:
          session == null
              ? Center(child: Text(S.of(context).liveTrackingNoSession))
              : _SessionDetails(session: session),
    );
  }
}

class _SessionDetails extends ConsumerWidget {
  const _SessionDetails({required this.session});

  final LiveTrackingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = session.status == LiveTrackingStatus.tracking;
    final lastFix = session.lastFix;
    return ListView(
      children: [
        ListTile(
          title: Text(S.of(context).liveTrackingTarget),
          subtitle: Text(
            '${session.config.target.entityType} ${session.config.target.id}',
          ),
        ),
        ListTile(
          title: Text(S.of(context).liveTrackingStatus),
          subtitle: Text(
            tracking
                ? S.of(context).liveTrackingActive
                : S.of(context).liveTrackingPaused,
          ),
        ),
        ListTile(
          title: Text(S.of(context).liveTrackingStarted),
          subtitle: Text(session.startedAt.toLocal().toString()),
        ),
        ListTile(
          title: Text(
            '${S.of(context).liveTrackingFixes}: ${session.fixCount} · '
            '${S.of(context).liveTrackingSaved}: ${session.savedCount} · '
            '${S.of(context).liveTrackingErrors}: ${session.saveErrorCount}',
          ),
        ),
        if (lastFix != null)
          ListTile(
            title: Text(S.of(context).liveTrackingLastFix),
            subtitle: Text(
              '${lastFix.latitude.toStringAsFixed(6)}, '
              '${lastFix.longitude.toStringAsFixed(6)} '
              '(±${lastFix.accuracy.toStringAsFixed(0)} m)',
            ),
          ),
        if (session.lastError != null)
          ListTile(
            title: Text(S.of(context).liveTrackingLastError),
            subtitle: Text(
              session.lastError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final notifier = ref.read(liveTrackingProvider.notifier);
                    tracking ? notifier.pause() : notifier.resume();
                  },
                  icon: Icon(tracking ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    tracking
                        ? S.of(context).liveTrackingPause
                        : S.of(context).liveTrackingResume,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      () => ref.read(liveTrackingProvider.notifier).stop(),
                  icon: const Icon(Icons.stop),
                  label: Text(S.of(context).liveTrackingStop),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
