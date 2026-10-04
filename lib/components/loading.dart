import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/file_interaction.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';
import 'package:venera_next/network/cloudflare.dart';
import 'package:venera_next/network/request_scope.dart';
import 'package:venera_next/routing/cloudflare.dart';

import 'appbar.dart';

class NetworkError extends StatelessWidget {
  const NetworkError({
    super.key,
    required this.message,
    this.retry,
    this.withAppbar = true,
    this.buttonText,
    this.action,
  });

  final String message;

  final void Function()? retry;

  final bool withAppbar;

  final String? buttonText;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    var cfe = CloudflareException.fromString(message);
    Widget body = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 28,
                  color: context.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  "Error".tl,
                  style: ts.withColor(context.colorScheme.error).s16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            cfe == null ? message : "Cloudflare verification required".tl,
            textAlign: TextAlign.center,
            maxLines: 3,
          ),
          TextButton(
            onPressed: () {
              saveFile(
                data: utf8.encode(Log().toString()),
                filename: 'log.txt',
              );
            },
            child: Text("Export logs".tl),
          ),
          const SizedBox(height: 8),
          if (retry != null)
            if (cfe != null)
              FilledButton(
                onPressed: () => passCloudflare(
                  CloudflareException.fromString(message)!,
                  retry!,
                ),
                child: Text('Verify'.tl),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (action != null) action!.paddingRight(8),
                  FilledButton(
                    onPressed: retry,
                    child: Text(buttonText ?? 'Retry'.tl),
                  ),
                ],
              ),
        ],
      ),
    );
    if (withAppbar) {
      body = Column(
        children: [
          const Appbar(title: Text("")),
          Expanded(child: body),
        ],
      );
    }
    return Material(child: body);
  }
}

class ListLoadingIndicator extends StatelessWidget {
  const ListLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      height: 80,
      child: Center(child: FiveDotLoadingAnimation()),
    );
  }
}

class SliverListLoadingIndicator extends StatelessWidget {
  const SliverListLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    // SliverToBoxAdapter can not been lazy loaded.
    // Use SliverList to make sure the animation can be lazy loaded.
    return SliverList.list(
      children: const [SizedBox(), ListLoadingIndicator()],
    );
  }
}

abstract class LoadingState<T extends StatefulWidget, S extends Object>
    extends State<T> {
  bool isLoading = false;

  S? data;

  String? error;

  RequestScope? _attempt;

  /// Implementations must check [scope] after awaits before publishing effects.
  Future<Res<S>> loadData(RequestScope scope);

  Future<Res<S>> _loadDataWithRetry(RequestScope scope) async {
    for (var retry = 0; ; retry++) {
      scope.check();
      final result = await loadData(scope);
      scope.check();
      if (result.success || retry >= 3) return result;
      await scope.wait(const Duration(milliseconds: 200));
    }
  }

  FutureOr<void> onDataLoaded(RequestScope scope) {}

  Widget buildContent(BuildContext context, S data);

  Widget? buildFrame(BuildContext context, Widget child) => null;

  Widget buildLoading() {
    return Center(
      child: const CircularProgressIndicator(
        strokeWidth: 2,
      ).fixWidth(32).fixHeight(32),
    );
  }

  bool _isCurrent(RequestScope scope) =>
      mounted && identical(_attempt, scope) && !scope.isCancelled;

  void retry() {
    if (!mounted) return;
    _attempt?.cancel();
    _attempt?.dispose();
    final scope = _attempt = RequestScope();
    setState(() {
      isLoading = true;
      error = null;
    });
    unawaited(_load(scope));
  }

  Future<void> _load(RequestScope scope) async {
    try {
      final result = await scope.run(() => _loadDataWithRetry(scope));
      if (!_isCurrent(scope)) return;
      if (result.success) {
        data = result.data;
        await scope.run(() => onDataLoaded(scope));
        if (!_isCurrent(scope)) return;
        setState(() => isLoading = false);
      } else {
        setState(() {
          isLoading = false;
          error = result.errorMessage!;
        });
      }
    } catch (exception, stack) {
      if (!_isCurrent(scope)) return;
      Log.error('Loading', exception, stack);
      setState(() {
        isLoading = false;
        error = exception.toString();
      });
    } finally {
      scope.dispose();
      if (identical(_attempt, scope)) _attempt = null;
    }
  }

  Widget buildError() {
    return NetworkError(message: error!, retry: retry);
  }

  @override
  @mustCallSuper
  void initState() {
    super.initState();
    isLoading = true;
    scheduleMicrotask(() {
      if (mounted && _attempt == null) retry();
    });
  }

  @override
  @mustCallSuper
  void dispose() {
    _attempt?.cancel();
    _attempt?.dispose();
    _attempt = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (isLoading) {
      child = buildLoading();
    } else if (error != null) {
      child = buildError();
    } else {
      child = buildContent(context, data!);
    }

    return buildFrame(context, child) ?? child;
  }
}

abstract class MultiPageLoadingState<T extends StatefulWidget, S extends Object>
    extends State<T> {
  bool _isFirstLoading = true;

  bool _isLoading = false;

  List<S>? data;

  String? _error;

  int _page = 1;

  int? _maxPage;

  RequestScope? _attempt;

  Future<Res<List<S>>> loadData(int page);

  Widget? buildFrame(BuildContext context, Widget child) => null;

  Widget buildContent(BuildContext context, List<S> data);

  bool get isLoading => _isLoading || _isFirstLoading;

  bool get isFirstLoading => _isFirstLoading;

  bool get haveNextPage => _maxPage == null || _page <= _maxPage!;

  void nextPage() {
    if (!mounted || isLoading || data == null || !haveNextPage) return;
    _isLoading = true;
    final scope = _attempt = RequestScope();
    unawaited(_load(scope, _page, first: false));
  }

  void reset() {
    if (!mounted) return;
    setState(() {
      _isFirstLoading = true;
      _isLoading = false;
      data = null;
      _error = null;
      _page = 1;
      _maxPage = null;
    });
    firstLoad();
  }

  bool _isCurrent(RequestScope scope) =>
      mounted && identical(_attempt, scope) && !scope.isCancelled;

  void firstLoad() {
    if (!mounted) return;
    _attempt?.cancel();
    _attempt?.dispose();
    final scope = _attempt = RequestScope();
    scheduleMicrotask(() {
      if (_isCurrent(scope)) unawaited(_load(scope, 1, first: true));
    });
  }

  Future<void> _load(
    RequestScope scope,
    int page, {
    required bool first,
  }) async {
    try {
      final result = await scope.run(() => loadData(page));
      if (!_isCurrent(scope)) return;
      if (result.success) {
        setState(() {
          _page = page + 1;
          if (result.subData is int) _maxPage = result.subData as int;
          if (first) {
            data = List<S>.of(result.data);
          } else {
            data!.addAll(result.data);
          }
          _isFirstLoading = false;
          _isLoading = false;
        });
      } else {
        _reportError(result.errorMessage ?? 'Network Error', first: first);
      }
    } catch (exception, stack) {
      if (!_isCurrent(scope)) return;
      Log.error('Loading', exception, stack);
      _reportError(exception.toString(), first: first);
    } finally {
      scope.dispose();
      if (identical(_attempt, scope)) _attempt = null;
    }
  }

  void _reportError(String message, {required bool first}) {
    setState(() {
      _isLoading = false;
      if (first) {
        _isFirstLoading = false;
        _error = message;
      }
    });
    if (!first) {
      if (message.length > 20) {
        message = '${message.substring(0, 20)}...';
      }
      context.showMessage(message: message);
    }
  }

  @override
  void dispose() {
    _attempt?.cancel();
    _attempt?.dispose();
    _attempt = null;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    firstLoad();
  }

  Widget buildLoading(BuildContext context) {
    return Center(
      child: const CircularProgressIndicator().fixWidth(32).fixHeight(32),
    );
  }

  Widget buildError(BuildContext context, String error) {
    return NetworkError(withAppbar: false, message: error, retry: reset);
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_isFirstLoading) {
      child = buildLoading(context);
    } else if (_error != null) {
      child = buildError(context, _error!);
    } else {
      child = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels ==
              notification.metrics.maxScrollExtent) {
            nextPage();
          }
          return false;
        },
        child: buildContent(context, data!),
      );
    }

    return buildFrame(context, child) ?? child;
  }
}

class FiveDotLoadingAnimation extends StatefulWidget {
  const FiveDotLoadingAnimation({super.key});

  @override
  State<FiveDotLoadingAnimation> createState() =>
      _FiveDotLoadingAnimationState();
}

class _FiveDotLoadingAnimationState extends State<FiveDotLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      upperBound: 6,
    )..repeat(min: 0, max: 5.2, period: const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _colors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
  ];

  static const _padding = 12.0;

  static const _dotSize = 12.0;

  static const _height = 24.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: _dotSize * 5 + _padding * 6,
          height: _height,
          child: Stack(children: List.generate(5, (index) => buildDot(index))),
        );
      },
    );
  }

  Widget buildDot(int index) {
    var value = _controller.value;
    var startValue = index * 0.8;
    return Positioned(
      left: index * _dotSize + (index + 1) * _padding,
      bottom:
          (math.sin(math.pi / 2 * (value - startValue).clamp(0, 2))) *
          (_height - _dotSize),
      child: Container(
        width: _dotSize,
        height: _dotSize,
        decoration: BoxDecoration(
          color: _colors[index],
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
