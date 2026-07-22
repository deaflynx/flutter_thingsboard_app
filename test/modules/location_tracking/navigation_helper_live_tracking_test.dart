import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thingsboard_app/modules/main/providers/navigation_helper.dart';
import 'package:thingsboard_app/utils/services/layouts/pages_layout.dart';

void main() {
  const layout = PageLayout(id: Pages.live_location_tracking);

  test('parses LIVE_LOCATION_TRACKING from server string', () {
    expect(
      pagesFromString('LIVE_LOCATION_TRACKING'),
      Pages.live_location_tracking,
    );
  });

  test('maps to route, label and icon', () {
    expect(NavigationHelper.getPath(layout), '/liveTracking');
    expect(NavigationHelper.getLabel(layout), 'Live location tracking');
    expect(NavigationHelper.getIcon(layout), Icons.my_location);
  });
}
