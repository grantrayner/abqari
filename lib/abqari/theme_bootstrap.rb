# frozen_string_literal: true

require 'digest'
require 'base64'

module Abqari
  # Tiny inline `<script>` injected into <head> on every page. It reads the
  # user's stored theme preference from localStorage and sets a `data-theme`
  # attribute on <html> *before* the document renders — so dark/light mode
  # snaps in immediately, no flash of unstyled content.
  #
  # Kept as a stable single-line string so its SHA256 hash is stable across
  # builds. The hash is added to the CSP's script-src directive so the strict
  # `'self'`-only policy still allows this one inline script.
  module ThemeBootstrap
    SCRIPT = "(function(){var t=localStorage.getItem('theme');if(t)document.documentElement.setAttribute('data-theme',t)})()"
    SHA256 = "sha256-#{Base64.strict_encode64(Digest::SHA256.digest(SCRIPT))}"
  end
end
