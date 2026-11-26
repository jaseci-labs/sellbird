graph layers {
    layer all { *; }
}

graph import {
    sellbird.collectors.discover --> scripts.diagnose_overpass { OpenStreetMap }
    sellbird.claude_runtime --> tests.conftest;
    sellbird.dashboard --> tests.conftest;
    sellbird.humanize --> tests.conftest;
    sellbird.home --> tests.conftest;
    sellbird.collectors.discover --> tests.test_accelerators_funding {
        Business,
        PRESETS,
        _observations,
        build_queries,
        is_junk,
        preset_problem,
    }
    sellbird.collectors.profile --> tests.test_accelerators_funding {
        ProfileCollector,
        accelerators,
        funding_round,
        yc_backed,
    }
    sellbird.models.company --> tests.test_accelerators_funding { Company }
    sellbird.signals --> tests.test_accelerators_funding { SIGNAL_CATALOG, seed_signal_catalog }
    sellbird.state --> tests.test_accelerators_funding { StateManager }
    sellbird.startups --> tests.test_accelerators_funding { funding_recency }
    sellbird.dashboard --> tests.test_accelerators_funding;
    sellbird.paths --> tests.test_accelerators_funding { PROJECT_ROOT }
    sellbird.brain --> tests.test_accelerators_funding { Brain }
    sellbird.models.prospect --> tests.test_accelerators_funding { Prospect }
    sellbird.agents.writer --> tests.test_accelerators_funding { Writer }
    sellbird.agents.handler --> tests.test_accelerators_funding { Handler }
    sellbird.models.conversation --> tests.test_accelerators_funding { Conversation, Message }
    tests.test_outbox_native --> tests.test_accelerators_funding { Cfg, Env }
    sellbird.gate --> tests.test_outbox_native { pre_send_check }
    sellbird.models.campaign --> tests.test_outbox_native { Campaign, EmailStep }
    sellbird.models.prospect --> tests.test_outbox_native { Prospect }
    sellbird.state --> tests.test_outbox_native { StateManager }
    sellbird.integrations.mail_provider --> tests.test_outbox_native {
        InboundMessage,
        MailProvider,
        SendResult,
        looks_like_bounce,
    }
    sellbird.agents.sender --> tests.test_outbox_native { Sender }
    sellbird.agents.handler --> tests.test_outbox_native;
    sellbird.agents.handler --> tests.test_outbox_native { Handler }
    sellbird.export --> tests.test_outbox_native { collect_prospects }
    sellbird.collectors.ats --> tests.test_ats_hiring;
    sellbird.collectors.ats --> tests.test_ats_hiring {
        Board,
        MAX_FEED_BYTES,
        detect_board,
        feed_url,
        matching_roles,
        parse_feed,
        read_board,
        role_keywords,
    }
    sellbird.collectors.discover --> tests.test_ats_hiring;
    sellbird.collectors.discover --> tests.test_ats_hiring {
        Business,
        DiscoveryProvider,
        DiscoveryQuery,
        PRESETS,
        _observations,
        build_queries,
        is_junk,
        preset_problem,
        run_discovery,
    }
    sellbird.collectors.profile --> tests.test_ats_hiring;
    sellbird.collectors.profile --> tests.test_ats_hiring { ProfileCollector, profile_companies }
    sellbird.models.company --> tests.test_ats_hiring { Company }
    sellbird.signals --> tests.test_ats_hiring { SIGNAL_CATALOG, seed_signal_catalog }
    sellbird.state --> tests.test_ats_hiring { StateManager }
    sellbird.brain --> tests.test_booking;
    sellbird.booking --> tests.test_booking { booking_instruction }
    sellbird.config --> tests.test_booking { SendWindowConfig }
    sellbird.models.conversation --> tests.test_booking { Conversation, Message }
    sellbird.models.prospect --> tests.test_booking { Prospect }
    sellbird.state --> tests.test_booking { StateManager }
    tests.test_outbox_native --> tests.test_booking { Cfg, Env }
    tests.test_prompt_injection --> tests.test_booking { RecordingBrain }
    sellbird.agents.handler --> tests.test_booking { Handler }
    sellbird.gate --> tests.test_prompt_injection { autopilot_review, find_link_domains }
    sellbird.models.prospect --> tests.test_prompt_injection { Prospect }
    sellbird.state --> tests.test_prompt_injection { MIGRATIONS, StateManager }
    sellbird.untrusted --> tests.test_prompt_injection { UNTRUSTED_RULE, fence }
    tests.test_dashboard_signals --> tests.test_prompt_injection { client }
    sellbird.agents.writer --> tests.test_prompt_injection { Writer }
    sellbird.models.company --> tests.test_prompt_injection { Company }
    sellbird.agents.handler --> tests.test_prompt_injection;
    sellbird.agents.handler --> tests.test_prompt_injection { Handler }
    sellbird.models.conversation --> tests.test_prompt_injection { Conversation, Message }
    tests.test_outbox_native --> tests.test_prompt_injection {
        Cfg,
        Env,
        FakeProvider,
        _now_iso,
        make_sender,
        seed_prospect,
    }
    sellbird.agents.scout --> tests.test_prompt_injection { Scout }
    sellbird.humanize --> tests.test_prompt_injection { humanize }
    sellbird.agents.sender --> tests.test_prompt_injection { Sender }
    sellbird.models.campaign --> tests.test_prompt_injection { Campaign, EmailStep }
    sellbird.paths --> tests.test_prompt_injection { PROJECT_ROOT }
    sellbird.trainer --> tests.test_prompt_injection { Trainer, merge_trained_config }
    sellbird.dashboard --> tests.test_dashboard_signals;
    sellbird.dashboard --> tests.test_dashboard_signals { CATEGORY_ORDER }
    sellbird.signals --> tests.test_dashboard_signals { SIGNAL_CATALOG, seed_signal_catalog }
    sellbird.state --> tests.test_dashboard_signals { StateManager }
    sellbird.models --> tests.test_dashboard_signals { Company }
    sellbird.brain --> tests.test_brain_no_tools;
    sellbird.brain --> tests.test_brain_no_tools { Brain }
    sellbird.claude_runtime --> tests.test_brain_no_tools;
    sellbird.paths --> tests.test_brain_no_tools { PROJECT_ROOT }
    sellbird.state --> tests.test_brain_no_tools { StateManager }
    sellbird.brain --> tests.test_brain_provider;
    sellbird.brain --> tests.test_brain_provider { Brain }
    sellbird.dashboard --> tests.test_brain_provider;
    sellbird.codex --> tests.test_brain_provider;
    sellbird.codex --> tests.test_brain_provider { CodexError, CodexResult, SUGGESTED_MODEL }
    sellbird.config --> tests.test_brain_provider;
    sellbird.config --> tests.test_brain_provider {
        BrainConfig,
        ConfigError,
        SellbirdConfig,
        load_brain_config,
    }
    sellbird.state --> tests.test_brain_provider;
    sellbird.state --> tests.test_brain_provider { MIGRATIONS, StateManager }
    sellbird.main --> tests.test_brain_provider;
    sellbird.trainer --> tests.test_brain_provider;
    sellbird.cli --> tests.test_brain_provider;
    sellbird.setup --> tests.test_brain_provider;
    sellbird.integrations.quota --> tests.test_brain_provider;
    sellbird.brain --> tests.test_brain_transport { Brain }
    sellbird.workspace_home --> tests.test_brain_transport { Home, use_home }
    sellbird.claude_runtime --> tests.test_claude_cli_isolation;
    sellbird.brain --> tests.test_claude_cli_isolation { Brain }
    sellbird.state --> tests.test_claude_cli_isolation { StateManager }
    sellbird.codex --> tests.test_codex;
    sellbird.codex --> tests.test_codex_cli_surface;
    sellbird.brain --> tests.test_codex_cli_surface { Brain }
    sellbird.config --> tests.test_codex_cli_surface { load_config }
    sellbird.state --> tests.test_codex_cli_surface { StateManager }
    sellbird.brain --> tests.test_codex_e2e;
    sellbird.brain --> tests.test_codex_e2e { Brain, BrainUnavailable }
    sellbird.codex --> tests.test_codex_e2e;
    sellbird.main --> tests.test_codex_e2e;
    sellbird.config --> tests.test_codex_e2e { EnvConfig, SellbirdConfig }
    sellbird.integrations.mail_provider --> tests.test_codex_e2e { InboundMessage }
    sellbird.models.conversation --> tests.test_codex_e2e { Conversation, Message }
    sellbird.state --> tests.test_codex_e2e { StateManager }
    tests.test_codex --> tests.test_codex_e2e { _write_login }
    tests.test_outbox_native --> tests.test_codex_e2e { FakeProvider, _now_iso, seed_prospect }
    sellbird.agents.handler --> tests.test_codex_e2e;
    sellbird.agents.handler --> tests.test_codex_e2e { Handler }
    sellbird.agents.scout --> tests.test_codex_e2e;
    sellbird.agents.sender --> tests.test_codex_e2e;
    sellbird.models.campaign --> tests.test_codex_e2e { Campaign }
    sellbird.codex --> tests.test_codex_platform;
    tests.test_codex --> tests.test_codex_platform {
        FAKE,
        PROMPT,
        _client,
        _write_login,
        fake,
        native_home,
        private_tempdir,
    }
    sellbird.brain --> tests.test_codex_platform;
    sellbird.brain --> tests.test_codex_platform { BRAIN_STATUS_KEY, Brain }
    sellbird.config --> tests.test_codex_platform { BrainConfig }
    sellbird.state --> tests.test_codex_platform { StateManager }
    sellbird.setup --> tests.test_codex_platform;
    sellbird.brain --> tests.test_codex_soak;
    sellbird.brain --> tests.test_codex_soak { Brain }
    sellbird.codex --> tests.test_codex_soak;
    sellbird.config --> tests.test_codex_soak { BrainConfig }
    sellbird.state --> tests.test_codex_soak { StateManager }
    tests.test_codex --> tests.test_codex_soak { _write_login }
    sellbird.collectors.profile --> tests.test_collectors_profile {
        ProfileCollector,
        _strip_code,
        title_looks_like_role,
    }
    sellbird.models.company --> tests.test_collectors_profile { Company }
    sellbird.models.prospect --> tests.test_collectors_profile { Prospect }
    sellbird.signals --> tests.test_collectors_profile { SIGNAL_CATALOG, seed_signal_catalog }
    sellbird.state --> tests.test_collectors_profile { StateManager }
    sellbird.collectors.discover --> tests.test_collectors_profile { name_from_domain }
    sellbird.agents.scout --> tests.test_company_inbox;
    sellbird.agents.scout --> tests.test_company_inbox { Scout }
    sellbird.integrations.email_finder --> tests.test_company_inbox;
    sellbird.agents.sender --> tests.test_company_inbox { Sender }
    sellbird.models.prospect --> tests.test_company_inbox { COMPANY_INBOX_SOURCE, Prospect }
    sellbird.agents.writer --> tests.test_company_inbox { Writer }
    sellbird.agents.sender --> tests.test_company_stop { COLLEAGUE_REPLIED }
    sellbird.state --> tests.test_company_stop { Company, Prospect }
    tests.test_outbox_native --> tests.test_company_stop {
        FakeProvider,
        InboundMessage,
        _now_iso,
        make_handler,
        make_sender,
        seed_campaign,
        state,
    }
    sellbird.integrations.instantly --> tests.test_company_stop { InstantlyClient }
    sellbird.agents.sender --> tests.test_compliance_footer { Sender }
    sellbird.config --> tests.test_compliance_footer;
    sellbird.config --> tests.test_compliance_footer {
        ComplianceConfig,
        EnvConfig,
        FRENCH_OPT_OUT_WORDS,
        HEBREW_OPT_OUT_WORDS,
        OPT_OUT_WORDS,
        PREVIOUS_DEFAULT_OPT_OUT_LINE,
        SPANISH_OPT_OUT_WORDS,
        compliance_notice,
    }
    sellbird.gate --> tests.test_compliance_footer { pre_send_check }
    sellbird.integrations.mail_provider --> tests.test_compliance_footer {
        InboundMessage,
        strip_quoted_reply,
    }
    sellbird.models.campaign --> tests.test_compliance_footer { Campaign, EmailStep }
    tests.test_outbox_native --> tests.test_compliance_footer {
        FakeProvider,
        StubBrain,
        _logged,
        make_handler,
        make_sender,
        seed_prospect,
        state,
    }
    tests.test_dashboard_manual_send --> tests.test_compliance_footer {
        _campaign,
        _prospect,
        client,
        env,
    }
    sellbird.agents.handler --> tests.test_compliance_footer {
        OurText,
        _escalates,
        _flat,
        _opt_out_reason,
    }
    sellbird.dashboard --> tests.test_dashboard_manual_send;
    sellbird.state --> tests.test_dashboard_manual_send { MAYBE_SENT_PREFIX, StateManager }
    sellbird.config --> tests.test_dashboard_manual_send;
    sellbird.integrations.mail_provider --> tests.test_dashboard_manual_send;
    sellbird.config --> tests.test_config { EnvConfig, SellbirdConfig }
    sellbird.config --> tests.test_config_extra {
        ConfigError,
        EnvConfig,
        QuietHoursConfig,
        SellbirdConfig,
        load_config,
        load_env,
    }
    sellbird.config --> tests.test_config_source;
    sellbird.config --> tests.test_config_source {
        ConfigFileNotFoundError,
        current_config,
        load_config,
        use_config,
    }
    sellbird.workspace_home --> tests.test_config_source { Home, use_home }
    sellbird.dashboard --> tests.test_dashboard_auth;
    sellbird.dashboard_auth --> tests.test_dashboard_auth;
    sellbird.cli --> tests.test_dashboard_auth;
    sellbird.config --> tests.test_dashboard_companies;
    sellbird.dashboard --> tests.test_dashboard_companies;
    sellbird.signals --> tests.test_dashboard_companies { seed_signal_catalog }
    sellbird.state --> tests.test_dashboard_companies { StateManager }
    sellbird.register --> tests.test_dashboard_companies;
    tests.test_dashboard_signals --> tests.test_dashboard_conversations { client }
    sellbird.state --> tests.test_dashboard_conversations { StateManager }
    sellbird.dashboard --> tests.test_dashboard_live_status;
    sellbird.signals --> tests.test_dashboard_live_status { seed_signal_catalog }
    sellbird.state --> tests.test_dashboard_live_status { StateManager }
    tests.test_dashboard_signals --> tests.test_dashboard_opt_out { client }
    sellbird.state --> tests.test_dashboard_opt_out { StateManager }
    tests.test_dashboard_signals --> tests.test_dashboard_pipeline { client }
    sellbird.state --> tests.test_dashboard_pipeline { StateManager }
    sellbird.dashboard --> tests.test_dashboard_pipeline;
    tests.test_dashboard_signals --> tests.test_dashboard_trend { client }
    sellbird.state --> tests.test_dashboard_trend { StateManager }
    sellbird.dashboard --> tests.test_dashboard_trulyinbox;
    sellbird.integrations.trulyinbox --> tests.test_dashboard_trulyinbox;
    tests.test_dashboard_live_status --> tests.test_dashboard_trulyinbox { client, env }
    sellbird.dashboard --> tests.test_dashboard_usage_date;
    sellbird.state --> tests.test_dashboard_usage_date { StateManager }
    tests.test_dashboard_signals --> tests.test_dashboard_usage_date { client }
    sellbird.collectors.discover --> tests.test_discover;
    sellbird.config --> tests.test_discover;
    sellbird.config --> tests.test_discover { EnvConfig, load_config }
    sellbird.signals --> tests.test_discover { SIGNAL_CATALOG, seed_signal_catalog }
    sellbird.state --> tests.test_discover { StateManager }
    sellbird.cli --> tests.test_discover { cmd_discover }
    sellbird.paths --> tests.test_discover { PROJECT_ROOT }
    sellbird.agents.scout --> tests.test_discover { Scout }
    sellbird.pipeline --> tests.test_discover;
    sellbird.config --> tests.test_do_not_contact {
        ComplianceConfig,
        live_do_not_contact,
        load_config,
    }
    sellbird.gate --> tests.test_do_not_contact {
        do_not_contact_domain_match,
        do_not_contact_match,
        pre_send_check,
    }
    tests.test_outbox_native --> tests.test_do_not_contact {
        Cfg,
        Env,
        FakeProvider,
        make_sender,
        seed_prospect,
        state,
    }
    sellbird.agents.sender --> tests.test_do_not_contact { Sender }
    sellbird.models.prospect --> tests.test_do_not_contact { Prospect }
    sellbird.agents.handler --> tests.test_do_not_contact { Handler }
    sellbird.paths --> tests.test_do_not_contact { PROJECT_ROOT }
    sellbird.export --> tests.test_do_not_contact;
    sellbird.paths --> tests.test_docker_config { PROJECT_ROOT }
    sellbird.setup --> tests.test_docker_config;
    sellbird.dashboard --> tests.test_docker_config;
    sellbird.config --> tests.test_docker_config { load_config }
    sellbird.trainer --> tests.test_docker_config { write_trained_config }
    sellbird.integrations.email_finder --> tests.test_email_evidence;
    sellbird.state --> tests.test_email_finder { StateManager }
    sellbird.integrations.email_finder --> tests.test_email_finder;
    sellbird.integrations.email_finder --> tests.test_email_finder {
        _status_from_verdict,
        _translate_hunter_pattern,
        build_email,
        classify_mx,
        derive_pattern,
        find_email,
        generate_patterns,
        infer_pattern_from_email,
    }
    sellbird.email_style --> tests.test_email_style {
        BREAKUP_MAX_WORDS,
        FIRST_EMAIL_MAX_WORDS,
        style_problems,
        tidy,
        with_sign_off,
    }
    sellbird.agents.writer --> tests.test_email_style { Writer, offer_block }
    sellbird.agents.sender --> tests.test_email_style { Sender }
    sellbird.state --> tests.test_email_style { HELD_FOR_REVIEW }
    sellbird.brain --> tests.test_email_style { Brain }
    sellbird.trainer --> tests.test_email_style { _offer_from, merge_trained_config }
    sellbird.state --> tests.test_email_wiring { StateManager }
    sellbird.models.prospect --> tests.test_email_wiring { Prospect }
    sellbird.agents.sender --> tests.test_email_wiring;
    sellbird.agents.sender --> tests.test_email_wiring {
        SENDABLE_EMAIL_STATUSES,
        SENDABLE_EMAIL_STATUSES_WITH_RISKY,
        Sender,
    }
    sellbird.config --> tests.test_email_wiring { EnvConfig }
    sellbird.export --> tests.test_export_suppression { collect_prospects, export_prospects_csv }
    sellbird.models.prospect --> tests.test_export_suppression { Prospect }
    sellbird.state --> tests.test_export_suppression;
    sellbird.state --> tests.test_export_suppression { StateManager }
    sellbird.cli --> tests.test_export_suppression;
    sellbird.dashboard --> tests.test_export_suppression;
    sellbird.extensions --> tests.test_extensions;
    sellbird.state --> tests.test_extensions { StateManager }
    tests.test_prospecting_stall --> tests.test_extensions {
        _draft_and_open_conversation,
        _instantly_with_a_draft_and_an_open_conversation,
    }
    sellbird.cli --> tests.test_extensions;
    sellbird.dashboard --> tests.test_extensions;
    sellbird.workspace_home --> tests.test_extensions { Home, current_home, require_self_hosted }
    sellbird.main --> tests.test_prospecting_stall {
        PROSPECT_BACKLOG,
        decide_next_action,
        unusable_backlog_notice,
    }
    sellbird.models.prospect --> tests.test_prospecting_stall { Prospect }
    sellbird.state --> tests.test_prospecting_stall { StateManager }
    sellbird.agents.handler --> tests.test_prospecting_stall;
    sellbird.agents.handler --> tests.test_prospecting_stall { Handler }
    tests.test_do_not_contact --> tests.test_prospecting_stall { FakeProvider }
    tests.test_outbox_native --> tests.test_prospecting_stall { Cfg, Env, seed_prospect }
    sellbird.models.conversation --> tests.test_prospecting_stall { Conversation }
    tests.test_send_window --> tests.test_prospecting_stall { BASE, _patch_heartbeat }
    sellbird.agents.sender --> tests.test_prospecting_stall;
    sellbird.config --> tests.test_prospecting_stall { SellbirdConfig }
    sellbird.models.campaign --> tests.test_prospecting_stall { Campaign }
    sellbird.agents.sender --> tests.test_send_window;
    sellbird.config --> tests.test_send_window {
        ComplianceConfig,
        EmailChannelConfig,
        SellbirdConfig,
        SendWindowConfig,
        WarmupConfig,
    }
    sellbird.integrations.precleared --> tests.test_send_window {
        PreclearedClient,
        SETTINGS_PREFIX,
    }
    sellbird.models.company --> tests.test_send_window { Company }
    sellbird.models.prospect --> tests.test_send_window { Prospect }
    sellbird.send_window --> tests.test_send_window {
        START_SPREAD,
        country_for,
        icp_country,
        in_window,
        next_send_time,
        recipient_country,
        recipient_zone,
        zone_country,
        zone_for,
    }
    sellbird.state --> tests.test_send_window { MIGRATIONS, StateManager }
    tests.test_outbox_native --> tests.test_send_window { FakeProvider, make_sender, seed_campaign }
    sellbird.main --> tests.test_send_window;
    sellbird.main --> tests.test_send_window { sends_through_quiet_hours }
    sellbird.agents.analyst --> tests.test_send_window;
    sellbird.agents.handler --> tests.test_send_window;
    sellbird.agents.scout --> tests.test_send_window;
    sellbird.agents.writer --> tests.test_send_window;
    sellbird.fit --> tests.test_fit { company_fit }
    tests.test_outbox_native --> tests.test_followup_spacing {
        FakeProvider,
        make_sender,
        seed_campaign,
        seed_prospect,
        state,
    }
    sellbird.integrations.gmail --> tests.test_gmail { GmailProvider }
    sellbird.integrations.gmail --> tests.test_gmail_history;
    sellbird.integrations.gmail --> tests.test_gmail_history { GmailError, GmailProvider }
    sellbird.state --> tests.test_gmail_history { StateManager }
    tests.test_outbox_native --> tests.test_gmail_history {
        FakeProvider,
        make_handler,
        seed_prospect,
    }
    tests.test_codex_e2e --> tests.test_gmail_history { Harness, _approved_item }
    tests.test_gmail_send_outcomes --> tests.test_gmail_history { transport_provider }
    sellbird.brain --> tests.test_gmail_history { BrainUnavailable }
    sellbird.integrations.mail_provider --> tests.test_gmail_history { InboundMessage }
    sellbird.dashboard --> tests.test_gmail_send_outcomes;
    sellbird.integrations.gmail --> tests.test_gmail_send_outcomes;
    sellbird.state --> tests.test_gmail_send_outcomes { MAYBE_SENT_PREFIX, StateManager }
    tests.test_outbox_native --> tests.test_gmail_send_outcomes {
        _now_iso,
        make_sender,
        seed_prospect,
    }
    tests.test_gmail_inbox --> tests.test_gmail_send_outcomes { message }
    tests.test_codex_e2e --> tests.test_gmail_send_outcomes { Harness, _approved_item }
    sellbird.integrations.gmail --> tests.test_gmail_inbox;
    sellbird.integrations.gmail --> tests.test_gmail_inbox { GmailProvider }
    tests.test_codex_e2e --> tests.test_gmail_inbox { Harness, _approved_item }
    sellbird.state --> tests.test_hand_sent_guard { MANUAL_SEND_KEY }
    tests.test_outbox_native --> tests.test_hand_sent_guard {
        FakeProvider,
        make_sender,
        seed_campaign,
        seed_prospect,
        state,
    }
    sellbird.config --> tests.test_handoff { HandoffConfig }
    sellbird.handoff --> tests.test_handoff { call_tool, configured, fill, values_for }
    sellbird.models.conversation --> tests.test_handoff { Conversation, Message }
    sellbird.models.prospect --> tests.test_handoff { Prospect }
    sellbird.state --> tests.test_handoff { StateManager }
    tests.test_booking --> tests.test_handoff { OfferCfg, PromptBrain }
    tests.test_outbox_native --> tests.test_handoff { Env }
    sellbird.agents.handler --> tests.test_handoff { Handler }
    sellbird.config --> tests.test_home;
    sellbird.home --> tests.test_home;
    sellbird.home --> tests.test_home { bundled_defaults, seed_home }
    sellbird.main --> tests.test_home;
    sellbird.paths --> tests.test_home;
    sellbird.paths --> tests.test_home { resolve_home, user_home_default }
    sellbird.cli --> tests.test_home;
    sellbird.dashboard --> tests.test_home;
    sellbird.config --> tests.test_humanize { SellbirdConfig }
    sellbird.humanize --> tests.test_humanize { humanize, humanizer_enabled, load_skill }
    sellbird.dashboard --> tests.test_inbox_routes;
    sellbird.inbox_routes --> tests.test_inbox_routes;
    sellbird.dashboard_auth --> tests.test_inbox_routes { load_or_create_token }
    sellbird.mailboxes --> tests.test_inbox_routes { MailboxStore }
    sellbird.models.campaign --> tests.test_inbox_routes { Campaign, EmailStep }
    tests.test_mailboxes --> tests.test_inbox_routes { add_inbox, boxes }
    tests.test_outbox_native --> tests.test_inbox_routes { Cfg, Env }
    sellbird.dashboard_instance --> tests.test_inbox_routes;
    sellbird.mcp_server --> tests.test_inbox_routes;
    sellbird.secrets --> tests.test_inbox_routes { MemorySecretBackend, SecretStore }
    sellbird.extensions --> tests.test_mailboxes;
    sellbird.mailboxes --> tests.test_mailboxes;
    sellbird.mailboxes --> tests.test_mailboxes { ConnectRefused, MAIN, MailboxStore }
    sellbird.config --> tests.test_mailboxes { EmailChannelConfig, WarmupConfig }
    sellbird.integrations.mail_provider --> tests.test_mailboxes {
        InboundMessage,
        MailProvider,
        SendResult,
    }
    sellbird.integrations.smtp_mail --> tests.test_mailboxes { SmtpImapProvider, SmtpSettings }
    sellbird.secrets --> tests.test_mailboxes { MemorySecretBackend, SecretStore }
    tests.test_outbox_native --> tests.test_mailboxes {
        Cfg,
        Env,
        StubBrain,
        seed_campaign,
        seed_prospect,
    }
    sellbird.agents.sender --> tests.test_mailboxes { Sender }
    sellbird.agents.handler --> tests.test_mailboxes { Handler }
    sellbird.inbox_cli --> tests.test_mailboxes;
    harvey --> tests.test_legacy;
    harvey.cli --> tests.test_legacy;
    sellbird.legacy --> tests.test_legacy;
    tests.test_dashboard_live_status --> tests.test_legacy { client, env }
    sellbird.collectors.discover --> tests.test_local_rank;
    sellbird.config --> tests.test_local_rank { EnvConfig, load_config }
    sellbird.models --> tests.test_local_rank { Company }
    sellbird.signals --> tests.test_local_rank { SIGNAL_CATALOG, seed_signal_catalog }
    sellbird.state --> tests.test_local_rank { StateManager }
    sellbird.desktop.login_item --> tests.test_login_item;
    sellbird.desktop.login_item --> tests.test_login_item {
        ForeignLoginItem,
        LABEL,
        MARKER,
        PLIST_COMMENT,
        UnsupportedPlatform,
        WINDOWS_SHORTCUT,
    }
    sellbird.desktop_cli --> tests.test_login_item { cmd_autostart, register_desktop_commands }
    sellbird.integrations.gmail --> tests.test_mail_identity;
    sellbird.integrations.microsoft --> tests.test_mail_identity;
    sellbird.integrations.smtp_mail --> tests.test_mail_identity;
    sellbird.integrations.mail_provider --> tests.test_mail_identity {
        INBOX_NOT_CONNECTED,
        MailIdentity,
        SendResult,
        identity_from_config,
        missing_token_text,
        save_if_signed_in_as,
    }
    sellbird.state --> tests.test_mail_identity { MAYBE_SENT_PREFIX, StateManager }
    tests.test_outbox_native --> tests.test_mail_identity { _now_iso, make_sender, seed_prospect }
    sellbird.mcp_install --> tests.test_mcp_install;
    sellbird.cli --> tests.test_mcp_install;
    sellbird.home --> tests.test_mcp_install;
    sellbird.mcp_server --> tests.test_mcp_install;
    sellbird.codex --> tests.test_mcp_install { build_private_config_toml }
    sellbird.dashboard --> tests.test_mcp_server;
    sellbird.agent_policy --> tests.test_mcp_server;
    sellbird.dashboard_instance --> tests.test_mcp_server;
    sellbird.extensions --> tests.test_mcp_server;
    sellbird.mcp_server --> tests.test_mcp_server;
    sellbird.dashboard_auth --> tests.test_mcp_server { load_or_create_token }
    sellbird.state --> tests.test_mcp_server { StateManager }
    sellbird.integrations.microsoft --> tests.test_microsoft;
    sellbird.integrations.microsoft --> tests.test_microsoft { GraphError, MicrosoftProvider }
    sellbird.config --> tests.test_microsoft { SignatureConfig }
    tests.test_signature --> tests.test_microsoft { png }
    sellbird.agents.handler --> tests.test_microsoft { Handler }
    sellbird.state --> tests.test_microsoft { StateManager }
    tests.test_outbox_native --> tests.test_microsoft {
        Cfg,
        StubBrain,
        _now_iso,
        make_handler,
        seed_prospect,
    }
    sellbird.integrations.mail_provider --> tests.test_microsoft {
        NATIVE_PROVIDERS,
        get_mail_provider,
    }
    sellbird.config --> tests.test_signature { SignatureConfig }
    sellbird.integrations.signature --> tests.test_signature;
    sellbird.integrations.signature --> tests.test_signature {
        MAX_LOGO_BYTES,
        SignatureError,
        load_signature,
        render_html,
        set_body,
        signature_problem,
    }
    sellbird.integrations.smtp_mail --> tests.test_signature;
    sellbird.integrations.gmail --> tests.test_signature;
    sellbird.state --> tests.test_signature { StateManager }
    tests.test_outbox_native --> tests.test_signature {
        Cfg,
        FakeProvider,
        _now_iso,
        make_sender,
        seed_prospect,
    }
    sellbird.sending_mode --> tests.test_signature { held_message }
    sellbird.integrations.mail_provider --> tests.test_signature { SendResult }
    sellbird.models.prospect --> tests.test_models { Prospect }
    sellbird.models.campaign --> tests.test_models { Campaign, EmailStep }
    sellbird.models.company --> tests.test_models { Company }
    sellbird.models.conversation --> tests.test_models { Conversation, Message }
    sellbird.models.prospect --> tests.test_models_extra { Prospect }
    sellbird.models.company --> tests.test_models_extra { Company }
    sellbird.models.campaign --> tests.test_models_extra { Campaign, EmailStep }
    sellbird.models.conversation --> tests.test_models_extra { Conversation, Message, STAGES }
    sellbird.offer --> tests.test_offer { save_offer, suggest_offers }
    sellbird.state --> tests.test_outbox_claim { MANUAL_SEND_KEY }
    tests.test_outbox_native --> tests.test_outbox_claim {
        FakeProvider,
        make_sender,
        seed_prospect,
        state,
    }
    sellbird.dashboard --> tests.test_outbox_review;
    sellbird.config --> tests.test_outbox_review { DEFAULT_OPT_OUT_LINE }
    sellbird.models --> tests.test_outbox_review { Company }
    sellbird.models.campaign --> tests.test_outbox_review { Campaign }
    sellbird.models.prospect --> tests.test_outbox_review { Prospect }
    sellbird.signals --> tests.test_outbox_review { seed_signal_catalog }
    sellbird.state --> tests.test_outbox_review { StateManager }
    tests.test_outbox_native --> tests.test_outbox_review { FakeProvider, make_sender }
    sellbird.agents.sender --> tests.test_outreach_fixes { Sender }
    sellbird.collectors.people --> tests.test_people_finder;
    sellbird.collectors.profile --> tests.test_people_finder { ProfileCollector }
    sellbird.agents.scout --> tests.test_people_finder_fr { Scout }
    sellbird.collectors.people --> tests.test_people_finder_fr;
    sellbird.collectors.profile --> tests.test_people_finder_fr {
        ProfileCollector,
        title_looks_like_role,
    }
    sellbird.dashboard --> tests.test_pidfile;
    sellbird.pidfile --> tests.test_pidfile;
    sellbird.main --> tests.test_pidfile;
    sellbird.setup --> tests.test_pidfile;
    sellbird.pipeline --> tests.test_pipeline;
    sellbird.collectors.discover --> tests.test_pipeline;
    sellbird.config --> tests.test_pipeline { load_config }
    sellbird.models --> tests.test_pipeline { Company }
    sellbird.signals --> tests.test_pipeline { SIGNAL_CATALOG, seed_signal_catalog }
    sellbird.state --> tests.test_pipeline { StateManager }
    sellbird.config --> tests.test_precleared {
        PRECLEARED_SENDER_COUNTRIES,
        PreclearedConfig,
        load_config,
    }
    sellbird.integrations.precleared --> tests.test_precleared {
        PreclearedClient,
        SENDER_COUNTRIES,
        SETTINGS_PREFIX,
    }
    sellbird.models.company --> tests.test_precleared { Company }
    sellbird.models.prospect --> tests.test_precleared { COMPANY_INBOX_SOURCE, Prospect }
    sellbird.state --> tests.test_precleared { StateManager }
    tests.test_outbox_native --> tests.test_precleared {
        Cfg,
        Env,
        FakeProvider,
        _now_iso,
        make_sender,
        seed_prospect,
    }
    sellbird.integrations.precleared --> tests.test_precleared_checkout {
        BUY_URL,
        PreclearedClient,
        SETTINGS_PREFIX,
    }
    tests.test_precleared --> tests.test_precleared_checkout { OK_BODY, queue, state, with_check }
    tests.test_outbox_native --> tests.test_precleared_checkout {
        FakeProvider,
        make_sender,
        seed_prospect,
    }
    sellbird.config --> tests.test_precleared_free_key;
    sellbird.cli --> tests.test_precleared_free_key;
    sellbird.dashboard --> tests.test_precleared_free_key;
    sellbird.setup --> tests.test_precleared_free_key;
    sellbird.integrations.precleared --> tests.test_precleared_free_key;
    sellbird.integrations.precleared --> tests.test_precleared_free_key {
        KEYS_URL,
        NewKey,
        create_free_key,
    }
    sellbird.integrations.precleared --> tests.test_precleared_hold {
        BUY_URL,
        Clearance,
        PreclearedClient,
        STATUS_KEY,
        current_hold,
        hold_message,
        record_hold,
    }
    sellbird.state --> tests.test_precleared_hold;
    sellbird.state --> tests.test_precleared_hold { StateManager }
    tests.test_dashboard_signals --> tests.test_precleared_hold { client }
    tests.test_outbox_native --> tests.test_precleared_hold {
        FakeProvider,
        make_sender,
        seed_prospect,
    }
    tests.test_precleared --> tests.test_precleared_hold {
        OK_BODY,
        days_pass,
        mock_status,
        queue,
        with_check,
    }
    sellbird.config --> tests.test_precleared_hold;
    sellbird.cli --> tests.test_precleared_hold;
    sellbird.agents.sender --> tests.test_precleared_hold { Sender }
    sellbird.integrations.precleared --> tests.test_precleared_pause;
    sellbird.integrations.precleared --> tests.test_precleared_pause {
        BUY_URL,
        PreclearedClient,
        STATUS_KEY,
        hold_message,
    }
    sellbird.state --> tests.test_precleared_pause { RECHECK_PREFIX, StateManager }
    sellbird.agents.sender --> tests.test_precleared_pause;
    sellbird.agents.sender --> tests.test_precleared_pause {
        ADDRESS_RETRY_AFTER,
        DOMAINS_FAILING_TO_PAUSE,
    }
    tests.test_outbox_native --> tests.test_precleared_pause {
        FakeProvider,
        make_sender,
        seed_prospect,
    }
    tests.test_send_window --> tests.test_precleared_pause {
        WED_0200,
        approved,
        pin_now,
        seed_at,
        window_sender,
    }
    tests.test_precleared --> tests.test_precleared_pause {
        CONSENT_BODY,
        OK_BODY,
        mock_precleared,
        mock_raw,
        mock_status,
        queue,
        with_check,
    }
    sellbird.agents.sender --> tests.test_precleared_unknown { ADDRESS_RETRY_AFTER }
    sellbird.integrations.precleared --> tests.test_precleared_unknown {
        PreclearedClient,
        SETTINGS_PREFIX,
        UNKNOWN_ATTEMPTS,
        UNKNOWN_PREFIX,
        UNKNOWN_RETRY_AFTER,
    }
    sellbird.state --> tests.test_precleared_unknown {
        MOVED_BACK_PREFIXES,
        RECHECK_PREFIX,
        StateManager,
        UNKNOWN_HOLD_PREFIX,
    }
    tests.test_outbox_native --> tests.test_precleared_unknown {
        FakeProvider,
        make_sender,
        seed_prospect,
    }
    tests.test_precleared --> tests.test_precleared_unknown {
        CONSENT_BODY,
        OK_BODY,
        mock_status,
        queue,
        with_check,
    }
    tests.test_precleared_pause --> tests.test_precleared_unknown {
        make_due_again,
        people,
        send_at,
    }
    sellbird.public_http --> tests.test_public_http;
    sellbird.agents.scout --> tests.test_public_http { Scout }
    sellbird.collectors.profile --> tests.test_public_http { ProfileCollector }
    sellbird.trainer --> tests.test_public_http { FallbackCrawler }
    sellbird.register --> tests.test_register { build_register, company_status, to_csv }
    sellbird.config --> tests.test_register;
    sellbird.config --> tests.test_register { ComplianceConfig }
    sellbird.state --> tests.test_register;
    sellbird.state --> tests.test_register { StateManager }
    sellbird.cli --> tests.test_register { cmd_companies }
    sellbird.agents.handler --> tests.test_reply_history {
        HISTORY_BUDGET_CHARS,
        Handler,
        conversation_history,
    }
    sellbird.models.conversation --> tests.test_reply_history { Conversation, Message }
    sellbird.models.prospect --> tests.test_reply_history { Prospect }
    sellbird.state --> tests.test_reply_history { StateManager }
    tests.test_prompt_injection --> tests.test_reply_history { RecordingBrain }
    tests.test_outbox_native --> tests.test_reply_history { Cfg, Env }
    sellbird.agents.scout --> tests.test_scout_decision_maker;
    sellbird.agents.scout --> tests.test_scout_decision_maker { Scout }
    sellbird.integrations.email_finder --> tests.test_scout_decision_maker;
    sellbird.collectors.profile --> tests.test_scout_decision_maker { ProfileCollector }
    tests.test_people_finder --> tests.test_scout_decision_maker { LANTERN, WHITLOCK }
    sellbird.agents.scout --> tests.test_scout_do_not_contact;
    sellbird.agents.scout --> tests.test_scout_do_not_contact { Scout }
    sellbird.config --> tests.test_scout_do_not_contact { ComplianceConfig }
    sellbird.integrations.email_finder --> tests.test_scout_do_not_contact;
    sellbird.agents.scout --> tests.test_scout_profile_search_gate { Scout }
    sellbird.agents.handler --> tests.test_security_defaults { Handler }
    sellbird.agents.sender --> tests.test_security_defaults { Sender }
    sellbird.config --> tests.test_security_defaults;
    sellbird.config --> tests.test_security_defaults {
        BrainConfig,
        EnvConfig,
        LinkedInChannelConfig,
        SellbirdConfig,
        legacy_sending_held,
        sending_notice,
    }
    sellbird.models.campaign --> tests.test_security_defaults { Campaign, EmailStep }
    sellbird.models.prospect --> tests.test_security_defaults { Prospect }
    sellbird.paths --> tests.test_security_defaults { PROJECT_ROOT }
    sellbird.state --> tests.test_security_defaults;
    sellbird.state --> tests.test_security_defaults { StateManager }
    sellbird.trainer --> tests.test_security_defaults { FallbackCrawler, Trainer }
    sellbird.setup --> tests.test_security_defaults;
    sellbird.main --> tests.test_security_defaults { decide_next_action }
    sellbird.cli --> tests.test_security_defaults { cmd_status }
    sellbird.extensions --> tests.test_send_hooks;
    sellbird.integrations.mail_provider --> tests.test_send_hooks { SendResult }
    sellbird.send_hooks --> tests.test_send_hooks {
        Cancel,
        Hold,
        NO_HEADERS_HOLD,
        SendCheck,
        SendHookError,
        extra_headers,
        first_verdict,
    }
    tests.test_outbox_native --> tests.test_send_hooks {
        FakeProvider,
        make_sender,
        seed_prospect,
        state,
    }
    sellbird.integrations.microsoft --> tests.test_send_hooks { MicrosoftProvider }
    sellbird.integrations.gmail --> tests.test_send_hooks;
    sellbird.integrations.gmail --> tests.test_send_hooks { GmailProvider }
    sellbird.integrations.smtp_mail --> tests.test_send_hooks { SmtpImapProvider }
    tests.test_mail_identity --> tests.test_send_hooks { _Tokens, _config, _env, _gmail_transport }
    sellbird.sending_mode --> tests.test_sending_held { held_message }
    sellbird.state --> tests.test_sending_held;
    sellbird.state --> tests.test_sending_held { SENDS_HELD_KEY, StateManager }
    tests.test_dashboard_signals --> tests.test_sending_held { client }
    tests.test_outbox_native --> tests.test_sending_held { FakeProvider, _now_iso, make_handler }
    sellbird.integrations.gmail --> tests.test_sending_held;
    sellbird.integrations.gmail --> tests.test_sending_held { GmailError, GmailProvider }
    sellbird.main --> tests.test_sending_held { record_send_phase, send_hold_reason }
    sellbird.cli --> tests.test_sending_held;
    sellbird.dashboard --> tests.test_sending_held;
    sellbird.config --> tests.test_sending_mode {
        ConfigError,
        load_config,
        refresh_sending_mode,
        set_require_approval,
    }
    sellbird.paths --> tests.test_sending_mode { PROJECT_ROOT }
    sellbird.state --> tests.test_sending_mode { MIGRATIONS, StateManager }
    tests.test_dashboard_signals --> tests.test_sending_mode { client }
    tests.test_outbox_native --> tests.test_sending_mode {
        Cfg,
        Env,
        FakeProvider,
        InboundMessage,
        _now_iso,
        make_handler,
        make_sender,
        seed_campaign,
        seed_prospect,
    }
    sellbird.dashboard --> tests.test_sending_mode;
    tests.test_writer_feedback --> tests.test_sending_mode { RecordingBrain, prospect, writer }
    sellbird.agents.sender --> tests.test_sending_mode { Sender }
    sellbird.sending_mode --> tests.test_sending_mode { sync_sending_mode }
    sellbird.agents.writer --> tests.test_writer_feedback { Writer }
    sellbird.models.campaign --> tests.test_writer_feedback { Campaign }
    sellbird.models.prospect --> tests.test_writer_feedback { Prospect }
    sellbird.state --> tests.test_writer_feedback { StateManager }
    sellbird.setup --> tests.test_setup_manual_product;
    sellbird.setup --> tests.test_setup_precleared;
    sellbird.config --> tests.test_setup_precleared { load_config }
    sellbird.integrations.precleared --> tests.test_setup_precleared { NewKey, PreclearedClient }
    sellbird.paths --> tests.test_setup_precleared { PROJECT_ROOT }
    sellbird.state --> tests.test_signals_export { StateManager }
    sellbird.models.company --> tests.test_signals_export { Company }
    sellbird.models.prospect --> tests.test_signals_export { Prospect }
    sellbird.integrations.tech_detect --> tests.test_signals_export { detect_tech }
    sellbird.export --> tests.test_signals_export {
        CSV_COLUMNS,
        collect_prospects,
        export_prospects_csv,
        to_csv,
    }
    sellbird.agents.writer --> tests.test_site_facts { Writer }
    sellbird.config --> tests.test_site_facts { ComplianceConfig, WriterConfig }
    sellbird.models.company --> tests.test_site_facts { Company }
    sellbird.models.prospect --> tests.test_site_facts { Prospect }
    sellbird.signals --> tests.test_site_facts { seed_signal_catalog }
    sellbird.site_facts --> tests.test_site_facts { HEADER, STALE_DAYS, THIN_PAGES, site_facts }
    sellbird.state --> tests.test_site_facts { StateManager }
    sellbird.state --> tests.test_state { StateManager }
    sellbird.models.prospect --> tests.test_state { Prospect }
    sellbird.models.company --> tests.test_state { Company }
    sellbird.state --> tests.test_state_extra { StateManager }
    sellbird.models.company --> tests.test_state_extra { Company }
    sellbird.models.prospect --> tests.test_state_extra { Prospect }
    sellbird.models.campaign --> tests.test_state_extra { Campaign, EmailStep }
    sellbird.models.conversation --> tests.test_state_extra { Conversation, Message }
    sellbird.storage --> tests.test_storage;
    sellbird.state --> tests.test_storage { StateManager }
    sellbird.workspace_home --> tests.test_storage { Home, use_home }
    sellbird.integrations.mail_provider --> tests.test_suppressions { InboundMessage }
    tests.test_outbox_native --> tests.test_suppressions {
        FakeProvider,
        make_handler,
        make_sender,
        seed_campaign,
        seed_prospect,
        state,
    }
    sellbird.cli --> tests.test_suppressions;
    sellbird.config --> tests.test_trainer_config { SellbirdConfig }
    sellbird.paths --> tests.test_trainer_config { PROJECT_ROOT }
    sellbird.trainer --> tests.test_trainer_config { write_trained_config }
    sellbird.trainer --> tests.test_trainer_objections { Trainer }
    sellbird.dashboard_instance --> tests.test_tray;
    sellbird.desktop.tray --> tests.test_tray;
    sellbird.desktop.tray --> tests.test_tray { COLORS, MENUBAR_PT, make_icon, menubar_png }
    sellbird.desktop_cli --> tests.test_tray { cmd_tray }
    sellbird.dashboard_auth --> tests.test_tray { load_or_create_token }
    sellbird.deliverability --> tests.test_trulyinbox;
    sellbird.config --> tests.test_trulyinbox { WarmupConfig }
    sellbird.integrations.trulyinbox --> tests.test_trulyinbox;
    sellbird.paths --> tests.test_trulyinbox { PROJECT_ROOT }
    sellbird.state --> tests.test_trulyinbox { StateManager }
    sellbird.brain --> tests.test_usage { Brain }
    sellbird.state --> tests.test_usage { StateManager }
    sellbird.integrations.quota --> tests.test_usage { _parse_window, _token_from_json_blob }
    sellbird.usage --> tests.test_usage;
    sellbird.integrations.email_finder --> tests.test_verifier_key_logging;
    sellbird.main --> tests.test_verifier_key_logging;
    sellbird.deliverability --> tests.test_warmup;
    sellbird.config --> tests.test_warmup { EmailChannelConfig, EnvConfig, WarmupConfig }
    tests.test_outbox_native --> tests.test_warmup {
        FakeProvider,
        make_sender,
        seed_prospect,
        state,
    }
    sellbird.agents.sender --> tests.test_warmup { Sender }
    sellbird.models.campaign --> tests.test_warmup { Campaign, EmailStep }
    sellbird.claude_runtime --> tests.test_windows_support;
    sellbird.claude_runtime --> tests.test_windows_support { find_claude }
    sellbird.brain --> tests.test_windows_support;
    sellbird.brain --> tests.test_windows_support { Brain }
    sellbird.config --> tests.test_windows_support { load_config }
    sellbird.textio --> tests.test_windows_support { read_user_text, utf8_stdio }
    sellbird.workspace_home --> tests.test_workspace_home {
        HOSTED_REFUSED,
        Home,
        LOCAL_ONLY,
        NotOnHosted,
        current_home,
        default_home,
        require_self_hosted,
        use_home,
    }
    sellbird.dashboard --> tests.test_workspace_home;
    sellbird.integrations.microsoft --> tests.test_workspace_home;
    sellbird.paths --> tests.test_workspace_home { PROJECT_ROOT }
    sellbird.brain --> tests.test_workspace_home { Brain }
    sellbird.config --> tests.test_writer_email_rules;
    sellbird.config --> tests.test_writer_email_rules {
        ComplianceConfig,
        EmailRulesError,
        MAX_EMAIL_RULES_CHARS,
        WriterConfig,
        load_email_rules,
    }
    sellbird.agents.writer --> tests.test_writer_email_rules {
        BUILT_IN_FOOTER,
        EMAIL_RULES_PROBLEM_KEY,
        Writer,
    }
    sellbird.models.prospect --> tests.test_writer_email_rules { Prospect }
    sellbird.state --> tests.test_writer_email_rules { StateManager }
    sellbird.untrusted --> tests.test_writer_email_rules { UNTRUSTED_RULE }
    sellbird.dashboard --> tests.test_writer_email_rules;
    sellbird.agents.writer --> tests.test_writer_min_score { Writer }
    sellbird.models.prospect --> tests.test_writer_min_score { Prospect }
    tests.test_writer_retry --> tests.test_writer_min_score { FakeBrain, GOOD, state, status }
    sellbird.config --> tests.test_writer_min_score { EmailChannelConfig }
    sellbird.agents.writer --> tests.test_writer_retry { MAX_WRITE_ATTEMPTS, Writer }
    sellbird.main --> tests.test_writer_retry { decide_next_action }
    sellbird.models.prospect --> tests.test_writer_retry { Prospect }
    sellbird.state --> tests.test_writer_retry { StateManager }
    sellbird.brain --> tests.test_writer_retry;
    sellbird.brain --> tests.test_writer_retry { Brain }
    sellbird.config --> tests.test_writer_retry { BrainConfig }
    sellbird.agents.writer --> tests.test_writer_require_tip { NO_TIP_STATUS, Writer }
    sellbird.config --> tests.test_writer_require_tip { WriterConfig }
    sellbird.models.company --> tests.test_writer_require_tip { Company }
    sellbird.models.prospect --> tests.test_writer_require_tip { Prospect }
    sellbird.signals --> tests.test_writer_require_tip { seed_signal_catalog }
    tests.test_writer_retry --> tests.test_writer_require_tip {
        FakeBrain,
        GOOD,
        add,
        state,
        status,
    }
    sellbird.cli --> tests.test_writer_require_tip;
    sellbird.collectors.discover --> tests.test_yc_startups {
        Business,
        _observations,
        build_queries,
        is_junk,
        preset_problem,
    }
    sellbird.collectors.profile --> tests.test_yc_startups {
        ProfileCollector,
        _is_their_yc_page,
        yc_backed,
    }
    sellbird.models.company --> tests.test_yc_startups { Company }
    sellbird.signals --> tests.test_yc_startups { SIGNAL_CATALOG, seed_signal_catalog }
    sellbird.state --> tests.test_yc_startups;
    sellbird.state --> tests.test_yc_startups { StateManager }
    sellbird.cli --> tests.test_yc_startups;
    sellbird.config --> tests.test_yc_startups;
    sellbird.brain --> tests.test_yc_startups { Brain }
    sellbird.paths --> tests.test_yc_startups { PROJECT_ROOT }
    sellbird.models.prospect --> tests.test_yc_startups { Prospect }
    sellbird.agents.writer --> tests.test_yc_startups { Writer }
    sellbird.agents.handler --> tests.test_yc_startups { Handler }
    sellbird.models.conversation --> tests.test_yc_startups { Conversation, Message }
    tests.test_outbox_native --> tests.test_yc_startups { Cfg, Env }
    sellbird.dashboard --> tests.test_yc_startups;
    tests.test_dashboard_signals --> tests.test_yc_startups { client }
    sellbird.paths --> tests.test_signature;
    sellbird.paths --> tests.test_writer_email_rules;
    sellbird.agents.sender --> tests.test_email_style;
    sellbird.register --> tests.test_register;
    sellbird.cli --> tests.test_accelerators_funding;
    sellbird.paths --> tests.test_login_item;
    sellbird.legacy ++> sellbird { adopt_legacy_env }
    sellbird.collectors.profile ++> sellbird.pipeline { profile_companies }
    sellbird.collectors.discover ++> sellbird.pipeline { DEFAULT_PROVIDER, run_discovery }
    sellbird.dashboard_instance as dashboard_instance ++> sellbird.mcp_server;
    sellbird.dashboard_auth ++> sellbird.mcp_server { TokenError, load_or_create_token }
    sellbird.paths ++> sellbird.mcp_server { PROJECT_ROOT }
    sellbird.workspace_home ++> sellbird.mcp_server { NotOnHosted }
    sellbird.extensions as extensions ++> sellbird.mcp_server;
    sellbird.config ++> sellbird.sending_mode { refresh_sending_mode }
    sellbird.integrations.trulyinbox ++> sellbird.deliverability { AFFILIATE_TAG, AFFILIATE_URL }
    sellbird.gate ++> sellbird.export { do_not_contact_match }
    sellbird.state ++> sellbird.export { StateManager }
    sellbird.storage ++> sellbird.export;
    sellbird.config ++> sellbird.export {
        ConfigError,
        ConfigFileNotFoundError,
        do_not_contact_from_file,
        live_do_not_contact,
    }
    sellbird.storage as storage ++> sellbird.export;
    sellbird.config ++> sellbird.booking { operator_timezone, send_window_of }
    sellbird.cli ++> sellbird.__main__ { main }
    sellbird.config ++> sellbird.mailboxes { WarmupConfig, cold_daily_cap }
    sellbird.integrations.mail_provider ++> sellbird.mailboxes {
        MailIdentity,
        MailProvider,
        NATIVE_PROVIDERS,
        identity_from_config,
    }
    sellbird.secrets ++> sellbird.mailboxes { SecretStore, SecretStoreUnavailable }
    sellbird.state ++> sellbird.mailboxes { StateManager, _new_id, _norm }
    sellbird.state ++> sellbird.brain { StateManager }
    sellbird.paths ++> sellbird.brain { PROJECT_ROOT }
    sellbird.textio ++> sellbird.brain { read_user_text }
    sellbird.workspace_home ++> sellbird.brain { current_home }
    sellbird.home ++> sellbird.brain { bundled_defaults }
    sellbird.config ++> sellbird.brain { BrainConfig }
    sellbird.codex ++> sellbird.brain { CodexClient, CodexQuotaClient, CodexError }
    sellbird.integrations.quota ++> sellbird.brain { QuotaClient }
    sellbird.claude_runtime ++> sellbird.brain {
        ClaudeRuntimeError,
        check_cli,
        fingerprint,
        build_command,
        isolated_cwd,
        runtime_env,
    }
    sellbird.textio ++> sellbird.config { read_user_text }
    sellbird.paths ++> sellbird.config { PROJECT_ROOT, HOME_ENV, is_checkout }
    sellbird.gate ++> sellbird.config { do_not_contact_entries }
    sellbird.workspace_home ++> sellbird.config { current_home }
    sellbird.workspace_home ++> sellbird.secrets { current_home }
    sellbird.textio ++> sellbird.offer { read_user_text }
    sellbird.untrusted ++> sellbird.offer { UNTRUSTED_RULE, fence }
    sellbird.agents.writer ++> sellbird.offer { Writer, _names }
    sellbird.textio ++> sellbird.humanize { read_user_text }
    sellbird.untrusted ++> sellbird.humanize { UNTRUSTED_RULE, fence }
    sellbird.paths ++> sellbird.desktop_cli { PROJECT_ROOT }
    sellbird.logsafety ++> sellbird.desktop_cli { RedactSecrets }
    sellbird.desktop.login_item as li ++> sellbird.desktop_cli;
    sellbird.desktop.tray as tray ++> sellbird.desktop_cli;
    sellbird.paths as paths ++> sellbird.home;
    sellbird.mailboxes ++> sellbird.extensions { BUILT_IN_CONNECTIONS }
    sellbird.mailboxes ++> sellbird.inbox_cli {
        ConnectRefused,
        HARD_MAX_INBOX_CAP,
        MAIN,
        MailboxStore,
        build_provider,
        check_provider_allows_inboxes,
        connect_oauth_mailbox,
        connect_smtp_mailbox,
        load_inboxes,
    }
    sellbird.secrets ++> sellbird.inbox_cli { SecretStore, SecretStoreUnavailable }
    sellbird.config ++> sellbird.inbox_cli { load_config, load_env }
    sellbird.state ++> sellbird.inbox_cli { StateManager }
    sellbird.integrations.mail_provider ++> sellbird.inbox_cli {
        NATIVE_PROVIDERS,
        get_mail_provider,
    }
    sellbird.integrations.smtp_mail ++> sellbird.inbox_cli { SmtpSettings }
    sellbird.agent_policy as agent_policy ++> sellbird.dashboard;
    sellbird.dashboard_auth as auth ++> sellbird.dashboard;
    sellbird.paths ++> sellbird.dashboard { PACKAGE_ROOT, PROJECT_ROOT, is_checkout }
    sellbird.storage as storage ++> sellbird.dashboard;
    sellbird.pidfile ++> sellbird.dashboard { LOCK_FILE, loop_lock_held, pid_alive }
    sellbird.textio ++> sellbird.dashboard { read_user_text }
    sellbird.workspace_home ++> sellbird.dashboard { NotOnHosted, use_home }
    sellbird.config ++> sellbird.dashboard {
        ConfigError,
        ConfigFileNotFoundError,
        _find_config_file,
        compliance_footer_lines,
        compliance_notice,
        legacy_sending_held,
        load_brain_config,
        load_config,
        load_env,
        set_require_approval,
    }
    sellbird.integrations.trulyinbox as ti ++> sellbird.dashboard;
    sellbird.deliverability as d ++> sellbird.dashboard;
    sellbird.legacy as legacy ++> sellbird.dashboard;
    sellbird.brain ++> sellbird.dashboard { BRAIN_STATUS_KEY, Brain, active_brain_status }
    sellbird.offer ++> sellbird.dashboard {
        MAX_OFFER_CHARS,
        PROPOSED_KEY,
        company_view,
        offer_view,
        preview_email,
        save_company,
        save_offer,
        suggest_offers,
    }
    sellbird.register ++> sellbird.dashboard { build_register, to_csv }
    sellbird.main ++> sellbird.dashboard { _needs_setup }
    sellbird.codex ++> sellbird.dashboard { CodexClient, CodexQuotaClient }
    sellbird.integrations.quota ++> sellbird.dashboard { QuotaClient }
    sellbird.state ++> sellbird.dashboard {
        HAND_SENT_REASON,
        MANUAL_SEND_KEY,
        MAYBE_SENT_PREFIX,
        StateManager,
    }
    sellbird.gate ++> sellbird.dashboard { _booking_prefix, allowed_link_domains, pre_send_check }
    sellbird.email_style ++> sellbird.dashboard { style_problems }
    sellbird.integrations.mail_provider ++> sellbird.dashboard {
        NATIVE_PROVIDERS,
        get_mail_provider,
    }
    sellbird.export ++> sellbird.dashboard { export_prospects_csv }
    sellbird.collectors.discover ++> sellbird.dashboard {
        DEFAULT_PROVIDER,
        PROVIDERS,
        build_queries,
        estimate_cost,
        preset_problem,
        provider_menu,
    }
    sellbird.pipeline ++> sellbird.dashboard { run_profile_stage, run_prospecting }
    sellbird.signals ++> sellbird.dashboard { seed_signal_catalog }
    sellbird.agents.writer ++> sellbird.dashboard { EMAIL_RULES_PROBLEM_KEY }
    sellbird.sending_mode ++> sellbird.dashboard { held_message }
    sellbird.integrations.precleared ++> sellbird.dashboard { current_hold, hold_message }
    sellbird.inbox_routes ++> sellbird.dashboard { router as _inbox_router }
    sellbird.extensions as _extensions ++> sellbird.dashboard;
    sellbird.dashboard_instance as dashboard_instance ++> sellbird.dashboard;
    sellbird.collectors.people ++> sellbird.fit { title_matches }
    sellbird.gate ++> sellbird.fit { do_not_contact_match }
    sellbird.config ++> sellbird.register { ComplianceConfig, live_do_not_contact }
    sellbird.fit ++> sellbird.register { company_fit, current_roles }
    sellbird.gate ++> sellbird.register { do_not_contact_match }
    sellbird.storage ++> sellbird.register;
    sellbird.storage as storage ++> sellbird.register;
    sellbird.extensions as extensions ++> sellbird.agent_policy;
    sellbird.paths ++> sellbird.legacy { PROJECT_ROOT }
    sellbird.pidfile ++> sellbird.legacy { pid_alive, read_pid }
    sellbird.brain ++> sellbird.main { Brain }
    sellbird.extensions ++> sellbird.main { run_tick_steps }
    sellbird.sending_mode ++> sellbird.main { sync_sending_mode }
    sellbird.config ++> sellbird.main {
        ConfigError,
        load_config,
        load_env,
        SellbirdConfig,
        legacy_sending_held,
        sending_notice,
        compliance_notice,
        send_window_of,
        _find_config_file,
        ConfigFileNotFoundError,
    }
    sellbird.integrations.mail_provider ++> sellbird.main { NATIVE_PROVIDERS }
    sellbird.pidfile ++> sellbird.main {
        LOCK_FILE,
        hold_loop_lock,
        read_pid,
        release_loop_lock,
        remove_pid_file,
        write_pid_file,
    }
    sellbird.pipeline ++> sellbird.main { run_profile_stage }
    sellbird.state ++> sellbird.main { StateManager }
    sellbird.agents.scout ++> sellbird.main { Scout }
    sellbird.agents.writer ++> sellbird.main { Writer }
    sellbird.agents.sender ++> sellbird.main { Sender }
    sellbird.agents.handler ++> sellbird.main { Handler }
    sellbird.agents.analyst ++> sellbird.main { Analyst }
    sellbird.paths ++> sellbird.main { PROJECT_ROOT }
    sellbird.textio ++> sellbird.main { read_user_text, utf8_stdio }
    sellbird.setup ++> sellbird.main { run_setup }
    sellbird.brain ++> sellbird.trainer { Brain }
    sellbird.config ++> sellbird.trainer { BrainConfig, load_brain_config }
    sellbird.public_http ++> sellbird.trainer { UnsafeURLError, public_http_client }
    sellbird.state ++> sellbird.trainer { StateManager }
    sellbird.paths ++> sellbird.trainer { PROJECT_ROOT }
    sellbird.textio ++> sellbird.trainer { read_user_text, utf8_stdio }
    sellbird.untrusted ++> sellbird.trainer { UNTRUSTED_RULE, fence }
    sellbird.paths ++> sellbird.pidfile { PROJECT_ROOT }
    sellbird.models.company ++> sellbird.state { Company }
    sellbird.models.prospect ++> sellbird.state { Prospect }
    sellbird.models.campaign ++> sellbird.state { Campaign }
    sellbird.models.conversation ++> sellbird.state { Conversation }
    sellbird.paths ++> sellbird.state { PROJECT_ROOT }
    sellbird.startups ++> sellbird.state { parse_funding }
    sellbird.storage as storage ++> sellbird.state;
    sellbird.storage ++> sellbird.state { BUSY_TIMEOUT_SECONDS }
    sellbird.workspace_home ++> sellbird.state { _HOME }
    sellbird.paths ++> sellbird.mcp_install { HOME_ENV, PROJECT_ROOT }
    sellbird.workspace_home ++> sellbird.mcp_install { NotOnHosted, require_self_hosted }
    sellbird.mailboxes ++> sellbird.inbox_routes {
        ConnectRefused,
        HARD_MAX_INBOX_CAP,
        MAIN,
        MailboxStore,
        build_provider,
        check_provider_allows_inboxes,
        connect_oauth_mailbox,
        connect_smtp_mailbox,
        load_inboxes,
    }
    sellbird.secrets ++> sellbird.inbox_routes { SecretStore, SecretStoreUnavailable }
    sellbird.config ++> sellbird.inbox_routes { load_config, load_env }
    sellbird.integrations.mail_provider ++> sellbird.inbox_routes {
        NATIVE_PROVIDERS,
        get_mail_provider,
    }
    sellbird.integrations.smtp_mail ++> sellbird.inbox_routes { SmtpSettings }
    sellbird.brain ++> sellbird.setup { Brain }
    sellbird.config ++> sellbird.setup { BrainConfig, COUNTRY_ALIASES, normalize_prospect_country }
    sellbird.integrations.precleared ++> sellbird.setup {
        GET_KEY_URL,
        SENDER_COUNTRIES,
        create_free_key,
    }
    sellbird.state ++> sellbird.setup { StateManager }
    sellbird.paths ++> sellbird.setup { PROJECT_ROOT }
    sellbird.textio ++> sellbird.setup { read_user_text, utf8_stdio }
    sellbird.untrusted ++> sellbird.gate { UNTRUSTED_RULE }
    sellbird.paths ++> sellbird.gate { PROJECT_ROOT }
    include sellbird.models.campaign ++> sellbird.models { Campaign, EmailStep }
    include sellbird.models.company ++> sellbird.models { Company }
    include sellbird.models.conversation ++> sellbird.models { Conversation, Message, STAGES }
    include sellbird.models.prospect ++> sellbird.models { Prospect }
    sellbird.models.company ++> sellbird.models.campaign { _utcnow }
    sellbird.models.company ++> sellbird.models.conversation { _utcnow }
    sellbird.models.company ++> sellbird.models.prospect { _utcnow }
    sellbird.models.conversation ++> sellbird.models.campaign { _parse_rows }
    sellbird.brain ++> sellbird.agents.writer { Brain }
    sellbird.config ++> sellbird.agents.writer {
        EmailRulesError,
        SellbirdConfig,
        compliance_of,
        load_config,
        load_email_rules,
    }
    sellbird.email_style ++> sellbird.agents.writer {
        BREAKUP_MAX_WORDS,
        FIRST_EMAIL_MAX_WORDS,
        FOLLOW_UP_MAX_WORDS,
        style_problems,
        tidy,
        with_sign_off,
    }
    sellbird.humanize ++> sellbird.agents.writer { humanize, humanizer_enabled }
    sellbird.integrations.mail_provider ++> sellbird.agents.writer { NATIVE_PROVIDERS }
    sellbird.models.campaign ++> sellbird.agents.writer { Campaign, EmailStep }
    sellbird.state ++> sellbird.agents.writer { StateManager, WRITABLE_EMAIL_STATUSES }
    sellbird.sending_mode ++> sellbird.agents.writer { sync_sending_mode }
    sellbird.site_facts ++> sellbird.agents.writer { site_facts }
    sellbird.startups ++> sellbird.agents.writer { startup_facts }
    sellbird.untrusted ++> sellbird.agents.writer { UNTRUSTED_RULE, fence }
    sellbird.workspace_home ++> sellbird.agents.writer { current_home }
    sellbird.brain ++> sellbird.agents.scout { Brain }
    sellbird.collectors.people as people_mod ++> sellbird.agents.scout;
    sellbird.collectors.discover ++> sellbird.agents.scout { site_name_from_html }
    sellbird.collectors.profile ++> sellbird.agents.scout {
        _reads_like_title,
        fold_accents,
        looks_like_challenge,
    }
    sellbird.config ++> sellbird.agents.scout { EnvConfig, SellbirdConfig, live_do_not_contact }
    sellbird.gate ++> sellbird.agents.scout { do_not_contact_domain_match }
    sellbird.integrations.email_finder ++> sellbird.agents.scout {
        DEFAULT_PATTERN,
        SMALL_BUSINESS_PATTERN,
        find_email,
        hunter_domain_people,
        hunter_searches_remaining,
        record_hunter_search,
        site_email_evidence,
        verify_published_address,
    }
    sellbird.integrations.linkedin ++> sellbird.agents.scout { LinkedInAutomation }
    sellbird.models.company ++> sellbird.agents.scout { Company }
    sellbird.models.prospect ++> sellbird.agents.scout { COMPANY_INBOX_SOURCE, Prospect }
    sellbird.public_http ++> sellbird.agents.scout { public_http_client }
    sellbird.state ++> sellbird.agents.scout { StateManager }
    sellbird.untrusted ++> sellbird.agents.scout { UNTRUSTED_RULE, fence }
    sellbird.integrations.tech_detect ++> sellbird.agents.scout { detect_tech }
    sellbird.collectors.ats ++> sellbird.agents.scout { role_keywords }
    sellbird.config ++> sellbird.agents.sender {
        cold_daily_cap,
        compliance_footer_lines,
        compliance_notice,
        compliance_of,
        live_do_not_contact,
        operator_timezone,
        send_window_of,
    }
    sellbird.extensions as extensions ++> sellbird.agents.sender;
    sellbird.gate ++> sellbird.agents.sender {
        autopilot_review,
        do_not_contact_match,
        pre_send_check,
    }
    sellbird.send_hooks ++> sellbird.agents.sender {
        NO_HEADERS_HOLD,
        SendCheck,
        SendHookError,
        extra_headers,
        first_verdict,
    }
    sellbird.send_window ++> sellbird.agents.sender {
        in_window,
        next_send_time,
        recipient_country,
        recipient_zone,
    }
    sellbird.integrations.instantly ++> sellbird.agents.sender { InstantlyClient }
    sellbird.integrations.mail_provider ++> sellbird.agents.sender {
        NATIVE_PROVIDERS,
        get_mail_provider,
    }
    sellbird.integrations.precleared ++> sellbird.agents.sender {
        UNKNOWN_ATTEMPTS,
        UNKNOWN_RETRY_AFTER,
        PreclearedClient,
        clear_hold,
        record_hold,
    }
    sellbird.integrations.signature ++> sellbird.agents.sender { signature_problem }
    sellbird.email_style ++> sellbird.agents.sender { style_problems }
    sellbird.mailboxes ++> sellbird.agents.sender { load_inboxes }
    sellbird.sending_mode ++> sellbird.agents.sender { SIGNATURE_HOLD_PREFIX, sync_sending_mode }
    sellbird.state ++> sellbird.agents.sender {
        AUTOPILOT_OFF_REASON,
        COLLEAGUE_REPLIED,
        HAND_SENT_REASON,
        HELD_FOR_REVIEW,
        MANUAL_SEND_KEY,
        MAYBE_SENT_PREFIX,
        MOVED_BACK_PREFIXES,
        RECHECK_PREFIX,
        UNKNOWN_HOLD_PREFIX,
    }
    sellbird.models.conversation ++> sellbird.agents.sender { Message }
    sellbird.storage as storage ++> sellbird.agents.sender;
    sellbird.state ++> sellbird.agents.analyst { StateManager }
    sellbird.booking ++> sellbird.agents.handler { booking_instruction }
    sellbird.brain ++> sellbird.agents.handler { BrainUnavailable }
    sellbird.config ++> sellbird.agents.handler {
        DEFAULT_OPT_OUT_LINE,
        PREVIOUS_DEFAULT_OPT_OUT_LINE,
        compliance_of,
        legacy_sending_held,
        live_do_not_contact,
    }
    sellbird.gate ++> sellbird.agents.handler {
        autopilot_review,
        do_not_contact_match,
        pre_send_check,
    }
    sellbird.email_style ++> sellbird.agents.handler { style_problems, tidy }
    sellbird.humanize ++> sellbird.agents.handler { humanize, humanizer_enabled }
    sellbird.integrations.instantly ++> sellbird.agents.handler { InstantlyClient }
    sellbird.integrations.mail_provider ++> sellbird.agents.handler {
        NATIVE_PROVIDERS,
        get_mail_provider,
        strip_quoted_reply,
    }
    sellbird.models.conversation ++> sellbird.agents.handler { Conversation, Message }
    sellbird.send_window ++> sellbird.agents.handler { recipient_zone }
    sellbird.state ++> sellbird.agents.handler { COLLEAGUE_REPLIED, REVIEW_NEXT_REPLY_KEY }
    sellbird.sending_mode ++> sellbird.agents.handler { sync_sending_mode }
    sellbird.startups ++> sellbird.agents.handler { startup_facts }
    sellbird.untrusted ++> sellbird.agents.handler { UNTRUSTED_RULE, fence }
    sellbird.mailboxes ++> sellbird.agents.handler { load_inboxes }
    sellbird.handoff ++> sellbird.agents.handler { hand_off }
    sellbird.integrations.signature ++> sellbird.integrations.mail_provider { set_body }
    sellbird.paths ++> sellbird.integrations.signature { PROJECT_ROOT }
    sellbird.paths ++> sellbird.integrations.linkedin { PROJECT_ROOT }
    sellbird.paths ++> sellbird.integrations.gmail { PROJECT_ROOT }
    sellbird.workspace_home ++> sellbird.integrations.gmail { current_home }
    sellbird.integrations.mail_provider ++> sellbird.integrations.gmail {
        InboundMessage,
        MailIdentity,
        MailProvider,
        SendResult,
        TokenSource,
        compose,
        identity_from_config,
        looks_like_bounce,
        missing_token_text,
        read_token_file,
        save_if_signed_in_as,
        token_urlsafe,
        write_token_file,
    }
    sellbird.integrations.loopback ++> sellbird.integrations.gmail { loopback_code }
    sellbird.integrations.signature ++> sellbird.integrations.gmail {
        SignatureError,
        load_signature,
    }
    sellbird.usage ++> sellbird.integrations.quota { claude_config_dir }
    sellbird.paths ++> sellbird.integrations.microsoft { PROJECT_ROOT }
    sellbird.workspace_home ++> sellbird.integrations.microsoft { current_home }
    sellbird.integrations.mail_provider ++> sellbird.integrations.microsoft {
        InboundMessage,
        MailIdentity,
        MailProvider,
        SendResult,
        TokenSource,
        identity_from_config,
        looks_like_bounce,
        missing_token_text,
        read_token_file,
        save_if_signed_in_as,
        token_urlsafe,
        write_token_file,
    }
    sellbird.integrations.loopback ++> sellbird.integrations.microsoft { loopback_code }
    sellbird.integrations.signature ++> sellbird.integrations.microsoft {
        SignatureError,
        load_signature,
        render_html,
    }
    sellbird.integrations.mail_provider ++> sellbird.integrations.smtp_mail {
        InboundMessage,
        MailIdentity,
        MailProvider,
        SendResult,
        compose,
        identity_from_config,
        looks_like_bounce,
    }
    sellbird.integrations.signature ++> sellbird.integrations.smtp_mail {
        SignatureError,
        load_signature,
    }
    sellbird.config ++> sellbird.integrations.precleared {
        PRECLEARED_SENDER_COUNTRIES,
        normalize_prospect_country,
    }
    sellbird.send_window ++> sellbird.integrations.precleared { icp_country }
    sellbird.integrations.mail_provider ++> sellbird.integrations.precleared { NATIVE_PROVIDERS }
    sellbird.public_http ++> sellbird.collectors.profile { public_http_client }
    sellbird.startups ++> sellbird.collectors.profile { funding_text }
    sellbird.collectors.ats ++> sellbird.collectors.profile {
        detect_board,
        matching_roles,
        read_board,
        role_keywords,
    }
    sellbird.collectors.discover ++> sellbird.collectors.profile {
        name_from_domain,
        name_matches_domain,
        site_name_from_html,
    }
    sellbird.signals ++> sellbird.collectors.profile { seed_signal_catalog }
    sellbird.models ++> sellbird.collectors.discover { Company }
    sellbird.collectors.ats ++> sellbird.collectors.discover { role_keywords }
    sellbird.config ++> sellbird.collectors.discover { live_do_not_contact, load_env }
    sellbird.gate ++> sellbird.collectors.discover { do_not_contact_domain_match }
    sellbird.signals ++> sellbird.collectors.discover { seed_signal_catalog }
    sellbird.collectors.profile ++> sellbird.collectors.people {
        NON_NAME_WORDS,
        _NOUN_SUFFIX,
        _reads_like_title,
        _strip_code,
        fold_accents,
        nfc,
        ProfileCollector,
    }
    sellbird.paths ++> sellbird.desktop.login_item { HOME_ENV, PROJECT_ROOT, user_home_default }
    sellbird.dashboard_instance as dashboard_instance ++> sellbird.desktop.tray;
    sellbird.dashboard_auth ++> sellbird.desktop.tray { TokenError, TokenStore }
    sellbird.mcp_server ++> sellbird.desktop.tray { base_url }
    sellbird.desktop.login_item as login_item ++> sellbird.desktop.tray;
    sellbird.pidfile ++> sellbird.desktop.tray { hold_loop_lock, release_loop_lock }
    harvey.cli ++> harvey.__main__ { main }
    harvey ++> harvey.cli { NOTICE }
    sellbird ++> harvey.cli;
    sellbird.cli ++> harvey.cli { main as sellbird_main }
}

graph spaces {
    space sellbird: cpython { "."; }
    package sellbird { ship sellbird; }
    space sellbird_dev: cpython { scripts.* | tests | tests.*; }
}
