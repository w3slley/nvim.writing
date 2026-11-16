# nvim-writing

A suggestion-first writing plugin for Neovim. A small box under the text you are working on offers alternatives for it, chosen by where the cursor is. Nothing in the buffer changes until you accept. There is no chat buffer.

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
| Resting on a word (about 400 ms) | Synonyms | LLM |
| Resting on a misspelled word | Spelling fixes | Neovim's built-in spell checker, no LLM |
| Right after a sentence-ending `.` `!` `?` (about 350 ms) | Sentence variations | LLM |
| A visual selection of 2 or more words on one line (about 350 ms) | Replacements for the fragment | LLM |
| `<leader>lp` on a paragraph or a line selection | Two plans plus off-topic flags, with a diff preview | LLM |

Details:

- Typing a space after the period means a new sentence starts, so no suggestion appears.
- Misspelled words get a red underline. Resting on one shows Neovim's spell suggestions. `Ctrl+r` then asks the LLM for more likely corrections and skips the ones already shown.
- The highlighted suggestion is previewed as a diff: the old text struck through and the new text in green (see Change preview).
- Any typing or cursor movement cancels the pending request and closes the box. A response that arrives late is discarded.
- Escaping a suggestion (`Esc`) is remembered for that text, so it does not nag again until the text changes.

## Find a word from a description

When you know what you mean but not the word, press `<leader>lw` (or `<A-w>` in insert mode). A modal opens: describe the word, for example "a feeling of longing for the past", and press `Enter`.

1. Matches from a local dictionary show up at once. They come from searching the dictionary's definitions for your description.
2. The fast model is then asked for its own guesses. **Only guesses that exist in the dictionary are kept**, and every word is shown with the dictionary's definition, not the model's. An invented word never reaches the list, and a real word with the wrong meaning shows its real meaning, so you can see it does not fit.
3. Words from the model are marked ✨ and words from the dictionary search 📖. The last 3 places are kept for dictionary matches, so the model cannot push them all out.
4. Move with `<C-n>`/`<C-p>` (or `<Tab>`/`<S-Tab>`, arrows) and press `Enter` to insert the word at the cursor. Spaces are added only where the word would touch another word. `Esc` closes the modal.

The model never sees the dictionary list: small models just echo a list back, so they guess freely and the dictionary filters. If the model is slow or fails, the dictionary matches stay. Editing the description and pressing `Enter` searches again.

The description can be in English or European Portuguese. Its language is detected from the description itself. When the description gives no clue, for example a single word, the language of the text around the cursor decides. The modal title shows the language in use (`Describe a word · PT`). That language picks the dictionary, and the model is asked for words in that language, in PT-PT spelling for Portuguese.

Install the dictionaries once with `:WritingDictInstall` (both), or `:WritingDictInstall en` / `:WritingDictInstall pt` for one:

- English: [Open English WordNet](https://en-word.net) (CC BY 4.0, about 107,000 word senses), converted to a 12 MB file.
- Portuguese: the [Portuguese Wiktionary](https://pt.wiktionary.org) as extracted by [kaikki.org](https://kaikki.org/ptwiktionary/) (CC BY-SA), with definitions written in Portuguese, about 145,000 word senses converted to an 11 MB file, plus a 6 MB table of conjugated and inflected forms used by word lookup. Left out is anything marked as used only outside Portugal: Brazil-only senses, and Brazilian spellings such as "econômico" when "económico" exists. A model guess with Brazilian accents is matched to the European spelling ("efêmero" shows as "efémero"). Converting takes about 10 seconds, in the background.

Both files go in Neovim's data folder. Each index is built in the background the first time the modal opens in a session (about 2 seconds; about 80 MB of memory for English and 150 MB for Portuguese).

## Look up a word's meaning

Press `<leader>lk` and type a word to see its meanings from the same dictionaries, without the model. The meanings show below the input as you type, grouped by part of speech, with the main sense first. `Enter` looks the word up at once, `<C-f>`/`<C-b>` (or `<C-n>`/`<C-p>`, one line at a time) scroll a long entry, and `Esc` closes the modal. `:WritingDefine palavra` opens the modal with the word already looked up.

- The language of the word, or of the line you were writing when that is unclear, picks the dictionary. If the word is not in it, the other dictionary is tried, so an English word quoted in Portuguese text still gets its meaning.
- Inflected forms lead to the base word: "fui" shows both "ir" and "ser", "andava" shows "andar" with the verb senses first, and "wandered" shows "wander". Portuguese forms come from Wiktionary's conjugation and plural entries. English and missing Portuguese forms use the regular endings.
- In English, other words from the same WordNet sense are listed after the definition ("also: roam").

## Box layouts

Where the suggestions appear is configurable. Switch live with `<leader>lv` or `:WritingLayout <name>` to compare them on your own text, and set a default with `box.layout`.

| Layout | What it looks like |
| --- | --- |
| `popup` (default) | A small floating box right under the word or sentence, aligned with it. It flips above the text when there is no room below |
| `list` | The alternatives drawn as extra lines directly under the text, no floating window. Pushes the text below it down while open |
| `strip` | One compact line under the text with the alternatives side by side (synonyms, spelling, selections) or just a counter (sentences, where the change preview already shows the text) |
| `corner` | The box pinned to the bottom-right corner above the mode badge |

The box itself only lists the alternatives. The text being changed is not repeated inside it.

## Change preview

The highlighted alternative is previewed against your text as a diff: the old text struck through, the new text in green. Where it is drawn is configurable. Switch live with `<leader>ld` or `:WritingPreview <name>`, and set a default with `box.preview`.

| Preview | What it looks like |
| --- | --- |
| `strike` (default) | The old text is struck through where it sits, and only the new text is shown in green on a line below it, aligned with it. Works for visual selections too |
| `below` | A line under the text: `~~bought~~ → acquired`, aligned with the word. Long sentences become the struck-through old sentence followed by the new one in green |
| `above` | The same line, drawn above the text |
| `inline` | The old text is struck through in place and the new text appears right after it, in green |

For make-sense, the diff appears after the first accept, and the second accept applies it.

## Keys

Keys that act on a visible box are only mapped while the box is showing, so they never get in the way of normal editing. They work in normal, insert and visual mode.

| Key | Action |
| --- | --- |
| `<Tab>` | Accept the highlighted suggestion (one undo step). In make-sense mode the first press shows the diff and the second applies it |
| `<S-Tab>` | Cycle to the next suggestion |
| `<A-k>` | Previous suggestion |
| `<C-r>` | More: request new suggestions that avoid the ones already shown |
| `<Esc>` | Ignore, or cancel a request in flight |

Keys that are always available in attached buffers:

| Key | Action |
| --- | --- |
| `<leader>ls` | Suggest now. On a misspelled word, repeated presses go spelling, then synonyms, then sentence variations |
| `<leader>ly` | Synonyms for the word under the cursor, even if it is misspelled |
| `<leader>lp` | Make sense, on the paragraph or the visual selection |
| `<leader>lt` | Switch between burst and editor mode |
| `<leader>lb` / `<leader>le` | Go to burst / editor mode |
| `<leader>lv` | Cycle the box layout (popup, list, strip, corner) |
| `<leader>ld` | Cycle the change preview (strike, below, above, inline) |
| `<leader>lm` | Manual only: stop ambient suggestions, keep the keys |
| `<leader>lw` / `<A-w>` | Find a word from a description (`<A-w>` works in insert mode) |
| `<leader>lk` | Look up the meaning of a word |
| `<A-m>` | Switch mode (also in insert and visual mode) |

Note: `<leader>l` followed by another key means Neovim waits for `timeoutlen` if you also map plain `<leader>l`. That only affects Markdown and text buffers. Every key can be changed in `setup()`.

## Install

Needs Neovim 0.10 or newer (developed and tested on 0.12), plus `curl`, `unzip` and `gzip` for the one-time dictionary downloads. Suggestions need an LLM provider: the Claude CLI by default, or any OpenAI-compatible server such as a local Ollama (see LLM configuration).

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "w3slley/nvim-writing",
  ft = { "markdown", "text" },
  cmd = { "WritingEnable", "WritingDisable" },
  config = function()
    require("writing").setup({
      -- see Configuration
    })
  end,
}
```

From a local clone, use `dir = "~/path/to/nvim-writing"` instead of the GitHub name. Without a plugin manager, add the folder to the runtime path and call `setup`:

```lua
vim.opt.runtimepath:prepend("~/path/to/nvim-writing")
require("writing").setup()
```

After installing, run `:WritingDictInstall` once for word search and meanings, and `:WritingSpellInstall` once for Portuguese spelling.

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

## How it stays fast

- **Prefetch.** The request starts shortly after the cursor rests, while the delay is still counting down. Moving the cursor cancels it.
- **Plain-text replies.** Synonyms, spelling, selections and sentences are requested as one alternative per line, with a token cap, instead of JSON. Make-sense still uses JSON.
- **Streaming.** With OpenAI-compatible providers, each alternative appears as soon as its line is complete, and the rest fill in. The highlighted choice is kept while they arrive.

The `claude_cli` provider does not stream and keeps using JSON.

## Local setup

1. Install [Ollama](https://ollama.com) and start the server: `ollama serve` (or open the Ollama app).
2. Pull a model: `ollama pull gemma3:4b` (about 3.4 GB). `llama3.2:3b` (about 2 GB) is faster but writes weaker sentence variations and Portuguese.
3. Keep the model loaded between requests, otherwise the first request after an idle period pays a load delay: `OLLAMA_KEEP_ALIVE=60m ollama serve`.
4. Point the plugin at it with the local config above.
5. For spelling in Portuguese, install the dictionary once from Neovim: `:WritingSpellInstall`. English ships with Neovim.
6. For finding words from a description, install the word dictionaries once: `:WritingDictInstall`.

Measured on an M1 Max with 32 GB (roughly 0.4 to 0.7 seconds for synonyms and 0.9 to 1.5 seconds for sentence variations with `gemma3:4b`). Run your own numbers with `make bench`. Small models make mistakes, so `Ctrl+r` is useful.

### Spell checker notes

- Spelling mode needs every language in `spell.langs` installed. If one is missing, spelling is turned off with a warning, because an English-only dictionary would flag every Portuguese word.
- The Portuguese dictionary accepts both European and Brazilian spellings. It catches typos but does not enforce PT-PT. The LLM prompts do ask for PT-PT.
- The underline is controlled by `spell.highlight`. It only changes the window option the plugin itself switched on.

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
  box = { layout = "popup", preview = "strike", position = "bottom_right", badge = true },
  providers = { fast = {}, strong = {} },
  keys = {},
})
```

- `mode`: `"editor"` or `"burst"` at startup.
- `delays`: how long the cursor must rest before the box appears, in ms.
- `prefetch`: start the request this many ms after the cursor rests, while the delay is still running, so the answer is ready when the box appears. Nothing is shown early. `0` or `false` turns it off, and the request then starts when the delay ends.
- `describe.results`: how many words the description modal lists. `describe.guesses`: how many words the model is asked for (some are dropped by the dictionary check).
- `spell.while_typing`: also show spelling suggestions right after you type a misspelled word and a space. Off by default.
- `box.layout`: `"popup"`, `"list"`, `"strip"` or `"corner"`.
- `enabled`: set to `false` to load the plugin turned off, so `:WritingEnable` turns it on when you want it.
- `box.preview`: `"strike"`, `"below"`, `"above"` or `"inline"`.
- `box.position`: `"bottom_right"` or `"top_right"`. Used by the `corner` layout and the mode badge.
- `box.badge`: show the always-on mode badge.
- `style_file`: a `.writing-style.md` file at the project root (tone, words to avoid, glossary) is added to every prompt.
- `disable_file`: a `.writing-off` file in a folder disables the plugin for those files.
- Highlight groups you can override: `WritingBadgeEditor`, `WritingBadgeBurst`, `WritingTarget`, `WritingOld`, `WritingNew`, `WritingBox`, `WritingBoxSel`, `WritingBoxDim`, `WritingDescribeModel`, `WritingDescribeDict`.

## Turning it on and off

`:WritingDisable` turns the whole plugin off. Pending requests are cancelled, the box, badge and modals close, and every buffer is detached: its autocommands and keymaps are removed, and its spell options go back to what they were before. The dictionary indexes are freed too. While it is off, no buffer attaches and the other commands only say it is off. `:WritingEnable` turns it back on and attaches the open buffers again. From Lua: `require("writing").disable()`, `.enable()` and `.is_enabled()`.

`:WritingToggle` is different: it switches between editor and burst mode and leaves the plugin attached.

A key to switch it on and off, for your config:

```lua
vim.keymap.set("n", "<leader>lo", function()
  local w = require("writing")
  if w.is_enabled() then w.disable() else w.enable() end
end, { desc = "writing: on/off" })
```

## Commands

`:WritingEnable`, `:WritingDisable`, `:WritingNow`, `:WritingSense`, `:WritingLayout [name]`, `:WritingPreview [name]`, `:WritingToggle`, `:WritingBurst`, `:WritingEditor`, `:WritingManual`, `:WritingAttach`, `:WritingSpellInstall`, `:WritingDescribe`, `:WritingDefine [word]`, `:WritingDictInstall [en|pt]`, `:WritingLog`.

`:WritingLog` opens the request log. Every request records provider, model, time to first token and total time, plus accept, ignore and regenerate events, so you can see which modes are worth keeping.

## Development

```
make run      open nvim with the plugin and a scratch copy of sample.md
make test     run the headless test suite (T=context, core, buffer, dict, finder or define for one file)
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
- Portuguese word search matches definitions with a light stemmer, so a loose description finds fewer dictionary matches than in English. The model's guesses make up for most of that. The Wiktionary data does not mark every Brazilian term, so a few can still appear.

## License

MIT, see [LICENSE](LICENSE). The dictionaries are not part of this repository: `:WritingDictInstall` downloads them from their sources, under their own licenses. Open English WordNet is CC BY 4.0. The Portuguese Wiktionary data is CC BY-SA, extracted by [wiktextract](https://github.com/tatuylonen/wiktextract) and published by kaikki.org.
