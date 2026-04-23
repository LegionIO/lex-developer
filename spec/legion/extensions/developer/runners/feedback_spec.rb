# frozen_string_literal: true

RSpec.describe Legion::Extensions::Developer::Runners::Feedback do
  let(:work_item) do
    {
      work_item_id: 'uuid-fb-001',
      source:       'github',
      source_ref:   'LegionIO/lex-exec#42',
      title:        'Fix sandbox timeout on macOS',
      description:  'The exec sandbox times out after 30s',
      repo:         { owner: 'LegionIO', name: 'lex-exec', default_branch: 'main', language: 'ruby' },
      config:       {
        priority:             :medium,
        complexity:           :moderate_feature,
        estimated_difficulty: 0.5,
        planning:             { enabled: true },
        implementation:       { solvers: 1, validators: 3, max_iterations: 5, models: nil },
        validation:           { enabled: true },
        feedback:             { drain_enabled: true, max_drain_rounds: 3, summarize_after: 2 },
        context:              { load_repo_docs: true, load_file_tree: true, max_context_files: 50 }
      },
      pipeline:     {
        stage:            'validated',
        trace:            [
          { stage: 'assessor', node: 'test', started_at: '2026-04-12T00:00:00Z',
            completed_at: '2026-04-12T00:00:01Z' },
          { stage: 'developer', node: 'test', started_at: '2026-04-12T00:00:02Z',
            completed_at: '2026-04-12T00:00:03Z' }
        ],
        attempt:          1,
        feedback_history: [
          { verdict: 'rejected', issues: ['Missing error handling'], round: 0 }
        ],
        review_result:    { verdict: 'rejected', issues: ['Missing error handling'] },
        changes:          nil,
        pr_number:        nil,
        branch_name:      nil,
        context_ref:      nil
      }
    }
  end

  describe '.incorporate_feedback' do
    it 'delegates to Runners::Developer' do
      expect(Legion::Extensions::Developer::Runners::Developer)
        .to receive(:incorporate_feedback).and_call_original
      described_class.incorporate_feedback(work_item: work_item)
    end

    it 'returns success' do
      result = described_class.incorporate_feedback(work_item: work_item)
      expect(result[:success]).to be true
    end

    it 'increments the attempt counter' do
      result = described_class.incorporate_feedback(work_item: work_item)
      expect(result[:work_item][:pipeline][:attempt]).to eq(2)
    end

    it 'escalates when attempt reaches max_iterations' do
      escalated_item = work_item.merge(
        pipeline: work_item[:pipeline].merge(attempt: 4),
        config:   work_item[:config].merge(
          implementation: work_item[:config][:implementation].merge(max_iterations: 5)
        )
      )
      result = described_class.incorporate_feedback(work_item: escalated_item)
      expect(result[:escalate]).to be true
      expect(result[:work_item][:pipeline][:stage]).to eq('escalated')
    end
  end
end
