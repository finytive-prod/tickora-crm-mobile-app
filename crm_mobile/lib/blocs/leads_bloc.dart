import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/custom_field.dart';
import 'package:crm_mobile/models/lead_form_layout.dart';
import 'package:crm_mobile/models/lead_filter_params.dart';
import 'package:crm_mobile/usecases/update_lead_active_status_usecase.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/usecases/get_leads_usecase.dart';
import 'package:crm_mobile/usecases/search_leads_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_statuses_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_sources_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_priorities_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_users_usecase.dart';
import 'package:crm_mobile/usecases/get_custom_fields_usecase.dart';
import 'package:crm_mobile/usecases/create_lead_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_details_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_audit_logs_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_attachments_usecase.dart';
import 'package:crm_mobile/usecases/upload_lead_attachment_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_audios_usecase.dart';
import 'package:crm_mobile/usecases/get_lead_call_logs_usecase.dart';
import 'package:crm_mobile/usecases/upload_lead_audio_usecase.dart';
import 'package:crm_mobile/usecases/update_lead_usecase.dart';
import 'package:crm_mobile/usecases/quick_invite_lead_usecase.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/core/services/notification_service.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';

class LeadsBloc extends Bloc<LeadsEvent, LeadsState> {
  final GetLeadsUseCase getLeadsUseCase;
  final GetLeadStatusesUseCase getLeadStatusesUseCase;
  final GetLeadSourcesUseCase getLeadSourcesUseCase;
  final GetLeadPrioritiesUseCase getLeadPrioritiesUseCase;
  final GetStaffUsersUseCase getStaffUsersUseCase;
  final GetCustomFieldsUseCase getCustomFieldsUseCase;
  final CreateLeadUseCase createLeadUseCase;
  final GetLeadDetailsUseCase getLeadDetailsUseCase;
  final GetLeadAuditLogsUseCase getLeadAuditLogsUseCase;
  final GetLeadAttachmentsUseCase getLeadAttachmentsUseCase;
  final UploadLeadAttachmentUseCase uploadLeadAttachmentUseCase;
  final GetLeadAudiosUseCase getLeadAudiosUseCase;
  final GetLeadCallLogsUseCase getLeadCallLogsUseCase;
  final UploadLeadAudioUseCase uploadLeadAudioUseCase;
  final UpdateLeadUseCase updateLeadUseCase;
  final SearchLeadsUseCase searchLeadsUseCase;
  final UpdateLeadActiveStatusUseCase updateLeadActiveStatusUseCase;
  final QuickInviteLeadUseCase? quickInviteLeadUseCase;

  static List<dynamic>? _cachedStatuses;
  static List<LeadSource>? _cachedSources;
  static List<String>? _cachedPriorities;
  static List<dynamic>? _cachedOwners;
  static List<CustomField>? _cachedCustomFields;
  static List<FixedField>? _cachedFixedFields;

  static List<dynamic>? get cachedStatuses => _cachedStatuses;
  static List<LeadSource>? get cachedSources => _cachedSources;
  static List<String>? get cachedPriorities => _cachedPriorities;
  static List<dynamic>? get cachedOwners => _cachedOwners;

  final Set<String> _inFlightAudios = {};
  final Set<String> _inFlightCallLogs = {};
  final Set<String> _inFlightAuditLogs = {};
  final Set<String> _inFlightAttachments = {};
  bool _isFetchingStatuses = false;
  bool _isFetchingSources = false;
  bool _isFetchingPriorities = false;
  bool _isFetchingOwners = false;
  bool _isFetchingCustomFields = false;

  LeadsBloc({
    required this.getLeadsUseCase,
    required this.getLeadStatusesUseCase,
    required this.getLeadSourcesUseCase,
    required this.getLeadPrioritiesUseCase,
    required this.getStaffUsersUseCase,
    required this.getCustomFieldsUseCase,
    required this.createLeadUseCase,
    required this.getLeadDetailsUseCase,
    required this.getLeadAuditLogsUseCase,
    required this.getLeadAttachmentsUseCase,
    required this.uploadLeadAttachmentUseCase,
    required this.getLeadAudiosUseCase,
    required this.getLeadCallLogsUseCase,
    required this.uploadLeadAudioUseCase,
    required this.updateLeadUseCase,
    required this.searchLeadsUseCase,
    required this.updateLeadActiveStatusUseCase,
    this.quickInviteLeadUseCase,
  }) : super(LeadsInitial()) {
    on<FetchLeads>(_onFetchLeads);
    on<SearchLeads>(_onSearchLeads);
    on<FetchLeadStatuses>(_onFetchLeadStatuses);
    on<FetchLeadSources>(_onFetchLeadSources);
    on<FetchLeadPriorities>(_onFetchLeadPriorities);
    on<FetchStaffUsers>(_onFetchStaffUsers);
    on<FetchCustomFieldsForm>(_onFetchCustomFieldsForm);
    on<CreateLead>(_onCreateLead);
    on<QuickInviteLead>(_onQuickInviteLead);
    on<UpdateLead>(_onUpdateLead);
    on<FetchLeadDetails>(_onFetchLeadDetails);
    on<FetchLeadAuditLogs>(_onFetchLeadAuditLogs);
    on<FetchLeadAttachments>(_onFetchLeadAttachments);
    on<UploadLeadAttachment>(_onUploadLeadAttachment);
    on<FetchLeadAudios>(_onFetchLeadAudios);
    on<FetchLeadCallLogs>(_onFetchLeadCallLogs);
    on<UploadLeadAudio>(_onUploadLeadAudio);
    on<UpdateLeadActiveStatus>(_onUpdateLeadActiveStatus);
  }

  Future<void> _onFetchLeads(FetchLeads event, Emitter<LeadsState> emit) async {
    final currentState = state;
    List<Lead> existingLeads = [];
    List<dynamic>? currentStatuses;
    List<LeadSource>? currentSources;
    List<String>? currentPriorities;
    List<dynamic>? currentOwners;
    
    if ((currentState is! LeadsLoaded || currentState.fixedFields.isEmpty) && (_cachedFixedFields == null || _cachedFixedFields!.isEmpty)) {
      add(FetchCustomFieldsForm());
    }

    LeadFilterParams? effectiveFilter = event.filterParams;
    String? effectiveSearchQuery;

    if (currentState is LeadsLoaded) {
      currentStatuses = currentState.statuses;
      currentSources = currentState.sources;
      currentPriorities = currentState.priorities;
      currentOwners = currentState.owners;
      effectiveFilter ??= currentState.filterParams;

      if (event.isLoadMore) {
        existingLeads = currentState.leads;
        effectiveSearchQuery = event.searchQuery ?? currentState.searchQuery;
        emit(currentState.copyWith(isLoadingMore: true));
      } else {
        effectiveSearchQuery = (event.searchQuery != null && event.searchQuery!.isNotEmpty) ? event.searchQuery : null;
        emit(LeadsLoading());
      }
    } else {
      effectiveSearchQuery = (event.searchQuery != null && event.searchQuery!.isNotEmpty) ? event.searchQuery : null;
      emit(LeadsLoading());
    }

    final result = await getLeadsUseCase(
      event.page,
      event.size,
      statusId: event.statusId,
      isActive: event.isActive,
      filterParams: effectiveFilter,
      searchQuery: effectiveSearchQuery,
    );

    result.fold(
      (failure) {
        if (event.isLoadMore && currentState is LeadsLoaded) {
          emit(currentState.copyWith(isLoadingMore: false));
        } else {
          emit(LeadsError(failure.message));
        }
      },
      (newLeads) {
        final allLeads = event.isLoadMore ? [...existingLeads, ...newLeads] : newLeads;
        final hasMore = newLeads.length >= event.size;
        AutoCallRecordingUploader.registerKnownLeads(allLeads);

        List<dynamic> finalStatuses = (state is LeadsLoaded ? (state as LeadsLoaded).statuses : null) ?? currentStatuses ?? _cachedStatuses ?? [];
        List<LeadSource> finalSources = (state is LeadsLoaded ? (state as LeadsLoaded).sources : null) ?? currentSources ?? _cachedSources ?? [];
        List<String> finalPriorities = (state is LeadsLoaded ? (state as LeadsLoaded).priorities : null) ?? currentPriorities ?? _cachedPriorities ?? [];
        List<dynamic> finalOwners = (state is LeadsLoaded ? (state as LeadsLoaded).owners : null) ?? currentOwners ?? _cachedOwners ?? [];
        List<CustomField> finalCustomFields = (state is LeadsLoaded ? (state as LeadsLoaded).customFields : null) ?? (currentState is LeadsLoaded ? currentState.customFields : null) ?? _cachedCustomFields ?? [];
        List<FixedField> finalFixedFields = (state is LeadsLoaded ? (state as LeadsLoaded).fixedFields : null) ?? (currentState is LeadsLoaded ? currentState.fixedFields : null) ?? _cachedFixedFields ?? [];

        emit(LeadsLoaded(
          allLeads, 
          statuses: finalStatuses.cast(),
          sources: finalSources,
          priorities: finalPriorities,
          owners: finalOwners.cast(),
          customFields: finalCustomFields,
          fixedFields: finalFixedFields,
          selectedStatusId: event.statusId,
          selectedIsActive: event.isActive,
          isLeadsLoaded: true,
          currentPage: event.page,
          hasMoreLeads: hasMore,
          isLoadingMore: false,
          searchQuery: effectiveSearchQuery,
          filterParams: effectiveFilter,
        ));
      },
    );
  }

  Future<void> _onSearchLeads(SearchLeads event, Emitter<LeadsState> emit) async {
    final query = event.query.trim();
    final currentState = state;
    LeadFilterParams? currentFilter = event.filterParams;

    if (currentState is LeadsLoaded) {
      currentFilter ??= currentState.filterParams;
    }

    if (query.isEmpty) {
      add(FetchLeads(page: 0, size: 15, filterParams: currentFilter));
      return;
    }

    List<Lead> existingLeads = [];
    List<dynamic>? currentStatuses;
    List<LeadSource>? currentSources;
    List<String>? currentPriorities;
    List<dynamic>? currentOwners;
    List<CustomField>? currentCustomFields;
    List<FixedField>? currentFixedFields;

    if (currentState is LeadsLoaded) {
      currentStatuses = currentState.statuses;
      currentSources = currentState.sources;
      currentPriorities = currentState.priorities;
      currentOwners = currentState.owners;
      currentCustomFields = currentState.customFields;
      currentFixedFields = currentState.fixedFields;

      if (event.isLoadMore) {
        existingLeads = currentState.leads;
        emit(currentState.copyWith(isLoadingMore: true));
      } else {
        emit(LeadsLoading());
      }
    } else {
      emit(LeadsLoading());
    }

    final result = await searchLeadsUseCase(query, page: event.page, size: event.size, filterParams: currentFilter);

    result.fold(
      (failure) {
        if (event.isLoadMore && currentState is LeadsLoaded) {
          emit(currentState.copyWith(isLoadingMore: false));
        } else {
          emit(LeadsError(failure.message));
        }
      },
      (newLeads) {
        final allLeads = event.isLoadMore ? [...existingLeads, ...newLeads] : newLeads;
        final hasMore = newLeads.length >= event.size;
        AutoCallRecordingUploader.registerKnownLeads(allLeads);

        List<dynamic> finalStatuses = currentStatuses ?? [];
        List<LeadSource> finalSources = currentSources ?? [];
        List<String> finalPriorities = currentPriorities ?? [];
        List<dynamic> finalOwners = currentOwners ?? [];
        List<CustomField> finalCustomFields = currentCustomFields ?? [];
        List<FixedField> finalFixedFields = currentFixedFields ?? [];

        if (state is LeadsLoaded) {
          finalStatuses = (state as LeadsLoaded).statuses;
          finalSources = (state as LeadsLoaded).sources;
          finalPriorities = (state as LeadsLoaded).priorities;
          finalOwners = (state as LeadsLoaded).owners;
          finalCustomFields = (state as LeadsLoaded).customFields;
          finalFixedFields = (state as LeadsLoaded).fixedFields;
        }

        emit(LeadsLoaded(
          allLeads,
          statuses: finalStatuses.cast(),
          sources: finalSources,
          priorities: finalPriorities,
          owners: finalOwners.cast(),
          customFields: finalCustomFields,
          fixedFields: finalFixedFields,
          selectedStatusId: currentState is LeadsLoaded ? currentState.selectedStatusId : null,
          selectedIsActive: currentState is LeadsLoaded ? currentState.selectedIsActive : true,
          isLeadsLoaded: true,
          currentPage: event.page,
          hasMoreLeads: hasMore,
          isLoadingMore: false,
          searchQuery: query,
          filterParams: currentFilter,
        ));
      },
    );
  }


  Future<void> _onFetchLeadStatuses(FetchLeadStatuses event, Emitter<LeadsState> emit) async {
    if (_cachedStatuses != null && _cachedStatuses!.isNotEmpty) {
      if (state is LeadsLoaded) {
        emit((state as LeadsLoaded).copyWith(statuses: _cachedStatuses!.cast()));
      } else if (state is LeadDetailsLoaded) {
        return;
      } else {
        emit(LeadsLoaded(
          const [],
          statuses: _cachedStatuses!.cast(),
          sources: _cachedSources ?? const [],
          priorities: _cachedPriorities ?? const [],
          owners: (_cachedOwners ?? const []).cast(),
          customFields: _cachedCustomFields ?? const [],
          fixedFields: _cachedFixedFields ?? const [],
        ));
      }
      return;
    }
    if (_isFetchingStatuses) return;
    _isFetchingStatuses = true;
    try {
      final result = await getLeadStatusesUseCase();
      result.fold(
        (failure) {},
        (statuses) {
          _cachedStatuses = statuses;
          if (state is LeadsLoaded) {
            emit((state as LeadsLoaded).copyWith(statuses: statuses));
          } else if (state is LeadDetailsLoaded) {
            return;
          } else {
            emit(LeadsLoaded(
              const [],
              statuses: statuses,
              sources: _cachedSources ?? const [],
              priorities: _cachedPriorities ?? const [],
              owners: (_cachedOwners ?? const []).cast(),
              customFields: _cachedCustomFields ?? const [],
              fixedFields: _cachedFixedFields ?? const [],
            ));
          }
        },
      );
    } finally {
      _isFetchingStatuses = false;
    }
  }

  Future<void> _onFetchLeadSources(FetchLeadSources event, Emitter<LeadsState> emit) async {
    if (_cachedSources != null && _cachedSources!.isNotEmpty) {
      if (state is LeadsLoaded) {
        emit((state as LeadsLoaded).copyWith(sources: _cachedSources!));
      } else if (state is LeadDetailsLoaded) {
        return;
      } else {
        emit(LeadsLoaded(
          const [],
          statuses: (_cachedStatuses ?? const []).cast(),
          sources: _cachedSources!,
          priorities: _cachedPriorities ?? const [],
          owners: (_cachedOwners ?? const []).cast(),
          customFields: _cachedCustomFields ?? const [],
          fixedFields: _cachedFixedFields ?? const [],
        ));
      }
      return;
    }
    if (_isFetchingSources) return;
    _isFetchingSources = true;
    try {
      final result = await getLeadSourcesUseCase();
      result.fold(
        (failure) {},
        (sources) {
          _cachedSources = sources;
          if (state is LeadsLoaded) {
            emit((state as LeadsLoaded).copyWith(sources: sources));
          } else if (state is LeadDetailsLoaded) {
            return;
          } else {
            emit(LeadsLoaded(
              const [],
              statuses: (_cachedStatuses ?? const []).cast(),
              sources: sources,
              priorities: _cachedPriorities ?? const [],
              owners: (_cachedOwners ?? const []).cast(),
              customFields: _cachedCustomFields ?? const [],
              fixedFields: _cachedFixedFields ?? const [],
            ));
          }
        },
      );
    } finally {
      _isFetchingSources = false;
    }
  }

  Future<void> _onFetchLeadPriorities(FetchLeadPriorities event, Emitter<LeadsState> emit) async {
    if (_cachedPriorities != null && _cachedPriorities!.isNotEmpty) {
      if (state is LeadsLoaded) {
        emit((state as LeadsLoaded).copyWith(priorities: _cachedPriorities!));
      } else if (state is LeadDetailsLoaded) {
        return;
      } else {
        emit(LeadsLoaded(
          const [],
          statuses: (_cachedStatuses ?? const []).cast(),
          sources: _cachedSources ?? const [],
          priorities: _cachedPriorities!,
          owners: (_cachedOwners ?? const []).cast(),
          customFields: _cachedCustomFields ?? const [],
          fixedFields: _cachedFixedFields ?? const [],
        ));
      }
      return;
    }
    if (_isFetchingPriorities) return;
    _isFetchingPriorities = true;
    try {
      final result = await getLeadPrioritiesUseCase();
      result.fold(
        (failure) {},
        (priorities) {
          _cachedPriorities = priorities;
          if (state is LeadsLoaded) {
            emit((state as LeadsLoaded).copyWith(priorities: priorities));
          } else if (state is LeadDetailsLoaded) {
            return;
          } else {
            emit(LeadsLoaded(
              const [],
              statuses: (_cachedStatuses ?? const []).cast(),
              sources: _cachedSources ?? const [],
              priorities: priorities,
              owners: (_cachedOwners ?? const []).cast(),
              customFields: _cachedCustomFields ?? const [],
              fixedFields: _cachedFixedFields ?? const [],
            ));
          }
        },
      );
    } finally {
      _isFetchingPriorities = false;
    }
  }

  Future<void> _onFetchStaffUsers(FetchStaffUsers event, Emitter<LeadsState> emit) async {
    if ((event.search == null || event.search!.isEmpty) && _cachedOwners != null && _cachedOwners!.isNotEmpty) {
      if (state is LeadsLoaded) {
        emit((state as LeadsLoaded).copyWith(owners: _cachedOwners!.cast()));
      } else if (state is LeadDetailsLoaded) {
        return;
      } else {
        emit(LeadsLoaded(
          const [],
          statuses: (_cachedStatuses ?? const []).cast(),
          sources: _cachedSources ?? const [],
          priorities: _cachedPriorities ?? const [],
          owners: _cachedOwners!.cast(),
          customFields: _cachedCustomFields ?? const [],
          fixedFields: _cachedFixedFields ?? const [],
        ));
      }
      return;
    }
    if ((event.search == null || event.search!.isEmpty) && _isFetchingOwners) return;
    final trackInFlight = event.search == null || event.search!.isEmpty;
    if (trackInFlight) _isFetchingOwners = true;
    try {
      final result = await getStaffUsersUseCase(search: event.search);
      result.fold(
        (failure) {},
        (owners) {
          if (trackInFlight) {
            _cachedOwners = owners;
          }
          if (state is LeadsLoaded) {
            emit((state as LeadsLoaded).copyWith(owners: owners));
          } else if (state is LeadDetailsLoaded) {
            return;
          } else {
            emit(LeadsLoaded(
              const [],
              statuses: (_cachedStatuses ?? const []).cast(),
              sources: _cachedSources ?? const [],
              priorities: _cachedPriorities ?? const [],
              owners: owners,
              customFields: _cachedCustomFields ?? const [],
              fixedFields: _cachedFixedFields ?? const [],
            ));
          }
        },
      );
    } finally {
      if (trackInFlight) _isFetchingOwners = false;
    }
  }

  Future<void> _onFetchCustomFieldsForm(FetchCustomFieldsForm event, Emitter<LeadsState> emit) async {
    if (_cachedFixedFields != null && _cachedFixedFields!.isNotEmpty) {
      if (state is LeadsLoaded) {
        emit((state as LeadsLoaded).copyWith(
          fixedFields: _cachedFixedFields!,
          customFields: _cachedCustomFields ?? const [],
        ));
      } else if (state is LeadDetailsLoaded) {
        return;
      } else {
        emit(LeadsLoaded(
          const [],
          statuses: (_cachedStatuses ?? const []).cast(),
          sources: _cachedSources ?? const [],
          priorities: _cachedPriorities ?? const [],
          owners: (_cachedOwners ?? const []).cast(),
          customFields: _cachedCustomFields ?? const [],
          fixedFields: _cachedFixedFields!,
        ));
      }
      return;
    }
    if (_isFetchingCustomFields) return;
    _isFetchingCustomFields = true;
    try {
      final result = await getCustomFieldsUseCase();
      result.fold(
        (failure) {},
        (layout) {
          _cachedFixedFields = layout.fixedFields;
          _cachedCustomFields = layout.customFields;
          if (state is LeadsLoaded) {
            emit((state as LeadsLoaded).copyWith(
              fixedFields: layout.fixedFields,
              customFields: layout.customFields,
            ));
          } else if (state is LeadDetailsLoaded) {
            return;
          } else {
            emit(LeadsLoaded(
              const [],
              statuses: (_cachedStatuses ?? const []).cast(),
              sources: _cachedSources ?? const [],
              priorities: _cachedPriorities ?? const [],
              owners: (_cachedOwners ?? const []).cast(),
              customFields: layout.customFields,
              fixedFields: layout.fixedFields,
            ));
          }
        },
      );
    } finally {
      _isFetchingCustomFields = false;
    }
  }

  Future<void> _onCreateLead(CreateLead event, Emitter<LeadsState> emit) async {
    emit(LeadActionLoading());
    final result = await createLeadUseCase(event.leadData, event.filePaths, leadFileName: event.leadFileName);
    
    result.fold(
      (failure) => emit(LeadActionError(failure.message)),
      (_) {
        AutoCallRecordingUploader.invalidatePhoneLookupCache();
        NotificationService.instance.recordSelfLeadCreated();
        emit(const LeadActionSuccess("Lead created successfully."));
        add(const FetchLeads());
      },
    );
  }

  Future<void> _onQuickInviteLead(QuickInviteLead event, Emitter<LeadsState> emit) async {
    emit(LeadActionLoading());
    if (quickInviteLeadUseCase == null) {
      emit(const LeadActionError("Quick invite service not initialized."));
      return;
    }
    final result = await quickInviteLeadUseCase!(event.data);
    result.fold(
      (failure) => emit(LeadActionError(failure.message)),
      (_) {
        AutoCallRecordingUploader.invalidatePhoneLookupCache();
        NotificationService.instance.recordSelfLeadCreated();
        emit(const LeadActionSuccess("Lead invited successfully."));
        add(const FetchLeads());
      },
    );
  }

  Future<void> _onUpdateLead(UpdateLead event, Emitter<LeadsState> emit) async {
    emit(LeadActionLoading());
    final result = await updateLeadUseCase(event.leadId, event.leadData, event.filePaths, leadFileName: event.leadFileName);
    
    result.fold(
      (failure) => emit(LeadActionError(failure.message)),
      (_) {
        AutoCallRecordingUploader.invalidatePhoneLookupCache();
        emit(const LeadActionSuccess("Lead updated successfully."));
        add(FetchLeadDetails(event.leadId)); // Refresh the currently viewed details
      },
    );
  }

  Future<void> _onFetchLeadDetails(FetchLeadDetails event, Emitter<LeadsState> emit) async {
    final currentState = state;
    if (currentState is! LeadDetailsLoaded) {
      emit(LeadDetailsLoading());
    }
    final result = await getLeadDetailsUseCase(event.id);
    result.fold(
      (failure) {
        if (state is! LeadDetailsLoaded) {
          emit(LeadDetailsError(failure.message));
        }
      },
      (leadDetail) {
        AutoCallRecordingUploader.registerKnownLeads([leadDetail]);
        if (state is LeadDetailsLoaded) {
          final existing = state as LeadDetailsLoaded;
          if (existing.leadDetail.id == leadDetail.id) {
            emit(existing.copyWith(leadDetail: leadDetail));
          } else {
            emit(LeadDetailsLoaded(
              leadDetail,
              isAudiosLoading: true,
              isCallLogsLoading: true,
              isAuditLogsLoading: true,
            ));
            add(FetchLeadAudios(event.id));
            add(FetchLeadCallLogs(event.id));
            add(FetchLeadAuditLogs(event.id));
          }
        } else {
          emit(LeadDetailsLoaded(
            leadDetail,
            isAudiosLoading: true,
            isCallLogsLoading: true,
            isAuditLogsLoading: true,
          ));
          add(FetchLeadAudios(event.id));
          add(FetchLeadCallLogs(event.id));
          add(FetchLeadAuditLogs(event.id));
        }
      },
    );
  }

  Future<void> _onFetchLeadAuditLogs(FetchLeadAuditLogs event, Emitter<LeadsState> emit) async {
    if (_inFlightAuditLogs.contains(event.id)) return;
    _inFlightAuditLogs.add(event.id);
    try {
      final currentState = state;
      if (currentState is LeadDetailsLoaded && currentState.leadDetail.id == event.id) {
        emit(currentState.copyWith(isAuditLogsLoading: true, auditLogsError: null));
      }
      final result = await getLeadAuditLogsUseCase(event.id);
      result.fold(
        (failure) {
          final latest = state;
          if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.id) {
            emit(latest.copyWith(isAuditLogsLoading: false, auditLogsError: failure.message));
          }
        },
        (auditLogs) {
          final latest = state;
          if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.id) {
            emit(latest.copyWith(isAuditLogsLoading: false, auditLogs: auditLogs));
          }
        },
      );
    } finally {
      _inFlightAuditLogs.remove(event.id);
    }
  }

  Future<void> _onFetchLeadAttachments(FetchLeadAttachments event, Emitter<LeadsState> emit) async {
    if (_inFlightAttachments.contains(event.id)) return;
    _inFlightAttachments.add(event.id);
    try {
      final currentState = state;
      if (currentState is LeadDetailsLoaded && currentState.leadDetail.id == event.id) {
        emit(currentState.copyWith(isAttachmentsLoading: true, attachmentsError: null));
      }
      final result = await getLeadAttachmentsUseCase(event.id);
      result.fold(
        (failure) {
          final latest = state;
          if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.id) {
            emit(latest.copyWith(isAttachmentsLoading: false, attachmentsError: failure.message));
          }
        },
        (attachments) {
          final latest = state;
          if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.id) {
            emit(latest.copyWith(isAttachmentsLoading: false, attachments: attachments));
          }
        },
      );
    } finally {
      _inFlightAttachments.remove(event.id);
    }
  }

  Future<void> _onUploadLeadAttachment(UploadLeadAttachment event, Emitter<LeadsState> emit) async {
    final currentState = state;
    if (currentState is LeadDetailsLoaded && currentState.leadDetail.id == event.leadId) {
      emit(currentState.copyWith(isAttachmentsLoading: true, attachmentsError: null));
      final result = await uploadLeadAttachmentUseCase(event.leadId, event.filePath);
      result.fold(
        (failure) {
          final latest = state;
          if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.leadId) {
            emit(latest.copyWith(isAttachmentsLoading: false, attachmentsError: failure.message));
          }
        },
        (_) {
          add(FetchLeadAttachments(event.leadId));
        },
      );
    }
  }

  Future<void> _onFetchLeadAudios(FetchLeadAudios event, Emitter<LeadsState> emit) async {
    if (_inFlightAudios.contains(event.id)) return;
    _inFlightAudios.add(event.id);
    try {
      final currentState = state;
      if (currentState is LeadDetailsLoaded && currentState.leadDetail.id == event.id) {
        emit(currentState.copyWith(isAudiosLoading: true, audiosError: null));
        final result = await getLeadAudiosUseCase(event.id);
        result.fold(
          (failure) {
            final latest = state;
            if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.id) {
              emit(latest.copyWith(isAudiosLoading: false, audiosError: failure.message));
            }
          },
          (audios) {
            final latest = state;
            if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.id) {
              emit(latest.copyWith(isAudiosLoading: false, audios: audios));
            }
          },
        );
      }
    } finally {
      _inFlightAudios.remove(event.id);
    }
  }

  Future<void> _onFetchLeadCallLogs(FetchLeadCallLogs event, Emitter<LeadsState> emit) async {
    if (_inFlightCallLogs.contains(event.id)) return;
    _inFlightCallLogs.add(event.id);
    try {
      final currentState = state;
      if (currentState is LeadDetailsLoaded && currentState.leadDetail.id == event.id) {
        emit(currentState.copyWith(isCallLogsLoading: true, callLogsError: null));
        final result = await getLeadCallLogsUseCase(event.id);
        result.fold(
          (failure) {
            final latest = state;
            if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.id) {
              emit(latest.copyWith(isCallLogsLoading: false, callLogsError: failure.message));
            }
          },
          (callLogs) {
            final latest = state;
            if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.id) {
              emit(latest.copyWith(isCallLogsLoading: false, callLogs: callLogs));
            }
          },
        );
      }
    } finally {
      _inFlightCallLogs.remove(event.id);
    }
  }

  Future<void> _onUploadLeadAudio(UploadLeadAudio event, Emitter<LeadsState> emit) async {
    final currentState = state;
    if (currentState is LeadDetailsLoaded && currentState.leadDetail.id == event.leadId) {
      emit(currentState.copyWith(isAudiosLoading: true, audiosError: null));
      final result = await uploadLeadAudioUseCase(
        event.leadId,
        event.filePath,
        bound: event.bound,
        startTime: event.startTime,
        endTime: event.endTime,
        from: event.from,
        to: event.to,
        duration: event.duration,
        callDate: event.callDate,
        callStatus: event.callStatus,
      );
      result.fold(
        (failure) {
          final latest = state;
          if (latest is LeadDetailsLoaded && latest.leadDetail.id == event.leadId) {
            emit(latest.copyWith(isAudiosLoading: false, audiosError: failure.message));
          }
        },
        (_) {
          add(FetchLeadAudios(event.leadId));
        },
      );
    }
  }

  Future<void> _onUpdateLeadActiveStatus(UpdateLeadActiveStatus event, Emitter<LeadsState> emit) async {
    emit(LeadActionLoading());
    final result = await updateLeadActiveStatusUseCase(event.leadId, event.isActive);
    
    result.fold(
      (failure) => emit(LeadActionError(failure.message)),
      (_) {
        emit(LeadActionSuccess(event.isActive ? "Lead activated successfully." : "Lead deactivated successfully."));
        add(FetchLeadDetails(event.leadId));
      },
    );
  }
}

