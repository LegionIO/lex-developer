# lex-developer

Fleet Pipeline stage 3: code generation and PR creation. Receives a planned work item, materializes the target repository, generates code via LLM, commits the changes, opens a draft PR, and handles the feedback loop when a validator rejects. Also ships finalized work — marking PRs ready, adding labels, posting summaries, and cleaning up.

## Pipeline Position

```
assessor → planner → developer → validator → developer (feedback) → ship
                         ↑                         ↓
                         └─────── incorporate_feedback ────────────┘
```

## Installation

Add to your Gemfile or gemspec:

```ruby
gem 'lex-developer'
```

## Runners

### `Runners::Developer`

#### `implement(work_item:, **)`

Materializes the target repo into a worktree, generates code via LLM, applies file changes, commits, pushes, and opens a draft PR.

```ruby
result = Legion::Extensions::Developer::Runners::Developer.implement(
  work_item: {
    work_item_id: 'uuid-001',
    source_ref:   'LegionIO/lex-exec#42',
    title:        'Fix sandbox timeout on macOS',
    repo:         { owner: 'LegionIO', name: 'lex-exec', default_branch: 'main', language: 'ruby' },
    config: {
      estimated_difficulty: 0.5,
      implementation: { max_iterations: 5 },
      feedback:       { summarize_after: 2 }
    },
    pipeline: {
      stage: 'planned',
      attempt: 0,
      trace: [],
      feedback_history: [],
      plan: {
        approach:        'Increase default timeout to 120s',
        files_to_modify: [{ path: 'lib/sandbox.rb', action: 'modify', reason: 'Fix timeout' }],
        test_strategy:   'Add unit test for default timeout'
      }
    }
  }
)

result[:success]                              # => true
result[:work_item][:pipeline][:stage]         # => 'implemented'
result[:work_item][:pipeline][:branch_name]   # => 'fleet/fix-lex-exec-42'
result[:work_item][:pipeline][:pr_number]     # => 99
result[:work_item][:pipeline][:changes]       # => ['lib/sandbox.rb', 'spec/sandbox_spec.rb']
```

The thinking budget scales with attempt number: 16K tokens on attempt 0, doubling each round up to 64K.

#### `incorporate_feedback(work_item:, **)`

Called by the feedback actor when the validator rejects. Summarizes accumulated feedback (AALP pattern), increments the attempt counter, and re-enters `implement` on the existing worktree branch.

```ruby
result = Legion::Extensions::Developer::Runners::Developer.incorporate_feedback(
  work_item: {
    # ... same shape as implement ...
    pipeline: {
      stage:   'validated',
      attempt: 1,
      branch_name: 'fleet/fix-lex-exec-42',
      feedback_history: [
        { verdict: 'rejected', issues: ['Missing nil check on timeout value'], round: 0 }
      ],
      review_result: { verdict: 'rejected', issues: ['Missing nil check on timeout value'] }
    }
  }
)

result[:success]                           # => true
result[:work_item][:pipeline][:attempt]    # => 2
result[:work_item][:pipeline][:stage]      # => 'implemented'
```

When `attempt >= max_iterations - 1`, the method escalates instead:

```ruby
result[:escalate]                            # => true
result[:work_item][:pipeline][:stage]        # => 'escalated'
```

---

### `Runners::Ship`

#### `finalize(work_item:, **)`

Finalizes a validated work item: checks consent, marks the draft PR ready for review, adds labels, posts a summary comment, removes the worktree, clears Redis refs, and writes an audit record.

```ruby
result = Legion::Extensions::Developer::Runners::Ship.finalize(
  work_item: {
    work_item_id: 'uuid-001',
    source_ref:   'LegionIO/lex-exec#42',
    config: {
      escalation: { consent_domain: 'fleet.shipping' }
    },
    pipeline: {
      stage:    'validated',
      pr_number: 99,
      branch_name: 'fleet/fix-lex-exec-42',
      changes:  ['lib/sandbox.rb', 'spec/sandbox_spec.rb'],
      review_result: { verdict: 'approved', score: 0.94 }
    }
  }
)

result[:success]                        # => true
result[:work_item][:pipeline][:stage]   # => 'shipped'
```

If the consent domain requires human approval, `finalize` suspends itself and submits to the approval queue:

```ruby
result[:awaiting_approval]   # => true
```

When the approval is granted and the message is re-delivered with `pipeline[:resumed]: true`, the consent gate is skipped and finalization completes.

---

## Helpers

### `Helpers::ChangeParser`

Parses LLM output into structured file changes. Recognizes fenced code blocks with a `# file: path/to/file` comment as the first line.

```ruby
changes = Legion::Extensions::Developer::Helpers::ChangeParser.parse(content: llm_response)
# => [
#      { path: 'lib/sandbox.rb',      content: "# frozen_string_literal: true\n..." },
#      { path: 'spec/sandbox_spec.rb', content: "# frozen_string_literal: true\n..." }
#    ]

Legion::Extensions::Developer::Helpers::ChangeParser.file_paths_only(changes: changes)
# => ['lib/sandbox.rb', 'spec/sandbox_spec.rb']
```

### `Helpers::PromptBuilder`

Builds structured LLM prompts for implementation and feedback revision rounds.

```ruby
prompt = Legion::Extensions::Developer::Helpers::PromptBuilder.build_implementation_prompt(
  work_item: work_item,
  context:   { docs: 'README contents', file_tree: ['lib/', 'lib/sandbox.rb'] }
)

feedback_prompt = Legion::Extensions::Developer::Helpers::PromptBuilder.build_feedback_prompt(
  work_item: work_item_with_history
)

# Thinking budget scales with attempt number
Legion::Extensions::Developer::Helpers::PromptBuilder.thinking_budget(attempt: 0)  # => 16_000
Legion::Extensions::Developer::Helpers::PromptBuilder.thinking_budget(attempt: 1)  # => 32_000
Legion::Extensions::Developer::Helpers::PromptBuilder.thinking_budget(attempt: 2)  # => 64_000 (cap)
```

### `Helpers::RepoMaterializer`

Generates deterministic branch names and stores them in Redis under `fleet:worktree:<work_item_id>`. In production, delegates repo clone/fetch to `lex-exec`'s `RepoMaterializer`.

```ruby
Legion::Extensions::Developer::Helpers::RepoMaterializer.branch_name(
  repo_name:  'lex-exec',
  source_ref: 'LegionIO/lex-exec#42'
)
# => 'fleet/fix-lex-exec-42'

Legion::Extensions::Developer::Helpers::RepoMaterializer.repo_cache_path(
  owner: 'LegionIO',
  name:  'lex-exec'
)
# => '/Users/you/.legionio/fleet/repos/LegionIO/lex-exec'
```

### `Helpers::FeedbackSummarizer`

AALP (Adaptive Accumulating Loss Prevention) pattern — collapses growing feedback history into a single deduplicated summary entry to prevent O(n²) context growth across rejection rounds.

```ruby
history = [
  { verdict: 'rejected', issues: ['Missing nil check', 'No test'], round: 0 },
  { verdict: 'rejected', issues: ['No test', 'Timeout too short'],  round: 1 },
  { verdict: 'rejected', issues: ['Timeout too short'],             round: 2 }
]

Legion::Extensions::Developer::Helpers::FeedbackSummarizer.needs_summarization?(
  feedback_history: history, threshold: 2
)
# => true

Legion::Extensions::Developer::Helpers::FeedbackSummarizer.summarize(
  feedback_history: history
)
# => [{ verdict: 'rejected', issues: ['Missing nil check', 'No test', 'Timeout too short'],
#        round: 2, summarized: true, source_rounds: [0, 1, 2] }]
```

---

## Transport

| Queue | Routing Key | Purpose |
|---|---|---|
| `lex.developer.runners.developer` | `lex.developer.runners.developer.implement` | Incoming implement jobs |
| `lex.developer.runners.feedback` | `lex.developer.runners.developer.incorporate_feedback` | Feedback revision jobs |
| `lex.developer.runners.ship` | `lex.developer.runners.ship.#` | Finalization jobs |

Exchange: `lex.developer` (topic, durable)

---

## Settings

All settings read from `Legion::Settings.dig(:fleet, ...)`:

| Key | Default | Description |
|---|---|---|
| `:fleet, :github, :token` | — | GitHub token for PR creation |
| `:fleet, :implementation, :max_iterations` | `5` | Max LLM attempts before escalation |
| `:fleet, :feedback, :summarize_after` | `2` | Rounds before AALP summarization kicks in |
| `:fleet, :llm, :thinking_budget_base_tokens` | `16_000` | Base thinking budget |
| `:fleet, :llm, :thinking_budget_max_tokens` | `64_000` | Cap on thinking budget |
| `:fleet, :workspace, :worktree_base` | `~/.legionio/fleet/worktrees` | Worktree directory |

---

## Development

```bash
bundle install
bundle exec rspec      # 57 examples, 0 failures
bundle exec rubocop    # 0 offenses
```

## License

MIT. See [LICENSE](LICENSE).
