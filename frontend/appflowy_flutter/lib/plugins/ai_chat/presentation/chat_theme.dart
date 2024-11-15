import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

/// Default chat theme which extends [ChatTheme].
@immutable
class AFDefaultChatTheme extends ChatTheme {
  const AFDefaultChatTheme({
    required super.primaryColor,
    required super.secondaryColor,
  }) : super(
          backgroundColor: Colors.transparent,
          // TODO: think how to offset the default 12 pixels set by chat package
          bubbleMargin: const EdgeInsets.symmetric(vertical: 4.0),
          messageMaxWidth: double.infinity,
          // unused
          dateDividerMargin: EdgeInsets.zero,
          dateDividerTextStyle: const TextStyle(),
          attachmentButtonIcon: null,
          attachmentButtonMargin: null,
          deliveredIcon: null,
          documentIcon: null,
          emptyChatPlaceholderTextStyle: const TextStyle(),
          errorColor: error,
          errorIcon: null,
          inputBackgroundColor: neutral0,
          inputSurfaceTintColor: neutral0,
          inputElevation: 0,
          inputBorderRadius: BorderRadius.zero,
          inputContainerDecoration: null,
          inputMargin: EdgeInsets.zero,
          inputPadding: EdgeInsets.zero,
          inputTextColor: neutral7,
          inputTextCursorColor: null,
          inputTextDecoration: const InputDecoration(),
          inputTextStyle: const TextStyle(),
          messageBorderRadius: 0,
          messageInsetsHorizontal: 0,
          messageInsetsVertical: 0,
          receivedEmojiMessageTextStyle: const TextStyle(),
          receivedMessageBodyBoldTextStyle: null,
          receivedMessageBodyCodeTextStyle: null,
          receivedMessageBodyLinkTextStyle: null,
          receivedMessageBodyTextStyle: const TextStyle(),
          receivedMessageDocumentIconColor: primary,
          receivedMessageCaptionTextStyle: const TextStyle(),
          receivedMessageLinkDescriptionTextStyle: const TextStyle(),
          receivedMessageLinkTitleTextStyle: const TextStyle(),
          seenIcon: null,
          sendButtonIcon: null,
          sendButtonMargin: null,
          sendingIcon: null,
          sentEmojiMessageTextStyle: const TextStyle(),
          sentMessageBodyBoldTextStyle: null,
          sentMessageBodyCodeTextStyle: null,
          sentMessageBodyLinkTextStyle: null,
          sentMessageBodyTextStyle: const TextStyle(),
          sentMessageCaptionTextStyle: const TextStyle(),
          sentMessageDocumentIconColor: neutral7,
          sentMessageLinkDescriptionTextStyle: const TextStyle(),
          sentMessageLinkTitleTextStyle: const TextStyle(),
          statusIconPadding: EdgeInsets.zero,
          systemMessageTheme: const SystemMessageTheme(
            margin: EdgeInsets.zero,
            textStyle: TextStyle(),
          ),
          typingIndicatorTheme: const TypingIndicatorTheme(
            animatedCirclesColor: neutral1,
            animatedCircleSize: 0.0,
            bubbleBorder: BorderRadius.zero,
            bubbleColor: neutral7,
            countAvatarColor: primary,
            countTextColor: secondary,
            multipleUserTextStyle: TextStyle(),
          ),
          unreadHeaderTheme: const UnreadHeaderTheme(
            color: secondary,
            textStyle: TextStyle(),
          ),
          userAvatarImageBackgroundColor: Colors.transparent,
          userAvatarNameColors: colors,
          userAvatarTextStyle: const TextStyle(),
          userNameTextStyle: const TextStyle(),
          highlightMessageColor: null,
        );
}
