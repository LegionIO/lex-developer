# frozen_string_literal: true

RSpec.describe Legion::Extensions::Developer::Runners::Developer do
  let(:runner) { Module.new { extend Legion::Extensions::Developer::Runners::Developer } }

  let(:work_item) do
    {
      work_item_id: 'uuid-impl-001',
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
        stage:            'planned',
        trace:            [
          { stage: 'assessor', node: 'test', started_at: '2026-04-12T00:00:00Z', completed_at: '2026-04-12T00:00:01Z' },
          { stage: 'planner', node: 'test', started_at: '2026-04-12T00:00:01Z', completed_at: '2026-04-12T00:00:02Z' }
        ],
        attempt:          0,
        feedback_history: [],
        plan:             {
          approach:          'Increase default timeout',
          files_to_modify:   [{ path: 'lib/sandbox.rb', action: 'modify', reason: 'Fix timeout' }],
          test_strategy:     'Add unit test',
          estimated_changes: 2
        },
        changes:          nil,
        review_result:    nil,
        pr_number:        nil,
        branch_name:      nil,
        context_ref:      nil
      }
    }
  end

  describe '#implement' do
    it 'returns success' do
      result = runner.implement(work_item: work_item)
      expect(result[:success]).to be true
    end

    it 'sets pipeline stage to implemented' do
      result = runner.implement(work_item: work_item)
      expect(result[:work_item][:pipeline][:stage]).to eq('implemented')
    end

    it 'populates pipeline.changes with file paths' do
      result = runner.implement(work_item: work_item)
      expect(result[:work_item][:pipeline][:changes]).to be_an(Array)
      expect(result[:work_item][:pipeline][:changes]).not_to be_empty
    end

    it 'sets pipeline.branch_name' do
      result = runner.implement(work_item: work_item)
      expect(result[:work_item][:pipeline][:branch_name]).to match(%r{\Afleet/fix-})
    end

    it 'adds a trace entry for developer' do
      result = runner.implement(work_item: work_item)
      trace = result[:work_item][:pipeline][:trace]
      expect(trace.last[:stage]).to eq('developer')
    end

    it 'preserves existing trace entries' do
      result = runner.implement(work_item: work_item)
      trace = result[:work_item][:pipeline][:trace]
      expect(trace.size).to eq(3)
    end
  end

  describe '#incorporate_feedback' do
    let(:feedback_item) do
      work_item.merge(
        pipeline: work_item[:pipeline].merge(
          stage:            'validated',
          attempt:          1,
          feedback_history: [
            { verdict: 'rejected', issues: ['Missing error handling'], round: 0 }
          ],
          review_result:    { verdict: 'rejected', issues: ['Missing error handling'] }
        )
      )
    end

    it 'returns success' do
      result = runner.incorporate_feedback(work_item: feedback_item)
      expect(result[:success]).to be true
    end

    it 'increments the attempt counter' do
      result = runner.incorporate_feedback(work_item: feedback_item)
      expect(result[:work_item][:pipeline][:attempt]).to eq(2)
    end

    it 'sets stage to implemented' do
      result = runner.incorporate_feedback(work_item: feedback_item)
      expect(result[:work_item][:pipeline][:stage]).to eq('implemented')
    end

    it 'summarizes feedback when above threshold' do
      many_rounds = (0..3).map do |i|
        { verdict: 'rejected', issues: ["Issue #{i}"], round: i }
      end
      item = feedback_item.merge(
        pipeline: feedback_item[:pipeline].merge(
          attempt:          3,
          feedback_history: many_rounds
        )
      )
      result = runner.incorporate_feedback(work_item: item)
      history = result[:work_item][:pipeline][:feedback_history]
      expect(history.size).to be <= 3
    end

    it 'reuses existing worktree on retry instead of re-materializing' do
      retry_item = feedback_item.merge(
        pipeline: feedback_item[:pipeline].merge(
          attempt:     1,
          branch_name: 'fleet/fix-lex-exec-42'
        )
      )
      expect(Legion::Extensions::Developer::Helpers::RepoMaterializer).not_to receive(:materialize)
      result = runner.incorporate_feedback(work_item: retry_item)
      expect(result[:success]).to be true
      expect(result[:work_item][:pipeline][:branch_name]).to eq('fleet/fix-lex-exec-42')
    end

    it 'escalates when attempt reaches max_iterations' do
      escalated_item = feedback_item.merge(
        pipeline: feedback_item[:pipeline].merge(attempt: 4),
        config:   feedback_item[:config].merge(
          implementation: feedback_item[:config][:implementation].merge(max_iterations: 5)
        )
      )
      result = runner.incorporate_feedback(work_item: escalated_item)
      expect(result[:escalate]).to be true
      expect(result[:work_item][:pipeline][:stage]).to eq('escalated')
    end
  end
end
