# frozen_string_literal: true

require 'digest'
require 'base64'

module Abqari
  # Tiny inline `<script>` that respects user opt-outs from background
  # prefetching/prerendering. Reads three signals; if any is on, the
  # `<script type="speculationrules">` block in the head gets removed
  # before the browser acts on it:
  #
  #   1. `prefers-reduced-data: reduce` — CSS media query (Chrome
  #      supports it; Safari doesn't but treats it as no-match).
  #   2. `navigator.connection.saveData` — JS flag set when the user
  #      has Save-Data on in their browser data settings.
  #   3. (Implicit) `navigator.connection.effectiveType === 'slow-2g'`
  #      or `'2g'` — very slow connections get the same opt-out.
  #
  # Stable single-line string so the SHA256 hash is constant across
  # builds; HeadersFile adds the hash to the CSP script-src list so
  # strict CSP still allows this one inline script.
  module SpeculationRulesGuard
    SCRIPT = "(function(){try{var c=navigator.connection;var saveData=c&&c.saveData;var slow=c&&(c.effectiveType==='slow-2g'||c.effectiveType==='2g');var reducedData=window.matchMedia&&window.matchMedia('(prefers-reduced-data: reduce)').matches;if(saveData||slow||reducedData){var s=document.getElementById('abqari-spec-rules');if(s)s.remove()}}catch(e){}})()"
    SHA256 = "sha256-#{Base64.strict_encode64(Digest::SHA256.digest(SCRIPT))}"
  end
end
