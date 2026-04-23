# frozen_string_literal: true

module Legion
  module Extensions
    module Developer
      module Runners
        module Feedback
          include Legion::Extensions::Helpers::Lex if defined?(Legion::Extensions::Helpers::Lex)
          extend self

          def incorporate_feedback(**)
            Developer.incorporate_feedback(**)
          end
        end
      end
    end
  end
end
