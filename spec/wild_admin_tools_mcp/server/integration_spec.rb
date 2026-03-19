# frozen_string_literal: true

RSpec.describe 'MCP Server end-to-end lifecycle' do
  let(:job_adapter) { WildAdminToolsMcp::TestSupport::TestJobAdapter.new }
  let(:cache_adapter) { WildAdminToolsMcp::TestSupport::TestCacheAdapter.new }
  let(:flag_adapter) { WildAdminToolsMcp::TestSupport::TestFlagAdapter.new }
  let(:gate) { WildAdminToolsMcp::TestSupport::TestGate.new }
  let(:audit_store) { WildAdminToolsMcp::Audit::MemoryStore.new }

  let(:pipeline) do
    WildAdminToolsMcp::Server::ServerFactory.build_pipeline(
      gate: gate,
      policy_config: valid_policy_config,
      audit_store: audit_store
    )
  end

  let(:caller_id) { 'operator-mcp-e2e' }

  let(:server_context) do
    WildAdminToolsMcp::Server::ServerFactory.build_server_context(
      pipeline: pipeline,
      caller_id: caller_id
    )
  end

  before do
    WildAdminToolsMcp.configure do |c|
      c.job_adapter = job_adapter
      c.cache_adapter = cache_adapter
      c.flag_adapter = flag_adapter
    end
    job_adapter.seed_job('job-e2e')
    cache_adapter.seed_key('cache:e2e', 'cached_value')
    flag_adapter.seed_flag('release_flag')
  end

  after do
    pipeline.instance_variable_get(:@audited_pipeline).two_phase.nonce_manager.store.stop_sweep!
  end

  describe 'read lifecycle via manage_background_jobs' do
    it 'returns success directly for a read action' do
      response = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'inspect_job', job_id: 'job-e2e', server_context: server_context
      )

      expect(response.error?).to be false
      body = response.structured_content
      expect(body[:status]).to eq('success')
      expect(body[:operation]).to eq('read')
    end
  end

  describe 'mutation two-phase lifecycle via manage_background_jobs' do
    it 'returns a preview with nonce on first call' do
      preview = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'retry_job', job_id: 'job-e2e', server_context: server_context
      )

      expect(preview.error?).to be false
      body = preview.structured_content
      expect(body[:status]).to eq('preview')
      expect(body[:metadata][:nonce]).to start_with('wnc_')
      expect(body[:metadata][:requires_confirmation]).to be true
    end

    it 'executes with snapshots when confirmed with nonce' do
      preview = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'retry_job', job_id: 'job-e2e', server_context: server_context
      )
      nonce = preview.structured_content[:metadata][:nonce]

      confirm = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'retry_job', job_id: 'job-e2e', nonce: nonce, server_context: server_context
      )

      expect(confirm.error?).to be false
      body = confirm.structured_content
      expect(body[:status]).to eq('success')
      expect(body[:before_snapshot]).not_to be_nil
      expect(body[:after_snapshot]).not_to be_nil
    end
  end

  describe 'gate denial' do
    it 'returns denied when the gate rejects the caller' do
      gate.default_result = false

      response = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'inspect_job', job_id: 'job-e2e', server_context: server_context
      )

      expect(response.error?).to be true
      body = response.structured_content
      expect(body[:status]).to eq('denied')
      expect(body[:reason]).to eq('gate_denied')
    end
  end

  describe 'anonymous rejection' do
    it 'returns denied when no caller_id is provided' do
      anon_context = WildAdminToolsMcp::Server::ServerFactory.build_server_context(
        pipeline: pipeline,
        caller_id: nil
      )

      response = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'inspect_job', job_id: 'job-e2e', server_context: anon_context
      )

      expect(response.error?).to be true
      body = response.structured_content
      expect(body[:status]).to eq('denied')
      expect(body[:reason]).to eq('anonymous_request_rejected')
    end
  end

  describe 'unknown action' do
    it 'returns denied with action_not_allowed' do
      response = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'drop_database', server_context: server_context
      )

      expect(response.error?).to be true
      body = response.structured_content
      expect(body[:status]).to eq('denied')
      expect(body[:reason]).to eq('action_not_allowed')
    end
  end

  describe 'nonce replay protection' do
    it 'rejects a reused nonce' do
      preview = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'retry_job', job_id: 'job-e2e', server_context: server_context
      )
      nonce = preview.structured_content[:metadata][:nonce]

      WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'retry_job', job_id: 'job-e2e', nonce: nonce, server_context: server_context
      )

      replay = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'retry_job', job_id: 'job-e2e', nonce: nonce, server_context: server_context
      )

      expect(replay.error?).to be true
      expect(replay.structured_content[:status]).to eq('denied')
      expect(replay.structured_content[:reason]).to eq('nonce_invalid')
    end
  end

  describe 'audit trail verification' do
    it 'records audit entries for both read and mutation paths' do
      WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
        action: 'inspect_job', job_id: 'job-e2e', server_context: server_context
      )

      preview = WildAdminToolsMcp::Server::Tools::ManageCache.call(
        action: 'invalidate_cache_key', cache_key: 'cache:e2e', server_context: server_context
      )
      nonce = preview.structured_content[:metadata][:nonce]
      WildAdminToolsMcp::Server::Tools::ManageCache.call(
        action: 'invalidate_cache_key', cache_key: 'cache:e2e', nonce: nonce,
        server_context: server_context
      )

      expect(audit_store.count).to be >= 3
    end
  end

  describe 'each tool dispatches correctly' do
    it 'manage_cache handles a read action' do
      response = WildAdminToolsMcp::Server::Tools::ManageCache.call(
        action: 'inspect_cache_key', cache_key: 'cache:e2e', server_context: server_context
      )

      expect(response.error?).to be false
      expect(response.structured_content[:status]).to eq('success')
    end

    it 'manage_feature_flags handles a read action' do
      response = WildAdminToolsMcp::Server::Tools::ManageFeatureFlags.call(
        action: 'read_flag', flag_name: 'release_flag', server_context: server_context
      )

      expect(response.error?).to be false
      expect(response.structured_content[:status]).to eq('success')
    end

    it 'manage_feature_flags handles a mutation lifecycle' do
      preview = WildAdminToolsMcp::Server::Tools::ManageFeatureFlags.call(
        action: 'toggle_flag', flag_name: 'release_flag', enabled: true,
        server_context: server_context
      )

      expect(preview.structured_content[:status]).to eq('preview')
      nonce = preview.structured_content[:metadata][:nonce]

      confirm = WildAdminToolsMcp::Server::Tools::ManageFeatureFlags.call(
        action: 'toggle_flag', flag_name: 'release_flag', enabled: true,
        nonce: nonce, server_context: server_context
      )

      expect(confirm.structured_content[:status]).to eq('success')
    end
  end
end
