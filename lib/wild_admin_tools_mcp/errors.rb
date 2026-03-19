# frozen_string_literal: true

module WildAdminToolsMcp
  class Error < StandardError; end

  class ActionNotFoundError < Error
    attr_reader :action_name

    def initialize(action_name)
      @action_name = action_name
      super("Unknown action: #{action_name}")
    end
  end

  class ValidationError < Error
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super("Validation failed: #{@errors.join(', ')}")
    end
  end

  class AdapterError < Error
    attr_reader :original_error

    def initialize(message, original_error: nil)
      @original_error = original_error
      super(message)
    end
  end

  class ConfigurationError < Error; end

  class AuthenticationError < Error; end

  class GateError < Error
    attr_reader :original_error

    def initialize(message, original_error: nil)
      @original_error = original_error
      super(message)
    end
  end
end
