import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'logging.dart';

/// Logs providers as they start, change, fail and go: the types of their
/// values, never the values.
final class StateLog extends ProviderObserver {
  const StateLog();

  static const _log = Logger('photolib.state');

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    _log.debug('provider added', fields: _fields(context, value));
    _retrying(context, value);
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    _log.debug('provider updated', fields: _fields(context, newValue));
    _retrying(context, newValue);
  }

  // Riverpod retries a provider that threw an Exception without calling
  // providerDidFail: its error shows only in the loading state.
  static void _retrying(ProviderObserverContext context, Object? value) {
    if (value case AsyncValue(
      retrying: true,
      :final error?,
      :final stackTrace,
    )) {
      _log.error(
        'provider failed',
        fields: {..._fields(context), 'retrying': true},
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) =>
      _log.debug('provider disposed', fields: _fields(context));

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) => _log.error(
    'provider failed',
    fields: _fields(context),
    error: error,
    stackTrace: stackTrace,
  );

  static Map<String, Object?> _fields(
    ProviderObserverContext context, [
    Object? value,
  ]) => {
    'provider': '${context.provider}',
    if (value != null) 'value': '${value.runtimeType}',
  };
}

/// Logs the routes pushed onto and popped off the root navigator.
class NavigationLog extends NavigatorObserver {
  static const _log = Logger('photolib.navigation');

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log.debug('push', fields: _fields(route, previousRoute));

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log.debug('pop', fields: _fields(route, previousRoute));

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _log.debug('replace', fields: _fields(newRoute, oldRoute));

  static Map<String, Object?> _fields(
    Route<dynamic>? route,
    Route<dynamic>? other,
  ) => {
    'route': route?.settings.name ?? '${route.runtimeType}',
    'other': other?.settings.name ?? '${other.runtimeType}',
  };
}
