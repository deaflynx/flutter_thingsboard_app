import 'package:thingsboard_ce_client/thingsboard_ce_client.dart';

/// Extension that restores typed access to an [AlarmCommentInfo]'s free-form
/// `comment` payload on the new built_value model.
///
/// The new client types `comment` as a [JsonObject] (a `MapJsonObject` at
/// runtime), whereas the old client exposed it pre-parsed. This decodes the
/// underlying map back into the handwritten [AlarmCommentJsonNode] consumed by
/// the alarm activity widgets.
extension AlarmCommentInfoExt on AlarmCommentInfo {
  AlarmCommentJsonNode get commentNode =>
      AlarmCommentJsonNode.fromJson(comment!.asMap.cast<String, dynamic>());
}
