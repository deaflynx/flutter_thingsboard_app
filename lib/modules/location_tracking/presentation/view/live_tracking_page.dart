import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/location_tracking/presentation/provider/live_tracking_provider.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/live_tracking_display.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/last_tracking_record.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_config.dart';
import 'package:thingsboard_app/utils/services/live_location_tracking/model/live_tracking_session.dart';
import 'package:thingsboard_app/utils/services/tb_client_service/i_tb_client_service.dart';

class LiveTrackingPage extends ConsumerWidget {
  const LiveTrackingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(liveTrackingProvider).session;
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).liveTrackingSessionTitle)),
      body: session != null ? _ActiveSession(session: session) : _IdleView(),
    );
  }
}

class _ActiveSession extends ConsumerWidget {
  const _ActiveSession({required this.session});

  final LiveTrackingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = session.status == LiveTrackingStatus.tracking;
    final lastFix = session.lastFix;
    final target = session.config.target;
    final nameAsync = ref.watch(
      targetNameProvider(entityType: target.entityType, id: target.id),
    );
    final name = displayTargetName(nameAsync.valueOrNull, target);
    return ListView(
      children: [
        ListTile(
          title: Text(S.of(context).liveTrackingTarget),
          subtitle: Text(name),
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

class _IdleView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordAsync = ref.watch(lastRecordProvider);
    return recordAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(S.of(context).liveTrackingNoRecord)),
      data: (record) {
        if (record == null) {
          return Center(child: Text(S.of(context).liveTrackingNoRecord));
        }
        return _LastSession(record: record);
      },
    );
  }
}

class _LastSession extends ConsumerWidget {
  const _LastSession({required this.record});

  final LastTrackingRecord record;

  String _endReasonLabel(BuildContext context) => switch (record.endReason) {
    TrackingEndReason.manual => S.of(context).liveTrackingEndReasonManual,
    TrackingEndReason.maxDuration =>
      S.of(context).liveTrackingEndReasonMaxDuration,
    TrackingEndReason.interrupted =>
      S.of(context).liveTrackingEndReasonInterrupted,
  };

  Future<void> _startAgain(WidgetRef ref) async {
    // AuthUser.sub is the current user's email (phase-1c trackedBy semantics);
    // re-derive it so a relaunch is attributed to whoever is logged in now.
    final email = getIt<ITbClientService>().client.getAuthUser()?.sub;
    final config = LiveTrackingConfig.fromJson({
      ...record.configJson,
      if (email != null) 'trackedBy': email,
    });
    await ref.read(liveTrackingProvider.notifier).startConfig(config);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = record.config.target;
    final name = displayTargetName(record.targetName, target);
    return ListView(
      children: [
        ListTile(
          title: Text(S.of(context).liveTrackingLastSession),
          subtitle: Text(name),
        ),
        ListTile(
          title: Text(S.of(context).liveTrackingStarted),
          subtitle: Text(record.startedAt.toLocal().toString()),
        ),
        if (record.endedAt != null)
          ListTile(
            title: Text(S.of(context).liveTrackingEnded),
            subtitle: Text(record.endedAt!.toLocal().toString()),
          ),
        ListTile(
          title: Text(S.of(context).liveTrackingEndReason),
          subtitle: Text(_endReasonLabel(context)),
        ),
        ListTile(
          title: Text(
            '${S.of(context).liveTrackingFixes}: ${record.fixCount} · '
            '${S.of(context).liveTrackingSaved}: ${record.savedCount} · '
            '${S.of(context).liveTrackingErrors}: ${record.saveErrorCount}',
          ),
        ),
        if (record.lastLat != null && record.lastLng != null)
          ListTile(
            title: Text(S.of(context).liveTrackingLastFix),
            subtitle: Text(
              '${record.lastLat!.toStringAsFixed(6)}, '
              '${record.lastLng!.toStringAsFixed(6)}',
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => _startAgain(ref),
            icon: const Icon(Icons.play_arrow),
            label: Text(S.of(context).liveTrackingStartAgain),
          ),
        ),
      ],
    );
  }
}
