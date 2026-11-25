import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/models/staff_stats.dart';
import 'package:crm_mobile/usecases/create_staff_member_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_members_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_stats_usecase.dart';
import 'package:crm_mobile/usecases/update_staff_member_usecase.dart';
import 'package:crm_mobile/usecases/toggle_staff_status_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_member_by_id_usecase.dart';
import 'package:crm_mobile/blocs/staff_event.dart';
import 'package:crm_mobile/blocs/staff_state.dart';

class StaffBloc extends Bloc<StaffEvent, StaffState> {
  final GetStaffMembersUseCase getStaffMembersUseCase;
  final GetStaffStatsUseCase getStaffStatsUseCase;
  final UpdateStaffMemberUseCase updateStaffMemberUseCase;
  final ToggleStaffStatusUseCase toggleStaffStatusUseCase;
  final CreateStaffMemberUseCase createStaffMemberUseCase;
  final GetStaffMemberByIdUseCase getStaffMemberByIdUseCase;

  StaffBloc({
    required this.getStaffMembersUseCase,
    required this.getStaffStatsUseCase,
    required this.updateStaffMemberUseCase,
    required this.toggleStaffStatusUseCase,
    required this.createStaffMemberUseCase,
    required this.getStaffMemberByIdUseCase,
  }) : super(StaffInitial()) {
    on<FetchStaffMembers>(_onFetchStaffMembers);
    on<LoadMoreStaffMembers>(_onLoadMoreStaffMembers);
    on<UpdateStaffMemberEvent>(_onUpdateStaffMember);
    on<ToggleStaffStatusEvent>(_onToggleStaffStatus);
    on<CreateStaffMemberEvent>(_onCreateStaffMember);
    on<AddNewlyCreatedStaffMember>(_onAddNewlyCreatedStaffMember);
    on<FetchStaffDetailEvent>(_onFetchStaffDetail);
  }

  Future<void> _onFetchStaffDetail(FetchStaffDetailEvent event, Emitter<StaffState> emit) async {
    emit(StaffLoading());
    final result = await getStaffMemberByIdUseCase(event.id);
    result.fold(
      (failure) => emit(StaffDetailError(failure.message)),
      (member) => emit(StaffDetailLoaded(member)),
    );
  }

  Future<void> _onFetchStaffMembers(FetchStaffMembers event, Emitter<StaffState> emit) async {
    emit(StaffLoading());

    StaffStats? stats;
    final results = await Future.wait([
      getStaffStatsUseCase(),
      getStaffMembersUseCase(page: event.page, size: event.size, status: event.status, searchQuery: event.searchQuery),
    ]);

    final statsResult = results[0] as Either<Failure, StaffStats>;
    final membersResult = results[1] as Either<Failure, List<StaffMember>>;

    bool hasServerStats = false;
    statsResult.fold((_) => null, (s) {
      stats = s;
      hasServerStats = true;
    });

    membersResult.fold(
      (failure) => emit(StaffError(failure.message)),
      (staffMembers) {
        // Deduplicate staff members by ID
        final seen = <String>{};
        final uniqueStaff = staffMembers.where((s) => seen.add(s.id)).toList();

        // If backend returned more than requested page size (e.g. 40 items when size is 20),
        // the endpoint returned all records unpaginated.
        final bool isUnpaginated = staffMembers.length > event.size;

        // If stats is missing, calculate from unique staff members
        if (stats == null) {
          final activeCount = uniqueStaff.where((s) => s.isActive).length;
          final inactiveCount = uniqueStaff.length - activeCount;
          stats = StaffStats(
            activeMembers: activeCount,
            inactiveMembers: inactiveCount,
            totalMembers: uniqueStaff.length,
          );
        }

        // Determine target count from stats if server actually returned it
        final int targetCount = (event.status.toUpperCase() == 'INACTIVE')
            ? stats!.inactiveMembers
            : stats!.activeMembers;

        bool hasMore;
        if (isUnpaginated) {
          hasMore = false;
        } else if (hasServerStats && targetCount > 0 && uniqueStaff.length >= targetCount) {
          hasMore = false;
        } else {
          hasMore = staffMembers.length >= event.size && staffMembers.isNotEmpty;
        }

        emit(StaffLoaded(
          staffMembers: uniqueStaff,
          stats: stats,
          currentPage: event.page,
          hasMore: hasMore,
          currentStatus: event.status,
          searchQuery: event.searchQuery,
        ));
      },
    );
  }

  Future<void> _onLoadMoreStaffMembers(LoadMoreStaffMembers event, Emitter<StaffState> emit) async {
    final currentState = state;
    if (currentState is StaffLoaded) {
      if (!currentState.hasMore || currentState.isLoadingMore) {
        return;
      }

      emit(currentState.copyWith(isLoadingMore: true));
      final result = await getStaffMembersUseCase(
        page: event.page,
        size: event.size,
        status: event.status,
        searchQuery: event.searchQuery,
      );

      result.fold(
        (failure) => emit(currentState.copyWith(isLoadingMore: false)),
        (newStaff) {
          final existingIds = currentState.staffMembers.map((s) => s.id).toSet();
          final uniqueNewStaff = <StaffMember>[];
          for (final s in newStaff) {
            if (!existingIds.contains(s.id)) {
              existingIds.add(s.id);
              uniqueNewStaff.add(s);
            }
          }

          // If no new unique staff members were returned (or backend sent repeated items), stop pagination!
          if (uniqueNewStaff.isEmpty) {
            emit(currentState.copyWith(
              hasMore: false,
              isLoadingMore: false,
            ));
            return;
          }

          final updatedList = [...currentState.staffMembers, ...uniqueNewStaff];

          final int targetCount = (currentState.stats != null)
              ? (event.status.toUpperCase() == 'INACTIVE'
                  ? currentState.stats!.inactiveMembers
                  : currentState.stats!.activeMembers)
              : -1;

          bool hasMore;
          if (targetCount > 0 && updatedList.length >= targetCount) {
            hasMore = false;
          } else {
            hasMore = newStaff.length >= event.size;
          }

          emit(StaffLoaded(
            staffMembers: updatedList,
            stats: currentState.stats,
            currentPage: event.page,
            hasMore: hasMore,
            isLoadingMore: false,
            currentStatus: event.status,
            searchQuery: event.searchQuery,
          ));
        },
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

  Future<void> _onCreateStaffMember(CreateStaffMemberEvent event, Emitter<StaffState> emit) async {
    emit(StaffUpdateLoading());
    final result = await createStaffMemberUseCase(event.data);
    result.fold(
      (failure) => emit(StaffCreateError(failure.message)),
      (member) => emit(StaffCreateSuccess(member)),
    );
  }

  void _onAddNewlyCreatedStaffMember(AddNewlyCreatedStaffMember event, Emitter<StaffState> emit) {
    final currentState = state;
    if (currentState is StaffLoaded) {
      final filteredList = currentState.staffMembers.where((s) => s.id != event.staffMember.id).toList();
      final updatedList = [event.staffMember, ...filteredList];

      StaffStats? updatedStats;
      if (currentState.stats != null) {
        final activeDelta = event.staffMember.isActive ? 1 : 0;
        final inactiveDelta = event.staffMember.isActive ? 0 : 1;
        updatedStats = StaffStats(
          activeMembers: currentState.stats!.activeMembers + activeDelta,
          inactiveMembers: currentState.stats!.inactiveMembers + inactiveDelta,
          totalMembers: currentState.stats!.totalMembers + 1,
        );
      }

      emit(currentState.copyWith(
        staffMembers: updatedList,
        stats: updatedStats ?? currentState.stats,
      ));
    } else {
      emit(StaffLoaded(
        staffMembers: [event.staffMember],
        stats: StaffStats(
          activeMembers: event.staffMember.isActive ? 1 : 0,
          inactiveMembers: event.staffMember.isActive ? 0 : 1,
          totalMembers: 1,
        ),
        currentPage: 0,
        hasMore: false,
        currentStatus: event.staffMember.isActive ? 'ACTIVE' : 'INACTIVE',
      ));
    }
  }
}
