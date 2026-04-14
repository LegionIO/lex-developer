# frozen_string_literal: true

module Legion
  module Extensions
    module Developer
      module Transport
        module Exchanges
          class Developer < Legion::Transport::Exchange
            def exchange_name
              'lex.developer'
            end

            def exchange_options
              { type: 'topic', durable: true }
            end
          end
        end
      end
    end
  end
end
