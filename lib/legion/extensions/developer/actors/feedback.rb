# frozen_string_literal: true

return unless defined?(Legion::Extensions::Actors::Subscription)

module Legion
  module Extensions
    module Developer
      module Actor
        class Feedback < Legion::Extensions::Actors::Subscription
          def runner_function
            'incorporate_feedback'
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
