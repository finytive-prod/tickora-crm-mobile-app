import 'package:equatable/equatable.dart';

class OAuthTokenResponse extends Equatable {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;

  const OAuthTokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
  });

  factory OAuthTokenResponse.fromJson(Map<String, dynamic> json) {
    final access = (json['accessToken'] ?? json['access_token'] ?? '').toString();
    final refresh = (json['refreshToken'] ?? json['refresh_token'] ?? '').toString();
    final type = (json['tokenType'] ?? json['token_type'] ?? 'Bearer').toString();

    int expires = 3600;
    final expVal = json['expiresIn'] ?? json['expires_in'];
    if (expVal is int) {
      expires = expVal;
    } else if (expVal is num) {
      expires = expVal.toInt();
    } else if (expVal != null) {
      expires = int.tryParse(expVal.toString()) ?? 3600;
    }

    return OAuthTokenResponse(
      accessToken: access,
      refreshToken: refresh,
      tokenType: type,
      expiresIn: expires,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'tokenType': tokenType,
      'expiresIn': expiresIn,
    };
  }

  @override
  List<Object?> get props => [accessToken, refreshToken, tokenType, expiresIn];
}
