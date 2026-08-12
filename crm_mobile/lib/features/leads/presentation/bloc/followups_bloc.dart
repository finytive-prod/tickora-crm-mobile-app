import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_followups_usecase.dart';
import '../../domain/usecases/get_lead_followups_usecase.dart';
import '../../domain/usecases/update_followup_usecase.dart';
import 'followups_event.dart';
import 'followups_state.dart';

class FollowUpsBloc extends Bloc<FollowUpsEvent, FollowUpsState> {
  final GetFollowUpsUseCase getFollowUpsUseCase;
  final GetLeadFollowUpsUseCase getLeadFollowUpsUseCase;
  final UpdateFollowUpUseCase updateFollowUpUseCase;

  FollowUpsBloc({
    required this.getFollowUpsUseCase,
    required this.getLeadFollowUpsUseCase,
    required this.updateFollowUpUseCase,
  }) : super(FollowUpsInitial()) {
    on<FetchFollowUps>(_onFetchFollowUps);
    on<FetchLeadFollowUps>(_onFetchLeadFollowUps);
    on<UpdateFollowUp>(_onUpdateFollowUp);
  }

  Future<void> _onFetchFollowUps(FetchFollowUps event, Emitter<FollowUpsState> emit) async {
    emit(FollowUpsLoading());
    final result = await getFollowUpsUseCase(category: event.category, page: event.page, size: event.size);
    result.fold(
      (failure) => emit(FollowUpsError(failure.message)),
      (response) => emit(FollowUpsLoaded(response)),
    );
  }

  Future<void> _onFetchLeadFollowUps(FetchLeadFollowUps event, Emitter<FollowUpsState> emit) async {
    emit(LeadFollowUpsLoading());
    final result = await getLeadFollowUpsUseCase(event.leadId);
    result.fold(
      (failure) => emit(LeadFollowUpsError(failure.message)),
      (leadFollowUps) => emit(LeadFollowUpsLoaded(leadFollowUps)),
    );
  }

  Future<void> _onUpdateFollowUp(UpdateFollowUp event, Emitter<FollowUpsState> emit) async {
    emit(UpdateFollowUpLoading());
    final result = await updateFollowUpUseCase(event.followupId, event.updateData);
    result.fold(
      (failure) => emit(UpdateFollowUpError(failure.message)),
      (_) => emit(UpdateFollowUpSuccess()),
    );
  }
}
