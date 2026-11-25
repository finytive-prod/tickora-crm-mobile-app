import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/core/services/oauth_service.dart';
import 'package:crm_mobile/core/services/secure_token_storage.dart';
import 'package:crm_mobile/models/user.dart';

class TestLinks extends Fake implements AppLinks {
  @override
  Stream<Uri> get uriLinkStream => const Stream.empty();
  @override
  Future<Uri?> getInitialLink() async => null;
}

class CallbackService extends OAuthService {
  CallbackService(SecureTokenStorage storage, SharedPreferences prefs)
    : super(
        tokenStorage: storage,
        sharedPreferences: prefs,
        appLinks: TestLinks(),
      );
  int exchanges = 0;
  String expectedVerifier = 'test-verifier';
  final exchangeStarted = Completer<void>();
  Completer<void>? gate;
  @override
  Future<User> exchangeAuthorizationCode({
    required String code,
    required String codeVerifier,
  }) async {
    exchanges++;
    if (!exchangeStarted.isCompleted) exchangeStarted.complete();
    expect(codeVerifier, expectedVerifier);
    if (gate != null) await gate!.future;
    return const User(
      accessToken: 'test-access',
      expiresIn: 1800,
      tokenType: 'Bearer',
      userId: 'local-crm-user',
      userName: 'Staff',
      role: 'STAFF',
      privileges: [],
    );
  }
}

class RefreshAdapter implements HttpClientAdapter {
  int calls = 0;
  int status = 200;
  Completer<void>? gate;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (gate != null) await gate!.future;
    return ResponseBody.fromString(
      jsonEncode(
        status == 200
            ? {
                'accessToken': 'renewed-access',
                'refreshToken': 'rotated-refresh',
                'expiresIn': 1800,
              }
            : {'error': 'temporarily_unavailable'},
      ),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.crm_mobile/call_recording');
  late SharedPreferences prefs;
  late SecureTokenStorage storage;
  late CallbackService service;
  late List<OAuthCallbackResult> events;
  late StreamSubscription<OAuthCallbackResult> subscription;

  Uri callback(String code, String state) => Uri.parse(
    ApiUrl.mobileRedirectUri,
  ).replace(queryParameters: {'code': code, 'state': state});
  Future<void> pending(String state) =>
      storage.savePendingPkce(codeVerifier: 'test-verifier', state: state);
  Future<void> drain() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = SecureTokenStorage(sharedPreferences: prefs);
    service = CallbackService(storage, prefs);
    events = [];
    subscription = service.callbackStream.listen(events.add);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => true);
  });
  tearDown(() async {
    await subscription.cancel();
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'duplicate callbacks after successful exchange do not report expired state',
    () async {
      await pending('login-one');
      final uri = callback('code-one', 'login-one');
      await service.handleAuthorizationCallback(uri);
      await service.handleAuthorizationCallback(uri);
      await drain();
      expect(service.exchanges, 1);
      expect(events.length, 1);
      expect(events.single.isSuccess, isTrue);
      expect(await storage.getPendingState(), isNull);
    },
  );

  test('concurrent native and app-link delivery exchanges once', () async {
    await pending('login-one');
    service.gate = Completer<void>();
    final uri = callback('code-one', 'login-one');
    final first = service.handleAuthorizationCallback(uri);
    final second = service.handleAuthorizationCallback(uri);
    await service.exchangeStarted.future;
    expect(service.exchanges, 1);
    service.gate!.complete();
    await Future.wait([first, second]);
    await drain();
    expect(events.length, 1);
    expect(events.single.isSuccess, isTrue);
  });

  test('stale callback cannot erase a different pending login', () async {
    await pending('new-login');
    await service.handleAuthorizationCallback(
      callback('old-code', 'old-login'),
    );
    await drain();
    expect(await storage.getPendingState(), 'new-login');
    expect(service.exchanges, 0);
    expect(events, isEmpty);
    await service.handleAuthorizationCallback(
      callback('new-code', 'new-login'),
    );
    await drain();
    expect(events.single.isSuccess, isTrue);
  });

  test(
    'foreign callback endpoint and missing state cannot consume PKCE',
    () async {
      await pending('valid-state');
      final uri = callback('code', 'valid-state');
      await service.handleAuthorizationCallback(
        uri.replace(host: 'untrusted.example'),
      );
      await service.handleAuthorizationCallback(
        uri.replace(path: '/other/callback'),
      );
      await service.handleAuthorizationCallback(
        uri.replace(queryParameters: {'code': 'code'}),
      );
      expect(await storage.getPendingState(), 'valid-state');
      expect(service.exchanges, 0);
      expect(events, isEmpty);
    },
  );

  test('five successive logins tolerate repeated callbacks', () async {
    for (var i = 0; i < 5; i++) {
      await pending('state-$i');
      final uri = callback('code-$i', 'state-$i');
      await service.handleAuthorizationCallback(uri);
      await service.handleAuthorizationCallback(uri);
    }
    await drain();
    expect(service.exchanges, 5);
    expect(events.length, 5);
    expect(events.every((event) => event.isSuccess), isTrue);
  });

  test(
    'repeated sign-in taps preserve the pending browser transaction',
    () async {
      final browser = Completer<String?>();
      var opens = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'openOAuthWebView') {
              opens++;
              return browser.future;
            }
            if (call.method == 'closeOAuthWebView' && !browser.isCompleted) {
              browser.complete(null);
            }
            return true;
          });
      final first = service.startAuthorizationFlow();
      await drain();
      final state = await storage.getPendingState();
      expect(await service.startAuthorizationFlow(), isTrue);
      expect(await storage.getPendingState(), state);
      expect(opens, 1);
      await service.cancelAuthorizationFlow();
      await first;
      expect(await storage.getPendingState(), isNull);
    },
  );

  test(
    'app-link success can close the native dialog without cancelling login',
    () async {
      final browser = Completer<String?>();
      final opened = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'openOAuthWebView') {
              opened.complete();
              return browser.future;
            }
            if (call.method == 'closeOAuthWebView' && !browser.isCompleted) {
              browser.complete(null);
            }
            return true;
          });
      final flow = service.startAuthorizationFlow();
      await opened.future;
      service.expectedVerifier = (await storage.getPendingVerifier())!;
      final state = (await storage.getPendingState())!;
      await service.handleAuthorizationCallback(callback('code-one', state));
      expect(await flow, isTrue);
      await drain();
      expect(events.length, 1);
      expect(events.single.isSuccess, isTrue);
      expect(await storage.getPendingState(), isNull);
    },
  );

  test('simultaneous refresh calls rotate the refresh token once', () async {
    await storage.saveTokens(
      accessToken: 'expired',
      refreshToken: 'original-refresh',
      expiresIn: 1,
    );
    final adapter = RefreshAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final oauth = OAuthService(
      tokenStorage: storage,
      sharedPreferences: prefs,
      dio: dio,
      appLinks: TestLinks(),
    );
    try {
      final results = await Future.wait(
        List.generate(8, (_) => oauth.refreshToken()),
      );
      expect(results, everyElement('renewed-access'));
      expect(adapter.calls, 1);
      expect(await storage.getRefreshToken(), 'rotated-refresh');
    } finally {
      oauth.dispose();
    }
  });

  test('temporary refresh failure preserves the stored session', () async {
    await storage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'original-refresh',
      expiresIn: 1800,
    );
    final dio = Dio()..httpClientAdapter = (RefreshAdapter()..status = 503);
    final oauth = OAuthService(
      tokenStorage: storage,
      sharedPreferences: prefs,
      dio: dio,
      appLinks: TestLinks(),
    );
    try {
      expect(await oauth.refreshToken(), isNull);
      expect(await storage.getRefreshToken(), 'original-refresh');
      expect(await storage.getAccessToken(), 'old-access');
    } finally {
      oauth.dispose();
    }
  });

  test('an in-flight refresh cannot restore tokens after logout', () async {
    await storage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'original-refresh',
      expiresIn: 1800,
    );
    final adapter = RefreshAdapter()..gate = Completer<void>();
    final dio = Dio()..httpClientAdapter = adapter;
    final oauth = OAuthService(
      tokenStorage: storage,
      sharedPreferences: prefs,
      dio: dio,
      appLinks: TestLinks(),
    );
    try {
      final renewal = oauth.refreshToken();
      await drain();
      final logout = oauth.logout();
      await drain();
      adapter.gate!.complete();
      await logout;
      expect(await renewal, isNull);
      expect(await storage.getRefreshToken(), isNull);
      expect(await storage.getAccessToken(), isNull);
    } finally {
      oauth.dispose();
    }
  });
}
