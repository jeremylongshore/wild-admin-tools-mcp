# frozen_string_literal: true

require 'wild_admin_tools_mcp'
require_relative 'support/test_adapters'
require_relative 'support/shared_examples/executor_shared_examples'
require_relative 'support/policy_fixtures'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  config.include WildAdminToolsMcp::TestSupport::PolicyFixtures

  config.before do
    WildAdminToolsMcp.reset_configuration!
  end
end
