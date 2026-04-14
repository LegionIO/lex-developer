# frozen_string_literal: true

module Legion
  module Extensions
    module Developer
      module Helpers
        module FeedbackSummarizer
          extend self

          DEFAULT_MAX_ENTRIES = 3

          def summarize(feedback_history:, max_entries: DEFAULT_MAX_ENTRIES)
            return feedback_history if feedback_history.size <= max_entries

            unique_issues = extract_unique_issues(feedback_history: feedback_history)
            most_recent = feedback_history.last

            summary_entry = {
              verdict:       'rejected',
              issues:        unique_issues,
              round:         most_recent[:round],
              summarized:    true,
              source_rounds: feedback_history.filter_map { |f| f[:round] }
            }

            [summary_entry]
          end

          def needs_summarization?(feedback_history:, threshold: 2)
            feedback_history.size >= threshold
          end

          def extract_unique_issues(feedback_history:)
            feedback_history
              .flat_map { |entry| Array(entry[:issues]) }
              .uniq
          end
        end
      end
    end
  end
end
