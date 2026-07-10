# homebrew-loginmacaffirmations

Homebrew tap *and* source for `loginmacaffirmations`, a small service that
rotates your macOS login window text through affirmations (or any message)
pulled from an HTTP API. Everything -- the formula, the updater script, and
a manual (non-Homebrew) install path -- lives in this one repo.

## Install

```bash
brew tap nikolazleo/loginmacaffirmations
brew install loginmacaffirmations
```

Because the updater writes a root-owned system preference
(`LoginwindowText`), the service must be started as root:

```bash
sudo brew services start loginmacaffirmations
```

That's it -- with default settings the service pulls a fresh affirmation
from [affirmations.dev](https://www.affirmations.dev/) every hour and at
boot, no configuration required.

Verify it worked:

```bash
defaults read /Library/Preferences/com.apple.loginwindow LoginwindowText
```

## Configuration (optional)

The formula installs an editable config to:

```
$(brew --prefix)/etc/loginmacaffirmations/config
```

Edit it to add/change `API_URLS` and `API_AUTH_HEADERS`, then restart the
service so the change takes effect:

```bash
sudo brew services restart loginmacaffirmations
```

Reinstalling or upgrading the formula will never overwrite an existing
config file.

## Uninstall

```bash
sudo brew services stop loginmacaffirmations
brew uninstall loginmacaffirmations
brew untap nikolazleo/loginmacaffirmations
```

## Manual install (without Homebrew)

If you'd rather not use Homebrew, [`steps.sh`](steps.sh) performs an
equivalent manual install using a privileged helper and a scoped sudoers
rule instead of a root-owned LaunchDaemon:

```bash
git clone https://github.com/nikolazleo/homebrew-loginmacaffirmations.git
cd homebrew-loginmacaffirmations
zsh steps.sh
```

Before running it, edit the configurable variables (`USER_NAME`, `API_URLS`,
`API_AUTH_HEADERS`, `CRON_INTERVAL_SECONDS`) at the top of the script. It
installs a root-owned helper (`/usr/local/sbin/set-loginmessage`), a
narrowly-scoped sudoers rule, and a per-user LaunchAgent that fetches,
rotates, and applies a message at login and on a schedule. See the comments
in `steps.sh` for the full breakdown of what it installs and how to
uninstall.

## Security notes

- **Homebrew path**: the LaunchDaemon runs `bin/update-lock-message.sh`
  fully as root (since it's started via `sudo brew services start`), so
  there's no separate privileged helper or sudoers rule to review -- the
  script itself is the trusted boundary. Read it before pointing `API_URLS`
  at anything you don't control.
- **Manual path**: the sudoers entry is scoped to `set-loginmessage` with
  arbitrary arguments, which is sufficient because the helper only writes a
  plist and restarts `cfprefsd`. Review `steps.sh` before deployment if you
  require stricter guarantees.
- Consider pointing `API_URLS` at internal services or static JSON files if
  you do not control the remote endpoints.

## Formula source

See [`Formula/loginmacaffirmations.rb`](Formula/loginmacaffirmations.rb),
[`bin/update-lock-message.sh`](bin/update-lock-message.sh), and
[`config/loginmacaffirmations.example`](config/loginmacaffirmations.example).

## License

MIT -- see [LICENSE](LICENSE).
