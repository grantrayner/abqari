# frozen_string_literal: true

require 'date'
require 'fileutils'

module Abqari
  class SecurityTxt
    def initialize(site)
      @site = site
    end

    def write
      contact = @site.config['security_contact']
      return unless contact

      dest = File.join(@site.output_dir, '.well-known', 'security.txt')
      FileUtils.mkdir_p(File.dirname(dest))
      File.write(dest, build(contact))
    end

    private

    def build(contact)
      expires = (Date.today + 365).strftime('%Y-%m-%dT00:00:00.000Z')

      locale = @site.config['locale'] || 'en'
      lines = ["Contact: #{contact_uri(contact)}", "Expires: #{expires}", "Preferred-Languages: #{locale}"]
      lines << "Canonical: #{@site.config['url']&.sub(%r{/\z}, '')}/.well-known/security.txt" if @site.config['url']
      "#{lines.join("\n")}\n"
    end

    # RFC 9116 requires the Contact value to be a URI. A bare email
    # address (`security@example.com`) is invalid and parsers reject the
    # whole file — normalise it to `mailto:`. Values that already carry a
    # scheme (mailto:, https://, tel:) pass through untouched.
    def contact_uri(contact)
      value = contact.to_s.strip
      return value if value.match?(%r{\A[a-z][a-z0-9+.-]*:}i) # already has a scheme
      return "mailto:#{value}" if value.include?('@')

      value
    end
  end
end
