# frozen_string_literal: true

require_relative 'wild_admin_tools_mcp/version'
require_relative 'wild_admin_tools_mcp/errors'
require_relative 'wild_admin_tools_mcp/result'
require_relative 'wild_admin_tools_mcp/configuration'
require_relative 'wild_admin_tools_mcp/executor/adapters/job_adapter'
require_relative 'wild_admin_tools_mcp/executor/adapters/cache_adapter'
require_relative 'wild_admin_tools_mcp/executor/adapters/flag_adapter'
require_relative 'wild_admin_tools_mcp/executor/state_capture'
require_relative 'wild_admin_tools_mcp/executor/base'
require_relative 'wild_admin_tools_mcp/executor/job_executor'
require_relative 'wild_admin_tools_mcp/executor/cache_executor'
require_relative 'wild_admin_tools_mcp/executor/flag_executor'
require_relative 'wild_admin_tools_mcp/guard/policy_config'
require_relative 'wild_admin_tools_mcp/guard/action_allowlist'
require_relative 'wild_admin_tools_mcp/guard/parameter_validator'
require_relative 'wild_admin_tools_mcp/guard/blast_radius_enforcer'
require_relative 'wild_admin_tools_mcp/guard/sliding_window'
require_relative 'wild_admin_tools_mcp/guard/rate_limiter'
require_relative 'wild_admin_tools_mcp/guard/nonce_store'
require_relative 'wild_admin_tools_mcp/guard/nonce_manager'
require_relative 'wild_admin_tools_mcp/guard/two_phase_flow'
require_relative 'wild_admin_tools_mcp/guard/pipeline'
require_relative 'wild_admin_tools_mcp/audit/record'
require_relative 'wild_admin_tools_mcp/audit/parameter_sanitizer'
require_relative 'wild_admin_tools_mcp/audit/store'
require_relative 'wild_admin_tools_mcp/audit/recorder'
require_relative 'wild_admin_tools_mcp/audit/audited_pipeline'
require_relative 'wild_admin_tools_mcp/identity/session_context'
require_relative 'wild_admin_tools_mcp/identity/identity_extractor'
require_relative 'wild_admin_tools_mcp/identity/gate_client'
require_relative 'wild_admin_tools_mcp/identity/gate_health_check'
require_relative 'wild_admin_tools_mcp/identity/authenticated_pipeline'

module WildAdminToolsMcp
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
