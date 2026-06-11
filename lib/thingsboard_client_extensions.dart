import 'package:thingsboard_ce_client/thingsboard_ce_client.dart';

/// Extension that restores typed access to an [AlarmCommentInfo]'s free-form
/// `comment` payload on the new built_value model.
///
/// The new client types `comment` as a [JsonObject] (a `MapJsonObject` at
/// runtime), whereas the old client exposed it pre-parsed. This decodes the
/// underlying map back into the handwritten [AlarmCommentJsonNode] consumed by
/// the alarm activity widgets.
extension AlarmCommentInfoExt on AlarmCommentInfo {
  /// `comment` is nullable on the new built_value model, and system-generated
  /// activity entries may not carry a payload, so callers must handle null.
  AlarmCommentJsonNode? get commentNode {
    final raw = comment?.asMap;
    if (raw == null) return null;
    return AlarmCommentJsonNode.fromJson(raw.cast<String, dynamic>());
  }
}
