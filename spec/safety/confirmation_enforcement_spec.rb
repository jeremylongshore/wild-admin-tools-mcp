# frozen_string_literal: true

RSpec.describe 'Confirmation enforcement — adversarial safety' do
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

  let(:caller_id) { 'confirmation-tester' }

  let(:server_context) do
    WildAdminToolsMcp::Server::ServerFactory.build_server_context(
      pipeline: pipeline, caller_id: caller_id
    )
  end

  before do
    WildAdminToolsMcp.configure do |c|
      c.job_adapter = job_adapter
      c.cache_adapter = cache_adapter
      c.flag_adapter = flag_adapter
    end
    job_adapter.seed_job('job-1')
  end

  after { nonce_store.stop_sweep! }

  it 'returns preview (not execute) when nonce is nil' do
    response = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', server_context: server_context
    )
    expect(response.structured_content[:status]).to eq('preview')
    expect(job_adapter.write_methods_called).to be_empty
  end

  it 'denies a fabricated nonce' do
    response = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', nonce: 'fake_nonce_123',
      server_context: server_context
    )
    body = response.structured_content
    expect(body[:status]).to eq('denied')
    expect(body[:reason]).to eq('nonce_invalid')
    expect(job_adapter.write_methods_called).to be_empty
  end

  it 'denies an empty string nonce' do
    response = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', nonce: '',
      server_context: server_context
    )
    body = response.structured_content
    expect(body[:status]).to eq('denied')
    expect(body[:reason]).to eq('nonce_invalid')
    expect(job_adapter.write_methods_called).to be_empty
  end

  it 'denies an expired nonce' do
    preview = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', server_context: server_context
    )
    nonce = preview.structured_content[:metadata][:nonce]
    expire_nonce!(nonce)

    response = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', nonce: nonce, server_context: server_context
    )
    expect(response.structured_content[:status]).to eq('denied')
    expect(response.structured_content[:reason]).to eq('nonce_invalid')
    expect(job_adapter.write_methods_called).to be_empty
  end

  it 'denies a previously consumed nonce' do
    preview = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', server_context: server_context
    )
    nonce = preview.structured_content[:metadata][:nonce]
    tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', nonce: nonce, server_context: server_context
    )

    replay = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', nonce: nonce, server_context: server_context
    )
    expect(replay.structured_content[:status]).to eq('denied')
    expect(replay.structured_content[:reason]).to eq('nonce_invalid')
  end

  it 'denies a nonce generated for a different action' do
    preview = tools::ManageBackgroundJobs.call(
      action: 'discard_job', job_id: 'job-1', server_context: server_context
    )
    nonce = preview.structured_content[:metadata][:nonce]

    response = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', nonce: nonce, server_context: server_context
    )
    expect(response.structured_content[:status]).to eq('denied')
    expect(response.structured_content[:reason]).to eq('nonce_invalid')
    expect(job_adapter.write_methods_called).to be_empty
  end

  it 'denies a nonce generated for a different caller' do
    preview = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', server_context: server_context
    )
    nonce = preview.structured_content[:metadata][:nonce]

    other_context = WildAdminToolsMcp::Server::ServerFactory.build_server_context(
      pipeline: pipeline, caller_id: 'impersonator'
    )
    response = tools::ManageBackgroundJobs.call(
      action: 'retry_job', job_id: 'job-1', nonce: nonce, server_context: other_context
    )
    expect(response.structured_content[:status]).to eq('denied')
    expect(response.structured_content[:reason]).to eq('nonce_invalid')
    expect(job_adapter.write_methods_called).to be_empty
  end
end
