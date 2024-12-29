import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart'
    hide ChatAnimatedListReversed;
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:url_launcher/url_launcher.dart';

import 'application/ai_prompt_input_bloc.dart';
import 'application/chat_bloc.dart';
import 'application/chat_entity.dart';
import 'application/chat_member_bloc.dart';
import 'application/chat_message_stream.dart';
import 'presentation/animated_chat_list.dart';
import 'presentation/chat_input/desktop_ai_prompt_input.dart';
import 'presentation/chat_input/mobile_ai_prompt_input.dart';
import 'presentation/chat_related_question.dart';
import 'presentation/chat_welcome_page.dart';
import 'presentation/layout_define.dart';
import 'presentation/message/ai_text_message.dart';
import 'presentation/message/error_text_message.dart';
import 'presentation/message/message_util.dart';
import 'presentation/message/user_text_message.dart';
import 'presentation/scroll_to_bottom.dart';

class AIChatPage extends StatelessWidget {
  const AIChatPage({
    super.key,
    required this.view,
    required this.onDeleted,
    required this.userProfile,
  });

  final ViewPB view;
  final VoidCallback onDeleted;
  final UserProfilePB userProfile;

  @override
  Widget build(BuildContext context) {
    if (userProfile.authenticator != AuthenticatorPB.AppFlowyCloud) {
      return Center(
        child: FlowyText(
          LocaleKeys.chat_unsupportedCloudPrompt.tr(),
          fontSize: 20,
        ),
      );
    }

    return MultiBlocProvider(
      providers: [
        /// [ChatBloc] is used to handle chat messages including send/receive message
        BlocProvider(
          create: (_) => ChatBloc(
            chatId: view.id,
            userId: userProfile.id.toString(),
          ),
        ),

        /// [AIPromptInputBloc] is used to handle the user prompt
        BlocProvider(create: (_) => AIPromptInputBloc()),
        BlocProvider(create: (_) => ChatMemberBloc()),
      ],
      child: Builder(
        builder: (context) {
          return DropTarget(
            onDragDone: (DropDoneDetails detail) async {
              if (context.read<AIPromptInputBloc>().state.supportChatWithFile) {
                for (final file in detail.files) {
                  context
                      .read<AIPromptInputBloc>()
                      .add(AIPromptInputEvent.attachFile(file.path, file.name));
                }
              }
            },
            child: _ChatContentPage(
              view: view,
              userProfile: userProfile,
            ),
          );
        },
      ),
    );
  }
}

class _ChatContentPage extends StatelessWidget {
  const _ChatContentPage({
    required this.view,
    required this.userProfile,
  });

  final UserProfilePB userProfile;
  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 784),
        margin: UniversalPlatform.isDesktop
            ? const EdgeInsets.symmetric(horizontal: 60.0)
            : null,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return switch (state.loadingState) {
                LoadChatMessageStatus.ready => Column(
                    children: [
                      Expanded(
                        child: Chat(
                          chatController:
                              context.read<ChatBloc>().chatController,
                          user: User(id: userProfile.id.toString()),
                          darkTheme: ChatTheme.fromThemeData(Theme.of(context)),
                          theme: ChatTheme.fromThemeData(Theme.of(context)),
                          builders: Builders(
                            inputBuilder: (_) => const SizedBox.shrink(),
                            textMessageBuilder: _buildTextMessage,
                            chatMessageBuilder: _buildChatMessage,
                            scrollToBottomBuilder: _buildScrollToBottom,
                            chatAnimatedListBuilder: _buildChatAnimatedList,
                          ),
                        ),
                      ),
                      _buildInput(context),
                    ],
                  ),
                _ => const Center(child: CircularProgressIndicator.adaptive()),
              };
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTextMessage(
    BuildContext context,
    TextMessage message,
  ) {
    final messageType = onetimeMessageTypeFromMeta(
      message.metadata,
    );

    if (messageType == OnetimeShotType.error) {
      return ChatErrorMessageWidget(
        errorMessage: message.metadata?[errorMessageTextKey] ?? "",
      );
    }

    if (messageType == OnetimeShotType.relatedQuestion) {
      return RelatedQuestionList(
        relatedQuestions: message.metadata!['questions'],
        onQuestionSelected: (question) {
          context
              .read<ChatBloc>()
              .add(ChatEvent.sendMessage(message: question));
        },
      );
    }

    if (message.author.id == userProfile.id.toString()) {
      return ChatUserMessageWidget(
        user: message.author,
        message: message,
        isCurrentUser: true,
      );
    }

    if (isOtherUserMessage(message)) {
      return ChatUserMessageWidget(
        user: message.author,
        message: message,
        isCurrentUser: false,
      );
    }

    final stream = message.metadata?["$AnswerStream"];
    final questionId = message.metadata?[messageQuestionIdKey];
    final refSourceJsonString =
        message.metadata?[messageRefSourceJsonStringKey] as String?;

    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        final chatController = context.read<ChatBloc>().chatController;
        final messages = chatController.messages
            .where((e) => onetimeMessageTypeFromMeta(e.metadata) == null);
        final isLastMessage =
            messages.isEmpty ? false : messages.last.id == message.id;
        return ChatAIMessageWidget(
          user: message.author,
          messageUserId: message.id,
          message: message,
          stream: stream is AnswerStream ? stream : null,
          questionId: questionId,
          chatId: view.id,
          refSourceJsonString: refSourceJsonString,
          isStreaming: state.promptResponseState != PromptResponseState.ready,
          isLastMessage: isLastMessage,
          onSelectedMetadata: (metadata) =>
              _onSelectMetadata(context, metadata),
          onRegenerate: () => context
              .read<ChatBloc>()
              .add(ChatEvent.regenerateAnswer(message.id)),
        );
      },
    );
  }

  Widget _buildChatMessage(
    BuildContext context,
    Message message,
    Animation<double> animation,
    Widget child,
  ) {
    return ChatMessage(
      message: message,
      animation: animation,
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      receivedMessageScaleAnimationAlignment: Alignment.center,
      child: child,
    );
  }

  Widget _buildScrollToBottom(
    BuildContext context,
    Animation<double> animation,
    VoidCallback onPressed,
  ) {
    return CustomScrollToBottom(
      animation: animation,
      onPressed: onPressed,
    );
  }

  Widget _buildChatAnimatedList(
    BuildContext context,
    ScrollController scrollController,
    ChatItem itemBuilder,
  ) {
    final bloc = context.read<ChatBloc>();

    if (bloc.chatController.messages.isEmpty) {
      return ChatWelcomePage(
        userProfile: userProfile,
        onSelectedQuestion: (question) {
          bloc.add(ChatEvent.sendMessage(message: question));
        },
      );
    }

    return ChatAnimatedListReversed(
      scrollController: scrollController,
      itemBuilder: itemBuilder,
      onLoadPreviousMessages: () {
        bloc.add(const ChatEvent.loadPreviousMessages());
      },
    );
  }

  Widget _buildInput(BuildContext context) {
    return Padding(
      padding: AIChatUILayout.safeAreaInsets(context),
      child: BlocSelector<ChatBloc, ChatState, bool>(
        selector: (state) {
          return state.promptResponseState == PromptResponseState.ready;
        },
        builder: (context, canSendMessage) {
          final chatBloc = context.read<ChatBloc>();

          return UniversalPlatform.isDesktop
              ? DesktopAIPromptInput(
                  chatId: view.id,
                  isStreaming: !canSendMessage,
                  onStopStreaming: () {
                    chatBloc.add(const ChatEvent.stopStream());
                  },
                  onSubmitted: (text, metadata) {
                    chatBloc.add(
                      ChatEvent.sendMessage(
                        message: text,
                        metadata: metadata,
                      ),
                    );
                  },
                  onUpdateSelectedSources: (ragOnly, ids) {
                    if (ragOnly != chatBloc.state.onlyUseSelectedSources) {
                      chatBloc.add(
                        ChatEvent.setRagOnly(
                          ragOnly: ragOnly,
                        ),
                      );
                    }
                    if (!listEquals(ids, chatBloc.state.selectedSourceIds)) {
                      chatBloc.add(
                        ChatEvent.updateSelectedSources(
                          selectedSourcesIds: ids,
                        ),
                      );
                    }
                  },
                )
              : MobileAIPromptInput(
                  chatId: view.id,
                  isStreaming: !canSendMessage,
                  onStopStreaming: () {
                    chatBloc.add(const ChatEvent.stopStream());
                  },
                  onSubmitted: (text, metadata) {
                    chatBloc.add(
                      ChatEvent.sendMessage(
                        message: text,
                        metadata: metadata,
                      ),
                    );
                  },
                  onUpdateSelectedSources: (ids) {
                    chatBloc.add(
                      ChatEvent.updateSelectedSources(
                        selectedSourcesIds: ids,
                      ),
                    );
                  },
                );
        },
      ),
    );
  }

  void _onSelectMetadata(
    BuildContext context,
    ChatMessageRefSource metadata,
  ) async {
    if (isURL(metadata.name)) {
      late Uri uri;
      try {
        uri = Uri.parse(metadata.name);
        // `Uri` identifies `localhost` as a scheme
        if (!uri.hasScheme || uri.scheme == 'localhost') {
          uri = Uri.parse("http://${metadata.name}");
          await InternetAddress.lookup(uri.host);
        }
        await launchUrl(uri);
      } catch (err) {
        Log.error("failed to open url $err");
      }
    } else {
      final sidebarView =
          await ViewBackendService.getView(metadata.id).toNullable();
      if (context.mounted) {
        openPageFromMessage(context, sidebarView);
      }
    }
  }
}
