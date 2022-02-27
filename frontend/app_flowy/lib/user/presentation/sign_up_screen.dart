import 'package:app_flowy/startup/startup.dart';
import 'package:app_flowy/user/application/sign_up_bloc.dart';
import 'package:app_flowy/user/infrastructure/router.dart';
import 'package:app_flowy/user/presentation/widgets/background.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/rounded_button.dart';
import 'package:flowy_infra_ui/widget/rounded_input_field.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flowy_sdk/protobuf/flowy-error/errors.pb.dart';
import 'package:flowy_sdk/protobuf/flowy-user-data-model/protobuf.dart' show UserProfile;
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:flowy_infra/image.dart';
import 'package:app_flowy/generated/locale_keys.g.dart';

class SignUpScreen extends StatelessWidget {
  final AuthRouter router;
  const SignUpScreen({Key? key, required this.router}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<SignUpBloc>(),
      child: BlocListener<SignUpBloc, SignUpState>(
        listener: (context, state) {
          state.successOrFail.fold(
            () => {},
            (result) => _handleSuccessOrFail(context, result),
          );
        },
        child: const Scaffold(body: SignUpForm()),
      ),
    );
  }

  void _handleSuccessOrFail(BuildContext context, Either<UserProfile, FlowyError> result) {
    result.fold(
      (user) => router.pushWelcomeScreen(context, user),
      (error) => showSnapBar(context, error.msg),
    );
  }
}

class SignUpForm extends StatelessWidget {
  const SignUpForm({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: AuthFormContainer(
        children: [
          FlowyLogoTitle(
            title: LocaleKeys.signUp_title.tr(),
            logoSize: const Size(60, 60),
          ),
          const VSpace(30),
          const EmailTextField(),
          const PasswordTextField(),
          const RepeatPasswordTextField(),
          const VSpace(30),
          const SignUpButton(),
          const VSpace(10),
          const SignUpPrompt(),
          if (context.read<SignUpBloc>().state.isSubmitting) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(value: null),
          ]
        ],
      ),
    );
  }
}

class SignUpPrompt extends StatelessWidget {
  const SignUpPrompt({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(LocaleKeys.signUp_alreadyHaveAnAccount.tr(), style: Theme.of(context).textTheme.subtitle2),
        TextButton(
          style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 12)),
          onPressed: () => Navigator.pop(context),
          child: Text(LocaleKeys.signIn_buttonText.tr(), style: TextStyle(color: Theme.of(context).primaryColor)),
        ),
      ],
      mainAxisAlignment: MainAxisAlignment.center,
    );
  }
}

class SignUpButton extends StatelessWidget {
  const SignUpButton({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RoundedTextButton(
      title: LocaleKeys.signUp_getStartedText.tr(),
      height: 48,
      color: Theme.of(context).primaryColor,
      onPressed: () {
        context.read<SignUpBloc>().add(const SignUpEvent.signUpWithUserEmailAndPassword());
      },
    );
  }
}

class PasswordTextField extends StatelessWidget {
  const PasswordTextField({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SignUpBloc, SignUpState>(
      buildWhen: (previous, current) => previous.passwordError != current.passwordError,
      builder: (context, state) {
        return RoundedInputField(
          obscureText: true,
          obscureIcon: svg("home/hide"),
          obscureHideIcon: svg("home/show"),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          hintText: LocaleKeys.signUp_passwordHint.tr(),
          normalBorderColor: Colors.transparent,
          highlightBorderColor: Theme.of(context).primaryColor,
          cursorColor: Theme.of(context).primaryColor,
          errorText: context.read<SignUpBloc>().state.passwordError.fold(() => "", (error) => error),
          onChanged: (value) => context.read<SignUpBloc>().add(SignUpEvent.passwordChanged(value)),
        );
      },
    );
  }
}

class RepeatPasswordTextField extends StatelessWidget {
  const RepeatPasswordTextField({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SignUpBloc, SignUpState>(
      buildWhen: (previous, current) => previous.repeatPasswordError != current.repeatPasswordError,
      builder: (context, state) {
        return RoundedInputField(
          obscureText: true,
          obscureIcon: svg("home/hide"),
          obscureHideIcon: svg("home/show"),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          hintText: LocaleKeys.signUp_repeatPasswordHint.tr(),
          normalBorderColor: Colors.transparent,
          highlightBorderColor: Theme.of(context).primaryColor,
          cursorColor: Theme.of(context).primaryColor,
          errorText: context.read<SignUpBloc>().state.repeatPasswordError.fold(() => "", (error) => error),
          onChanged: (value) => context.read<SignUpBloc>().add(SignUpEvent.repeatPasswordChanged(value)),
        );
      },
    );
  }
}

class EmailTextField extends StatelessWidget {
  const EmailTextField({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SignUpBloc, SignUpState>(
      buildWhen: (previous, current) => previous.emailError != current.emailError,
      builder: (context, state) {
        return RoundedInputField(
          hintText: LocaleKeys.signUp_emailHint.tr(),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          normalBorderColor: Colors.transparent,
          highlightBorderColor: Theme.of(context).primaryColor,
          cursorColor: Theme.of(context).primaryColor,
          errorText: context.read<SignUpBloc>().state.emailError.fold(() => "", (error) => error),
          onChanged: (value) => context.read<SignUpBloc>().add(SignUpEvent.emailChanged(value)),
        );
      },
    );
  }
}
