import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:flutter/widgets.dart';

class CalendarSize {
  static double scale = 1;

  static double get headerContainerPadding => 12 * scale;

  static EdgeInsets get contentInsets => EdgeInsets.fromLTRB(
        GridSize.leadingHeaderPadding,
        CalendarSize.headerContainerPadding,
        GridSize.leadingHeaderPadding,
        CalendarSize.headerContainerPadding,
      );

  static EdgeInsets get contentInsetsMobile => EdgeInsets.fromLTRB(
        GridSize.leadingHeaderPadding / 2,
        0,
        GridSize.leadingHeaderPadding / 2,
        0,
      );

  static double get scrollBarSize => 8 * scale;
  static double get navigatorButtonWidth => 20 * scale;
  static double get navigatorButtonHeight => 24 * scale;
  static EdgeInsets get daysOfWeekInsets =>
      EdgeInsets.only(top: 12.0 * scale, bottom: 5.0 * scale);
}
