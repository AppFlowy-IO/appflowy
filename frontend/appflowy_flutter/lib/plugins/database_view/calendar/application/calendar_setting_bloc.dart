import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'calendar_setting_bloc.freezed.dart';

typedef DayOfWeek = int;

class CalendarSettingBloc
    extends Bloc<CalendarSettingEvent, CalendarSettingState> {
  CalendarSettingBloc({required CalendarLayoutSettingPB? layoutSettings})
      : super(CalendarSettingState.initial(layoutSettings)) {
    on<CalendarSettingEvent>((event, emit) {
      event.when(
        performAction: (action) {
          emit(state.copyWith(selectedAction: Some(action)));
        },
        updateLayoutSetting: (setting) {
          emit(state.copyWith(layoutSetting: Some(setting)));
        },
      );
    });
  }

}

@freezed
class CalendarSettingState with _$CalendarSettingState {
  const factory CalendarSettingState({
    required Option<CalendarSettingAction> selectedAction,
    required Option<CalendarLayoutSettingPB> layoutSetting,
  }) = _CalendarSettingState;

  factory CalendarSettingState.initial(
          CalendarLayoutSettingPB? layoutSettings) =>
      CalendarSettingState(
        selectedAction: none(),
        layoutSetting: layoutSettings == null ? none() : Some(layoutSettings),
      );
}

@freezed
class CalendarSettingEvent with _$CalendarSettingEvent {
  const factory CalendarSettingEvent.performAction(
      CalendarSettingAction action) = _PerformAction;
  const factory CalendarSettingEvent.updateLayoutSetting(
      CalendarLayoutSettingPB setting) = _UpdateLayoutSetting;
}

enum CalendarSettingAction {
  layout,
}
