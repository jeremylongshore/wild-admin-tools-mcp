# frozen_string_literal: true

module WildAdminToolsMcp
  Result = Data.define(
    :status,
    :action,
    :operation,
    :data,
    :before_snapshot,
    :after_snapshot,
    :metadata
  ) do
    def initialize(status:, action:, operation:, data: {}, before_snapshot: nil, after_snapshot: nil, metadata: {})
      super
    end

    def success?
      status == :success
    end

    def preview?
      status == :preview
    end

    def denied?
      status == :denied
    end

    def error?
      status == :error
    end
  end
end
