# frozen_string_literal: true

module Legion
  module Extensions
    module Developer
      module Helpers
        module PromptBuilder
          extend self

          def build_implementation_prompt(work_item:, context: nil)
            plan = work_item.dig(:pipeline, :plan) || {}
            repo = work_item[:repo] || {}

            <<~PROMPT
              You are a senior software developer implementing a code change.

              ## Task
              Title: #{work_item[:title]}
              Description: #{work_item[:description]}
              Repository: #{repo[:owner]}/#{repo[:name]}
              Language: #{repo[:language] || 'unknown'}

              ## Plan
              Approach: #{plan[:approach]}
              Test strategy: #{plan[:test_strategy]}

              ## Files to Modify
              #{format_files_to_modify(plan[:files_to_modify] || [])}

              #{format_context(context)}

              ## Instructions
              Implement the changes described above. For each file you modify or create,
              output the complete file content in a fenced code block with a `# file: path/to/file`
              comment as the first line inside the block.

              Example format:
              ```ruby
              # file: lib/example.rb
              # frozen_string_literal: true

              class Example
                # implementation here
              end
              ```
            PROMPT
          end

          def build_feedback_prompt(work_item:, context: nil)
            feedback = work_item.dig(:pipeline, :feedback_history) || []
            attempt = work_item.dig(:pipeline, :attempt) || 0

            <<~PROMPT
              You are a senior software developer revising a code change based on review feedback.

              ## Task
              Title: #{work_item[:title]}
              Description: #{work_item[:description]}

              ## Current Attempt
              This is attempt #{attempt} (previous attempts were rejected).

              ## Review Feedback
              #{format_feedback(feedback)}

              ## Plan
              #{format_plan(work_item.dig(:pipeline, :plan))}

              #{format_context(context)}

              ## Instructions
              Address ALL feedback issues listed above. Output complete file contents using the
              `# file: path/to/file` format inside fenced code blocks.
            PROMPT
          end

          def thinking_budget(attempt:)
            budget = base_thinking_budget * (2**attempt)
            [budget, max_thinking_budget].min
          end

          private

          def max_thinking_budget
            Legion::Settings.dig(:fleet, :llm, :thinking_budget_max_tokens) || 64_000
          end

          def base_thinking_budget
            Legion::Settings.dig(:fleet, :llm, :thinking_budget_base_tokens) || 16_000
          end

          def format_files_to_modify(files)
            return 'No specific files listed.' if files.empty?

            files.map { |f| "- #{f[:path]} (#{f[:action]}): #{f[:reason]}" }.join("\n")
          end

          def format_context(context)
            return '' if context.nil? || context.empty?

            parts = []
            parts << "## Repository Documentation\n#{context[:docs]}" if context[:docs]
            parts << "## File Tree\n#{Array(context[:file_tree]).join("\n")}" if context[:file_tree]
            parts.join("\n\n")
          end

          def format_feedback(feedback_history)
            return 'No prior feedback.' if feedback_history.empty?

            feedback_history.map.with_index do |entry, idx|
              issues_list = Array(entry[:issues])
              issues_text = issues_list.empty? ? '  (none listed)' : "  - #{issues_list.join("\n  - ")}"
              "### Round #{entry[:round] || idx}\nVerdict: #{entry[:verdict]}\nIssues:\n#{issues_text}"
            end.join("\n\n")
          end

          def format_plan(plan)
            return '' if plan.nil?

            "Approach: #{plan[:approach]}\nTest strategy: #{plan[:test_strategy]}"
          end
        end
      end
    end
  end
end
