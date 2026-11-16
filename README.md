# nvim-writing

A suggestion-first writing plugin for Neovim. A small box in the bottom-right corner offers alternatives for what you are writing, chosen by where the cursor is. Nothing in the buffer changes until you accept. There is no chat buffer.

Works in Markdown and plain text, in English and European Portuguese (PT-PT). The reply language follows the language of the sentence.

## Two modes

| Mode | What it is |
| --- | --- |
| **Burst** | Just write. No suggestions, no spell underline. |
| **Editor** | Everything below is on. |

A badge in the bottom-right corner always shows the current mode (`EDITOR` or `BURST`). Switch with `<A-m>` (works in normal, insert and visual mode) or `<leader>lt`.

## What the box shows

The cursor position decides what you get.

| Cursor | Suggestion | Source |
| --- | --- | --- |
| Resting on a word (about 700 ms) | Synonyms | LLM |
| Resting on a misspelled word | Spelling fixes | Neovim's built-in spell checker, no LLM |
| Right after a sentence-ending `.` `!` `?` (about 600 ms) | Sentence variations | LLM |
| A visual selection of 2 or more words on one line (about 500 ms) | Replacements for the fragment | LLM |
| `<leader>lp` on a paragraph or a line selection | Two plans plus off-topic flags, with a diff preview | LLM |

Details:

- Typing a space after the period means a new sentence starts, so no suggestion appears.
- Misspelled words get a red underline. Resting on one shows Neovim's spell suggestions. `Ctrl+r` then asks the LLM for more likely corrections and skips the ones already shown.
- The word or sentence being changed is highlighted, and the highlighted suggestion is previewed as a ghost line below it.
- Any typing or cursor movement cancels the pending request and closes the box. A response that arrives late is discarded.
- Escaping a suggestion (`Esc`) is remembered for that text, so it does not nag again until the text changes.

## Keys

Keys that act on a visible box are only mapped while the box is showing, so they never get in the way of normal editing. They work in normal, insert and visual mode.

| Key | Action |
| --- | --- |
| `<Tab>` | Accept the highlighted suggestion (one undo step). In make-sense mode the first press shows the diff and the second applies it |
| `<S-Tab>` | Cycle to the next suggestion |
| `<A-k>` | Previous suggestion |
| `<C-r>` | More: request new suggestions that avoid the ones already shown |
| `<A-t>` `<A-c>` `<A-f>` | Regenerate tighter, clearer or more formal (variations and selections) |
| `<Esc>` | Ignore, or cancel a request in flight |

Keys that are always available in attached buffers:

| Key | Action |
| --- | --- |
| `<leader>ls` | Suggest now. On a misspelled word, repeated presses go spelling, then synonyms, then sentence variations |
| `<leader>ly` | Synonyms for the word under the cursor, even if it is misspelled |
| `<leader>lp` | Make sense, on the paragraph or the visual selection |
| `<leader>lt` | Switch between burst and editor mode |
| `<leader>lb` / `<leader>le` | Go to burst / editor mode |
| `<leader>lm` | Manual only: stop ambient suggestions, keep the keys |
| `<A-m>` | Switch mode (also in insert and visual mode) |

Note: `<leader>l` followed by another key means Neovim waits for `timeoutlen` if you also map plain `<leader>l`. That only affects Markdown and text buffers. Every key can be changed in `setup()`.

## Install

The plugin has no dependencies beyond Neovim and `curl`. It was developed and tested on Neovim 0.12; it uses `vim.system` and `vim.uv`, so it needs a recent version (0.10 or newer should work, but that is untested).

With lazy.nvim, from a local checkout:

```lua
{
  dir = "~/projects/nvim-writing",
  config = function()
    require("writing").setup({
      -- see Configuration
    })
  end,
}
```

Without a plugin manager, add the folder to the runtime path and call `setup`:

```lua
vim.opt.runtimepath:prepend("~/projects/nvim-writing")
require("writing").setup()
```

The plugin attaches to `markdown` and `text` buffers. Use `:WritingAttach` to attach to the current buffer of another filetype.

## LLM configuration

There are two tiers behind one interface. The **fast** tier handles synonyms, variations, selections and spelling-more. The **strong** tier handles make-sense. If the fast tier errors or times out, the request is retried once on the strong tier.

The default config uses the `claude` CLI, which works with a Claude subscription and needs no API key. It is slow (roughly 3 to 5 seconds per call) and is best for the explicit make-sense key. For ambient suggestions, use a local model or a fast hosted provider.

### Provider types

| `type` | What it calls | Fields |
| --- | --- | --- |
| `claude_cli` | The `claude` CLI in print mode | `model`, `timeout`, `command` |
| `openai` | Any OpenAI-compatible `chat/completions` endpoint (Ollama, Groq, Cerebras and others) | `url`, `model`, `timeout`, `api_key_env`, `temperature`, `extra` |

`api_key_env` is the name of an environment variable holding the key. Leave it out for servers that need none, such as Ollama. `extra` is merged into the request body, for example `{ reasoning_effort = "low" }`.

### Local model with Ollama

```lua
local local_model = {
  type = "openai",
  url = "http://localhost:11434/v1/chat/completions",
  model = "gemma3:4b",
  timeout = 30000,
}

require("writing").setup({
  providers = { fast = local_model, strong = local_model },
})
```

### Hosted, fast inference (Groq)

```lua
local groq = {
  type = "openai",
  url = "https://api.groq.com/openai/v1/chat/completions",
  api_key_env = "GROQ_API_KEY",
  timeout = 15000,
}

require("writing").setup({
  providers = {
    fast = vim.tbl_extend("force", groq, { model = "llama-3.1-8b-instant" }),
    strong = vim.tbl_extend("force", groq, { model = "llama-3.3-70b-versatile" }),
  },
})
```

Check Groq's model list for current model IDs. Other OpenAI-compatible providers such as Cerebras work the same way with their own `url` and key.

### Using the Claude CLI

```lua
require("writing").setup({
  providers = {
    fast = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 20000 },
    strong = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 40000 },
  },
})
```

The CLI must be logged in (`claude` then `/login`).

## Local setup

1. Install [Ollama](https://ollama.com) and start the server: `ollama serve` (or open the Ollama app).
2. Pull a model: `ollama pull gemma3:4b` (about 3.4 GB). `llama3.2:3b` (about 2 GB) is faster but writes weaker sentence variations and Portuguese.
3. Keep the model loaded between requests, otherwise the first request after an idle period pays a load delay: `OLLAMA_KEEP_ALIVE=60m ollama serve`.
4. Point the plugin at it with the local config above.
5. For spelling in Portuguese, install the dictionary once from Neovim: `:WritingSpellInstall`. English ships with Neovim.

Measured on an M1 Max with 32 GB (roughly 0.4 to 0.7 seconds for synonyms and 0.9 to 1.5 seconds for sentence variations with `gemma3:4b`). Run your own numbers with `make bench`. Small models make mistakes, so `Ctrl+r` is useful.

### Spell checker notes

- Spelling mode needs every language in `spell.langs` installed. If one is missing, spelling is turned off with a warning, because an English-only dictionary would flag every Portuguese word.
- The Portuguese dictionary accepts both European and Brazilian spellings. It catches typos but does not enforce PT-PT. The LLM prompts do ask for PT-PT.
- The underline is controlled by `spell.highlight`. It only changes the window option the plugin itself switched on.

## Configuration

All defaults, all optional:

```lua
require("writing").setup({
  mode = "editor",
  filetypes = { "markdown", "text" },
  delays = { word = 700, sentence = 600, spell = 250, selection = 500 },
  spell = {
    enabled = true,
    langs = { "en", "pt" },
    suggestions = 4,
    highlight = true,
    while_typing = false,
  },
  max_requests_per_minute = 30,
  counts = { synonyms = 4, variations = 3, make_sense = 2, selection = 3, spelling = 4 },
  box = { position = "bottom_right", badge = true },
  providers = { fast = {}, strong = {} },
  keys = {},
})
```

- `mode`: `"editor"` or `"burst"` at startup.
- `spell.while_typing`: also show spelling suggestions right after you type a misspelled word and a space. Off by default.
- `box.position`: `"bottom_right"` or `"top_right"`.
- `box.badge`: show the always-on mode badge.
- `style_file`: a `.writing-style.md` file at the project root (tone, words to avoid, glossary) is added to every prompt.
- `disable_file`: a `.writing-off` file in a folder disables the plugin for those files.
- Highlight groups you can override: `WritingBadgeEditor`, `WritingBadgeBurst`, `WritingTarget`, `WritingGhost`, `WritingBox`, `WritingBoxSel`.

## Commands

`:WritingNow`, `:WritingSense`, `:WritingToggle`, `:WritingBurst`, `:WritingEditor`, `:WritingManual`, `:WritingAttach`, `:WritingSpellInstall`, `:WritingLog`.

`:WritingLog` opens the request log. Every request records provider, model, time to first token and total time, plus accept, ignore and regenerate events, so you can see which modes are worth keeping.

## Development

```
make run      open nvim with the plugin and a scratch copy of sample.md
make test     run the headless test suite (T=context, core or buffer for one file)
make bench    run the latency benchmark
make clean    remove the scratch copy
```

`make run` uses an isolated Neovim profile (`NVIM_APPNAME=writing-dev`), so your own config does not load. It reads `init.lua` in this folder, which points the plugin at a local Ollama `gemma3:4b`. Edit that file to try another provider.

The benchmark reads targets from `BENCH_TARGETS` as `name|url|model|KEY_ENV`, separated by `;`, and skips targets whose key variable is unset. The key variable is optional for local servers:

```
BENCH_TARGETS="local|http://localhost:11434/v1/chat/completions|gemma3:4b" make bench
```

## Limits

- Sentence and selection suggestions work within one line. A sentence wrapped across lines is not handled.
- Make-sense works on a paragraph or line selection and shows the plan with a diff before applying.
- Quality depends on the model. Small local models are fast but make mistakes, especially in Portuguese.
