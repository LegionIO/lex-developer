# frozen_string_literal: true

require 'digest'

module Legion
  module Extensions
    module Developer
      module Runners
        module Ship
          extend self

          RESUME_ROUTING_KEY = 'lex.developer.runners.ship.finalize'
          RESUME_EXCHANGE = 'lex.developer'

          def finalize(results: nil, work_item: nil, args: nil, **)
            results = json_load(results) if results.is_a?(String)
            work_item ||= results&.dig(:work_item) || args&.dig(:work_item)
            raise ArgumentError, "work_item is nil in #{__method__}" if work_item.nil?

            started_at = Time.now.utc.iso8601

            gate = consent_gate(work_item)
            return gate if gate

            finalize_pr_actions(work_item)
            cleanup_caches(work_item)
            write_audit(work_item)

            work_item = stamp_shipped(work_item, started_at)
            { success: true, work_item: work_item }
          end

          private

          def consent_gate(work_item)
            return nil if work_item.dig(:pipeline, :resumed)

            consent = check_consent(work_item)
            return nil unless %i[consult human_only].include?(consent[:tier])

            work_item = work_item.merge(pipeline: work_item[:pipeline].merge(resumed: true))
            Legion::Extensions::Audit::Runners::ApprovalQueue.submit(
              approval_type:      work_item.dig(:config, :escalation, :consent_domain) || 'fleet.shipping',
              payload:            { work_item: work_item },
              requester_id:       'fleet:developer',
              resume_routing_key: RESUME_ROUTING_KEY,
              resume_exchange:    RESUME_EXCHANGE
            )
            { success: true, work_item: work_item, awaiting_approval: true }
          end

          def finalize_pr_actions(work_item)
            pr_number = work_item.dig(:pipeline, :pr_number)
            return unless pr_number

            owner = work_item.dig(:repo, :owner)
            repo_name = work_item.dig(:repo, :name)
            issue_number = work_item[:source_ref].to_s.scan(/\d+/).last&.to_i || pr_number

            Legion::Extensions::Github::Runners::PullRequests.mark_pr_ready(
              owner: owner, repo: repo_name, pull_number: pr_number
            )
            Legion::Extensions::Github::Runners::Labels.add_labels_to_issue(
              owner: owner, repo: repo_name, issue_number: issue_number,
              labels: ['fleet:pr-open', "fleet:attempt-#{work_item.dig(:pipeline, :attempt) || 0}"]
            )
            Legion::Extensions::Github::Runners::Issues.create_issue_comment(
              owner: owner, repo: repo_name, issue_number: issue_number,
              body: build_summary_comment(work_item)
            )
          end

          def write_audit(work_item)
            pr_number = work_item.dig(:pipeline, :pr_number)
            Legion::Extensions::Audit::Runners::Audit.write(
              event_type:       'fleet.shipped',
              principal_id:     'fleet:developer',
              action:           'ship',
              resource:         work_item[:source_ref],
              context_snapshot: {
                work_item_id: work_item[:work_item_id],
                pr_number:    pr_number,
                attempt:      work_item.dig(:pipeline, :attempt),
                score:        work_item.dig(:pipeline, :review_result, :score)
              }
            )
          end

          def stamp_shipped(work_item, started_at)
            work_item.merge(
              pipeline: work_item[:pipeline].merge(
                stage: 'shipped',
                trace: work_item[:pipeline][:trace] + [build_trace_entry(started_at: started_at)]
              )
            )
          end

          def check_consent(work_item)
            domain = work_item.dig(:config, :escalation, :consent_domain) || 'fleet.shipping'
            if defined?(Legion::Extensions::Agentic::Social::Consent::Runners::Consent)
              Legion::Extensions::Agentic::Social::Consent::Runners::Consent.check_consent(domain: domain)
            else
              { tier: :autonomous, allowed: true }
            end
          end

          def build_summary_comment(work_item)
            attempt = work_item.dig(:pipeline, :attempt) || 0
            score = work_item.dig(:pipeline, :review_result, :score)
            plan = work_item.dig(:pipeline, :plan, :approach) || 'N/A'
            changes = Array(work_item.dig(:pipeline, :changes))

            <<~COMMENT
              ## Fleet Pipeline -- Shipped

              **Work Item**: #{work_item[:work_item_id]}
              **Attempts**: #{attempt}
              **Review Score**: #{score.is_a?(Hash) ? score[:aggregate] : score}

              ### Approach
              #{plan}

              ### Files Changed
              #{changes.map { |f| "- `#{f}`" }.join("\n")}
            COMMENT
          end

          def cleanup_caches(work_item)
            wid = work_item[:work_item_id]

            Exec::Helpers::Worktree.remove(task_id: wid)

            Legion::Cache.delete("fleet:payload:#{wid}") # rubocop:disable Legion/HelperMigration/DirectCache
            Legion::Cache.delete("fleet:context:#{wid}") # rubocop:disable Legion/HelperMigration/DirectCache
            Legion::Cache.delete("fleet:worktree:#{wid}") # rubocop:disable Legion/HelperMigration/DirectCache

            fingerprint = Digest::SHA256.hexdigest(
              "#{work_item[:source]}:#{work_item[:source_ref]}:#{work_item[:title]}"
            )
            Legion::Cache.delete("fleet:active:#{fingerprint}") # rubocop:disable Legion/HelperMigration/DirectCache
          end

          def build_trace_entry(started_at: Time.now.utc.iso8601)
            {
              stage:        'ship',
              node:         node_name,
              model:        nil,
              provider:     nil,
              started_at:   started_at,
              completed_at: Time.now.utc.iso8601,
              token_usage:  {}
            }
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
