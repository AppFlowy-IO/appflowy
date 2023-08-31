import 'package:appflowy_backend/protobuf/flowy-document2/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy/plugins/document/application/editor_transaction_adapter.dart';

void main() {
  group('TransactionAdapter', () {
    test('toBlockAction insert node with children operation', () {
      final editorState = EditorState.blank();

      final transaction = editorState.transaction;
      transaction.insertNode(
        [0],
        paragraphNode(
          children: [
            paragraphNode(text: '1', children: [paragraphNode(text: '1.1')]),
            paragraphNode(text: '2'),
            paragraphNode(text: '3', children: [paragraphNode(text: '3.1')]),
            paragraphNode(text: '4'),
          ],
        ),
      );

      expect(transaction.operations.length, 1);
      expect(transaction.operations[0] is InsertOperation, true);

      final actions = transaction.operations[0].toBlockAction(editorState);

      expect(actions.length, 7);
      for (final action in actions) {
        expect(action.action, BlockActionTypePB.Insert);
      }

      expect(
        actions[0].payload.parentId,
        editorState.document.root.id,
        reason: '0 - parent id',
      );
      expect(
        actions[0].payload.prevId,
        editorState.document.root.children.first.id,
        reason: '0 - prev id',
      );
      expect(
        actions[1].payload.parentId,
        actions[0].payload.block.id,
        reason: '1 - parent id',
      );
      expect(
        actions[1].payload.prevId,
        '',
        reason: '1 - prev id',
      );
      expect(
        actions[2].payload.parentId,
        actions[1].payload.block.id,
        reason: '2 - parent id',
      );
      expect(
        actions[2].payload.prevId,
        '',
        reason: '2 - prev id',
      );
      expect(
        actions[3].payload.parentId,
        actions[0].payload.block.id,
        reason: '3 - parent id',
      );
      expect(
        actions[3].payload.prevId,
        actions[1].payload.block.id,
        reason: '3 - prev id',
      );
      expect(
        actions[4].payload.parentId,
        actions[0].payload.block.id,
        reason: '4 - parent id',
      );
      expect(
        actions[4].payload.prevId,
        actions[3].payload.block.id,
        reason: '4 - prev id',
      );
      expect(
        actions[5].payload.parentId,
        actions[4].payload.block.id,
        reason: '5 - parent id',
      );
      expect(
        actions[5].payload.prevId,
        '',
        reason: '5 - prev id',
      );
      expect(
        actions[6].payload.parentId,
        actions[0].payload.block.id,
        reason: '6 - parent id',
      );
      expect(
        actions[6].payload.prevId,
        actions[4].payload.block.id,
        reason: '6 - prev id',
      );
    });
  });
}
