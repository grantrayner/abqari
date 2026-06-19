# frozen_string_literal: true

require_relative 'test_helper'

class AuditTest < Minitest::Test
  def test_audit_runs_without_errors_on_canonical_site
    site = TestHelpers.built_site
    audit = Abqari::Audit.new(site)
    findings = audit.send(:find_all_for_test) if audit.respond_to?(:find_all_for_test)

    # Run the audit; we just want it to complete without raising.
    capture_io { audit.run }
  end

  def test_audit_writes_report_to_audit_directory
    site = TestHelpers.built_site
    Dir.chdir(Abqari::ROOT) do
      capture_io { Abqari::Audit.new(site).run }
      reports = Dir.glob(File.join(Abqari::ROOT, 'audit', '*.md'))
      refute_empty reports, 'expected audit report to be created'

      latest = reports.max_by { |f| File.mtime(f) }
      content = File.read(latest, encoding: 'UTF-8')
      assert_includes content, '# Abqari site audit'
      assert_includes content, '## Summary'
    end
  end
end
