import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/settings/notifications/notification_settings_cubit.dart';
import 'package:appflowy/workspace/presentation/notifications/notification_dialog.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class NotificationButton extends StatelessWidget {
  const NotificationButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final views = context.watch<SidebarSectionsBloc>().state.section.views;
    final mutex = PopoverMutex();

    return BlocProvider<ReminderBloc>.value(
      value: getIt<ReminderBloc>(),
      child: BlocBuilder<NotificationSettingsCubit, NotificationSettingsState>(
        builder: (notificationSettingsContext, notificationSettingsState) {
          return BlocBuilder<ReminderBloc, ReminderState>(
            builder: (context, state) => notificationSettingsState
                    .isShowNotificationsIconEnabled
                ? FlowyTooltip(
                    message: LocaleKeys.notificationHub_title.tr(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AppFlowyPopover(
                        mutex: mutex,
                        direction: PopoverDirection.bottomWithLeftAligned,
                        constraints:
                            const BoxConstraints(maxHeight: 500, maxWidth: 425),
                        windowPadding: EdgeInsets.zero,
                        margin: EdgeInsets.zero,
                        popupBuilder: (_) =>
                            NotificationDialog(views: views, mutex: mutex),
                        child:
                            _buildNotificationIcon(context, state.hasUnreads),
                      ),
                    ),
                  )
                : const SizedBox(),
          );
        },
      ),
    );
  }

  Widget _buildNotificationIcon(BuildContext context, bool hasUnreads) {
    return Stack(
      children: [
        FlowySvg(
          FlowySvgs.clock_alarm_s,
          size: const Size.square(24),
          color: Theme.of(context).colorScheme.tertiary,
        ),
        if (hasUnreads)
          Positioned(
            bottom: 2,
            right: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AFThemeExtension.of(context).warning,
              ),
              child: const SizedBox(height: 8, width: 8),
            ),
          ),
      ],
    );
  }
}
