# frozen_string_literal: true

module WildAdminToolsMcp
  module Audit
    class AuditedPipeline
      def initialize(pipeline:, recorder:)
        @pipeline = pipeline
        @recorder = recorder
      end

      attr_reader :recorder

      def call(action_name, params, caller_id, nonce: nil, session_context: nil)
        @recorder.record(
          action_name: action_name,
          params: params,
          caller_id: caller_id,
          nonce: nonce,
          session_context: session_context
        ) do
          @pipeline.call(action_name, params, caller_id, nonce: nonce)
        end
      end

      def register_executor(executor)
        @pipeline.register_executor(executor)
      end

      def two_phase
        @pipeline.two_phase
      end
    end
  end
end
