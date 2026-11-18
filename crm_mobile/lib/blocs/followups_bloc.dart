import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/usecases/get_followups_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_followups_usecase.dart';
import 'package:crm_mobile/usecases/update_followup_usecase.dart';
import 'package:crm_mobile/usecases/add_followup_usecase.dart';
import 'package:crm_mobile/blocs/followups_event.dart';
import 'package:crm_mobile/blocs/followups_state.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/models/follow_up.dart';

class FollowUpsBloc extends Bloc<FollowUpsEvent, FollowUpsState> {
  final GetFollowUpsUseCase getFollowUpsUseCase;
  final GetLeadFollowUpsUseCase getLeadFollowUpsUseCase;
  final UpdateFollowUpUseCase updateFollowUpUseCase;
  final AddFollowUpUseCase? addFollowUpUseCase;

  FollowUpsBloc({
    required this.getFollowUpsUseCase,
    required this.getLeadFollowUpsUseCase,
    required this.updateFollowUpUseCase,
    this.addFollowUpUseCase,
  }) : super(FollowUpsInitial()) {
    on<FetchFollowUps>(_onFetchFollowUps);
    on<FetchLeadFollowUps>(_onFetchLeadFollowUps);
    on<UpdateFollowUp>(_onUpdateFollowUp);
    on<AddFollowUpEvent>(_onAddFollowUp);
  }

  Future<void> _onFetchFollowUps(FetchFollowUps event, Emitter<FollowUpsState> emit) async {
    if (event.isLoadMore && state is FollowUpsLoaded) {
      final currentLoaded = state as FollowUpsLoaded;
      emit(FollowUpsLoaded(currentLoaded.response, isLoadingMore: true));

      final result = await getFollowUpsUseCase(category: event.category, page: event.page, size: event.size, searchQuery: event.searchQuery);

      result.fold(
        (failure) => emit(FollowUpsLoaded(currentLoaded.response, isLoadingMore: false)),
        (newResponse) {
          _registerFollowUpPhones(newResponse.followUps);
          final combinedList = List<FollowUp>.from(currentLoaded.response.followUps)..addAll(newResponse.followUps);
          final updatedResponse = currentLoaded.response.copyWith(
            summary: newResponse.summary,
            followUps: combinedList,
            totalElements: newResponse.totalElements,
            totalPages: newResponse.totalPages,
            size: newResponse.size,
            number: newResponse.number,
            numberOfElements: combinedList.length,
            first: currentLoaded.response.first,
            last: newResponse.last,
            empty: newResponse.empty && combinedList.isEmpty,
          );
          emit(FollowUpsLoaded(updatedResponse, isLoadingMore: false));
        },
      );
    } else {
      if (!event.isRefresh) {
        emit(FollowUpsLoading());
      }
      final result = await getFollowUpsUseCase(category: event.category, page: event.page, size: event.size, searchQuery: event.searchQuery);
      result.fold(
        (failure) => emit(FollowUpsError(failure.message)),
        (response) {
          _registerFollowUpPhones(response.followUps);
          emit(FollowUpsLoaded(response));
        },
      );
    }
  }

  void _registerFollowUpPhones(Iterable<FollowUp> followUps) {
    for (final f in followUps) {
      if (f.leadId.trim().isEmpty) continue;
      AutoCallRecordingUploader.registerLeadPhones(
        leadId: f.leadId,
        primaryPhone: f.phoneNumber,
        alternatePhone: f.alternatePhone,
      );
    }
  }

  Future<void> _onFetchLeadFollowUps(FetchLeadFollowUps event, Emitter<FollowUpsState> emit) async {
    emit(LeadFollowUpsLoading());
    final result = await getLeadFollowUpsUseCase(event.leadId);
    result.fold(
      (failure) => emit(LeadFollowUpsError(failure.message)),
      (leadFollowUps) {
        AutoCallRecordingUploader.registerKnownLeads([
          leadFollowUps.leadDetails,
        ]);
        emit(LeadFollowUpsLoaded(leadFollowUps));
      },
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

  Future<void> _onAddFollowUp(AddFollowUpEvent event, Emitter<FollowUpsState> emit) async {
    if (addFollowUpUseCase == null) return;
    emit(AddFollowUpLoading());
    final result = await addFollowUpUseCase!(event.leadId, event.data);
    result.fold(
      (failure) => emit(AddFollowUpError(failure.message)),
      (_) => emit(AddFollowUpSuccess()),
    );
  }
}

