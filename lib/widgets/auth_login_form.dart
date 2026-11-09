import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Campi email/password compatibili con i password manager su Flutter web.
///
/// [AutofillGroup] fa generare all'engine un `<form>` con `<input
/// autocomplete="username">` e `<input autocomplete="current-password">`
/// (quest'ultimo da [AutofillHints.password]) quando un campo riceve il focus.
class AuthLoginForm extends StatelessWidget {
  const AuthLoginForm({
    super.key,
    required this.email,
    required this.password,
    required this.onSubmit,
    this.busy = false,
    this.footer,
  });

  final TextEditingController email;
  final TextEditingController password;
  final VoidCallback onSubmit;
  final bool busy;
  final Widget? footer;

  static void markSaved() => TextInput.finishAutofillContext(shouldSave: true);

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: email,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: password,
            enabled: !busy,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: busy ? null : (_) => onSubmit(),
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          ?footer,
        ],
      ),
    );
  }
}
