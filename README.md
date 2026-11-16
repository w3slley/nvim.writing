# nvim.writing

A suggestion-first writing plugin for Neovim. A small box under the text you are working on offers alternatives, chosen by where the cursor is. Nothing changes until you accept. There is no chat buffer.

Works in Markdown and plain text, in English and European Portuguese (PT-PT). The reply language follows the sentence.

## Install

Needs Neovim 0.10+ (tested on 0.12), plus `curl`, `unzip` and `gzip` for the one-time dictionary downloads. Suggestions need an LLM provider: the Claude CLI by default, or any OpenAI-compatible server such as Ollama (see LLM configuration).

The plugin does nothing until `require("writing").setup()` is called. Options are listed under Configuration.

### lazy.nvim

```lua
{
  "w3slley/nvim.writing",
  ft = { "markdown", "text" },
  opts = {},
}
```

### packer.nvim

```lua
use({
  "w3slley/nvim.writing",
  config = function() require("writing").setup({}) end,
})
```

### vim-plug

```vim
Plug 'w3slley/nvim.writing'

" after call plug#end()
lua require("writing").setup({})
```

### mini.deps

```lua
MiniDeps.add({ source = "w3slley/nvim.writing" })
require("writing").setup({})
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ "https://github.com/w3slley/nvim.writing" })
require("writing").setup({})
```

### No manager

```sh
git clone https://github.com/w3slley/nvim.writing \
  ~/.local/share/nvim/site/pack/plugins/start/nvim.writing
```

Then add `require("writing").setup({})` to `init.lua`.

### Local clone

Use `dir = "~/path/to/nvim.writing"` with lazy.nvim, or without a manager:

```lua
vim.opt.runtimepath:prepend("~/path/to/nvim.writing")
require("writing").setup()
```

### After installing

Run `:WritingDictInstall` once for word search and meanings, and `:WritingSpellInstall` once for Portuguese spelling. The plugin attaches to `markdown` and `text` buffers. `:WritingAttach` attaches the current buffer of another filetype.

## Two modes

| Mode | What it is |
| --- | --- |
| **Burst** | Just write. No suggestions, no spell underline. |
| **Editor** | Everything below is on. |

A badge in the bottom-right corner shows the mode. Switch with `<A-m>` (any mode) or `<leader>lt`.

## What the box shows

| Cursor | Suggestion | Source |
| --- | --- | --- |
| Resting on a word (~400 ms) | Synonyms | LLM |
| Resting on a misspelled word | Spelling fixes | Neovim spell checker |
| Right after a sentence-ending `.` `!` `?` (~350 ms) | Sentence variations | LLM |
| Visual selection of 2+ words on one line (~350 ms) | Replacements for the fragment | LLM |
| `<leader>lp` on a paragraph or line selection | Two plans plus off-topic flags, with a diff | LLM |

- A space after the period starts a new sentence, so no suggestion appears.
- Resting on a misspelled word shows spell suggestions. `Ctrl+r` asks the LLM for more.
- Any typing or cursor movement cancels the request and closes the box. Late responses are discarded.
- `Esc` on a suggestion is remembered for that text until it changes.

## Change preview

The highlighted suggestion is previewed as a diff: old text struck through, new text in green. Switch live with `<leader>ld` or `:WritingPreview <name>`, and set a default with `box.preview`.

| Preview | What it looks like |
| --- | --- |
| `strike` (default) | Old text struck through in place, new text in green on a line below |
| `below` | One line under the text: `~~bought~~ → acquired` |
| `above` | The same line, above the text |
| `inline` | Old text struck through, new text right after it |

For make-sense, the diff appears on the first accept and the second accept applies it.

## Find a word from a description

Press `<leader>lw` (or `<A-w>` in insert mode), describe the word ("a feeling of longing for the past") and press `Enter`.

1. Matches from a local dictionary appear at once, found by searching its definitions.
2. The fast model then adds its own guesses. **Only guesses that exist in the dictionary are kept**, shown with the dictionary's definition. An invented word never reaches the list.
3. Model words are marked ✨, dictionary matches 📖. The last 3 places are reserved for dictionary matches.
4. Move with `<C-n>`/`<C-p>`, `<Tab>`/`<S-Tab>` or arrows, press `Enter` to insert, `Esc` to close.

If the model is slow or fails, the dictionary matches stay. The description can be English or PT-PT, detected from the text, or from the text around the cursor when unclear.

### Dictionaries

`:WritingDictInstall` installs both, or pass `en` or `pt`. Files go in Neovim's data folder, and each index is built in the background the first time the modal opens.

- English: [Open English WordNet](https://en-word.net) (CC BY 4.0, ~107,000 senses, 12 MB).
- Portuguese: [Portuguese Wiktionary](https://pt.wiktionary.org) via [kaikki.org](https://kaikki.org/ptwiktionary/) (CC BY-SA, ~145,000 senses, 11 MB, plus a 6 MB table of inflected forms). Brazil-only senses and spellings are left out, and Brazilian guesses are mapped to the European spelling ("efêmero" becomes "efémero").

Memory use is about 80 MB for English and 150 MB for Portuguese.

## Look up a word's meaning

Press `<leader>lk` and type a word. Meanings from the same dictionaries show as you type, grouped by part of speech. `Enter` looks up at once, `<C-f>`/`<C-b>` scroll, `Esc` closes. `:WritingDefine palavra` opens it with a word already looked up.

- The word's language, or the current line's, picks the dictionary. If the word is missing, the other one is tried.
- Inflected forms lead to the base word: "fui" shows "ir" and "ser", "wandered" shows "wander".
- English entries list other words from the same sense ("also: roam").

## Keys

Keys for a visible box are mapped only while it shows, in normal, insert and visual mode.

| Key | Action |
| --- | --- |
| `<Tab>` | Accept the highlighted suggestion (one undo step) |
| `<S-Tab>` / `<A-k>` | Next / previous suggestion |
| `<C-r>` | More suggestions, avoiding the ones shown |
| `<Esc>` | Ignore, or cancel a request in flight |

Always available in attached buffers:

| Key | Action |
| --- | --- |
| `<leader>ls` | Suggest now. Repeated presses on a misspelled word go spelling, synonyms, then variations |
| `<leader>ly` | Synonyms for the word under the cursor |
| `<leader>lp` | Make sense, on the paragraph or selection |
| `<leader>lt` / `<A-m>` | Switch between burst and editor mode |
| `<leader>lb` / `<leader>le` | Go to burst / editor mode |
| `<leader>ld` | Cycle the change preview |
| `<leader>lm` | Manual only: no ambient suggestions, keys kept |
| `<leader>lw` / `<A-w>` | Find a word from a description |
| `<leader>lk` | Look up a word's meaning |

If you also map plain `<leader>l`, Neovim waits for `timeoutlen` on these keys. Every key can be changed in `setup()`.

## LLM configuration

Two tiers share one interface. The **fast** tier handles synonyms, variations, selections and spelling-more. The **strong** tier handles make-sense. If the fast tier fails or times out, the request is retried once on the strong tier.

The default uses the `claude` CLI, which needs no API key but takes about 3 to 5 seconds per call. It suits make-sense. For ambient suggestions, use a local model or a fast hosted one.

| `type` | What it calls | Fields |
| --- | --- | --- |
| `claude_cli` | The `claude` CLI in print mode | `model`, `timeout`, `command` |
| `openai` | Any OpenAI-compatible `chat/completions` endpoint | `url`, `model`, `timeout`, `api_key_env`, `temperature`, `extra` |

`api_key_env` names an environment variable holding the key, and can be left out for Ollama. `extra` is merged into the request body.

### Ollama

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

1. Install [Ollama](https://ollama.com) and run `ollama serve`.
2. Pull a model: `ollama pull gemma3:4b` (~3.4 GB). `llama3.2:3b` is faster but weaker, especially in Portuguese.
3. Keep it loaded: `OLLAMA_KEEP_ALIVE=60m ollama serve`.

On an M1 Max, `gemma3:4b` takes about 0.4 to 0.7 s for synonyms and 0.9 to 1.5 s for variations. Run `make bench` for your own numbers.

### Groq

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

Other OpenAI-compatible hosts such as Cerebras work the same way. Check the provider's model list for current IDs.

### Claude CLI

```lua
require("writing").setup({
  providers = {
    fast = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 20000 },
    strong = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 40000 },
  },
})
```

The CLI must be logged in (`claude`, then `/login`).

### How it stays fast

- **Prefetch.** The request starts shortly after the cursor rests, and moving cancels it.
- **Plain-text replies.** One alternative per line with a token cap, instead of JSON. Make-sense still uses JSON.
- **Streaming.** With OpenAI-compatible providers, each alternative appears as its line completes. `claude_cli` does not stream.

## Spell checker

- Spelling needs every language in `spell.langs` installed. If one is missing, spelling is turned off with a warning.
- The Portuguese dictionary accepts European and Brazilian spellings, so it catches typos but does not enforce PT-PT. The LLM prompts do.
- `spell.highlight` controls the underline, and only changes the window option the plugin itself set.

## Configuration

All defaults, all optional:

```lua
require("writing").setup({
  enabled = true,
  mode = "editor",
  filetypes = { "markdown", "text" },
  delays = { word = 400, sentence = 350, spell = 250, selection = 350 },
  prefetch = 100,
  spell = {
    enabled = true,
    langs = { "en", "pt" },
    suggestions = 4,
    highlight = true,
    while_typing = false,
  },
  max_requests_per_minute = 30,
  counts = { synonyms = 4, variations = 3, make_sense = 2, selection = 3, spelling = 4 },
  describe = { results = 8, guesses = 8 },
  box = { preview = "strike", position = "bottom_right", badge = true },
  providers = { fast = {}, strong = {} },
  keys = {},
})
```

- `enabled`: `false` loads the plugin turned off until `:WritingEnable`.
- `mode`: `"editor"` or `"burst"` at startup.
- `delays`: how long the cursor must rest before the box appears, in ms.
- `prefetch`: start the request this many ms after the cursor rests, so the answer is ready when the box appears. `0` or `false` turns it off.
- `describe.results` / `describe.guesses`: words listed / words requested from the model.
- `spell.while_typing`: also suggest right after typing a misspelled word and a space.
- `box.preview`: `"strike"`, `"below"`, `"above"` or `"inline"`.
- `box.position`: `"bottom_right"` or `"top_right"`, used by the mode badge.
- `box.badge`: show the mode badge.
- `style_file`: a `.writing-style.md` at the project root (tone, words to avoid, glossary) is added to every prompt.
- `disable_file`: a `.writing-off` file in a folder disables the plugin there.
- Highlight groups: `WritingBadgeEditor`, `WritingBadgeBurst`, `WritingTarget`, `WritingOld`, `WritingNew`, `WritingBox`, `WritingBoxSel`, `WritingBoxDim`, `WritingDescribeModel`, `WritingDescribeDict`.

## Turning it on and off

`:WritingDisable` turns the plugin off completely: requests are cancelled, the box, badge and modals close, buffers are detached (autocommands, keymaps and spell options restored) and the dictionary indexes are freed. `:WritingEnable` reverses it. From Lua: `require("writing").disable()`, `.enable()`, `.is_enabled()`.

`:WritingToggle` only switches between editor and burst mode.

```lua
vim.keymap.set("n", "<leader>lo", function()
  local w = require("writing")
  if w.is_enabled() then w.disable() else w.enable() end
end, { desc = "writing: on/off" })
```

## Commands

`:WritingEnable`, `:WritingDisable`, `:WritingNow`, `:WritingSense`, `:WritingPreview [name]`, `:WritingToggle`, `:WritingBurst`, `:WritingEditor`, `:WritingManual`, `:WritingAttach`, `:WritingSpellInstall`, `:WritingDescribe`, `:WritingDefine [word]`, `:WritingDictInstall [en|pt]`, `:WritingLog`.

`:WritingLog` opens the request log: provider, model, time to first token, total time, and accept, ignore and regenerate events.

## Development

```
make run      open nvim with the plugin and a scratch copy of sample.md
make test     run the headless tests (T=context, core, buffer, dict, finder or define for one file)
make bench    run the latency benchmark
make clean    remove the scratch copy
```

`make run` uses an isolated profile (`NVIM_APPNAME=writing-dev`) and the repo's `init.lua`, which points at a local Ollama `gemma3:4b`. Edit it to try another provider.

The benchmark reads `BENCH_TARGETS` as `name|url|model|KEY_ENV`, separated by `;`, and skips targets whose key is unset (optional for local servers):

```
BENCH_TARGETS="local|http://localhost:11434/v1/chat/completions|gemma3:4b" make bench
```

## Limits

- Sentence and selection suggestions work within one line.
- Make-sense works on a paragraph or line selection and shows a diff before applying.
- Quality depends on the model. Small local models are fast but make mistakes, especially in Portuguese.
- Portuguese word search uses a light stemmer, so loose descriptions find fewer dictionary matches than in English. A few Brazilian terms may still appear.

## License

MIT, see [LICENSE](LICENSE). The dictionaries are not in this repository: `:WritingDictInstall` downloads them under their own licenses. Open English WordNet is CC BY 4.0. The Portuguese Wiktionary data is CC BY-SA, extracted by [wiktextract](https://github.com/tatuylonen/wiktextract) and published by kaikki.org.
