# frozen_string_literal: true

RSpec.describe 'Blast radius caps — adversarial safety' do
  let(:job_adapter) { WildAdminToolsMcp::TestSupport::TestJobAdapter.new }
  let(:tools) { WildAdminToolsMcp::Server::Tools }
  let(:cache_adapter) { WildAdminToolsMcp::TestSupport::TestCacheAdapter.new }
  let(:flag_adapter) { WildAdminToolsMcp::TestSupport::TestFlagAdapter.new }
  let(:gate) { WildAdminToolsMcp::TestSupport::TestGate.new }
  let(:audit_store) { WildAdminToolsMcp::Audit::MemoryStore.new }

  let(:pipeline) do
    WildAdminToolsMcp::Server::ServerFactory.build_pipeline(
      gate: gate, policy_config: full_policy_config, audit_store: audit_store
    )
  end

  let(:server_context) do
    WildAdminToolsMcp::Server::ServerFactory.build_server_context(
      pipeline: pipeline, caller_id: 'blast-radius-tester'
    )
  end

  before do
    WildAdminToolsMcp.configure do |c|
      c.job_adapter = job_adapter
      c.cache_adapter = cache_adapter
      c.flag_adapter = flag_adapter
    end
  end

  after { nonce_store.stop_sweep! }

  context 'when job count exceeds cap of 100' do
    before do
      150.times { |i| job_adapter.seed_job("job-#{i}", queue: 'overloaded') }
    end

    it 'denies retry_jobs_by_filter with blast_radius_exceeded' do
      response = tools::ManageBackgroundJobs.call(
        action: 'retry_jobs_by_filter',
        filter: { 'queue_name' => 'overloaded' },
        server_context: server_context
      )
      body = response.structured_content
      expect(body[:status]).to eq('denied')
      expect(body[:reason]).to eq('blast_radius_exceeded')
      expect(body[:estimated_count]).to eq(150)
      expect(body[:cap]).to eq(100)
      expect(job_adapter.write_methods_called).to be_empty
    end
  end

  context 'when cache key count exceeds cap of 500' do
    before do
      600.times { |i| cache_adapter.seed_key("bulk:key-#{i}", 'val') }
    end

    it 'denies invalidate_cache_pattern with blast_radius_exceeded' do
      response = tools::ManageCache.call(
        action: 'invalidate_cache_pattern',
        pattern: 'bulk:',
        server_context: server_context
      )
      body = response.structured_content
      expect(body[:status]).to eq('denied')
      expect(body[:reason]).to eq('blast_radius_exceeded')
      expect(body[:estimated_count]).to eq(600)
      expect(body[:cap]).to eq(500)
      expect(cache_adapter.write_methods_called).to be_empty
    end
  end

  context 'when count is within cap' do
    before do
      50.times { |i| job_adapter.seed_job("job-#{i}", queue: 'safe') }
    end

    it 'allows retry_jobs_by_filter when under the cap' do
      response = tools::ManageBackgroundJobs.call(
        action: 'retry_jobs_by_filter',
        filter: { 'queue_name' => 'safe' },
        server_context: server_context
      )
      expect(response.structured_content[:status]).to eq('preview')
    end
  end
end
