import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_leads_usecase.dart';
import '../../domain/usecases/get_lead_statuses_usecase.dart';
import 'leads_event.dart';
import 'leads_state.dart';

class LeadsBloc extends Bloc<LeadsEvent, LeadsState> {
  final GetLeadsUseCase getLeadsUseCase;
  final GetLeadStatusesUseCase getLeadStatusesUseCase;

  LeadsBloc({
    required this.getLeadsUseCase,
    required this.getLeadStatusesUseCase,
  }) : super(LeadsInitial()) {
    on<FetchLeads>(_onFetchLeads);
    on<FetchLeadStatuses>(_onFetchLeadStatuses);
  }

  Future<void> _onFetchLeads(FetchLeads event, Emitter<LeadsState> emit) async {
    final currentState = state;
    List<dynamic>? currentStatuses;
    
    if (currentState is LeadsLoaded) {
      currentStatuses = currentState.statuses;
    }

    emit(LeadsLoading());
    final result = await getLeadsUseCase(event.page, event.size, statusId: event.statusId);

    result.fold(
      (failure) => emit(LeadsError(failure.message)),
      (leads) {
        List<dynamic> finalStatuses = currentStatuses ?? [];
        if (state is LeadsLoaded) {
          finalStatuses = (state as LeadsLoaded).statuses;
        }

        emit(LeadsLoaded(
          leads, 
          statuses: finalStatuses.cast(),
          selectedStatusId: event.statusId,
        ));
      },
    );
  }

  Future<void> _onFetchLeadStatuses(FetchLeadStatuses event, Emitter<LeadsState> emit) async {
    final result = await getLeadStatusesUseCase();
    result.fold(
      (failure) {
        // Just log or handle silently if we don't want to crash the whole screen for filters
        if (state is LeadsLoaded) {
          // Do nothing, keep existing state
        }
      },
      (statuses) {
        if (state is LeadsLoaded) {
          emit((state as LeadsLoaded).copyWith(statuses: statuses));
        } else {
          // If leads haven't loaded yet, we could potentially hold these in a different way,
          // but typically FetchLeads is called first. 
          emit(LeadsLoaded(const [], statuses: statuses));
        }
      },
    );
  }
}
