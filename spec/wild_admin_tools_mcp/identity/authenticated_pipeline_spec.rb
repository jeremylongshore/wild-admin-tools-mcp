# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/test_gate'

RSpec.describe WildAdminToolsMcp::Identity::AuthenticatedPipeline do
  let(:test_gate) { WildAdminToolsMcp::TestSupport::TestGate.new }
  let(:gate_client) { WildAdminToolsMcp::Identity::GateClient.new(gate: test_gate) }
  let(:audit_store) { WildAdminToolsMcp::Audit::MemoryStore.new }
  let(:recorder) { WildAdminToolsMcp::Audit::Recorder.new(store: audit_store) }
  let(:policy_config) { valid_policy_config }
  let(:guard_pipeline) { WildAdminToolsMcp::Guard::Pipeline.new(policy_config: policy_config) }
  let(:audited_pipeline) { WildAdminToolsMcp::Audit::AuditedPipeline.new(pipeline: guard_pipeline, recorder: recorder) }
  let(:pipeline) { described_class.new(audited_pipeline: audited_pipeline, gate_client: gate_client) }

  before do
    WildAdminToolsMcp.configure do |config|
      config.job_adapter = WildAdminToolsMcp::TestSupport::TestJobAdapter.new
      config.cache_adapter = WildAdminToolsMcp::TestSupport::TestCacheAdapter.new
      config.flag_adapter = WildAdminToolsMcp::TestSupport::TestFlagAdapter.new
    end

    pipeline.register_executor(WildAdminToolsMcp::Executor::JobExecutor.new)
    pipeline.register_executor(WildAdminToolsMcp::Executor::CacheExecutor.new)
    pipeline.register_executor(WildAdminToolsMcp::Executor::FlagExecutor.new)

    WildAdminToolsMcp.configuration.job_adapter.seed_job(
      'job_1', status: 'completed', queue: 'default'
    )
  end

  describe '#call' do
    context 'with authenticated and authorized caller' do
      it 'executes the action' do
        result = pipeline.call('inspect_job', { job_id: 'job_1' }, { caller_id: 'user_1' })
        expect(result.status).to eq(:success)
      end

      it 'creates an audit record with identity' do
        pipeline.call('inspect_job', { job_id: 'job_1' }, { caller_id: 'user_1' })
        record = audit_store.recent(limit: 1).first
        expect(record.caller_id).to eq('user_1')
        expect(record.gate_result).to eq('allowed')
      end
    end

    context 'with anonymous caller' do
      it 'rejects the request' do
        result = pipeline.call('inspect_job', { job_id: 'job_1' }, nil)
        expect(result.status).to eq(:denied)
        expect(result.metadata[:reason]).to eq('anonymous_request_rejected')
      end

      it 'creates an audit record for the denial' do
        pipeline.call('inspect_job', { job_id: 'job_1' }, nil)
        record = audit_store.recent(limit: 1).first
        expect(record.outcome).to eq('denied')
        expect(record.denial_reason).to eq('anonymous_request_rejected')
      end

      it 'rejects empty caller_id' do
        result = pipeline.call('inspect_job', { job_id: 'job_1' }, { caller_id: '' })
        expect(result.status).to eq(:denied)
      end

      it 'rejects whitespace caller_id' do
        result = pipeline.call('inspect_job', { job_id: 'job_1' }, { caller_id: '   ' })
        expect(result.status).to eq(:denied)
      end
    end

    context 'when gate denies' do
      before { test_gate.default_result = false }

      it 'rejects the request' do
        result = pipeline.call('inspect_job', { job_id: 'job_1' }, { caller_id: 'user_1' })
        expect(result.status).to eq(:denied)
        expect(result.metadata[:reason]).to eq('gate_denied')
      end

      it 'creates an audit record with denial' do
        pipeline.call('inspect_job', { job_id: 'job_1' }, { caller_id: 'user_1' })
        record = audit_store.recent(limit: 1).first
        expect(record.outcome).to eq('denied')
        expect(record.gate_result).to eq('denied')
      end
    end

    context 'when gate is unavailable (raises error)' do
      let(:broken_gate) do
        Object.new.tap do |g|
          def g.evaluate(**_args)
            raise 'connection refused'
          end
        end
      end
      let(:gate_client) { WildAdminToolsMcp::Identity::GateClient.new(gate: broken_gate) }

      it 'fails closed — denies the request' do
        result = pipeline.call('inspect_job', { job_id: 'job_1' }, { caller_id: 'user_1' })
        expect(result.status).to eq(:denied)
        expect(result.metadata[:reason]).to eq('gate_denied')
      end
    end

    context 'with mutation (two-phase)' do
      before do
        WildAdminToolsMcp.configuration.job_adapter.seed_job(
          'job_fail', status: 'failed', queue: 'critical'
        )
      end

      it 'returns preview for mutations' do
        result = pipeline.call('retry_job', { job_id: 'job_fail' }, { caller_id: 'user_1' })
        expect(result.status).to eq(:preview)
      end
    end

    context 'when identity flows through to audit' do
      it 'records the real caller_id in audit' do
        pipeline.call('inspect_job', { job_id: 'job_1' }, { caller_id: 'real_admin_42' })
        record = audit_store.recent(limit: 1).first
        expect(record.caller_id).to eq('real_admin_42')
      end
    end
  end
end
