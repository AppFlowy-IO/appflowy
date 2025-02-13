import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/calculations/calculate_cell.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/filter/choicechip/text.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';

import 'package:appflowy/plugins/database/grid/presentation/widgets/filter/choicechip/number.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../shared/database_test_op.dart';
import '../../shared/util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Grid Calculations', () {
    testWidgets('add calculation and update cell', (tester) async {
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();

      await tester.createNewPageWithNameUnderParent(layout: ViewLayoutPB.Grid);

      // Change one Field to Number
      await tester.changeFieldTypeOfFieldWithName('Type', FieldType.Number);
      await tester.changeCalculateAtIndex(1, CalculationType.Sum);

      // Enter values in cells
      await tester.editCell(
        rowIndex: 0,
        fieldType: FieldType.Number,
        input: '100',
      );

      await tester.editCell(
        rowIndex: 1,
        fieldType: FieldType.Number,
        input: '100',
      );

      // Dismiss edit cell
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);

      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('200'), findsOneWidget);
    });

    testWidgets('add calculations and remove row', (tester) async {
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();

      await tester.createNewPageWithNameUnderParent(layout: ViewLayoutPB.Grid);

      // Change two Fields to Number
      await tester.changeFieldTypeOfFieldWithName('Type', FieldType.Number);
      await tester.changeFieldTypeOfFieldWithName('Done', FieldType.Number);

      expect(find.text('Calculate'), findsNWidgets(3));

      await tester.changeCalculateAtIndex(1, CalculationType.Sum);
      await tester.changeCalculateAtIndex(2, CalculationType.Min);

      // Enter values in cells
      await tester.editCell(
        rowIndex: 0,
        fieldType: FieldType.Number,
        input: '100',
      );
      await tester.editCell(
        rowIndex: 1,
        fieldType: FieldType.Number,
        input: '150',
      );
      await tester.editCell(
        rowIndex: 0,
        fieldType: FieldType.Number,
        input: '50',
        cellIndex: 1,
      );
      await tester.editCell(
        rowIndex: 1,
        fieldType: FieldType.Number,
        input: '100',
        cellIndex: 1,
      );

      await tester.pumpAndSettle();

      // Dismiss edit cell
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('250'), findsOneWidget);
      expect(find.text('50'), findsNWidgets(2));

      // Delete 1st row
      await tester.hoverOnFirstRowOfGrid();
      await tester.tapRowMenuButtonInGrid();
      await tester.tapDeleteOnRowMenu();
      await tester.tap(find.text(LocaleKeys.button_delete.tr()));

      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('150'), findsNWidgets(2));
      expect(find.text('100'), findsNWidgets(2));
    });

    testWidgets('Calculations with filter', (tester) async {
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();

      await tester.createNewPageWithNameUnderParent(layout: ViewLayoutPB.Grid);

      // Change two Fields to Number
      await tester.changeFieldTypeOfFieldWithName('Type', FieldType.Number);
      await tester.changeFieldTypeOfFieldWithName('Done', FieldType.Number);

      expect(find.text('Calculate'), findsNWidgets(3));

      await tester.changeCalculateAtIndex(1, CalculationType.Sum);
      await tester.changeCalculateAtIndex(2, CalculationType.Min);

      // Enter values in cells
      await tester.editCell(
        rowIndex: 0,
        fieldType: FieldType.Number,
        input: '100',
      );
      await tester.editCell(
        rowIndex: 1,
        fieldType: FieldType.Number,
        input: '150',
      );
      await tester.editCell(
        rowIndex: 2,
        fieldType: FieldType.Number,
        input: '100',
      );
      await tester.editCell(
        rowIndex: 0,
        fieldType: FieldType.Number,
        input: '150',
        cellIndex: 1,
      );
      await tester.editCell(
        rowIndex: 1,
        fieldType: FieldType.Number,
        input: '100',
        cellIndex: 1,
      );
      await tester.editCell(
        rowIndex: 2,
        fieldType: FieldType.Number,
        input: '50',
        cellIndex: 1,
      );
      await tester.pumpAndSettle();

      // Dismiss edit cell
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Expect sum to be 100 + 150 + 100 = 350
      expect(find.text('350'), findsOneWidget);

      // Expect min to be 50
      expect(find.text('50'), findsNWidgets(2));

      await tester.tapDatabaseFilterButton();
      await tester.tapCreateFilterByFieldType(FieldType.Number, 'Type');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NumberFilterChoiceChip));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(NumberFilterEditor),
          matching: find.byType(FlowyTextField),
        ),
        '100',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Expect the sum to be 100+100 = 200
      expect(find.text('200'), findsOneWidget);

      // Expect the min to be 50
      expect(find.text('50'), findsNWidgets(2));

      await tester.enterText(
        find.descendant(
          of: find.byType(NumberFilterEditor),
          matching: find.byType(FlowyTextField),
        ),
        '150',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Expect the sum to be 150 (3 times, text field, cell, and calculate cell)
      expect(find.text('150'), findsNWidgets(3));

      // Expect the min to be 100
      expect(find.text('100'), findsNWidgets(2));
    });

    testWidgets('Calculations count + count empty w/ filter', (tester) async {
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();

      await tester.createNewPageWithNameUnderParent(layout: ViewLayoutPB.Grid);
      expect(find.text('Calculate'), findsNWidgets(3));

      await tester.changeFieldTypeOfFieldWithName('Type', FieldType.RichText);

      await tester.changeCalculateAtIndex(0, CalculationType.Count);
      await tester.changeCalculateAtIndex(1, CalculationType.CountEmpty);

      // Enter values in 2nd column (count empty)
      await tester.editCell(
        rowIndex: 0,
        fieldType: FieldType.RichText,
        input: 'A',
        cellIndex: 1,
      );
      await tester.editCell(
        rowIndex: 1,
        fieldType: FieldType.RichText,
        input: 'A',
        cellIndex: 1,
      );
      await tester.pumpAndSettle();

      // Dismiss edit cell
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Expect count to be 3
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '3',
        ),
        findsOneWidget,
      );

      // Expect count empty to be 1
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '1',
        ),
        findsOneWidget,
      );

      await tester.tapDatabaseFilterButton();
      await tester.tapCreateFilterByFieldType(FieldType.RichText, 'Type');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextFilterChoicechip));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(TextFilterEditor),
          matching: find.byType(FlowyTextField),
        ),
        'A',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Expect the count to be 2
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '2',
        ),
        findsOneWidget,
      );

      // Expect the count empty to be 0
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '0',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.descendant(
          of: find.byType(TextFilterEditor),
          matching: find.byType(FlowyTextField),
        ),
        'B',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Expect the count to be 0
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '0',
        ),
        findsOneWidget,
      );

      // Expect the count empty to be 0
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '0',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.descendant(
          of: find.byType(TextFilterEditor),
          matching: find.byType(FlowyTextField),
        ),
        '',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.dismissCellEditor();

      await tester.tapCreateRowButtonInGrid();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Expect the count to be 4
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '4',
        ),
        findsOneWidget,
      );

      // Expect the count empty to be 2
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '2',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Calculations count not empty w/ filter', (tester) async {
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();

      await tester.createNewPageWithNameUnderParent(layout: ViewLayoutPB.Grid);
      expect(find.text('Calculate'), findsNWidgets(3));

      await tester.changeFieldTypeOfFieldWithName('Type', FieldType.Number);

      await tester.changeCalculateAtIndex(0, CalculationType.CountNonEmpty);
      await tester.changeCalculateAtIndex(1, CalculationType.CountNonEmpty);

      await tester.editCell(
        rowIndex: 0,
        fieldType: FieldType.Number,
        input: '1',
      );
      await tester.editCell(
        rowIndex: 1,
        fieldType: FieldType.Number,
        input: '2',
      );
      await tester.pumpAndSettle();

      // Dismiss edit cell
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '0',
        ),
        findsOneWidget,
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '2',
        ),
        findsOneWidget,
      );

      await tester.tapDatabaseFilterButton();
      await tester.tapCreateFilterByFieldType(FieldType.Number, 'Type');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NumberFilterChoiceChip));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(NumberFilterEditor),
          matching: find.byType(FlowyTextField),
        ),
        '1',
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '0',
        ),
        findsOneWidget,
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '1',
        ),
        findsOneWidget,
      );

      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.dismissCellEditor();

      await tester.tapCreateRowButtonInGrid();
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '0',
        ),
        findsOneWidget,
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CalculateCell &&
              w.calculation != null &&
              w.calculation!.value == '2',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Median calculation', (tester) async {
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();

      await tester.createNewPageWithNameUnderParent(layout: ViewLayoutPB.Grid);
      expect(find.text('Calculate'), findsNWidgets(3));

      await tester.changeFieldTypeOfFieldWithName('Type', FieldType.Number);
      await tester.changeCalculateAtIndex(1, CalculationType.Median);

      await tester.tapCreateRowButtonInGrid();
      await tester.pumpAndSettle();

      await tester.editCell(
        rowIndex: 0,
        fieldType: FieldType.Number,
        input: '10',
      );

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('10'),
        ),
        findsOneWidget,
      );

      await tester.editCell(
        rowIndex: 1,
        fieldType: FieldType.Number,
        input: '20',
      );

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('15'),
        ),
        findsOneWidget,
      );

      await tester.editCell(
        rowIndex: 2,
        fieldType: FieldType.Number,
        input: '30',
      );

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('20'),
        ),
        findsOneWidget,
      );

      await tester.editCell(
        rowIndex: 3,
        fieldType: FieldType.Number,
        input: '40',
      );

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('25'),
        ),
        findsOneWidget,
      );

      // Dismiss edit cell
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      await tester.tapDatabaseFilterButton();
      await tester.tapCreateFilterByFieldType(FieldType.Number, 'Type');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NumberFilterChoiceChip));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(NumberFilterEditor),
          matching: find.byType(FlowyTextField),
        ),
        '30',
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('30'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Median calculation', (tester) async {
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();

      await tester.createNewPageWithNameUnderParent(layout: ViewLayoutPB.Grid);
      expect(find.text('Calculate'), findsNWidgets(3));

      await tester.changeFieldTypeOfFieldWithName('Type', FieldType.Number);
      await tester.changeCalculateAtIndex(1, CalculationType.Median);

      await tester.tapCreateRowButtonInGrid();
      await tester.pumpAndSettle();

      await tester.editCell(
        rowIndex: 0,
        fieldType: FieldType.Number,
        input: '10',
      );

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('10'),
        ),
        findsOneWidget,
      );

      await tester.editCell(
        rowIndex: 1,
        fieldType: FieldType.Number,
        input: '20',
      );

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('15'),
        ),
        findsOneWidget,
      );

      await tester.editCell(
        rowIndex: 2,
        fieldType: FieldType.Number,
        input: '30',
      );

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('20'),
        ),
        findsOneWidget,
      );

      await tester.editCell(
        rowIndex: 3,
        fieldType: FieldType.Number,
        input: '40',
      );

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('25'),
        ),
        findsOneWidget,
      );

      // Dismiss edit cell
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      await tester.tapDatabaseFilterButton();
      await tester.tapCreateFilterByFieldType(FieldType.Number, 'Type');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NumberFilterChoiceChip));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(NumberFilterEditor),
          matching: find.byType(FlowyTextField),
        ),
        '30',
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        find.descendant(
          of: find.byType(CalculateCell),
          matching: find.text('30'),
        ),
        findsOneWidget,
      );
    });
  });
}
