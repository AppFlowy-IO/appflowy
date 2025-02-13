import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

class CalculationsBackendService {
  const CalculationsBackendService({required this.viewId});

  final String viewId;

  // Get Calculations (initial fetch)
  Future<FlowyResult<RepeatedCalculationsPB, FlowyError>>
      getCalculations() async {
    final payload = DatabaseViewIdPB()..value = viewId;
    return DatabaseEventGetAllCalculations(payload).send();
  }

  Future<void> updateCalculation(
    String fieldId,
    CalculationType type, {
    String? calculationId,
  }) async {
    final payload = UpdateCalculationChangesetPB()
      ..viewId = viewId
      ..fieldId = fieldId
      ..calculationType = type;

    if (calculationId != null) {
      payload.calculationId = calculationId;
    }

    await DatabaseEventUpdateCalculation(payload).send();
  }

  Future<void> removeCalculation(
    String fieldId,
    String calculationId,
  ) async {
    final payload = RemoveCalculationChangesetPB()
      ..viewId = viewId
      ..fieldId = fieldId
      ..calculationId = calculationId;

    await DatabaseEventRemoveCalculation(payload).send();
  }
}
