# frozen_string_literal: true

RSpec.describe WildAdminToolsMcp::Executor::Base do
  let(:job_adapter) { WildAdminToolsMcp::TestSupport::TestJobAdapter.new }
  let(:cache_adapter) { WildAdminToolsMcp::TestSupport::TestCacheAdapter.new }
  let(:flag_adapter) { WildAdminToolsMcp::TestSupport::TestFlagAdapter.new }

  before do
    WildAdminToolsMcp.configure do |c|
      c.job_adapter = job_adapter
      c.cache_adapter = cache_adapter
      c.flag_adapter = flag_adapter
    end
  end

  describe '#handles?' do
    let(:executor) { WildAdminToolsMcp::Executor::JobExecutor.new }

    it 'returns true for known actions' do
      expect(executor.handles?('inspect_job')).to be true
    end

    it 'returns false for unknown actions' do
      expect(executor.handles?('unknown_action')).to be false
    end
  end

  describe '#action_names' do
    it 'returns all action names for JobExecutor' do
      executor = WildAdminToolsMcp::Executor::JobExecutor.new
      expect(executor.action_names).to contain_exactly(
        'inspect_job', 'list_failed_jobs', 'list_queues',
        'retry_job', 'retry_jobs_by_filter', 'discard_job', 'discard_jobs_by_filter'
      )
    end
  end

  describe 'unknown action' do
    let(:executor) { WildAdminToolsMcp::Executor::JobExecutor.new }

    it 'raises ActionNotFoundError on preview' do
      expect { executor.preview('nonexistent') }.to raise_error(
        WildAdminToolsMcp::ActionNotFoundError, /nonexistent/
      )
    end

    it 'raises ActionNotFoundError on execute' do
      expect { executor.execute('nonexistent') }.to raise_error(
        WildAdminToolsMcp::ActionNotFoundError, /nonexistent/
      )
    end
  end

  describe 'adapter error translation' do
    let(:executor) { WildAdminToolsMcp::Executor::JobExecutor.new }

    it 'wraps unexpected errors in AdapterError' do
      allow(job_adapter).to receive(:find_job).and_raise(RuntimeError, 'connection lost')
      expect { executor.preview('inspect_job', { job_id: '123' }) }.to raise_error(
        WildAdminToolsMcp::AdapterError, /connection lost/
      )
    end
  end
end
