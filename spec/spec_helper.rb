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

require 'legion/extensions/developer'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  config.before { Legion::Cache.clear }
end
