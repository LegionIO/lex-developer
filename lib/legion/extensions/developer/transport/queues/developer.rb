# frozen_string_literal: true

module Legion
  module Extensions
    module Developer
      module Transport
        module Queues
          class Developer < Legion::Transport::Queue
            def queue_name
              'lex.developer.runners.developer'
            end

            def queue_options
              { durable: true }
            end

            def routing_key
              'lex.developer.runners.developer.implement'
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
