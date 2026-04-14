# lex-developer: Fleet Pipeline Implementation

**Level 3 Documentation**
- **Parent**: `CLAUDE.md` (monorepo root)

## Purpose

Third stage of the Fleet Pipeline. Receives planned (or directly assessed) work items, materializes the target repo, creates a worktree workspace, generates code via LLM, applies changes, commits, and opens a draft PR. Handles the feedback loop when the validator rejects (incorporate_feedback). Includes a ship runner for finalizing work (consent check, mark PR ready, labels, cleanup).

**Gem**: `lex-developer`
**Version**: 0.1.0
**Namespace**: `Legion::Extensions::Developer`

## Runners

### `Runners::Developer`
- `implement(work_item:, **)` -- Materialize repo, generate code via LLM, parse changes, commit, open PR
- `incorporate_feedback(work_item:, **)` -- Summarize feedback (AALP), increment attempt, re-enter implement

### `Runners::Ship`
- `finalize(work_item:, **)` -- Consent check, mark PR ready, set labels, post summary, cleanup caches

## Helpers

- `Helpers::RepoMaterializer` -- Clone/fetch repos to local cache, generate branch names, store branch in fleet:worktree: Redis key
- `Helpers::PromptBuilder` -- Build implementation and feedback prompts, thinking budget scaling (16K→64K exponential)
- `Helpers::ChangeParser` -- Extract file changes from LLM response (fenced code blocks with `# file:` comments)
- `Helpers::FeedbackSummarizer` -- AALP-style feedback condensation to prevent O(n^2) context growth

## Transport

- Exchange: `lex.developer` (topic, durable)
- Queues:
  - `lex.developer.runners.developer` (routing key `lex.developer.runners.developer.implement`)
  - `lex.developer.runners.ship` (routing key `lex.developer.runners.ship.#`)
  - `lex.developer.runners.feedback` (routing key `lex.developer.runners.developer.incorporate_feedback`)

## Actors

- `Actor::Developer` -- Subscription for implement function
- `Actor::Feedback` -- Subscription for incorporate_feedback function

## Key Design Notes

- Branch names stored in `fleet:worktree:<work_item_id>` Redis key (not filesystem paths)
- Worktree reused on retry: skips re-materialization when `pipeline[:branch_name]` is set
- PR creation guarded: skips if `pipeline[:pr_number]` already set
- Developer queue routing key is `implement` (not `#`) to prevent dual-delivery of incorporate_feedback messages
- Thinking budget scales exponentially: 16K * 2^attempt, capped at 64K

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```
