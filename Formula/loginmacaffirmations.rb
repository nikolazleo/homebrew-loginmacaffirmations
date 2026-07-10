class Loginmacaffirmations < Formula
  desc "Rotate macOS login window text with affirmations pulled from an API"
  homepage "https://github.com/nikolazleo/homebrew-loginmacaffirmations"
  url "https://github.com/nikolazleo/homebrew-loginmacaffirmations.git",
      revision: "8fcde51ae9527cc593b0049ea08bed5ea80ca5ec"
  version "1.1.0"
  license "MIT"

  def install
    bin.install "bin/update-lock-message.sh"

    config_dir = etc/"loginmacaffirmations"
    config_dir.mkpath
    config_file = config_dir/"config"
    config_file.write((buildpath/"config/loginmacaffirmations.example").read) unless config_file.exist?
  end

  def post_install
    (var/"loginmacaffirmations").mkpath
  end

  service do
    run [opt_bin/"update-lock-message.sh"]
    run_type :interval
    interval 3600
    require_root true
    environment_variables LOGINMACAFFIRMATIONS_CONFIG: (etc/"loginmacaffirmations/config").to_s,
                           LOGINMACAFFIRMATIONS_STATE_DIR: (var/"loginmacaffirmations").to_s
    log_path var/"log/loginmacaffirmations.log"
    error_log_path var/"log/loginmacaffirmations.log"
  end

  def caveats
    <<~EOS
      loginmacaffirmations writes a root-owned system preference
      (LoginwindowText) and ensures login window text is enabled
      (DisableLoginwindowText is cleared on every run), so the service must
      be run as root:
        sudo brew services start loginmacaffirmations

      Out of the box it rotates a default affirmation source
      (https://www.affirmations.dev/) every hour and at boot -- no
      configuration is required to get started.

      To customise the API sources, edit:
        #{etc}/loginmacaffirmations/config
      then restart the service:
        sudo brew services restart loginmacaffirmations

      Verify it worked:
        defaults read /Library/Preferences/com.apple.loginwindow LoginwindowText
    EOS
  end

  test do
    assert_predicate bin/"update-lock-message.sh", :exist?
    system "zsh", "-n", bin/"update-lock-message.sh"

    assert_match "API_URLS", (etc/"loginmacaffirmations/config").read
  end
end
