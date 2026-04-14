# frozen_string_literal: true

RSpec.describe Legion::Extensions::Developer::Helpers::RepoMaterializer do
  describe '.repo_cache_path' do
    it 'returns path under ~/.legionio/fleet/repos/' do
      result = described_class.repo_cache_path(owner: 'LegionIO', name: 'lex-exec')
      expect(result).to end_with('fleet/repos/LegionIO/lex-exec')
    end

    it 'includes the owner and repo name' do
      result = described_class.repo_cache_path(owner: 'MyOrg', name: 'my-repo')
      expect(result).to include('MyOrg/my-repo')
    end
  end

  describe '.branch_name' do
    it 'generates a fleet branch name' do
      result = described_class.branch_name(repo_name: 'lex-exec', source_ref: 'LegionIO/lex-exec#42')
      expect(result).to match(%r{\Afleet/fix-lex-exec-})
    end

    it 'sanitizes special characters' do
      result = described_class.branch_name(repo_name: 'my repo!', source_ref: 'Org/repo#99')
      expect(result).not_to include(' ')
      expect(result).not_to include('!')
    end
  end

  describe '.materialize' do
    it 'returns success with repo_path and branch' do
      result = described_class.materialize(
        owner: 'LegionIO', name: 'lex-exec', default_branch: 'main',
        source_ref: 'LegionIO/lex-exec#42', work_item_id: 'uuid-001'
      )
      expect(result[:success]).to be true
      expect(result).to have_key(:repo_path)
      expect(result).to have_key(:branch)
    end

    it 'caches the worktree path in Redis' do
      described_class.materialize(
        owner: 'LegionIO', name: 'lex-exec', default_branch: 'main',
        source_ref: 'LegionIO/lex-exec#42', work_item_id: 'uuid-mat-001'
      )
      expect(Legion::Cache.get('fleet:worktree:uuid-mat-001')).not_to be_nil
    end
  end
end
