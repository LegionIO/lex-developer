# frozen_string_literal: true

RSpec.describe Legion::Extensions::Developer::Helpers::FeedbackSummarizer do
  describe '.summarize' do
    let(:feedback_history) do
      [
        { verdict: 'rejected', issues: ['Missing error handling', 'No tests for edge case'], round: 0 },
        { verdict: 'rejected', issues: ['Error handling incomplete', 'Test coverage low'], round: 1 },
        { verdict: 'rejected', issues: ['Edge case still failing'], round: 2 }
      ]
    end

    it 'returns a condensed feedback list' do
      result = described_class.summarize(feedback_history: feedback_history)
      expect(result).to be_an(Array)
    end

    it 'caps output to max_entries' do
      result = described_class.summarize(feedback_history: feedback_history, max_entries: 2)
      expect(result.size).to be <= 2
    end

    it 'preserves the most recent feedback' do
      result = described_class.summarize(feedback_history: feedback_history, max_entries: 1)
      expect(result.last[:round]).to eq(2)
    end

    it 'sets summarized: true on the summary entry' do
      result = described_class.summarize(feedback_history: feedback_history, max_entries: 1)
      expect(result.last[:summarized]).to be true
    end

    it 'records source_rounds in the summary entry' do
      result = described_class.summarize(feedback_history: feedback_history, max_entries: 1)
      expect(result.last[:source_rounds]).to contain_exactly(0, 1, 2)
    end
  end

  describe '.needs_summarization?' do
    it 'returns false when below threshold' do
      history = [{ round: 0 }]
      expect(described_class.needs_summarization?(feedback_history: history, threshold: 2)).to be false
    end

    it 'returns true when at or above threshold' do
      history = [{ round: 0 }, { round: 1 }]
      expect(described_class.needs_summarization?(feedback_history: history, threshold: 2)).to be true
    end
  end

  describe '.extract_unique_issues' do
    it 'deduplicates across rounds' do
      history = [
        { issues: ['Fix A', 'Fix B'] },
        { issues: ['Fix B', 'Fix C'] }
      ]
      result = described_class.extract_unique_issues(feedback_history: history)
      expect(result).to contain_exactly('Fix A', 'Fix B', 'Fix C')
    end

    it 'returns empty array for empty history' do
      expect(described_class.extract_unique_issues(feedback_history: [])).to eq([])
    end
  end
end
