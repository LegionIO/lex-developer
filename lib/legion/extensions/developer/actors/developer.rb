# frozen_string_literal: true

return unless defined?(Legion::Extensions::Actors::Subscription)

module Legion
  module Extensions
    module Developer
      module Actor
        class Developer < Legion::Extensions::Actors::Subscription
          def runner_function
            'implement'
          end

          def check_subtask?
            true
          end

          def generate_task?
            false
          end
        end
      end
    end
  end
end
