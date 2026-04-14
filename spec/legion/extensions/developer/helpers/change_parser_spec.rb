# frozen_string_literal: true

RSpec.describe Legion::Extensions::Developer::Helpers::ChangeParser do
  describe '.parse' do
    let(:llm_response) do
      <<~RESPONSE
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
    end

    it 'extracts file changes from fenced code blocks' do
      result = described_class.parse(content: llm_response)
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
    end

    it 'extracts file paths from # file: comments' do
      result = described_class.parse(content: llm_response)
      paths = result.map { |c| c[:path] }
      expect(paths).to contain_exactly('lib/sandbox.rb', 'spec/sandbox_spec.rb')
    end

    it 'extracts file content without the file comment' do
      result = described_class.parse(content: llm_response)
      sandbox = result.find { |c| c[:path] == 'lib/sandbox.rb' }
      expect(sandbox[:content]).to include('def timeout')
      expect(sandbox[:content]).not_to include('# file:')
    end

    it 'returns empty array for content with no code blocks' do
      result = described_class.parse(content: 'No code here, just text.')
      expect(result).to eq([])
    end

    it 'handles code blocks without file path comments' do
      response = "```ruby\nputs 'hello'\n```"
      result = described_class.parse(content: response)
      expect(result).to eq([])
    end
  end

  describe '.file_paths_only' do
    it 'returns just the paths from parsed changes' do
      changes = [
        { path: 'lib/foo.rb', content: 'code' },
        { path: 'lib/bar.rb', content: 'more code' }
      ]
      expect(described_class.file_paths_only(changes: changes)).to eq(['lib/foo.rb', 'lib/bar.rb'])
    end
  end
end
