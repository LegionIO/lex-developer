# frozen_string_literal: true

require 'bundler/setup'
require 'json'
require 'legion/logging'
require 'legion/json'
require 'legion/cache'
require 'legion/crypt'
require 'legion/data'
require 'legion/settings'
require 'legion/transport'

# Stub Legion::Extensions::Helpers::Lex when running standalone
unless defined?(Legion::Extensions::Helpers::Lex)
  module Legion
    module Extensions
      module Helpers
        module Lex
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods; end
        end
      end

      module Core; end
    end
  end
end

# Stub Legion::Extensions::Helpers::Task when running standalone
unless defined?(Legion::Extensions::Helpers::Task)
  module Legion
    module Extensions
      module Helpers
        module Task
          def task_update(*); end
          def generate_task_log(**); end
        end
      end
    end
  end
end

# Stub Legion::Cache for in-memory testing
module Legion
  module Cache
    @store = {} # rubocop:disable ThreadSafety/MutableClassInstanceVariable

    def self.get(key)
      @store[key]
    end

    def self.set(key, value, ttl: nil) # rubocop:disable Lint/UnusedMethodArgument
      @store[key] = value
    end

    def self.delete(key)
      @store.delete(key)
    end

    def self.clear
      @store.clear
    end
  end
end

# Stub Legion::LLM for testing
module Legion
  module LLM
    module Prompt
      def self.dispatch(_prompt, **_kwargs)
        {
          content:  <<~RESPONSE,
            I'll fix the sandbox timeout issue.

            ```ruby
            # file: lib/sandbox.rb
            def timeout
              @timeout || 60
            end
            ```

            ```ruby
            # file: spec/sandbox_spec.rb
            RSpec.describe Sandbox do
              it 'defaults to 60 second timeout' do
                expect(subject.timeout).to eq(60)
              end
            end
            ```
          RESPONSE
          model:    'stub',
          provider: 'stub'
        }
      end
    end
  end
end

# Stub Legion::JSON for testing
module Legion
  module JSON
    def self.dump(object = nil, pretty: false, **kwargs) # rubocop:disable Lint/UnusedMethodArgument
      data = object.nil? ? kwargs : object
      ::JSON.generate(data)
    end

    def self.load(str)
      ::JSON.parse(str, symbolize_names: true)
    end
  end
end

# Stub production dependencies not available in standalone tests
module Exec
  module Helpers
    module RepoMaterializer
      def self.materialize(work_item:, credential_provider: nil, **) # rubocop:disable Lint/UnusedMethodArgument
        branch = "fleet/fix-#{work_item.dig(:repo, :name).to_s.gsub(/[^a-zA-Z0-9_-]/, '-')}-#{work_item[:source_ref].to_s.scan(/\d+/).last}"
        worktree_path = File.join(Dir.home, '.legionio', 'fleet', 'worktrees', work_item[:work_item_id].to_s)
        Legion::Cache.set("fleet:worktree:#{work_item[:work_item_id]}", branch)
        { success: true, branch: branch, worktree_path: worktree_path, repo_path: worktree_path }
      end
    end

    module VerifiedWrite
      def self.write(path:, content:, **) # rubocop:disable Lint/UnusedMethodArgument
        # No-op in tests
        true
      end
    end

    module Worktree
      def self.remove(task_id:, **) # rubocop:disable Lint/UnusedMethodArgument
        # No-op in tests
        true
      end
    end
  end

  module Runners
    module Git
      def self.add(path:, files:, **) # rubocop:disable Lint/UnusedMethodArgument
        true
      end

      def self.commit(path:, message:, **) # rubocop:disable Lint/UnusedMethodArgument
        true
      end

      def self.push(path:, branch:, **) # rubocop:disable Lint/UnusedMethodArgument
        true
      end
    end
  end
end

module Legion
  module Extensions
    module Github
      module Runners
        module PullRequests
          def self.create_pull_request(owner:, repo:, **)
            { number: 99, html_url: "https://github.com/#{owner}/#{repo}/pull/99" }
          end

          def self.mark_pr_ready(**)
            true
          end
        end

        module Labels
          def self.add_labels_to_issue(**)
            true
          end
        end

        module Issues
          def self.create_issue_comment(**)
            true
          end
        end
      end
    end

    module Audit
      module Runners
        module ApprovalQueue
          def self.submit(**)
            true
          end
        end

        module Audit
          def self.write(**)
            true
          end
        end
      end
    end
  end
end

require 'legion/extensions/developer'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  config.before { Legion::Cache.clear }
end
