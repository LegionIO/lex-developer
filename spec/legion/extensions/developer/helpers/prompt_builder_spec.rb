# frozen_string_literal: true

RSpec.describe Legion::Extensions::Developer::Helpers::PromptBuilder do
  let(:work_item) do
    {
      work_item_id: 'uuid-dev-001',
      title:        'Fix sandbox timeout',
      description:  'Timeout too short on macOS',
      repo:         { owner: 'LegionIO', name: 'lex-exec', language: 'ruby' },
      config:       { estimated_difficulty: 0.5 },
      pipeline:     {
        stage:            'planned',
        plan:             {
          approach:        'Increase default timeout',
          files_to_modify: [{ path: 'lib/sandbox.rb', action: 'modify', reason: 'Fix timeout' }],
          test_strategy:   'Add unit test'
        },
        attempt:          0,
        feedback_history: [],
        context_ref:      nil
      }
    }
  end

  describe '.build_implementation_prompt' do
    it 'returns a string' do
      result = described_class.build_implementation_prompt(work_item: work_item)
      expect(result).to be_a(String)
    end

    it 'includes the work item title' do
      result = described_class.build_implementation_prompt(work_item: work_item)
      expect(result).to include('Fix sandbox timeout')
    end

    it 'includes the plan approach' do
      result = described_class.build_implementation_prompt(work_item: work_item)
      expect(result).to include('Increase default timeout')
    end

    it 'includes file instructions' do
      result = described_class.build_implementation_prompt(work_item: work_item)
      expect(result).to include('# file:')
    end
  end

  describe '.build_feedback_prompt' do
    let(:feedback_item) do
      work_item.merge(
        pipeline: work_item[:pipeline].merge(
          attempt:          1,
          feedback_history: [
            { verdict: 'rejected', issues: ['Missing error handling'], round: 0 }
          ]
        )
      )
    end

    it 'returns a string' do
      result = described_class.build_feedback_prompt(work_item: feedback_item)
      expect(result).to be_a(String)
    end

    it 'includes feedback from previous rounds' do
      result = described_class.build_feedback_prompt(work_item: feedback_item)
      expect(result).to include('Missing error handling')
    end

    it 'includes the attempt number' do
      result = described_class.build_feedback_prompt(work_item: feedback_item)
      expect(result).to include('1')
    end
  end

  describe '.build_implementation_prompt with context' do
    it 'includes repository docs when provided' do
      result = described_class.build_implementation_prompt(
        work_item: work_item,
        context:   { docs: 'README content here' }
      )
      expect(result).to include('## Repository Documentation')
      expect(result).to include('README content here')
    end

    it 'includes file tree when provided' do
      result = described_class.build_implementation_prompt(
        work_item: work_item,
        context:   { file_tree: ['lib/', 'lib/foo.rb'] }
      )
      expect(result).to include('## File Tree')
      expect(result).to include('lib/foo.rb')
    end

    it 'omits context section when nil' do
      result = described_class.build_implementation_prompt(work_item: work_item, context: nil)
      expect(result).not_to include('## Repository Documentation')
      expect(result).not_to include('## File Tree')
    end
  end

  describe '.thinking_budget' do
    it 'returns 16000 for attempt 0' do
      expect(described_class.thinking_budget(attempt: 0)).to eq(16_000)
    end

    it 'returns 32000 for attempt 1' do
      expect(described_class.thinking_budget(attempt: 1)).to eq(32_000)
    end

    it 'caps at 64000 for attempt 2+' do
      expect(described_class.thinking_budget(attempt: 2)).to eq(64_000)
      expect(described_class.thinking_budget(attempt: 5)).to eq(64_000)
    end
  end
end
