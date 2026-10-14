import 'package:cctv_flutter/app.dart';
import 'package:cctv_flutter/widgets/channel_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('主页在手机尺寸下渲染频道网格', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CctvApp());
    await tester.pumpAndSettle();

    expect(find.text('CCTV 直播'), findsOneWidget);
    expect(find.text('18 个频道 · 点击开播'), findsOneWidget);
    expect(find.byType(ChannelCard), findsAtLeastNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
