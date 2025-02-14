import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_drop_manager.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/appflowy_network_svg.dart';
import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/permission/permission_checker.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/default_extensions.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/auth.pbenum.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:image_picker/image_picker.dart';
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';

@visibleForTesting
class IconUploader extends StatefulWidget {
  const IconUploader({
    super.key,
    required this.onUrl,
    required this.documentId,
    this.ensureFocus = false,
  });

  final ValueChanged<String> onUrl;
  final String documentId;
  final bool ensureFocus;

  @override
  State<IconUploader> createState() => _IconUploaderState();
}

class _IconUploaderState extends State<IconUploader> {
  bool isHovering = false;
  bool isUploading = false;

  final List<_Image> pickedImages = [];
  final FocusNode focusNode = FocusNode();
  final topEditorDropManagerState = getIt.get<EditorDropManagerState>();
  final iconUploaderType = 'iconUploaderType';

  @override
  void initState() {
    super.initState();

    /// Sometimes focus is lost due to the [SelectionGestureInterceptor] in [KeyboardServiceWidgetState]
    /// this is to ensure that focus can be regained within a short period of time
    if (widget.ensureFocus) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted || focusNode.hasFocus) return;
        focusNode.requestFocus();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      topEditorDropManagerState.add(iconUploaderType);
    });
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      topEditorDropManagerState.remove(iconUploaderType);
    });
    focusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(
          Platform.isMacOS
              ? LogicalKeyboardKey.meta
              : LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyV,
        ): _PasteIntent(),
      },
      child: Actions(
        actions: {
          _PasteIntent: CallbackAction<_PasteIntent>(
            onInvoke: (intent) => pasteAsAnImage(),
          ),
        },
        child: Focus(
          autofocus: true,
          focusNode: focusNode,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: DropTarget(
                    onDragEntered: (_) => setState(() => isHovering = true),
                    onDragExited: (_) => setState(() => isHovering = false),
                    onDragDone: (details) => loadImage(details.files),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: pickImage,
                        child: DottedBorder(
                          dashPattern: const [3, 3],
                          radius: const Radius.circular(8),
                          borderType: BorderType.RRect,
                          color: isHovering
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).hintColor,
                          child: Container(
                            alignment: Alignment.center,
                            child: pickedImages.isEmpty
                                ? (isHovering
                                    ? hoveringWidget()
                                    : dragHint(context))
                                : previewImage(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      Spacer(),
                      if (pickedImages.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: _ChangeIconButton(
                            onTap: pickImage,
                          ),
                        ),
                      _ConfirmButton(
                        onTap: uploadImage,
                        enable: pickedImages.isNotEmpty,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget hoveringWidget() {
    return Container(
      color: Color(0xffE0F8FF),
      child: Center(
        child: FlowyText(
          LocaleKeys.emojiIconPicker_iconUploader_dropToUpload.tr(),
        ),
      ),
    );
  }

  Widget dragHint(BuildContext context) {
    final style = TextStyle(
      fontSize: 14,
      color: Color(0xff666D76),
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            TextSpan(
              text:
                  LocaleKeys.emojiIconPicker_iconUploader_placeholderLeft.tr(),
            ),
            TextSpan(
              text: LocaleKeys.emojiIconPicker_iconUploader_placeholderUpload
                  .tr(),
              style: style.copyWith(color: Color(0xff00BCF0)),
            ),
            TextSpan(
              text:
                  LocaleKeys.emojiIconPicker_iconUploader_placeholderRight.tr(),
              mouseCursor: SystemMouseCursors.click,
            ),
          ],
          style: style,
        ),
      ),
    );
  }

  Widget previewImage() {
    final image = pickedImages.first;
    final url = image.url;
    if (image is _FileImage) {
      if (url.endsWith(_svgSuffix)) {
        return SvgPicture.file(
          File(url),
          width: 200,
          height: 200,
        );
      }
      return Image.file(
        File(url),
        width: 200,
        height: 200,
      );
    } else if (image is _NetworkImage) {
      if (url.endsWith(_svgSuffix)) {
        return FlowyNetworkSvg(
          url,
          width: 200,
          height: 200,
        );
      }
      return FlowyNetworkImage(
        width: 200,
        height: 200,
        url: url,
      );
    }
    return const SizedBox.shrink();
  }

  void loadImage(List<XFile> files) {
    final imageFiles = files
        .where(
          (file) =>
              file.mimeType?.startsWith('image/') ??
              false ||
                  imgExtensionRegex.hasMatch(file.name) ||
                  file.name.endsWith(_svgSuffix),
        )
        .toList();
    if (imageFiles.isEmpty) return;
    if (mounted) {
      setState(() {
        pickedImages.clear();
        pickedImages.add(_FileImage(imageFiles.first.path));
      });
    }
  }

  Future<void> pickImage() async {
    if (UniversalPlatform.isDesktopOrWeb) {
      // on desktop, the users can pick a image file from folder
      final result = await getIt<FilePickerService>().pickFiles(
        dialogTitle: '',
        type: FileType.custom,
        allowedExtensions: List.of(defaultImageExtensions)..add('svg'),
      );
      loadImage(result?.files.map((f) => f.xFile).toList() ?? const []);
    } else {
      final photoPermission =
          await PermissionChecker.checkPhotoPermission(context);
      if (!photoPermission) {
        Log.error('Has no permission to access the photo library');
        return;
      }
      // on mobile, the users can pick a image file from camera or image library
      final result = await ImagePicker().pickMultiImage();
      loadImage(result);
    }
  }

  Future<void> uploadImage() async {
    if (pickedImages.isEmpty || isUploading) return;
    isUploading = true;
    String? result;
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    final userProfile = userProfileResult.fold(
      (userProfile) => userProfile,
      (l) => null,
    );
    final isLocalMode = (userProfile?.authenticator ?? AuthenticatorPB.Local) ==
        AuthenticatorPB.Local;
    if (isLocalMode) {
      result = await pickedImages.first.saveToLocal();
    } else {
      result = await pickedImages.first.uploadToCloud(widget.documentId);
    }
    isUploading = false;
    if (result?.isNotEmpty ?? false) {
      widget.onUrl.call(result!);
    }
  }

  Future<void> pasteAsAnImage() async {
    final data = await getIt<ClipboardService>().getData();
    final plainText = data.plainText;
    Log.info('pasteAsAnImage plainText:$plainText');
    if (plainText == null) return;
    if (isURL(plainText) && (await validateImage(plainText))) {
      setState(() {
        pickedImages.clear();
        pickedImages.add(_NetworkImage(plainText));
      });
    }
  }

  Future<bool> validateImage(String imageUrl) async {
    Response res;
    try {
      res = await get(Uri.parse(imageUrl));
    } catch (e) {
      return false;
    }
    if (res.statusCode != 200) return false;
    final Map<String, dynamic> data = res.headers;
    return checkIfImage(data['content-type']);
  }

  bool checkIfImage(String? param) {
    if (param == 'image/jpeg' ||
        param == 'image/png' ||
        param == 'image/gif' ||
        param == 'image/tiff' ||
        param == 'image/webp' ||
        param == 'image/svg+xml' ||
        param == 'image/svg') {
      return true;
    }
    return false;
  }
}

class _ChangeIconButton extends StatelessWidget {
  const _ChangeIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 32,
      width: 84,
      child: FlowyButton(
        text: FlowyText(
          LocaleKeys.emojiIconPicker_iconUploader_change.tr(),
          fontSize: 14.0,
          fontWeight: FontWeight.w500,
          figmaLineHeight: 20.0,
          color: isDark ? Colors.white : Color(0xff1F2329),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 14.0),
        backgroundColor: Theme.of(context).colorScheme.surface,
        hoverColor:
            (isDark ? Colors.white : Color(0xffD1D8E0)).withValues(alpha: 0.9),
        decoration: BoxDecoration(
          border: Border.all(color: isDark ? Colors.white : Color(0xffD1D8E0)),
          borderRadius: BorderRadius.circular(10),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.onTap, this.enable = true});

  final VoidCallback onTap;
  final bool enable;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Opacity(
        opacity: enable ? 1.0 : 0.5,
        child: PrimaryRoundedButton(
          text: LocaleKeys.button_confirm.tr(),
          figmaLineHeight: 20.0,
          onTap: enable ? onTap : null,
        ),
      ),
    );
  }
}

const _svgSuffix = '.svg';

class _PasteIntent extends Intent {}

abstract class _Image {
  String get url;

  Future<String?> saveToLocal();

  Future<String?> uploadToCloud(String documentId);

  String get pureUrl => url.split('?').first;
}

class _FileImage extends _Image {
  _FileImage(this.url);

  @override
  final String url;

  @override
  Future<String?> saveToLocal() => saveImageToLocalStorage(url);

  @override
  Future<String?> uploadToCloud(String documentId) async {
    final (url, errorMsg) = await saveImageToCloudStorage(
      this.url,
      documentId,
    );
    if (errorMsg?.isNotEmpty ?? false) {
      Log.error('upload icon image :${this.url} error :$errorMsg');
    }
    return url;
  }
}

class _NetworkImage extends _Image {
  _NetworkImage(this.url);

  @override
  final String url;

  @override
  Future<String?> saveToLocal() async {
    final file = await CustomImageCacheManager().downloadFile(pureUrl);
    return file.file.path;
  }

  @override
  Future<String?> uploadToCloud(String documentId) async {
    final file = await CustomImageCacheManager().downloadFile(pureUrl);
    final (url, errorMsg) = await saveImageToCloudStorage(
      file.file.path,
      documentId,
    );
    if (errorMsg?.isNotEmpty ?? false) {
      Log.error('upload icon image :${this.url} error :$errorMsg');
    }
    return url;
  }
}
