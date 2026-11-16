# Neovim writing plugin: implementation plan

Nov 16, 2026 · @Wes

## Goals and principles

v1 turns Neovim into a suggestion-first writing tool: one fixed box in the top-right corner offers variations of what you are writing, chosen by cursor context and driven only by key bindings. There is no chat buffer.

- **Variation is the core idea.** You write loose, unconnected thoughts; the plugin offers alternatives that help them make sense. It never decides for you.
- **Suggest, never impose.** Nothing in the buffer changes until you accept. Ignoring a suggestion costs nothing.
- **Context decides the mode.** Idle on a word gives synonyms; the cursor after a period gives sentence variations; an explicit key on a paragraph gives a coherence pass.
- **Fast enough to stay in flow.** Ambient modes target a response under one second; the paragraph pass may take longer because you asked for it.
- **Markdown and plain text, PT-PT and English.** Language is detected per sentence, so suggestions come back in the language you wrote.

**Not in v1:** a chat interface, other file types, rewriting a whole document, and cross-document navigation or backlinks. Those come after the box feels right.

## Architecture

&#91;embedded content: plugin architecture · 8 modules, 2 paths\]

The trigger logic is the only part that reads editor events, and the suggestion box is the only part that draws. Everything between them is pure data, so each module can be tested alone. Written in Lua, with a small number of files: one per box above, plus a config module for keys, delays and providers.

## Context-aware triggers

A small state machine watches cursor and edit events and decides which mode the box shows. It is the heart of the plugin, so it gets built and tested before any real model is connected.

| Mode | Fires when | Input sent | Output | Model tier |
| --- | --- | --- | --- | --- |
| Synonyms | Cursor rests on a word for about 700 ms, or the action key | The word, its sentence | 4 alternatives | Fast |
| Variations | Cursor sits right after sentence-ending punctuation and you pause, or the action key | The sentence, the previous sentence | 3 variants | Fast |
| Make sense | Explicit key on a paragraph or visual selection | The paragraph, a few neighbours, the style note | 2 plans plus off-topic flags | Stronger |

**Rules that keep it calm**

- Any typing cancels the pending request and clears the box. Suggestions never appear while you are mid-word.
- A request carries an id; a response that arrives after the cursor moved is discarded.
- Ignoring a suggestion remembers that sentence at that revision, so the box does not nag again until the text changes.
- One toggle key hides the box completely, and a second sets the idle mode to manual only.
- The box never takes focus. Its keys work only while it is visible, and otherwise fall through to normal Neovim.

## LLM layer and latency

Two model tiers behind one interface, so the rest of the plugin never knows which provider answered.

- **Fast tier** (synonyms, variations): an inference-specialised provider such as Groq or Cerebras running an open model. Published figures put first-token latency around 100 to 200 ms, so the full answer fits well under a second.
- **Stronger tier** (make sense): a small frontier model such as Haiku or Gemini Flash with thinking switched off. First token lands around 0.7 to 0.9 s on short prompts, and a 1 to 2 s wait is fine for an explicit key.
- **Fallback:** if the fast tier errors or times out, retry once on the stronger tier, then show a quiet failure in the box.

**Latency budget for ambient modes:** about 150 ms debounce, plus network, plus first token, plus roughly 100 output tokens. The levers are small context (sentence plus paragraph), capped output of 3 to 4 items, reused HTTP connections, a cached prompt prefix for the style note, and cancelling in-flight requests when you type.

**Plumbing**

- Asynchronous HTTP through a job runner, never blocking the editor.
- Structured output (a list of alternatives) so there is no chatty text to parse.
- Keys read from environment variables. Nothing is sent until a mode fires, and a per-project switch disables the plugin for private files.
- Every request logs provider, model, time to first token and total time to a local file, which feeds the measurement work in the testing section.

**Decide by measuring, not by benchmarks.** Published numbers are noisy. Milestone 1 includes a small benchmark that runs your real prompts, in both languages, against each candidate model.

## Suggestion box

A floating window pinned to the top-right corner, always in the same place so your eye learns where to look. It never covers the cursor line because it does not follow the cursor.

- **Header:** mode name, the target (the word or a short snippet) and a position counter such as 2/3.
- **Body:** numbered alternatives, one highlighted. The highlighted one is previewed as ghost text in the buffer, so you see it in place before accepting.
- **Footer:** the keys valid right now. The footer changes with the mode and can collapse to one line once you know the keys.
- **States:** idle (hidden), loading (a subtle indicator, previous content kept), ready, error (one quiet line).

**Default keys (all rebindable, all active only while the box is visible)**

| Key | Action |
| --- | --- |
| Action key | Show suggestions for the current context right now |
| j / k | Cycle alternatives |
| 1 to 4 | Pick an alternative directly (synonyms) |
| Enter | Accept as one undo step |
| t / c / f | Regenerate tighter, clearer or more formal |
| r | Regenerate the same request |
| Esc | Ignore for this revision |
| Toggle key | Hide the box entirely |

Accepting a suggestion is a single undoable change, and the cursor lands after the inserted text so you keep typing. Make sense mode shows an inline diff first and applies only on Enter.

## Prompts and context

Each mode is one prompt template with a strict output shape. Adding a mode later means adding a template and a trigger rule, nothing else.

- **Variation prompts** ask for alternatives that differ in structure, not just wording, and keep your meaning. For loose, disconnected sentences they may lean toward linking to the previous sentence.
- **Make sense prompt** asks for two plans (keep one thread, or split into groups), a list of off-topic fragments, and a proposed rewrite. It never invents facts you did not write.
- **Language:** the reply language matches the language of the target sentence. For Portuguese the prompt states PT-PT with the new orthography (Acordo Ortográfico), because models drift toward Brazilian Portuguese by default.
- **Style note:** an optional file at the project root (tone, words to avoid, glossary, preferred spelling) is injected into every prompt. This is what makes suggestions sound like you, and it sits in the cached prefix.
- **Context window:** the target, its sentence, the previous sentence, and for paragraph mode a few neighbouring paragraphs. Nothing else leaves the machine.

**Quality check built into the box:** suggestions identical to your text, or that change meaning according to a cheap length and overlap check, are dropped before display.

## Milestones

&#91;embedded content: build roadmap · 5 phases with exit gates\]

The order follows risk: prove latency and the trigger logic first, then ship one mode at a time. Sentence variations come before synonyms because they are the heart of the idea. Each gate is a real writing session, not a checklist item; if a gate fails, fix it before starting the next phase.

## Testing and measurement

- **State machine tests:** feed scripted cursor and typing events with a fake clock and a fake provider. Check debounce, cancellation, stale-response discarding and the ignore memory. This needs no network and runs in seconds.
- **Buffer tests:** run headless Neovim to check that accepting is one undo step, that ghost text clears, and that the box never steals focus.
- **Latency benchmark:** a script replays 30 real sentences in each language against each candidate model and reports median and 95th percentile for first token and total time. Target: median under 800 ms and 95th percentile under 1.2 s for ambient modes.
- **Quality review:** a fixed set of rough sentences you wrote, run through each model. You rate suggestions on meaning kept, naturalness in PT-PT and English, and whether they help. Rerun after any prompt change.
- **Dogfooding log:** the request log records accept, ignore and regenerate rates per mode. A mode with a high ignore rate needs a better prompt or a different trigger.

## Risks, open questions and later

| Risk | Why it matters | Mitigation |
| --- | --- | --- |
| Suggestions feel distracting | Ambient popups can break flow | Long idle delay, one-key hide, manual-only mode, ignore memory |
| PT-PT drifts to Brazilian Portuguese | Small fast models lean that way | Explicit PT-PT prompt, glossary, benchmark in Portuguese before choosing the fast tier |
| Latency spikes | A slow reply after you moved on is worse than none | Cancellation, stale discard, quiet loading state, fallback tier |
| Cost or rate limits on free tiers | Ambient triggers fire often | Debounce, per-minute cap, cache repeated requests |
| Privacy of drafts | Text leaves the machine | Per-project disable, local model option, only the needed context sent |

**Open questions**

- Which provider do you want to try first for the fast tier?
- Should the idle word trigger be on by default, or manual until you tune the delay?
- Do you want a local model option (Ollama) in v1, or later?

**Later:** cross-document navigation and backlinks (reusing an existing notes plugin instead of building one), a heading outline picker, a whole-document coherence review, and more file types.
