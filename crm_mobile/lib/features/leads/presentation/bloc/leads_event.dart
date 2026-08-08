import 'package:equatable/equatable.dart';

abstract class LeadsEvent extends Equatable {
  const LeadsEvent();

  @override
  List<Object> get props => [];
}

class FetchLeads extends LeadsEvent {
  final int page;
  final int size;
  final String? statusId;

  const FetchLeads({this.page = 0, this.size = 10, this.statusId});

  @override
  List<Object> get props => [page, size, if (statusId != null) statusId!];
}

class FetchLeadStatuses extends LeadsEvent {}
