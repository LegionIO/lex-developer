# frozen_string_literal: true

require_relative 'developer/version'
require_relative 'developer/helpers/change_parser'
require_relative 'developer/helpers/prompt_builder'
require_relative 'developer/helpers/repo_materializer'
require_relative 'developer/helpers/feedback_summarizer'
require_relative 'developer/runners/developer'
require_relative 'developer/runners/feedback'
require_relative 'developer/runners/ship'

if defined?(Legion::Transport::Exchange)
  require_relative 'developer/transport/exchanges/developer'
  require_relative 'developer/transport/queues/developer'
  require_relative 'developer/transport/queues/ship'
  require_relative 'developer/transport/queues/feedback'
end

require_relative 'developer/actors/developer'
require_relative 'developer/actors/feedback'

module Legion
  module Extensions
    module Developer
      extend Legion::Extensions::Core if defined?(Legion::Extensions::Core)

      def self.llm_required?
        true
      end
    end
  end
end
