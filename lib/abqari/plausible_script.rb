# frozen_string_literal: true

require 'digest'
require 'base64'

module Abqari
  # Inline Plausible bootstrap, kept as a stable single-line string so its
  # SHA256 hash is stable across builds. The hash is added to the CSP's
  # script-src directive so the strict `'self'`-only policy still allows
  # this one inline script — same pattern as ThemeBootstrap.
  #
  # Renders only when BOTH `plausible.enabled: true` AND `plausible.key`
  # are set in config/site.yml. The external tracker
  # (https://plausible.io/js/<key>.js) is allowlisted in the same
  # script-src directive when the config is fully enabled.
  module PlausibleScript
    SCRIPT = "window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};plausible.init()"
    SHA256 = "sha256-#{Base64.strict_encode64(Digest::SHA256.digest(SCRIPT))}"
  end
end
