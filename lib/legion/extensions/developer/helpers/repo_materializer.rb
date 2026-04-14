# frozen_string_literal: true

module Legion
  module Extensions
    module Developer
      module Helpers
        module RepoMaterializer
          extend self

          FLEET_REPOS_DIR = File.join(Dir.home, '.legionio', 'fleet', 'repos')
          WORKTREE_CACHE_PREFIX = 'fleet:worktree:'
          DEFAULT_TTL = 86_400 # 24 hours

          def materialize(owner:, name:, default_branch:, source_ref:, work_item_id:, **)
            repo_path = repo_cache_path(owner: owner, name: name)
            branch = branch_name(repo_name: name, source_ref: source_ref)

            # Delegates to lex-exec RepoMaterializer (WS-01 prerequisite).
            # In production:
            #   token = Legion::Settings.dig(:fleet, :github, :token)
            #   Exec::Helpers::RepoMaterializer.materialize(
            #     work_item: work_item,
            #     credential_provider: token
            #   )
            # Stubbed here for standalone testing.

            # Store the BRANCH NAME in the worktree cache key, not a filesystem path.
            # The validator and other stages use this to locate the correct branch for the work item.
            worktree_base = Legion::Settings.dig(:fleet, :workspace, :worktree_base) ||
                            File.join(Dir.home, '.legionio', 'fleet', 'worktrees')
            worktree_path = "#{worktree_base}/#{work_item_id}"
            Legion::Cache.set("#{WORKTREE_CACHE_PREFIX}#{work_item_id}", branch, ttl: DEFAULT_TTL) # rubocop:disable Legion/HelperMigration/DirectCache

            {
              success:        true,
              repo_path:      repo_path,
              worktree_path:  worktree_path,
              branch:         branch,
              default_branch: default_branch,
              work_item_id:   work_item_id
            }
          end

          def repo_cache_path(owner:, name:)
            File.join(FLEET_REPOS_DIR, owner, name)
          end

          def branch_name(repo_name:, source_ref:)
            issue_num = source_ref.to_s.scan(/\d+/).last || 'unknown'
            sanitized = repo_name.to_s.gsub(/[^a-zA-Z0-9_-]/, '-')
            "fleet/fix-#{sanitized}-#{issue_num}"
          end
        end
      end
    end
  end
end
