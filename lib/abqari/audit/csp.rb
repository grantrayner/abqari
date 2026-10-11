# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'digest'

module Abqari
  class Audit
    # CSP rule. Checks every page's inline code against the
    # Content-Security-Policy the same build wrote to `_headers`: inline
    # `<script>` and `<style>` blocks, `style="…"` attributes and `on…=`
    # event handlers.
    #
    # The policy is strict on purpose (`style-src 'self'`, scripts pinned
    # by hash), so anything a template adds inline is blocked wherever
    # the CSP is enforced — and nothing else notices. The dev server
    # doesn't apply `_headers`, the page still renders, and the browser
    # only logs a console error. One site carried 52 inline
    # `style="--ratio: …"` attributes that would have collapsed every
    # photo pane, and the engine's own speculation-rules block shipped in
    # 1.1.x allowed only by a keyword Chrome ignores.
    #
    # Reads the BUILT `_headers`, not the engine's defaults, so a
    # `headers:` override or `csp:` extension in site.yml is what gets
    # checked. Error-severity: on a host that enforces the policy the
    # page is broken. A site on a host that ignores `_headers` (GitHub
    # Pages) will see these too; the code is still blocked the day the
    # policy is applied.
    class Csp < Rule
      # Script types the browser executes, so CSP governs them. Any other
      # `type` is a data block (JSON-LD, templates) and CSP ignores it.
      EXECUTABLE_TYPES = %w[
        text/javascript application/javascript application/ecmascript text/ecmascript
        module importmap speculationrules
      ].freeze
      HASH_ALGORITHMS = { 'sha256' => Digest::SHA256, 'sha384' => Digest::SHA384, 'sha512' => Digest::SHA512 }.freeze

      # Most specific directive first, as browsers resolve them.
      DIRECTIVES = {
        script:     %w[script-src-elem script-src default-src],
        script_attr: %w[script-src-attr script-src default-src],
        style:      %w[style-src-elem style-src default-src],
        style_attr: %w[style-src-attr style-src default-src]
      }.freeze

      LABELS = {
        script:      'inline <script>',
        script_attr: 'inline event handler',
        style:       '<style> block',
        style_attr:  'style attribute'
      }.freeze

      ADVICE = {
        script:      'Move it to a file under app/assets/js/, or add its sha256 to the CSP. ' \
                     'For the engine\'s own scripts, upgrade abqari and re-copy the CSP.',
        script_attr: 'Attach the handler from a script file with addEventListener instead.',
        style:       'Move the rules into app/assets/css/site.css.',
        style_attr:  'Move the styles into app/assets/css/site.css as a class, or a data ' \
                     'attribute matched by an attribute selector for per-element values.'
      }.freeze

      def run
        policies = csp_policies
        return if policies.empty?

        html_files.each do |file|
          url = page_url(file)
          applicable = policies.select { |prefix, _| url.start_with?(prefix) }.map(&:last)
          next if applicable.empty?

          check_page(url, File.read(file, encoding: 'UTF-8'), applicable)
        end
      end

      private

      # `[[path_prefix, { directive => [sources] }]]` for every CSP rule in
      # the built `_headers`. More than one can apply to a page; the
      # browser enforces all of them, so inline code has to pass each.
      def csp_policies
        path = File.join(@site.output_dir, '_headers')
        return [] unless File.file?(path)

        HeadersFile.parse(File.read(path, encoding: 'UTF-8'))
                   .select { |rule| rule['name'].casecmp?('Content-Security-Policy') }
                   .map { |rule| [rule['path'].delete_suffix('*'), parse_policy(rule['value'])] }
      end

      def parse_policy(value)
        value.split(';').each_with_object({}) do |directive, policy|
          name, *sources = directive.strip.split(/\s+/)
          policy[name.downcase] = sources if name
        end
      end

      def check_page(url, html, policies)
        blocked = Hash.new { |h, k| h[k] = [] }
        inline_code(html).each do |kind, content, type|
          policy = policies.find { |pol| !allowed?(pol, kind, content, type) }
          blocked[kind] << [content, policy] if policy
        end

        blocked.each do |kind, hits|
          content, policy = hits.first
          directive = DIRECTIVES[kind].find { |d| policy.key?(d) }
          count = hits.size
          add(category: 'security', severity: 'error', location: url,
              message: "#{count} #{LABELS[kind]}#{'s' unless count == 1} blocked by the CSP " \
                       "(#{directive} #{policy[directive].join(' ')}), e.g. #{example(kind, content)}",
              suggestion: ADVICE[kind])
        end
      end

      # Each piece of inline code as `[kind, content, script_type]`, where
      # content is exactly what the browser hashes.
      def inline_code(html)
        html = html.gsub(/<!--.*?-->/m, '')
        code = []

        html.scan(%r{<script\b([^>]*)>(.*?)</script>}mi).each do |attrs, body|
          next if attribute(attrs, 'src')

          type = attribute(attrs, 'type')&.strip&.downcase
          next unless type.nil? || type.empty? || EXECUTABLE_TYPES.include?(type)

          code << [:script, body, type]
        end
        html.scan(%r{<style\b[^>]*>(.*?)</style>}mi).each { |(body)| code << [:style, body] }

        # Attributes, with script and style bodies removed first so a
        # string inside a script that looks like markup isn't counted.
        tags_only = html.gsub(%r{<(script|style)\b[^>]*>.*?</\1>}mi, '')
        tags_only.scan(/<[a-zA-Z][^>]*>/).each do |tag|
          tag.scan(/\s(on[a-z]+|style)\s*=\s*(?:"([^"]*)"|'([^']*)')/i).each do |name, dq, sq|
            code << [name.casecmp?('style') ? :style_attr : :script_attr, CGI.unescapeHTML(dq || sq)]
          end
        end
        code
      end

      def attribute(attrs, name)
        match = attrs.match(/\b#{name}\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i)
        match && (match[1] || match[2] || match[3])
      end

      # Mirrors the CSP spec's inline checks: a hash or nonce in the list
      # switches `'unsafe-inline'` off; attribute hashes count only with
      # `'unsafe-hashes'`. `'inline-speculation-rules'` is honoured only
      # when the list has no hash or nonce: Chrome reports a block allowed
      # by nothing but the keyword as a violation once hashes are present.
      def allowed?(policy, kind, content, type = nil)
        directive = DIRECTIVES[kind].find { |d| policy.key?(d) }
        return true unless directive

        sources = policy[directive]
        hashed = sources.any? { |s| s.match?(/\A'(sha256|sha384|sha512|nonce)-/i) }
        hashed ||= kind == :script && sources.include?("'strict-dynamic'")
        return true if sources.include?("'unsafe-inline'") && !hashed
        return true if type == 'speculationrules' && sources.include?("'inline-speculation-rules'") && !hashed
        return false if %i[style_attr script_attr].include?(kind) && !sources.include?("'unsafe-hashes'")

        HASH_ALGORITHMS.any? do |alg, digest|
          sources.include?("'#{alg}-#{Base64.strict_encode64(digest.digest(content))}'")
        end
      end

      def example(kind, content)
        snippet = content.strip.gsub(/\s+/, ' ')
        snippet = "#{snippet[0, 60]}…" if snippet.length > 60
        case kind
        when :style_attr  then %(style="#{snippet}")
        when :script_attr then %(handler "#{snippet}")
        else %(`#{snippet}`)
        end
      end
    end
  end
end
