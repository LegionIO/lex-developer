# frozen_string_literal: true

module Legion
  module Extensions
    module Developer
      module Transport
        module Queues
          class Ship < Legion::Transport::Queue
            def queue_name
              'lex.developer.runners.ship'
            end

            def queue_options
              { durable: true }
            end

            def routing_key
              'lex.developer.runners.ship.#'
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
