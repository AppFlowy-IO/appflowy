import 'package:appflowy/mobile/presentation/selection_menu/mobile_selection_menu_item.dart';
import 'package:appflowy/mobile/presentation/selection_menu/mobile_selection_menu_item_widget.dart';
import 'package:appflowy/mobile/presentation/selection_menu/mobile_selection_menu_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/mobile_items.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../shared/util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const title = 'Test Slash Menu';

  group('slash menu', () {
    testWidgets('show slash menu', (tester) async {
      await tester.launchInAnonymousMode();
      await tester.createPageAndShowSlashMenu(title);
      final menuWidget = find.byType(MobileSelectionMenuWidget);
      expect(menuWidget, findsOneWidget);
      final items =
          (menuWidget.evaluate().first.widget as MobileSelectionMenuWidget)
              .items;
      int i = 0;
      for (final item in items) {
        final localItem = mobileItems[i];
        expect(item.name, localItem.name);
        i++;
      }
    });

    testWidgets('search by slash menu', (tester) async {
      await tester.launchInAnonymousMode();
      await tester.createPageAndShowSlashMenu(title);
      const searchText = 'Heading';
      await tester.ime.insertText(searchText);
      final itemWidgets = find.byType(MobileSelectionMenuItemWidget);
      int number = 0;
      for (final item in mobileItems) {
        if (item is MobileSelectionMenuItem) {
          for (final childItem in item.children) {
            if (childItem.name
                .toLowerCase()
                .contains(searchText.toLowerCase())) {
              number++;
            }
          }
        } else {
          if (item.name.toLowerCase().contains(searchText.toLowerCase())) {
            number++;
          }
        }
      }
      expect(itemWidgets, findsNWidgets(number));
    });

    testWidgets('tap to show submenu', (tester) async {
      await tester.launchInAnonymousMode();
      await tester.createNewDocumentOnMobile(title);
      await tester.editor.tapLineOfEditorAt(0);
      final listview = find.descendant(
        of: find.byType(MobileSelectionMenuWidget),
        matching: find.byType(ListView),
      );
      for (final item in mobileItems) {
        if (item is! MobileSelectionMenuItem) continue;
        await tester.editor.showSlashMenu();
        await tester.scrollUntilVisible(
          find.text(item.name),
          50,
          scrollable: listview,
          duration: const Duration(milliseconds: 250),
        );
        await tester.tap(find.text(item.name));
        final childrenLength = ((listview.evaluate().first.widget as ListView)
                .childrenDelegate as SliverChildListDelegate)
            .children
            .length;
        expect(childrenLength, item.children.length);
      }
    });
  });
}
