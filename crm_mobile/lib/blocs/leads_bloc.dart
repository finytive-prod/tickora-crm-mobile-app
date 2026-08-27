import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/custom_field.dart';
import 'package:crm_mobile/models/lead_form_layout.dart';
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
import 'package:crm_mobile/usecases/upload_lead_audio_usecase.dart';
import 'package:crm_mobile/usecases/update_lead_usecase.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';

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
  final UploadLeadAudioUseCase uploadLeadAudioUseCase;
  final UpdateLeadUseCase updateLeadUseCase;
  final SearchLeadsUseCase searchLeadsUseCase;
  final UpdateLeadActiveStatusUseCase updateLeadActiveStatusUseCase;

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
    required this.uploadLeadAudioUseCase,
    required this.updateLeadUseCase,
    required this.searchLeadsUseCase,
    required this.updateLeadActiveStatusUseCase,
  }) : super(LeadsInitial()) {
    on<FetchLeads>(_onFetchLeads);
    on<SearchLeads>(_onSearchLeads);
    on<FetchLeadStatuses>(_onFetchLeadStatuses);
    on<FetchLeadSources>(_onFetchLeadSources);
    on<FetchLeadPriorities>(_onFetchLeadPriorities);
    on<FetchStaffUsers>(_onFetchStaffUsers);
    on<FetchCustomFieldsForm>(_onFetchCustomFieldsForm);
    on<CreateLead>(_onCreateLead);
    on<UpdateLead>(_onUpdateLead);
    on<FetchLeadDetails>(_onFetchLeadDetails);
    on<FetchLeadAuditLogs>(_onFetchLeadAuditLogs);
    on<FetchLeadAttachments>(_onFetchLeadAttachments);
    on<UploadLeadAttachment>(_onUploadLeadAttachment);
    on<FetchLeadAudios>(_onFetchLeadAudios);
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
    
    if (currentState is! LeadsLoaded || currentState.fixedFields.isEmpty) {
      add(FetchCustomFieldsForm());
    }

    if (currentState is LeadsLoaded) {
      currentStatuses = currentState.statuses;
      currentSources = currentState.sources;
      currentPriorities = currentState.priorities;
      currentOwners = currentState.owners;

      if (event.isLoadMore) {
        existingLeads = currentState.leads;
        emit(currentState.copyWith(isLoadingMore: true));
      } else {
        emit(LeadsLoading());
      }
    } else {
      emit(LeadsLoading());
    }

    final result = await getLeadsUseCase(event.page, event.size, statusId: event.statusId, isActive: event.isActive);

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

        List<dynamic> finalStatuses = currentStatuses ?? [];
        List<LeadSource> finalSources = currentSources ?? [];
        List<String> finalPriorities = currentPriorities ?? [];
        List<dynamic> finalOwners = currentOwners ?? [];
        List<CustomField> finalCustomFields = [];
        List<FixedField> finalFixedFields = [];

        if (state is LeadsLoaded) {
          finalStatuses = (state as LeadsLoaded).statuses;
          finalSources = (state as LeadsLoaded).sources;
          finalPriorities = (state as LeadsLoaded).priorities;
          finalOwners = (state as LeadsLoaded).owners;
          finalCustomFields = (state as LeadsLoaded).customFields;
          finalFixedFields = (state as LeadsLoaded).fixedFields;
        } else if (currentState is LeadsLoaded) {
          finalCustomFields = currentState.customFields;
          finalFixedFields = currentState.fixedFields;
        }

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
          searchQuery: null, // Clear search query when fetching normal leads
        ));
      },
    );
  }

  Future<void> _onSearchLeads(SearchLeads event, Emitter<LeadsState> emit) async {
    final query = event.query.trim();
    if (query.isEmpty) {
      add(const FetchLeads(page: 0, size: 15));
      return;
    }

    final currentState = state;
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

    final result = await searchLeadsUseCase(query, page: event.page, size: event.size);

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
          isLeadsLoaded: true,
          currentPage: event.page,
          hasMoreLeads: hasMore,
          isLoadingMore: false,
          searchQuery: query,
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

  Future<void> _onFetchLeadSources(FetchLeadSources event, Emitter<LeadsState> emit) async {
    final result = await getLeadSourcesUseCase();
    result.fold(
      (failure) {
        if (state is LeadsLoaded) {}
      },
      (sources) {
        if (state is LeadsLoaded) {
          emit((state as LeadsLoaded).copyWith(sources: sources));
        } else {
          emit(LeadsLoaded(const [], sources: sources));
        }
      },
    );
  }

  Future<void> _onFetchLeadPriorities(FetchLeadPriorities event, Emitter<LeadsState> emit) async {
    final result = await getLeadPrioritiesUseCase();
    result.fold(
      (failure) {
        if (state is LeadsLoaded) {}
      },
      (priorities) {
        if (state is LeadsLoaded) {
          emit((state as LeadsLoaded).copyWith(priorities: priorities));
        } else {
          emit(LeadsLoaded(const [], priorities: priorities));
        }
      },
    );
  }

  Future<void> _onFetchStaffUsers(FetchStaffUsers event, Emitter<LeadsState> emit) async {
    final result = await getStaffUsersUseCase(search: event.search);
    result.fold(
      (failure) {
        if (state is LeadsLoaded) {}
      },
      (owners) {
        if (state is LeadsLoaded) {
          emit((state as LeadsLoaded).copyWith(owners: owners));
        } else {
          emit(LeadsLoaded(const [], owners: owners));
        }
      },
    );
  }

  Future<void> _onFetchCustomFieldsForm(FetchCustomFieldsForm event, Emitter<LeadsState> emit) async {
    final result = await getCustomFieldsUseCase();
    result.fold(
      (failure) {
        if (state is LeadsLoaded) {}
      },
      (layout) {
        if (state is LeadsLoaded) {
          emit((state as LeadsLoaded).copyWith(
            fixedFields: layout.fixedFields,
            customFields: layout.customFields,
          ));
        } else {
          emit(LeadsLoaded(
            const [],
            fixedFields: layout.fixedFields,
            customFields: layout.customFields,
          ));
        }
      },
    );
  }

  Future<void> _onCreateLead(CreateLead event, Emitter<LeadsState> emit) async {
    emit(LeadActionLoading());
    final result = await createLeadUseCase(event.leadData, event.filePaths, leadFileName: event.leadFileName);
    
    result.fold(
      (failure) => emit(LeadActionError(failure.message)),
      (_) {
        emit(const LeadActionSuccess("Lead created successfully."));
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
        emit(const LeadActionSuccess("Lead updated successfully."));
        add(const FetchLeads()); // Refresh the main leads list
        add(FetchLeadDetails(event.leadId)); // Refresh the currently viewed details
      },
    );
  }

  Future<void> _onFetchLeadDetails(FetchLeadDetails event, Emitter<LeadsState> emit) async {
    emit(LeadDetailsLoading());
    final result = await getLeadDetailsUseCase(event.id);
    result.fold(
      (failure) => emit(LeadDetailsError(failure.message)),
      (leadDetail) => emit(LeadDetailsLoaded(leadDetail)),
    );
  }

  Future<void> _onFetchLeadAuditLogs(FetchLeadAuditLogs event, Emitter<LeadsState> emit) async {
    final currentState = state;
    if (currentState is LeadDetailsLoaded) {
      emit(currentState.copyWith(isAuditLogsLoading: true, auditLogsError: null));
      final result = await getLeadAuditLogsUseCase(event.id);
      result.fold(
        (failure) => emit(currentState.copyWith(isAuditLogsLoading: false, auditLogsError: failure.message)),
        (auditLogs) => emit(currentState.copyWith(isAuditLogsLoading: false, auditLogs: auditLogs)),
      );
    }
  }

  Future<void> _onFetchLeadAttachments(FetchLeadAttachments event, Emitter<LeadsState> emit) async {
    final currentState = state;
    if (currentState is LeadDetailsLoaded) {
      emit(currentState.copyWith(isAttachmentsLoading: true, attachmentsError: null));
      final result = await getLeadAttachmentsUseCase(event.id);
      result.fold(
        (failure) => emit(currentState.copyWith(isAttachmentsLoading: false, attachmentsError: failure.message)),
        (attachments) => emit(currentState.copyWith(isAttachmentsLoading: false, attachments: attachments)),
      );
    }
  }

  Future<void> _onUploadLeadAttachment(UploadLeadAttachment event, Emitter<LeadsState> emit) async {
    final currentState = state;
    if (currentState is LeadDetailsLoaded) {
      emit(currentState.copyWith(isAttachmentsLoading: true, attachmentsError: null));
      final result = await uploadLeadAttachmentUseCase(event.leadId, event.filePath);
      result.fold(
        (failure) => emit(currentState.copyWith(isAttachmentsLoading: false, attachmentsError: failure.message)),
        (_) {
          add(FetchLeadAttachments(event.leadId));
        },
      );
    }
  }

  Future<void> _onFetchLeadAudios(FetchLeadAudios event, Emitter<LeadsState> emit) async {
    final currentState = state;
    if (currentState is LeadDetailsLoaded) {
      emit(currentState.copyWith(isAudiosLoading: true, audiosError: null));
      final result = await getLeadAudiosUseCase(event.id);
      result.fold(
        (failure) => emit(currentState.copyWith(isAudiosLoading: false, audiosError: failure.message)),
        (audios) => emit(currentState.copyWith(isAudiosLoading: false, audios: audios)),
      );
    }
  }

  Future<void> _onUploadLeadAudio(UploadLeadAudio event, Emitter<LeadsState> emit) async {
    final currentState = state;
    if (currentState is LeadDetailsLoaded) {
      emit(currentState.copyWith(isAudiosLoading: true, audiosError: null));
      final result = await uploadLeadAudioUseCase(event.leadId, event.filePath);
      result.fold(
        (failure) => emit(currentState.copyWith(isAudiosLoading: false, audiosError: failure.message)),
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
        add(const FetchLeads());
        add(FetchLeadDetails(event.leadId));
      },
    );
  }
}

