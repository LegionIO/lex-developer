# frozen_string_literal: true

module Legion
  module Extensions
    module Developer
      module Transport
        module Queues
          class Feedback < Legion::Transport::Queue
            def queue_name
              'lex.developer.runners.feedback'
            end

            def queue_options
              { durable: true }
            end

            def routing_key
              'lex.developer.runners.developer.incorporate_feedback'
            end

            def exchange
              Exchanges::Developer
            end
          end
        end
      end
    end
  end
end
