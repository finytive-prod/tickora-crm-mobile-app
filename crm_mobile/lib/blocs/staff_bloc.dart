import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/models/staff_stats.dart';
import 'package:crm_mobile/usecases/get_staff_members_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_stats_usecase.dart';
import 'package:crm_mobile/usecases/update_staff_member_usecase.dart';
import 'package:crm_mobile/usecases/toggle_staff_status_usecase.dart';
import 'package:crm_mobile/blocs/staff_event.dart';
import 'package:crm_mobile/blocs/staff_state.dart';

class StaffBloc extends Bloc<StaffEvent, StaffState> {
  final GetStaffMembersUseCase getStaffMembersUseCase;
  final GetStaffStatsUseCase getStaffStatsUseCase;
  final UpdateStaffMemberUseCase updateStaffMemberUseCase;
  final ToggleStaffStatusUseCase toggleStaffStatusUseCase;

  StaffBloc({
    required this.getStaffMembersUseCase,
    required this.getStaffStatsUseCase,
    required this.updateStaffMemberUseCase,
    required this.toggleStaffStatusUseCase,
  }) : super(StaffInitial()) {
    on<FetchStaffMembers>(_onFetchStaffMembers);
    on<LoadMoreStaffMembers>(_onLoadMoreStaffMembers);
    on<UpdateStaffMemberEvent>(_onUpdateStaffMember);
    on<ToggleStaffStatusEvent>(_onToggleStaffStatus);
  }

  Future<void> _onFetchStaffMembers(FetchStaffMembers event, Emitter<StaffState> emit) async {
    emit(StaffLoading());

    StaffStats? stats;
    final results = await Future.wait([
      getStaffStatsUseCase(),
      getStaffMembersUseCase(page: event.page, size: event.size, status: event.status),
    ]);

    final statsResult = results[0] as Either<Failure, StaffStats>;
    final membersResult = results[1] as Either<Failure, List<StaffMember>>;

    statsResult.fold((_) => null, (s) => stats = s);

    membersResult.fold(
      (failure) => emit(StaffError(failure.message)),
      (staffMembers) => emit(StaffLoaded(
        staffMembers: staffMembers,
        stats: stats,
        currentPage: event.page,
        hasMore: staffMembers.length >= event.size,
        currentStatus: event.status,
      )),
    );
  }

  Future<void> _onLoadMoreStaffMembers(LoadMoreStaffMembers event, Emitter<StaffState> emit) async {
    final currentState = state;
    if (currentState is StaffLoaded) {
      emit(currentState.copyWith(isLoadingMore: true));
      final result = await getStaffMembersUseCase(page: event.page, size: event.size, status: event.status);
      result.fold(
        (failure) => emit(currentState.copyWith(isLoadingMore: false)),
        (newStaff) => emit(StaffLoaded(
          staffMembers: [...currentState.staffMembers, ...newStaff],
          stats: currentState.stats,
          currentPage: event.page,
          hasMore: newStaff.length >= event.size,
          isLoadingMore: false,
          currentStatus: event.status,
        )),
      );
    }
  }

  Future<void> _onUpdateStaffMember(UpdateStaffMemberEvent event, Emitter<StaffState> emit) async {
    emit(StaffUpdateLoading());
    final result = await updateStaffMemberUseCase(event.id, event.data);
    result.fold(
      (failure) => emit(StaffUpdateError(failure.message)),
      (_) => emit(StaffUpdateSuccess()),
    );
  }

  Future<void> _onToggleStaffStatus(ToggleStaffStatusEvent event, Emitter<StaffState> emit) async {
    emit(StaffUpdateLoading());
    final result = await toggleStaffStatusUseCase(event.id, event.isActive);
    result.fold(
      (failure) => emit(StaffStatusToggleError(failure.message)),
      (_) => emit(StaffStatusToggled()),
    );
  }
}
