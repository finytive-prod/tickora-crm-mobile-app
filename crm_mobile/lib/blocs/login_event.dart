import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/user.dart';

abstract class LoginEvent extends Equatable {
  const LoginEvent();

  @override
  List<Object?> get props => [];
}

class LoginButtonPressed extends LoginEvent {
  final String email;
  final String password;

  const LoginButtonPressed({this.email = '', this.password = ''});

  @override
  List<Object?> get props => [email, password];
}

class LoginOAuthInitiated extends LoginEvent {
  final String? emailHint;

  const LoginOAuthInitiated({this.emailHint});

  @override
  List<Object?> get props => [emailHint];
}

class LoginOAuthCallbackReceived extends LoginEvent {
  final User user;

  const LoginOAuthCallbackReceived(this.user);

  @override
  List<Object?> get props => [user];
}

class LoginOAuthFailed extends LoginEvent {
  final String message;

  const LoginOAuthFailed(this.message);

  @override
  List<Object?> get props => [message];
}

class LoginOAuthCancelled extends LoginEvent {}
