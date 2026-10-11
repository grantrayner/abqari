# frozen_string_literal: true

require_relative 'test_helper'
require 'yaml'

# The deploy workflows a scaffolded site ships. The scaffold git-ignores
# vendor/fonts/, so a CI checkout has no font files until bin/fetch-fonts
# runs; the workflows used to go straight to bin/build, and every site
# deployed through them shipped in fallback fonts with a green build.
class SkeletonWorkflowsTest < Minitest::Test
  WORKFLOWS = Dir[File.join(Abqari::ROOT, 'lib', 'abqari', 'templates', 'site_skeleton',
                            '.github', 'workflows', 'deploy-*.yml')].sort.freeze

  def test_all_three_deploy_workflows_are_checked
    assert_equal %w[deploy-cloudflare.yml deploy-github-pages.yml deploy-render.yml],
                 WORKFLOWS.map { |path| File.basename(path) }
  end

  def test_every_workflow_fetches_fonts_before_building
    WORKFLOWS.each do |path|
      runs  = steps(path).map { |step| step['run'].to_s }
      fetch = runs.index { |run| run.include?('bin/fetch-fonts') }
      build = runs.index { |run| run.include?('bin/build') }

      refute_nil build, "#{File.basename(path)} should run bin/build"
      refute_nil fetch, "#{File.basename(path)} never runs bin/fetch-fonts"
      assert_operator fetch, :<, build, "#{File.basename(path)} fetches fonts after building"
    end
  end

  private

  def steps(path)
    YAML.safe_load(File.read(path, encoding: 'UTF-8'))['jobs'].values.flat_map { |job| job['steps'] || [] }
  end
end
