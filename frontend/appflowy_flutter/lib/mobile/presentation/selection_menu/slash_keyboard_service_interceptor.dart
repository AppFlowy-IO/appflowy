import 'package:appflowy/plugins/document/presentation/editor_plugins/keyboard_interceptor/keyboard_interceptor.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SlashKeyboardServiceInterceptor extends EditorKeyboardInterceptor {
  SlashKeyboardServiceInterceptor({
    required this.onDelete,
    required this.onEnter,
  });

  final AsyncValueGetter<bool> onDelete;
  final VoidCallback onEnter;

  @override
  Future<bool> interceptDelete(
    TextEditingDeltaDeletion deletion,
    EditorState editorState,
  ) async {
    final intercept = await onDelete.call();
    if (intercept) {
      return true;
    } else {
      return super.interceptDelete(deletion, editorState);
    }
  }

  @override
  Future<bool> interceptInsert(
    TextEditingDeltaInsertion insertion,
    EditorState editorState,
    List<CharacterShortcutEvent> characterShortcutEvents,
  ) async {
    final text = insertion.textInserted;
    if (text.contains('\n')) {
      onEnter.call();
      return true;
    }
    return super
        .interceptInsert(insertion, editorState, characterShortcutEvents);
  }
}
