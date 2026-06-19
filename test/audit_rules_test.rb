# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Per-rule audit spec. Builds tiny synthetic HTML pages and confirms the
# right Audit rule fires (or doesn't). Without this, a refactor of the
# audit checks can silently stop matching and the operator only
# discovers it when a real regression slips past review.
#
# Each rule is invoked directly (`Audit::SEO.new(site, findings).run`)
# against a tmpdir output_dir so the test is hermetic — no full site
# build required.
class AuditRulesTest < Minitest::Test
  HTML_OK_TITLE = 'A page'
  HTML_OK_DESC  = 'A description that is comfortably under the recommended length.'

  def setup
    @tmpdir   = Dir.mktmpdir('abqari-audit-rules')
    @site     = build_site_stub(@tmpdir)
    @findings = []
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def build_site_stub(output)
    site = Object.new
    site.define_singleton_method(:output_dir) { output }
    site.define_singleton_method(:site_root)  { output }
    site.define_singleton_method(:config) do
      { 'url' => 'https://example.test' }
    end
    site.define_singleton_method(:env) { :production }
    site.define_singleton_method(:taxonomy_pages) { [] }
    site
  end

  def write_page(rel_path, html)
    path = File.join(@tmpdir, rel_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, html)
    path
  end

  def page(title: HTML_OK_TITLE, description: HTML_OK_DESC, body: '<h1>Hi</h1>',
           og_image: '/share.png', extras: '')
    desc_tag = description ? %(<meta name="description" content="#{description}">) : ''
    og_tag   = og_image ? %(<meta property="og:image" content="#{og_image}">) : ''
    <<~HTML
      <!doctype html>
      <html><head>
      <title>#{title}</title>
      #{desc_tag}
      #{og_tag}
      #{extras}
      </head>
      <body>
      <a class="skip-link" href="#main-content">Skip to content</a>
      <main id="main-content" tabindex="-1">
      #{body}
      </main>
      </body></html>
    HTML
  end

  def run_seo
    Abqari::Audit::SEO.new(@site, @findings).run
  end

  def run_a11y
    Abqari::Audit::A11y.new(@site, @findings).run
  end

  def findings_for(category)
    @findings.select { |f| f[:category] == category }
  end

  # --- SEO --------------------------------------------------------------

  def test_missing_meta_description_is_flagged
    write_page('a/index.html', page(description: nil))
    run_seo
    msgs = findings_for('seo').map { |f| f[:message] }
    assert_includes msgs, 'Missing meta description'
  end

  def test_overlong_title_is_flagged
    long = 'x' * 80
    write_page('a/index.html', page(title: long))
    run_seo
    msgs = findings_for('seo').map { |f| f[:message] }
    assert msgs.any? { |m| m.start_with?('Title is ') && m.include?('chars') },
           "expected an overlong-title finding, got: #{msgs.inspect}"
  end

  def test_duplicate_titles_are_flagged
    write_page('a/index.html', page(title: 'Same'))
    write_page('b/index.html', page(title: 'Same'))
    run_seo
    msgs = findings_for('seo').map { |f| f[:message] }
    assert msgs.any? { |m| m.include?('Duplicate title') && m.include?('"Same"') },
           "expected a duplicate-title finding, got: #{msgs.inspect}"
  end

  def test_missing_og_image_is_info_level
    write_page('a/index.html', page(og_image: nil))
    run_seo
    og_findings = findings_for('seo').select { |f| f[:message].include?('og:image') }
    refute_empty og_findings
    assert_equal 'info', og_findings.first[:severity]
  end

  def test_workshop_without_event_jsonld_is_flagged
    write_page('workshops/intro/index.html', page) # no Event JSON-LD
    run_seo
    msgs = findings_for('seo').map { |f| f[:message] }
    assert_includes msgs, 'Workshop has no Event JSON-LD'
  end

  def test_workshop_with_event_jsonld_is_not_flagged
    extras = %(<script type="application/ld+json">{"@type":"Event","name":"Intro"}</script>)
    write_page('workshops/intro/index.html', page(extras: extras))
    run_seo
    msgs = findings_for('seo').map { |f| f[:message] }
    refute_includes msgs, 'Workshop has no Event JSON-LD'
  end

  def test_redirect_stubs_are_skipped
    redirect = <<~HTML
      <!doctype html>
      <meta http-equiv="refresh" content="0; url=/elsewhere/">
    HTML
    write_page('old/index.html', redirect)
    run_seo
    # Redirect stub has no title / no description; the audit should skip
    # it entirely rather than emit a description-missing finding.
    assert_empty findings_for('seo')
  end

  # --- Accessibility ----------------------------------------------------

  def test_image_without_alt_is_flagged_as_error
    body = '<img src="/cat.jpg">'
    write_page('a/index.html', page(body: body))
    run_a11y
    img_findings = findings_for('a11y').select { |f| f[:message].include?('alt') }
    refute_empty img_findings
    assert_equal 'error', img_findings.first[:severity]
    assert_includes img_findings.first[:message], '/cat.jpg'
  end

  def test_image_with_alt_is_not_flagged
    body = '<img src="/cat.jpg" alt="A cat">'
    write_page('a/index.html', page(body: body))
    run_a11y
    img_findings = findings_for('a11y').select { |f| f[:message].include?('alt') }
    assert_empty img_findings
  end

  def test_multiple_h1_elements_are_flagged
    body = '<h1>One</h1><h1>Two</h1>'
    write_page('a/index.html', page(body: body))
    run_a11y
    msgs = findings_for('a11y').map { |f| f[:message] }
    assert msgs.any? { |m| m.include?('<h1>') && m.include?('found') },
           "expected multiple-h1 finding, got: #{msgs.inspect}"
  end

  def test_missing_skip_link_is_flagged
    # Build a page without the skip-link.
    html = <<~HTML
      <!doctype html>
      <html><head>
      <title>X</title>
      <meta name="description" content="Y">
      </head>
      <body>
      <main id="main-content" tabindex="-1"><h1>X</h1></main>
      </body></html>
    HTML
    write_page('a/index.html', html)
    run_a11y
    msgs = findings_for('a11y').map { |f| f[:message] }
    assert_includes msgs, 'Missing skip-to-content link'
  end

  def test_missing_main_landmark_is_flagged
    html = <<~HTML
      <!doctype html>
      <html><head>
      <title>X</title>
      <meta name="description" content="Y">
      </head>
      <body>
      <a class="skip-link" href="#main-content">Skip</a>
      <h1>X</h1>
      </body></html>
    HTML
    write_page('a/index.html', html)
    run_a11y
    msgs = findings_for('a11y').map { |f| f[:message] }
    assert msgs.any? { |m| m.include?('Missing <main') },
           "expected missing-main finding, got: #{msgs.inspect}"
  end

  # --- count / severity surface ----------------------------------------

  def test_count_filters_by_severity
    audit = Abqari::Audit.new(@site)
    audit.findings << { category: 'seo', severity: 'error', location: '/x/', message: 'fake error' }
    audit.findings << { category: 'seo', severity: 'warn',  location: '/x/', message: 'fake warn' }
    audit.findings << { category: 'seo', severity: 'info',  location: '/x/', message: 'fake info' }

    assert_equal 1, audit.count(at_least: 'error')
    assert_equal 2, audit.count(at_least: 'warn')
    assert_equal 3, audit.count(at_least: 'info')
  end

  def test_count_rejects_unknown_severity
    audit = Abqari::Audit.new(@site)
    assert_raises(ArgumentError) { audit.count(at_least: 'critical') }
  end
end
