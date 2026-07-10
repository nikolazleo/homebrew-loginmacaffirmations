# homebrew-loginmacaffirmations

Homebrew tap for [`loginmacaffirmations`](https://github.com/nikolazleo/LoginwindowText-Updater), a small
service that rotates your macOS login window text through affirmations (or
any message) pulled from an HTTP API.

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

## Formula source

See [`Formula/loginmacaffirmations.rb`](Formula/loginmacaffirmations.rb).
For the full source, manual (non-Homebrew) install instructions, and
security notes, see the
[LoginwindowText-Updater](https://github.com/nikolazleo/LoginwindowText-Updater)
repository.

## License

MIT -- see [LICENSE](LICENSE).
