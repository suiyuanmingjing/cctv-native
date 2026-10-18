import 'package:cctv_tv_flutter/app.dart';
import 'package:cctv_tv_flutter/widgets/tv_channel_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('电视主页在 1080p 尺寸下渲染频道网格', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CctvTvApp());
    await tester.pumpAndSettle();

    expect(find.text('CCTV 直播'), findsOneWidget);
    expect(find.byType(TvChannelCard), findsAtLeastNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
