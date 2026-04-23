# frozen_string_literal: true

require 'fileutils'

module Legion
  module Extensions
    module Developer
      module Runners
        module Developer
          include Legion::Extensions::Helpers::Lex if defined?(Legion::Extensions::Helpers::Lex)
          extend self

          def implement(results: nil, work_item: nil, args: nil, **)
            results = Legion::JSON.load(results) if results.is_a?(String) # rubocop:disable Legion/HelperMigration/DirectJson
            work_item ||= results&.dig(:work_item) || args&.dig(:work_item)
            raise ArgumentError, "work_item is nil in #{__method__}" if work_item.nil?

            started_at = Time.now.utc.iso8601

            materialization = if work_item[:pipeline][:attempt].to_i.positive? && work_item[:pipeline][:branch_name]
                                reuse_worktree(work_item: work_item)
                              else
                                token = Legion::Settings.dig(:fleet, :github, :token)
                                Exec::Helpers::RepoMaterializer.materialize(
                                  work_item:           work_item,
                                  credential_provider: token
                                )
                              end

            unless materialization[:success]
              return { success: false, error: :materialization_failed,
                       message: materialization[:reason].to_s }
            end

            prompt = Helpers::PromptBuilder.build_implementation_prompt(work_item: work_item)
            llm_response = call_llm(work_item: work_item, prompt: prompt)

            changes = Helpers::ChangeParser.parse(content: llm_response[:content])
            file_paths = Helpers::ChangeParser.file_paths_only(changes: changes)

            worktree_path = materialization[:worktree_path] || materialization[:repo_path]
            write_changes(changes: changes, worktree_path: worktree_path)

            Exec::Runners::Git.add(path: worktree_path, files: file_paths)
            Exec::Runners::Git.commit(path: worktree_path, message: "fleet: #{work_item[:title]}")
            Exec::Runners::Git.push(path: worktree_path, branch: materialization[:branch])

            pr_result = if work_item.dig(:pipeline, :pr_number)
                          { number: work_item.dig(:pipeline, :pr_number) }
                        else
                          create_pull_request(work_item: work_item, branch: materialization[:branch],
                                              file_paths: file_paths)
                        end

            work_item = work_item.merge(
              pipeline: work_item[:pipeline].merge(
                stage:       'implemented',
                changes:     file_paths,
                branch_name: materialization[:branch],
                pr_number:   pr_result&.dig(:number),
                trace:       work_item[:pipeline][:trace] + [build_trace_entry(started_at: started_at)]
              )
            )

            { success: true, work_item: work_item, changes: changes }
          end

          def incorporate_feedback(results: nil, work_item: nil, args: nil, **)
            results = Legion::JSON.load(results) if results.is_a?(String) # rubocop:disable Legion/HelperMigration/DirectJson
            work_item ||= results&.dig(:work_item) || args&.dig(:work_item)
            raise ArgumentError, "work_item is nil in #{__method__}" if work_item.nil?

            max = work_item.dig(:config, :implementation, :max_iterations) ||
                  Legion::Settings.dig(:fleet, :implementation, :max_iterations) || 5

            if work_item[:pipeline][:attempt] >= max - 1
              return {
                success:   true,
                work_item: work_item.merge(pipeline: work_item[:pipeline].merge(stage: 'escalated')),
                escalate:  true
              }
            end

            feedback_history = Array(work_item.dig(:pipeline, :feedback_history))
            summarize_after = work_item.dig(:config, :feedback, :summarize_after) || 2

            if Helpers::FeedbackSummarizer.needs_summarization?(
              feedback_history: feedback_history, threshold: summarize_after
            )
              feedback_history = Helpers::FeedbackSummarizer.summarize(feedback_history: feedback_history)
            end

            new_attempt = (work_item.dig(:pipeline, :attempt) || 0) + 1

            work_item = work_item.merge(
              pipeline: work_item[:pipeline].merge(
                attempt:          new_attempt,
                feedback_history: feedback_history
              )
            )

            implement(work_item: work_item)
          end

          private

          def reuse_worktree(work_item:)
            worktree_base = Legion::Settings.dig(:fleet, :workspace, :worktree_base) ||
                            File.join(Dir.home, '.legionio', 'fleet', 'worktrees')
            default_path = File.join(worktree_base, work_item[:work_item_id].to_s)
            cached_path = Legion::Cache.get("fleet:worktree:#{work_item[:work_item_id]}") # rubocop:disable Legion/HelperMigration/DirectCache
            {
              success:       true,
              branch:        work_item[:pipeline][:branch_name],
              worktree_path: cached_path || default_path
            }
          end

          def write_changes(changes:, worktree_path:)
            changes.each do |change|
              target = File.join(worktree_path.to_s, change[:path])
              FileUtils.mkdir_p(File.dirname(target))
              Exec::Helpers::VerifiedWrite.write(path: target, content: change[:content])
            end
          end

          def create_pull_request(work_item:, branch:, file_paths:)
            owner = work_item.dig(:repo, :owner)
            repo_name = work_item.dig(:repo, :name)
            default_branch = work_item.dig(:repo, :default_branch) || 'main'

            Legion::Extensions::Github::Runners::PullRequests.create_pull_request(
              owner: owner,
              repo:  repo_name,
              base:  default_branch,
              head:  branch,
              title: "fleet: #{work_item[:title]}",
              body:  build_pr_body(work_item, file_paths),
              draft: true
            )
          end

          def call_llm(work_item:, prompt:)
            attempt = work_item.dig(:pipeline, :attempt) || 0
            scaled_budget = Helpers::PromptBuilder.thinking_budget(attempt: attempt)
            exclude = build_model_exclusions(work_item)

            Legion::LLM::Prompt.dispatch(
              prompt,
              tools:    [],
              exclude:  exclude,
              intent:   { capability: difficulty_to_capability(work_item) },
              agent:    { id: 'fleet:developer', name: 'Fleet Developer',
                       type: :autonomous, goal: work_item[:title] },
              tracing:  { trace_id:       work_item[:work_item_id],
                          correlation_id: work_item[:source_ref] },
              escalate: true,
              thinking: { budget_tokens: scaled_budget }
            )
          end

          def build_model_exclusions(work_item)
            exclude = {}
            work_item[:pipeline][:trace].each do |t|
              next unless t[:model]

              (exclude[t[:provider]&.to_sym] ||= []) << t[:model]
            end
            exclude.transform_values(&:uniq)
          end

          def difficulty_to_capability(work_item)
            difficulty = work_item.dig(:config, :estimated_difficulty) || 0.5
            case difficulty
            when 0.0...0.3 then :basic
            when 0.3...0.6 then :moderate
            else :reasoning
            end
          end

          def build_trace_entry(started_at: Time.now.utc.iso8601)
            {
              stage:        'developer',
              node:         node_name,
              model:        nil,
              provider:     nil,
              started_at:   started_at,
              completed_at: Time.now.utc.iso8601,
              token_usage:  {}
            }
          end

          def build_pr_body(work_item, file_paths)
            plan = work_item.dig(:pipeline, :plan, :approach) || 'N/A'
            files_list = file_paths.map { |f| "- `#{f}`" }.join("\n")
            <<~BODY
              ## Fleet Pipeline -- Draft PR

              **Work Item**: #{work_item[:work_item_id]}
              **Source**: #{work_item[:source_ref]}

              ### Approach
              #{plan}

              ### Files Changed
              #{files_list}
            BODY
          end

          def node_name
            if defined?(Legion::Settings)
              Legion::Settings.dig(:node, :name) || 'unknown'
            else
              'unknown'
            end
          end
        end
      end
    end
  end
end
