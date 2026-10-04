import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/translations.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.onSuccessfulAuth});

  final void Function()? onSuccessfulAuth;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _localAuth = LocalAuthentication();
  bool _running = false;
  bool _promptActive = false;
  bool _authenticated = false;
  String? _error;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          SchedulerBinding.instance.lifecycleState !=
              AppLifecycleState.paused) {
        auth();
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          SystemNavigator.pop();
        }
      },
      child: Material(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, size: 36),
              const SizedBox(height: 16),
              Text("Authentication Required".tl),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: _running || _authenticated ? null : auth,
                child: Text("Continue".tl),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> auth() async {
    if (!mounted || _running || _authenticated) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!mounted) return;
      final supported =
          canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!mounted) return;
      var isAuthorized = !supported;
      if (supported) {
        _promptActive = true;
        isAuthorized = await _localAuth.authenticate(
          localizedReason: "Please authenticate to continue".tl,
        );
      }
      if (mounted && isAuthorized) {
        _authenticated = true;
        widget.onSuccessfulAuth?.call();
      }
    } catch (error, stack) {
      if (!mounted) return;
      Log.error('Authentication', error, stack);
      setState(() => _error = "Please authenticate to continue".tl);
    } finally {
      _promptActive = false;
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    if (_promptActive) {
      unawaited(
        _localAuth.stopAuthentication().catchError((Object error) {
          Log.warning('Authentication', error.toString());
          return false;
        }),
      );
    }
    super.dispose();
  }
}
