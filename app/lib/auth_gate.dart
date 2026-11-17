import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_session.dart';
import 'inventory_repository.dart';
import 'inventory_theme.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.session,
    required this.navigatorKey,
    required this.homeBuilder,
  });

  final AuthSession session;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget Function(InventoryRepository repository, VoidCallback logout)
      homeBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool checking = true;
  String? connectionError;
  late final repo = HttpInventoryRepository(
      base: widget.session.base, client: widget.session.client);

  @override
  void initState() {
    super.initState();
    widget.session.addListener(changed);
    restore();
  }

  void changed() {
    if (!mounted) return;
    setState(() {});
    if (widget.session.user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
  }

  Future<void> restore() async {
    setState(() {
      checking = true;
      connectionError = null;
    });
    try {
      await widget.session.restore();
    } catch (error) {
      if (mounted) setState(() => connectionError = '$error');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> logout() async {
    try {
      await widget.session.logout();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (connectionError != null) {
      return Scaffold(
          body: Center(
              child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(connectionError!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: restore, child: const Text('Reintentar')),
        ]),
      )));
    }
    if (widget.session.user != null) return widget.homeBuilder(repo, logout);
    return LoginPage(session: widget.session);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});
  final AuthSession session;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.login(username.text, password.text);
      if (mounted) TextInput.finishAutofillContext();
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SheetSurface(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                  child: Form(
                key: form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Inventario TI',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      const Text('Ingresa con tu cuenta de TI.'),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: username,
                        enabled: !busy,
                        autofocus: true,
                        autofillHints: const [AutofillHints.username],
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Usuario'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Escribe tu usuario'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        enabled: !busy,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        autocorrect: false,
                        enableSuggestions: false,
                        onFieldSubmitted: (_) => submit(),
                        decoration:
                            const InputDecoration(labelText: 'Contraseña'),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Escribe tu contraseña'
                            : null,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                            liveRegion: true,
                            child: Text(error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                          onPressed: busy ? null : submit,
                          child: Text(busy ? 'Ingresando…' : 'Ingresar')),
                    ]),
              )),
            )),
          ),
        ),
      )));
}
