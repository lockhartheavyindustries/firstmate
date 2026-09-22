# Rendered sections with config/standing-skills = kun (live bin/fm-brief.sh output, isolated FM_HOME)

## ship brief: # Setup section (paragraph is last, before # Rules)
```
# Setup
You are in a disposable git worktree of demo-proj, at a detached HEAD on a clean default branch.

**Verify isolation before anything else.** Run `pwd -P` and `git rev-parse --show-toplevel`; both must resolve to the disposable task worktree you were launched in, such as a treehouse pool path or an Orca-managed worktree, not the primary checkout firstmate operates from.
The path check is authoritative: `git rev-parse --git-dir` and `git rev-parse --git-common-dir` can help inspect the repo, but they do not prove you are outside the primary checkout.
If the top-level path is the primary checkout or not the worktree you were launched in, STOP - do not branch or commit here - append `blocked [at=<epoch>]: launched in primary checkout, not an isolated worktree` to the status file and stop.

1. First action: create your branch: `git checkout -b fm/kun-ship`
2. Run `no-mistakes doctor`; if it reports the repo is not initialized here, run `no-mistakes init`.

Standing skills: before any task work, load each of these skills with your harness's own skill command: `/kun`, or `$kun` on Codex; where your harness has no verified skill command, ask for each skill by name.
Follow their guidance within this brief's boundaries; this brief's Definition of done and safety rules win on any conflict.

# Rules
```

## scout brief: # Setup section (paragraph is last, before # Rules)
```
# Setup
You are in a disposable git worktree of demo-proj, at a detached HEAD on a clean default branch.
This is a SCOUT task: the deliverable is a written report, not a PR.
The worktree is your laboratory - install, run, edit, and make scratch commits freely; all of it is discarded at teardown.
The report is the only thing that survives, so anything worth keeping must be in it.

Standing skills: before any task work, load each of these skills with your harness's own skill command: `/kun`, or `$kun` on Codex; where your harness has no verified skill command, ask for each skill by name.
Follow their guidance within this brief's boundaries; this brief's Definition of done and safety rules win on any conflict.

# Rules
```

## secondmate charter: # Operating model section (paragraph is last, before routed-work / captain sections)
```
# Operating model
You are in an isolated firstmate home. The local `AGENTS.md` is your job description, and your local `data/`, `state/`, `config/`, and `projects/` dirs are yours to operate.
This domain has no separate project clones: its subject is the firstmate repo this home lives in, and its crews take pooled worktrees of that repo.
Delegate project work to your own crewmates with the normal firstmate lifecycle: brief, spawn, status, watcher, steer, teardown, and recovery.
Do not invent a second delegation system.
You do not generate your own work.
Act only on tasks the main firstmate routes to you.
Never start a survey, audit, or "find improvements" sweep on your own initiative; that is not your job and it is unwanted.

Standing skills: before any task work, load each of these skills with your harness's own skill command: `/kun`, or `$kun` on Codex; where your harness has no verified skill command, ask for each skill by name.
Follow their guidance within this brief's boundaries; this brief's Definition of done and safety rules win on any conflict.

# The captain and the parent channel
```
