# ticktick-quick-add

An [Omarchy](https://omarchy.org/) overlay plugin that parks a one-line task prompt near the
top of the screen, Spotlight style.

![The quick-add prompt, with the task syntax as its placeholder](preview.png)

`omarchy-menu-input` already does free-text capture, but its card is stuck in the center of
the screen. Moving it means forking all of `Menu.qml`, so this plugin moves the prompt and
leaves the SUPER menu alone.

## Install

```bash
omarchy plugin add https://github.com/bnrobinson93/omarchy-ticktick-quick-add.git
omarchy plugin enable ticktick-quick-add
```

Updates come from `omarchy plugin update ticktick-quick-add`.

This plugin only draws the prompt. To send tasks to TickTick, also install the
[`ticktick`](https://github.com/bnrobinson93/omarchy-ticktick) bar widget. Clicking the
widget opens the prompt, and its README covers sign-in and task syntax.

Sending tasks needs your own TickTick API credentials.

<details>
<summary>Get a TickTick client ID and secret</summary>

1. Sign in to the [TickTick Developer Center](https://developer.ticktick.com/manage) with
   your TickTick account
2. Create a new app. The name can be anything
3. Open the app and set its OAuth redirect URL to exactly `http://127.0.0.1`.
   `ticktask.sh` hardcodes that value, and TickTick needs the two to match
4. Copy the client ID and client secret into `~/.config/ticktask/config`:

   ```bash
   CLIENT_ID="..."
   CLIENT_SECRET="..."
   ```

5. Lock the file down, then run the script once from a terminal to get a token:

   ```bash
   chmod 600 ~/.config/ticktask/config
   ~/.config/omarchy/plugins/ticktick/ticktask.sh "hello"
   ```

6. Approve access in the browser. The page you land on will fail to load, which is expected.
   Paste its URL into the terminal

Running that command creates a real task called "hello", so you'll want to delete it. The
token is saved to `~/.local/share/ticktask/token`.

Registration and sign-in are TickTick's own process, so if these steps stop matching, the
[TickTick Open API docs](https://developer.ticktick.com/docs/index.html#/openapi) have the
current version.

</details>

## Usage

To open the prompt from a keybinding or script, run the widget's launcher:

```bash
~/.config/omarchy/plugins/ticktick/ticktick-add-launch
```

Or summon the overlay with your own prompt and command:

```bash
omarchy-shell shell summon ticktick-quick-add \
  '{"prompt":"New task","exec":"ticktask.sh"}'
```

| Key | Default | What it does |
| --- | --- | --- |
| `prompt` | `Input` | Placeholder text shown until you start typing |
| `exec` | none | Command that receives the typed line as one argument. Without it, the line is dropped |
| `fontFamily` | the menu font | Font for the prompt |

`exec` runs in a login `bash`, so it can use anything on your `PATH`. The typed line never
goes through shell parsing, so quotes, `!` and `#` arrive intact.

| Input | What it does |
| --- | --- |
| `Enter` | Runs the command and closes the prompt. An empty line just closes it |
| `Esc` | Clears the line, or closes the prompt if it's already empty |
| Click outside the card | Closes the prompt |

Editing plugin files in `~/.config/omarchy/plugins/ticktick-quick-add/` needs
`omarchy restart shell` to take effect.

## Remove

```bash
omarchy plugin remove ticktick-quick-add
```

The `ticktick` widget's count and right-click keep working without it. Only click-to-capture
goes away.

## License and dependencies

MIT, see [LICENSE](LICENSE).

| Dependency | Required | Why |
| --- | --- | --- |
| Omarchy 4 (Quattro) with Quickshell | yes | the shell that hosts the plugin |
| [`ticktick`](https://github.com/bnrobinson93/omarchy-ticktick) | for TickTick capture | supplies the launcher and `ticktask.sh`, which needs your TickTick API credentials |

Nothing is vendored, nothing is compiled, and the plugin makes no network calls of its own.
