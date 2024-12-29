import 'dart:async';
import 'dart:collection';

import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nanoid/nanoid.dart';

import 'chat_entity.dart';
import 'chat_message_listener.dart';
import 'chat_message_service.dart';
import 'chat_message_stream.dart';

part 'chat_bloc.freezed.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required this.chatId,
    required this.userId,
  })  : chatController = InMemoryChatController(),
        listener = ChatMessageListener(chatId: chatId),
        super(ChatState.initial()) {
    _startListening();
    _dispatch();
    _loadMessages();
    _loadSetting();
  }

  final String chatId;
  final String userId;
  final ChatMessageListener listener;

  final ChatController chatController;

  /// The last streaming message id
  String answerStreamMessageId = '';
  String questionStreamMessageId = '';

  ChatMessagePB? lastSentMessage;

  /// Using a temporary map to associate the real message ID with the last streaming message ID.
  ///
  /// When a message is streaming, it does not have a real message ID. To maintain the relationship
  /// between the real message ID and the last streaming message ID, we use this map to store the associations.
  ///
  /// This map will be updated when receiving a message from the server and its author type
  /// is 3 (AI response).
  final HashMap<String, String> temporaryMessageIDMap = HashMap();

  bool isLoadingPreviousMessages = false;
  bool hasMorePreviousMessages = true;
  AnswerStream? answerStream;
  int numSendMessage = 0;

  @override
  Future<void> close() async {
    await answerStream?.dispose();
    await listener.stop();
    final request = ViewIdPB(value: chatId);
    unawaited(FolderEventCloseView(request).send());

    return super.close();
  }

  void _dispatch() {
    on<ChatEvent>(
      (event, emit) async {
        await event.when(
          // Loading messages
          didLoadLatestMessages: (List<Message> messages) async {
            for (final message in messages) {
              await chatController.insert(message, index: 0);
            }

            switch (state.loadingState) {
              case LoadChatMessageStatus.loading
                  when chatController.messages.isEmpty:
                emit(
                  state.copyWith(
                    loadingState: LoadChatMessageStatus.loadingRemote,
                  ),
                );
                break;
              case LoadChatMessageStatus.loading:
              case LoadChatMessageStatus.loadingRemote:
                emit(
                  state.copyWith(loadingState: LoadChatMessageStatus.ready),
                );
                break;
              default:
                break;
            }
          },
          loadPreviousMessages: () {
            if (isLoadingPreviousMessages) {
              return;
            }

            final oldestMessage = _getOldestMessage();

            if (oldestMessage != null) {
              final oldestMessageId = Int64.tryParseInt(oldestMessage.id);
              if (oldestMessageId == null) {
                Log.error("Failed to parse message_id: ${oldestMessage.id}");
                return;
              }
              isLoadingPreviousMessages = true;
              _loadPreviousMessages(oldestMessageId);
            }
          },
          didLoadPreviousMessages: (messages, hasMore) {
            Log.debug("did load previous messages: ${messages.length}");

            for (final message in messages) {
              chatController.insert(message, index: 0);
            }

            isLoadingPreviousMessages = false;
            hasMorePreviousMessages = hasMore;
          },
          didFinishAnswerStream: () {
            emit(
              state.copyWith(promptResponseState: PromptResponseState.ready),
            );
          },
          didReceiveRelatedQuestions: (List<String> questions) {
            if (questions.isEmpty) {
              return;
            }

            final metadata = {
              onetimeShotType: OnetimeShotType.relatedQuestion,
              'questions': questions,
            };

            final createdAt = DateTime.now();

            final message = TextMessage(
              id: "related_question_$createdAt",
              text: '',
              metadata: metadata,
              author: const User(id: systemUserId),
              createdAt: createdAt,
            );

            chatController.insert(message);
          },
          receiveMessage: (Message message) {
            final oldMessage = chatController.messages
                .firstWhereOrNull((m) => m.id == message.id);
            if (oldMessage == null) {
              chatController.insert(message);
            } else {
              chatController.update(oldMessage, message);
            }
          },
          sendMessage: (
            String message,
            Map<String, dynamic>? metadata,
          ) {
            numSendMessage += 1;

            _clearRelatedQuestions();
            _startStreamingMessage(message, metadata);
            lastSentMessage = null;

            emit(
              state.copyWith(
                promptResponseState: PromptResponseState.sendingQuestion,
              ),
            );
          },
          finishSending: () {
            emit(
              state.copyWith(
                promptResponseState: PromptResponseState.streamingAnswer,
              ),
            );
          },
          stopStream: () async {
            if (answerStream == null) {
              return;
            }

            // tell backend to stop
            final payload = StopStreamPB(chatId: chatId);
            await AIEventStopStream(payload).send();

            // allow user input
            emit(
              state.copyWith(
                promptResponseState: PromptResponseState.ready,
              ),
            );

            // no need to remove old message if stream has started already
            if (answerStream!.hasStarted) {
              return;
            }

            // remove the non-started message from the list
            final message = chatController.messages.lastWhereOrNull(
              (e) => e.id == answerStreamMessageId,
            );
            if (message != null) {
              await chatController.remove(message);
            }

            // set answer stream to null
            await answerStream?.dispose();
            answerStream = null;
            answerStreamMessageId = '';
          },
          failedSending: () {
            final lastMessage = chatController.messages.lastOrNull;
            if (lastMessage != null) {
              chatController.remove(lastMessage);
            }
            emit(
              state.copyWith(
                promptResponseState: PromptResponseState.ready,
              ),
            );
          },
          regenerateAnswer: (id) {
            _clearRelatedQuestions();
            _regenerateAnswer(id);
            lastSentMessage = null;

            emit(
              state.copyWith(
                promptResponseState: PromptResponseState.sendingQuestion,
              ),
            );
          },
          didReceiveChatSettings: (settings) {
            emit(
              state.copyWith(
                selectedSourceIds: settings.ragIds.ragIds,
                onlyUseSelectedSources: settings.ragOnly,
              ),
            );
          },
          updateSelectedSources: (selectedSourcesIds) async {
            emit(state.copyWith(selectedSourceIds: selectedSourcesIds));
            final ragIds = RepeatedRagId(ragIds: selectedSourcesIds);
            final payload = UpdateChatSettingsPB.create()
              ..chatId = ChatId(value: chatId)
              ..ragIds = ragIds;

            await AIEventUpdateChatSettings(payload)
                .send()
                .onFailure(Log.error);
          },
          setRagOnly: (ragOnly) async {
            emit(state.copyWith(onlyUseSelectedSources: ragOnly));
            final payload = UpdateChatSettingsPB.create()
              ..chatId = ChatId(value: chatId)
              ..ragOnly = ragOnly;

            await AIEventUpdateChatSettings(payload)
                .send()
                .onFailure(Log.error);
          },
        );
      },
    );
  }

  void _startListening() {
    listener.start(
      chatMessageCallback: (pb) {
        if (isClosed) {
          return;
        }

        // 3 mean message response from AI
        if (pb.authorType == 3 && answerStreamMessageId.isNotEmpty) {
          temporaryMessageIDMap[pb.messageId.toString()] =
              answerStreamMessageId;
          answerStreamMessageId = '';
        }

        // 1 mean message response from User
        if (pb.authorType == 1 && questionStreamMessageId.isNotEmpty) {
          temporaryMessageIDMap[pb.messageId.toString()] =
              questionStreamMessageId;
          questionStreamMessageId = '';
        }

        final message = _createTextMessage(pb);
        add(ChatEvent.receiveMessage(message));
      },
      chatErrorMessageCallback: (err) {
        if (!isClosed) {
          Log.error("chat error: ${err.errorMessage}");
          add(const ChatEvent.didFinishAnswerStream());
        }
      },
      latestMessageCallback: (list) {
        if (!isClosed) {
          final messages = list.messages.map(_createTextMessage).toList();
          add(ChatEvent.didLoadLatestMessages(messages));
        }
      },
      prevMessageCallback: (list) {
        if (!isClosed) {
          final messages = list.messages.map(_createTextMessage).toList();
          add(ChatEvent.didLoadPreviousMessages(messages, list.hasMore));
        }
      },
      finishStreamingCallback: () async {
        if (isClosed) {
          return;
        }

        add(const ChatEvent.didFinishAnswerStream());

        // The answer stream will bet set to null after the streaming has
        // finished, got cancelled, or errored. In this case, don't retrieve
        // related questions.
        if (answerStream == null || lastSentMessage == null) {
          return;
        }

        final payload = ChatMessageIdPB(
          chatId: chatId,
          messageId: lastSentMessage!.messageId,
        );

        // when previous numSendMessage is not equal to current numSendMessage, it means that the user
        // has sent a new message. So we don't need to get related questions.
        final preNumSendMessage = numSendMessage;
        await AIEventGetRelatedQuestion(payload).send().fold(
          (list) {
            if (!isClosed && preNumSendMessage == numSendMessage) {
              add(
                ChatEvent.didReceiveRelatedQuestions(
                  list.items.map((e) => e.content).toList(),
                ),
              );
            }
          },
          (err) => Log.error("Failed to get related questions: $err"),
        );
      },
    );
  }

  void _loadSetting() async {
    final getChatSettingsPayload =
        AIEventGetChatSettings(ChatId(value: chatId));
    await getChatSettingsPayload.send().fold(
      (settings) {
        if (!isClosed) {
          add(ChatEvent.didReceiveChatSettings(settings: settings));
        }
      },
      Log.error,
    );
  }

  void _loadMessages() async {
    final loadMessagesPayload = LoadNextChatMessagePB(
      chatId: chatId,
      limit: Int64(10),
    );
    await AIEventLoadNextMessage(loadMessagesPayload).send().fold(
      (list) {
        if (!isClosed) {
          final messages = list.messages.map(_createTextMessage).toList();
          add(ChatEvent.didLoadLatestMessages(messages));
        }
      },
      (err) => Log.error("Failed to load messages: $err"),
    );
  }

  bool _isOneTimeMessage(Message message) {
    return message.metadata != null &&
        message.metadata!.containsKey(onetimeShotType);
  }

  /// get the last message that is not a one-time message
  Message? _getOldestMessage() {
    return chatController.messages
        .firstWhereOrNull((message) => !_isOneTimeMessage(message));
  }

  void _loadPreviousMessages(Int64? beforeMessageId) {
    final payload = LoadPrevChatMessagePB(
      chatId: chatId,
      limit: Int64(10),
      beforeMessageId: beforeMessageId,
    );
    AIEventLoadPrevMessage(payload).send();
  }

  Future<void> _startStreamingMessage(
    String message,
    Map<String, dynamic>? metadata,
  ) async {
    await answerStream?.dispose();

    answerStream = AnswerStream();
    final questionStream = QuestionStream();

    // add a streaming question message
    final questionStreamMessage = _createQuestionStreamMessage(
      questionStream,
      metadata,
    );
    add(ChatEvent.receiveMessage(questionStreamMessage));

    final payload = StreamChatPayloadPB(
      chatId: chatId,
      message: message,
      messageType: ChatMessageTypePB.User,
      questionStreamPort: Int64(questionStream.nativePort),
      answerStreamPort: Int64(answerStream!.nativePort),
      metadata: await metadataPBFromMetadata(metadata),
    );

    // stream the question to the server
    await AIEventStreamMessage(payload).send().fold(
      (question) {
        if (!isClosed) {
          final streamAnswer = _createAnswerStreamMessage(
            answerStream!,
            question.messageId,
          );

          lastSentMessage = question;
          add(const ChatEvent.finishSending());
          add(ChatEvent.receiveMessage(streamAnswer));
        }
      },
      (err) {
        if (!isClosed) {
          Log.error("Failed to send message: ${err.msg}");

          final metadata = {
            onetimeShotType: OnetimeShotType.error,
            if (err.code != ErrorCode.Internal) errorMessageTextKey: err.msg,
          };

          final error = TextMessage(
            text: '',
            metadata: metadata,
            author: const User(id: systemUserId),
            id: systemUserId,
            createdAt: DateTime.now(),
          );

          add(const ChatEvent.failedSending());
          add(ChatEvent.receiveMessage(error));
        }
      },
    );
  }

  void _regenerateAnswer(String answerMessageIdString) async {
    final id = temporaryMessageIDMap.entries
            .firstWhereOrNull((e) => e.value == answerMessageIdString)
            ?.key ??
        answerMessageIdString;
    final answerMessageId = Int64.tryParseInt(id);

    if (answerMessageId == null) {
      return;
    }

    await answerStream?.dispose();
    answerStream = AnswerStream();

    final payload = RegenerateResponsePB(
      chatId: chatId,
      answerMessageId: answerMessageId,
      answerStreamPort: Int64(answerStream!.nativePort),
    );

    await AIEventRegenerateResponse(payload).send().fold(
      (success) {
        if (!isClosed) {
          final streamAnswer = _createAnswerStreamMessage(
            answerStream!,
            answerMessageId - 1,
          ).copyWith(id: answerMessageIdString);

          add(ChatEvent.receiveMessage(streamAnswer));
          add(const ChatEvent.finishSending());
        }
      },
      (err) => Log.error("Failed to send message: ${err.msg}"),
    );
  }

  Message _createAnswerStreamMessage(
    AnswerStream stream,
    Int64 questionMessageId,
  ) {
    answerStreamMessageId = (questionMessageId + 1).toString();

    return TextMessage(
      id: answerStreamMessageId,
      text: '',
      author: User(id: "streamId:${nanoid()}"),
      metadata: {
        "$AnswerStream": stream,
        messageQuestionIdKey: questionMessageId,
        "chatId": chatId,
      },
      createdAt: DateTime.now(),
    );
  }

  Message _createQuestionStreamMessage(
    QuestionStream stream,
    Map<String, dynamic>? sentMetadata,
  ) {
    final now = DateTime.now();

    questionStreamMessageId = (now.millisecondsSinceEpoch ~/ 1000).toString();

    return TextMessage(
      author: User(id: userId),
      metadata: {
        "$QuestionStream": stream,
        "chatId": chatId,
        messageChatFileListKey: chatFilesFromMessageMetadata(sentMetadata),
      },
      id: questionStreamMessageId,
      createdAt: now,
      text: '',
    );
  }

  Message _createTextMessage(ChatMessagePB message) {
    String messageId = message.messageId.toString();

    /// If the message id is in the temporary map, we will use the previous fake message id
    if (temporaryMessageIDMap.containsKey(messageId)) {
      messageId = temporaryMessageIDMap[messageId]!;
    }

    return TextMessage(
      author: User(id: message.authorId),
      id: messageId,
      text: message.content,
      createdAt: message.createdAt.toDateTime(),
      metadata: {
        messageRefSourceJsonStringKey: message.metadata,
      },
    );
  }

  void _clearRelatedQuestions() {
    final relatedQuestionMessages = chatController.messages
        .where(
          (message) =>
              onetimeMessageTypeFromMeta(message.metadata) ==
              OnetimeShotType.relatedQuestion,
        )
        .toList();

    for (final message in relatedQuestionMessages) {
      chatController.remove(message);
    }
  }
}

@freezed
class ChatEvent with _$ChatEvent {
  // chat settings
  const factory ChatEvent.didReceiveChatSettings({
    required ChatSettingsPB settings,
  }) = _DidReceiveChatSettings;
  const factory ChatEvent.updateSelectedSources({
    required List<String> selectedSourcesIds,
  }) = _UpdateSelectedSources;

  const factory ChatEvent.setRagOnly({
    required bool ragOnly,
  }) = _SetRagOnly;

  // send message
  const factory ChatEvent.sendMessage({
    required String message,
    Map<String, dynamic>? metadata,
  }) = _SendMessage;
  const factory ChatEvent.finishSending() = _FinishSendMessage;
  const factory ChatEvent.failedSending() = _FailSendMessage;

  // regenerate
  const factory ChatEvent.regenerateAnswer(String id) = _RegenerateAnswer;

  // streaming answer
  const factory ChatEvent.stopStream() = _StopStream;
  const factory ChatEvent.didFinishAnswerStream() = _DidFinishAnswerStream;

  // receive message
  const factory ChatEvent.receiveMessage(Message message) = _ReceiveMessage;

  // loading messages
  const factory ChatEvent.didLoadLatestMessages(List<Message> messages) =
      _DidLoadMessages;
  const factory ChatEvent.loadPreviousMessages() = _LoadPreviousMessages;
  const factory ChatEvent.didLoadPreviousMessages(
    List<Message> messages,
    bool hasMore,
  ) = _DidLoadPreviousMessages;

  // related questions
  const factory ChatEvent.didReceiveRelatedQuestions(
    List<String> questions,
  ) = _DidReceiveRelatedQueston;
}

@freezed
class ChatState with _$ChatState {
  const factory ChatState({
    required bool onlyUseSelectedSources,
    required List<String> selectedSourceIds,
    required LoadChatMessageStatus loadingState,
    required PromptResponseState promptResponseState,
  }) = _ChatState;

  factory ChatState.initial() => const ChatState(
        onlyUseSelectedSources: false,
        selectedSourceIds: [],
        loadingState: LoadChatMessageStatus.loading,
        promptResponseState: PromptResponseState.ready,
      );
}

bool isOtherUserMessage(Message message) {
  return message.author.id != aiResponseUserId &&
      message.author.id != systemUserId &&
      !message.author.id.startsWith("streamId:");
}
