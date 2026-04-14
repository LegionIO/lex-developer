# frozen_string_literal: true

RSpec.describe Legion::Extensions::Developer::Runners::Ship do
  let(:runner) { Module.new { extend Legion::Extensions::Developer::Runners::Ship } }

  let(:work_item) do
    {
      work_item_id: 'uuid-ship-001',
      source:       'github',
      source_ref:   'LegionIO/lex-exec#42',
      title:        'Fix sandbox timeout on macOS',
      description:  'The exec sandbox times out after 30s',
      repo:         { owner: 'LegionIO', name: 'lex-exec', default_branch: 'main', language: 'ruby' },
      config:       {
        priority:   :medium,
        complexity: :moderate_feature,
        escalation: { on_max_iterations: :human, consent_domain: 'fleet.shipping' }
      },
      pipeline:     {
        stage:            'validated',
        trace:            [
          { stage: 'assessor', node: 'test', started_at: '2026-04-12T00:00:00Z',
            completed_at: '2026-04-12T00:00:01Z' },
          { stage: 'developer', node: 'test', started_at: '2026-04-12T00:00:02Z',
            completed_at: '2026-04-12T00:00:03Z' },
          { stage: 'validator', node: 'test', started_at: '2026-04-12T00:00:04Z',
            completed_at: '2026-04-12T00:00:05Z' }
        ],
        attempt:          0,
        feedback_history: [],
        plan:             { approach: 'Fix timeout' },
        changes:          ['lib/sandbox.rb', 'spec/sandbox_spec.rb'],
        review_result:    { verdict: 'approved', score: 0.92 },
        pr_number:        99,
        branch_name:      'fleet/fix-lex-exec-42',
        context_ref:      'fleet:context:uuid-ship-001'
      }
    }
  end

  describe '#finalize' do
    it 'returns success' do
      result = runner.finalize(work_item: work_item)
      expect(result[:success]).to be true
    end

    it 'sets pipeline stage to shipped' do
      result = runner.finalize(work_item: work_item)
      expect(result[:work_item][:pipeline][:stage]).to eq('shipped')
    end

    it 'adds a trace entry for ship' do
      result = runner.finalize(work_item: work_item)
      trace = result[:work_item][:pipeline][:trace]
      expect(trace.last[:stage]).to eq('ship')
    end

    it 'clears Redis refs on completion' do
      Legion::Cache.set("fleet:payload:#{work_item[:work_item_id]}", 'data')
      Legion::Cache.set("fleet:context:#{work_item[:work_item_id]}", 'data')
      Legion::Cache.set("fleet:worktree:#{work_item[:work_item_id]}", 'fleet/fix-lex-exec-42')
      runner.finalize(work_item: work_item)
      expect(Legion::Cache.get("fleet:payload:#{work_item[:work_item_id]}")).to be_nil
      expect(Legion::Cache.get("fleet:context:#{work_item[:work_item_id]}")).to be_nil
      expect(Legion::Cache.get("fleet:worktree:#{work_item[:work_item_id]}")).to be_nil
    end

    it 'clears dedup cache' do
      fp = Digest::SHA256.hexdigest("#{work_item[:source]}:#{work_item[:source_ref]}:#{work_item[:title]}")
      Legion::Cache.set("fleet:active:#{fp}", '1')
      runner.finalize(work_item: work_item)
      expect(Legion::Cache.get("fleet:active:#{fp}")).to be_nil
    end

    context 'when consent requires human approval' do
      before do
        allow(runner).to receive(:check_consent).and_return({ tier: :consult, allowed: false })
      end

      it 'returns awaiting_approval: true' do
        result = runner.finalize(work_item: work_item)
        expect(result[:awaiting_approval]).to be true
      end

      it 'does not advance the stage to shipped' do
        result = runner.finalize(work_item: work_item)
        expect(result[:work_item][:pipeline][:stage]).not_to eq('shipped')
      end

      it 'stamps resumed: true on the work item before submitting' do
        result = runner.finalize(work_item: work_item)
        expect(result[:work_item][:pipeline][:resumed]).to be true
      end
    end

    context 'when resuming after approval' do
      let(:resumed_item) { work_item.merge(pipeline: work_item[:pipeline].merge(resumed: true)) }

      it 'skips consent check and ships' do
        result = runner.finalize(work_item: resumed_item)
        expect(result[:work_item][:pipeline][:stage]).to eq('shipped')
      end
    end
  end
end
