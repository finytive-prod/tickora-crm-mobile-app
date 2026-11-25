import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureTokenStorage {
  static const String _keyAccessToken = 'oauth_access_token';
  static const String _keyRefreshToken = 'oauth_refresh_token';
  static const String _keyTokenType = 'oauth_token_type';
  static const String _keyTokenExpiresAt = 'oauth_token_expires_at';
  static const String _keyPendingVerifier = 'oauth_code_verifier';
  static const String _keyPendingState = 'oauth_state';

  final FlutterSecureStorage _storage;
  final SharedPreferences _sharedPreferences;

  SecureTokenStorage({
    FlutterSecureStorage? storage,
    required SharedPreferences sharedPreferences,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        _sharedPreferences = sharedPreferences;

  /// Saves the OAuth access and refresh tokens securely with their expiration time.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
    String tokenType = 'Bearer',
  }) async {
    final validExpiresIn = expiresIn > 0 ? expiresIn : 86400; // default 24h if missing
    final expiresAtMs = DateTime.now().millisecondsSinceEpoch + (validExpiresIn * 1000);

    try {
      await Future.wait([
        _storage.write(key: _keyAccessToken, value: accessToken),
        if (refreshToken.isNotEmpty)
          _storage.write(key: _keyRefreshToken, value: refreshToken),
        _storage.write(key: _keyTokenType, value: tokenType),
        _storage.write(key: _keyTokenExpiresAt, value: expiresAtMs.toString()),
      ]);
    } catch (e) {
      debugPrint('SecureTokenStorage: secure write warning (falling back to prefs): $e');
    }

    // Mirror to SharedPreferences for resilience against Android KeyStore corruption
    await _sharedPreferences.setString('token', accessToken);
    await _sharedPreferences.setString(_keyAccessToken, accessToken);
    if (refreshToken.isNotEmpty) {
      await _sharedPreferences.setString(_keyRefreshToken, refreshToken);
    }
    await _sharedPreferences.setString(_keyTokenType, tokenType);
    await _sharedPreferences.setString(_keyTokenExpiresAt, expiresAtMs.toString());
  }

  /// Retrieves the current token type (typically 'Bearer').
  Future<String?> getTokenType() async {
    try {
      final type = await _storage.read(key: _keyTokenType);
      if (type != null && type.isNotEmpty) return type;
    } catch (e) {
      debugPrint('SecureTokenStorage: getTokenType error: $e');
    }
    return _sharedPreferences.getString(_keyTokenType) ?? 'Bearer';
  }

  /// Retrieves the current access token from secure storage or fallback preferences.
  Future<String?> getAccessToken() async {
    try {
      final token = await _storage.read(key: _keyAccessToken);
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (e) {
      debugPrint('SecureTokenStorage: getAccessToken error: $e');
    }

    // Fallback migration check from SharedPreferences
    final legacyToken = _sharedPreferences.getString('token') ??
        _sharedPreferences.getString(_keyAccessToken);
    if (legacyToken != null && legacyToken.isNotEmpty) {
      try {
        await _storage.write(key: _keyAccessToken, value: legacyToken);
      } catch (_) {}
      return legacyToken;
    }
    return null;
  }

  /// Retrieves the current refresh token from secure storage or fallback preferences.
  Future<String?> getRefreshToken() async {
    try {
      final token = await _storage.read(key: _keyRefreshToken);
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (e) {
      debugPrint('SecureTokenStorage: getRefreshToken error: $e');
    }

    final fallback = _sharedPreferences.getString(_keyRefreshToken);
    if (fallback != null && fallback.isNotEmpty) {
      try {
        await _storage.write(key: _keyRefreshToken, value: fallback);
      } catch (_) {}
      return fallback;
    }
    return null;
  }

  /// Retrieves token expiration epoch timestamp in milliseconds.
  Future<int?> getTokenExpiresAt() async {
    try {
      final raw = await _storage.read(key: _keyTokenExpiresAt);
      if (raw != null) {
        final parsed = int.tryParse(raw);
        if (parsed != null && parsed > 0) return parsed;
      }
    } catch (e) {
      debugPrint('SecureTokenStorage: getTokenExpiresAt error: $e');
    }

    final fallbackRaw = _sharedPreferences.getString(_keyTokenExpiresAt);
    if (fallbackRaw != null) {
      return int.tryParse(fallbackRaw);
    }
    return null;
  }

  /// Returns true if the token is already expired or within [buffer] of expiring.
  Future<bool> isTokenExpired({Duration buffer = const Duration(seconds: 30)}) async {
    final expiresAt = await getTokenExpiresAt();
    if (expiresAt != null && expiresAt > 0) {
      final expirationDate = DateTime.fromMillisecondsSinceEpoch(expiresAt);
      return DateTime.now().add(buffer).isAfter(expirationDate);
    }

    // If explicit expires_at is not recorded, check JWT 'exp' claim if possible
    final token = await getAccessToken();
    if (token == null || token.isEmpty) return true;

    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = parts[1];
        final normalized = base64Url.normalize(payload);
        final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
        if (decoded is Map && decoded.containsKey('exp')) {
          final exp = decoded['exp'] as int;
          final expDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
          return DateTime.now().add(buffer).isAfter(expDate);
        }
      }
    } catch (_) {}

    // If expiration cannot be parsed, treat as valid so we don't preemptively log out
    return false;
  }

  /// Securely stores the pending PKCE code_verifier and state during the authorization flow.
  Future<void> savePendingPkce({
    required String codeVerifier,
    required String state,
  }) async {
    try {
      await Future.wait([
        _storage.write(key: _keyPendingVerifier, value: codeVerifier),
        _storage.write(key: _keyPendingState, value: state),
      ]);
    } catch (_) {}
    await _sharedPreferences.setString(_keyPendingVerifier, codeVerifier);
    await _sharedPreferences.setString(_keyPendingState, state);
  }

  /// Retrieves the pending PKCE code verifier.
  Future<String?> getPendingVerifier() async {
    try {
      final v = await _storage.read(key: _keyPendingVerifier);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return _sharedPreferences.getString(_keyPendingVerifier);
  }

  /// Retrieves the pending PKCE state.
  Future<String?> getPendingState() async {
    try {
      final s = await _storage.read(key: _keyPendingState);
      if (s != null && s.isNotEmpty) return s;
    } catch (_) {}
    return _sharedPreferences.getString(_keyPendingState);
  }

  /// Clears the pending PKCE verifier and state after exchange or failure.
  Future<void> clearPendingPkce() async {
    try {
      await Future.wait([
        _storage.delete(key: _keyPendingVerifier),
        _storage.delete(key: _keyPendingState),
      ]);
    } catch (_) {}
    await _sharedPreferences.remove(_keyPendingVerifier);
    await _sharedPreferences.remove(_keyPendingState);
  }

  /// Clears all tokens securely on logout or session expiration.
  Future<void> clearTokens() async {
    try {
      await Future.wait([
        _storage.delete(key: _keyAccessToken),
        _storage.delete(key: _keyRefreshToken),
        _storage.delete(key: _keyTokenType),
        _storage.delete(key: _keyTokenExpiresAt),
        _storage.delete(key: _keyPendingVerifier),
        _storage.delete(key: _keyPendingState),
      ]);
    } catch (_) {}
    await _sharedPreferences.remove('token');
    await _sharedPreferences.remove(_keyAccessToken);
    await _sharedPreferences.remove(_keyRefreshToken);
    await _sharedPreferences.remove(_keyTokenType);
    await _sharedPreferences.remove(_keyTokenExpiresAt);
    await _sharedPreferences.remove(_keyPendingVerifier);
    await _sharedPreferences.remove(_keyPendingState);
  }

  /// Checks if there is any stored session token.
  Future<bool> hasValidSession() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
