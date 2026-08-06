# frozen_string_literal: true

require_relative 'test_helper'
require 'abqari/cli'
require 'tmpdir'
require 'fileutils'

# `abqari new <projectname>` — bootstrap a fresh Abqari site by recursive-
# copying the skeleton template with ERB token substitution.
#
# These tests cover the scaffolding mechanics. The end-to-end build of
# a scaffolded site (does it actually run?) is verified manually via
# the bin/build smoke test described in CHANGELOG.
class CliNewTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('abqari-cli-new-test')
    @original_pwd = Dir.pwd
    Dir.chdir(@tmpdir)
  end

  def teardown
    Dir.chdir(@original_pwd)
    FileUtils.rm_rf(@tmpdir)
  end

  # Tiny helper — runs the CLI's `new` subcommand with `--skip-bundle`
  # so the test doesn't try to fetch gems. Captures stdout/stderr so
  # the success-message noise doesn't pollute the test runner output.
  def run_new(*args)
    out, _err = capture_io do
      @result = Abqari::CLI::New.run(args + ['--skip-bundle'])
    end
    @stdout = out
    @result
  end

  # --- Happy path ----------------------------------------------------

  def test_creates_target_directory_with_skeleton
    assert run_new('mysite')
    assert Dir.exist?('mysite')
    assert File.exist?('mysite/Gemfile')
    assert File.exist?('mysite/config/site.yml')
    assert File.exist?('mysite/content/index.md')
    assert File.exist?('mysite/content/about.md')
    assert File.exist?('mysite/content/404.md')
    assert File.exist?('mysite/content/posts/index.md')
    assert File.exist?('mysite/app/assets/css/site.css')
    assert File.exist?('mysite/bin/build')
    assert File.exist?('mysite/bin/serve')
    assert File.exist?('mysite/.gitignore')
    assert File.exist?('mysite/README.md')
  end

  def test_bin_scripts_are_executable
    run_new('mysite')
    %w[build serve audit new import index fetch-fonts fetch-folio].each do |script|
      assert File.executable?("mysite/bin/#{script}"), "bin/#{script} should be executable"
    end
  end

  def test_scaffolds_themes_dir_so_serve_watches_it_from_day_one
    # Listen watch roots are computed once at serve startup and filtered
    # by Dir.exist? — without this dir, a theme created mid-session
    # never hot-reloads.
    run_new('mysite')
    assert Dir.exist?('mysite/themes')
    assert File.exist?('mysite/themes/.gitkeep')
  end

  def test_theme_none_scaffolds_an_editable_app_css
    # `--theme none` used to scaffold a site that failed its first
    # build: the head required css/app.css and the skeleton had none.
    run_new('mysite', '--theme', 'none')
    assert File.file?('mysite/app/assets/css/app.css')
    assert_includes File.read('mysite/app/assets/css/app.css'), 'theme: none'
  end

  def test_theme_custom_copies_the_starter_into_the_site
    # The starter used to load from inside the installed gem — a file
    # the user can't edit and has never seen. Now it's theirs.
    run_new('mysite', '--theme', 'custom')
    assert File.file?('mysite/themes/custom/css/app.css')
    engine_copy = File.read(File.join(Abqari::ROOT, 'themes', 'custom', 'css', 'app.css'))
    assert_equal engine_copy, File.read('mysite/themes/custom/css/app.css')
  end

  def test_pins_ruby_version_to_the_scaffolding_ruby
    # A committed `.ruby-version` is what stops a deploy host from
    # choosing its own default Ruby — the failure mode being a native
    # gem with no precompiled binary for that version.
    run_new('mysite')
    assert File.exist?('mysite/.ruby-version'), 'scaffold must pin a Ruby version'
    assert_equal RUBY_VERSION, File.read('mysite/.ruby-version', encoding: 'UTF-8').strip
  end

  def test_no_template_suffix_in_output
    # `.tt` files in the skeleton are ERB; output should land at the
    # path without the suffix.
    run_new('mysite')
    refute Dir.glob('mysite/**/*.tt').any?, 'no .tt files should survive in the scaffolded site'
  end

  # --- Token substitution --------------------------------------------

  def test_substitutes_projectname_into_title_by_default
    run_new('the-cool-site')
    config = File.read('the-cool-site/config/site.yml', encoding: 'UTF-8')
    # Default title is the projectname title-cased.
    assert_match(/^title: The Cool Site$/, config)
  end

  def test_name_flag_overrides_titleized_default
    run_new('mysite', '--name', 'My Custom Title')
    config = File.read('mysite/config/site.yml', encoding: 'UTF-8')
    assert_match(/^title: My Custom Title$/, config)
  end

  def test_substitutes_description_author_theme_locale
    run_new('mysite',
            '--description', 'A neat little blog',
            '--author',      'Jane Smith',
            '--theme',       'magazine',
            '--locale',      'fr')
    config = File.read('mysite/config/site.yml', encoding: 'UTF-8')
    assert_match(/^description: A neat little blog$/, config)
    assert_match(/^author: Jane Smith$/, config)
    assert_match(/^theme: magazine$/, config)
    assert_match(/^locale: fr$/, config)
  end

  # --- Per-theme fonts -------------------------------------------------

  def test_webfont_theme_scaffolds_its_fonts_block
    run_new('mysite', '--theme', 'sand')
    config = File.read('mysite/config/site.yml', encoding: 'UTF-8')
    assert_match(/^fonts:$/, config)
    assert_match(/family: Merriweather$/, config)
    assert_match(/family: Merriweather Sans$/, config)
    assert_includes @stdout, 'bin/fetch-fonts'
  end

  def test_system_font_theme_scaffolds_commented_example_only
    run_new('mysite') # default theme: minimal
    config = File.read('mysite/config/site.yml', encoding: 'UTF-8')
    refute_match(/^fonts:$/, config, 'no live fonts: block for a system-font theme')
    assert_match(/^# fonts:$/, config, 'commented example should remain')
    refute_includes @stdout, 'bin/fetch-fonts'
  end

  def test_every_shipped_theme_font_list_matches_its_stylesheet
    # Guard against drift: every family ThemeFonts declares for a theme
    # must actually appear in that theme's font stacks, so the map can't
    # quietly outlive a theme redesign.
    Abqari::ThemeFonts::FONTS.each do |theme, fonts|
      css = File.read(File.join(Abqari::ROOT, 'themes', theme, 'css', 'app.css'),
                      encoding: 'UTF-8')
      fonts.map { |f| f['family'] }.uniq.each do |family|
        assert_includes css, family,
                        "#{theme}'s ThemeFonts lists #{family.inspect} but its stylesheet never names it"
      end
    end
  end

  def test_gemfile_uses_rubygems_source_by_default
    run_new('mysite')
    gemfile = File.read('mysite/Gemfile', encoding: 'UTF-8')
    major_minor = Abqari::VERSION.split('.').first(2).join('.')
    assert_match(/^gem 'abqari', '~> #{Regexp.escape(major_minor)}'$/, gemfile)
    refute_match(/gem 'abqari', git:/, gemfile)
    refute_match(/gem 'abqari', path:/, gemfile)
  end

  def test_engine_git_writes_git_source_in_gemfile
    run_new('mysite', '--engine', 'git')
    gemfile = File.read('mysite/Gemfile', encoding: 'UTF-8')
    assert_match(/gem 'abqari', git:/, gemfile)
    refute_match(/gem 'abqari', path:/, gemfile)
  end

  def test_engine_path_writes_path_source_in_gemfile
    run_new('mysite', '--engine', 'path')
    gemfile = File.read('mysite/Gemfile', encoding: 'UTF-8')
    assert_match(%r{gem 'abqari', path: '../abqari'}, gemfile)
    refute_match(/gem 'abqari', git:/, gemfile)
  end

  # --- Optional collections (--with) ---------------------------------

  def config_yaml(project = 'mysite')
    YAML.safe_load_file("#{project}/config/site.yml")
  end

  # --- Config template drift ------------------------------------------

  def test_scaffolded_config_validates_strict
    run_new('mysite')
    Abqari::SiteConfig.validate!(config_yaml, strict: true)
  end

  def test_blank_scaffolded_config_validates_strict
    run_new('mysite', '--blank')
    Abqari::SiteConfig.validate!(config_yaml, strict: true)
  end

  def test_commented_config_examples_use_known_keys
    # YAML-level validation can't see commented examples, but they
    # teach users keys to uncomment — a key the engine doesn't read
    # silently no-ops (the `social_links:` regression). Scan `# key:`
    # lines at comment-root level in both config templates.
    skeleton_config = File.expand_path('../lib/abqari/templates/site_skeleton/config', __dir__)
    Dir.glob(File.join(skeleton_config, '*.yml.tt')).each do |path|
      File.readlines(path, encoding: 'UTF-8').each_with_index do |line, i|
        match = line.match(/^# (?<key>[a-z_][a-z0-9_]*):(\s|$)/)
        next unless match

        key = match[:key]
        assert Abqari::SiteConfig::KNOWN_KEYS.include?(key) || key.start_with?('x_'),
               "#{File.basename(path)}:#{i + 1} documents `#{key}:` — not in SiteConfig::KNOWN_KEYS, " \
               'so uncommenting it warns as an unknown key'
      end
    end
  end

  def test_default_scaffold_is_posts_only
    run_new('mysite')
    collections = config_yaml['collections']
    assert_equal true,  collections['posts']['enabled']
    assert_equal false, collections['photos']['enabled']
    assert_equal false, collections['publications']['enabled']
    assert_equal false, collections['workshops']['enabled']
    refute Dir.exist?('mysite/content/photos')
    refute Dir.exist?('mysite/content/publications')
    refute Dir.exist?('mysite/content/workshops')
  end

  def test_with_flag_enables_collection_and_scaffolds_its_index_page
    run_new('mysite', '--with', 'photos')
    assert_equal true,  config_yaml['collections']['photos']['enabled']
    assert_equal false, config_yaml['collections']['publications']['enabled']

    index = File.read('mysite/content/photos/index.md', encoding: 'UTF-8')
    assert_match(/^title: Photos$/, index)
    assert_match(/^nav:$/, index, 'collection index needs a nav entry')
    refute Dir.exist?('mysite/content/publications')
  end

  def test_with_flag_accepts_comma_separated_list
    run_new('mysite', '--with', 'photos,workshops')
    collections = config_yaml['collections']
    assert_equal true,  collections['photos']['enabled']
    assert_equal true,  collections['workshops']['enabled']
    assert_equal false, collections['publications']['enabled']
    assert File.exist?('mysite/content/photos/index.md')
    assert File.exist?('mysite/content/workshops/index.md')
  end

  def test_with_flag_is_repeatable
    run_new('mysite', '--with', 'publications', '--with', 'workshops')
    collections = config_yaml['collections']
    assert_equal true, collections['publications']['enabled']
    assert_equal true, collections['workshops']['enabled']
  end

  def test_with_flag_composes_with_blank_mode
    run_new('mysite', '--blank', '--with', 'photos')
    assert_equal true, config_yaml['collections']['photos']['enabled']
    assert File.exist?('mysite/content/photos/index.md')
    refute Dir.exist?('mysite/content/posts/welcome')
  end

  def test_unknown_with_collection_is_rejected
    refute run_new('mysite', '--with', 'posts')   # always on — not a valid --with value
    refute run_new('mysite2', '--with', 'banana')
    refute Dir.exist?('mysite')
    refute Dir.exist?('mysite2')
  end

  # --- Validation + safety -------------------------------------------

  def test_unknown_theme_is_rejected
    refute run_new('mysite', '--theme', 'banana')
    refute Dir.exist?('mysite'), 'should bail before creating the dir'
  end

  def test_unknown_engine_is_rejected
    refute run_new('mysite', '--engine', 'svn')
    refute Dir.exist?('mysite')
  end

  def test_refuses_to_overwrite_non_empty_target
    FileUtils.mkdir_p('existing/some-dir')
    File.write('existing/some-dir/file.txt', 'hands off')

    refute run_new('existing'), 'should refuse to overwrite without --force'
    assert File.exist?('existing/some-dir/file.txt'), 'existing files should be untouched'
  end

  def test_force_flag_overwrites_existing_target
    FileUtils.mkdir_p('existing')
    File.write('existing/old.txt', 'stale')

    assert run_new('existing', '--force')
    # The skeleton has been copied in alongside the existing file.
    assert File.exist?('existing/Gemfile')
    assert File.exist?('existing/old.txt'), '--force overlays; it does not wipe'
  end

  def test_requires_a_projectname
    refute run_new, 'should error when no projectname is given'
  end

  # --- Example post is scaffolded for first-run ergonomics -----------

  def test_includes_an_example_post
    run_new('mysite')
    post_paths = Dir.glob('mysite/content/posts/*/index.md')
    refute_empty post_paths, 'expected at least one example post'
    body = File.read(post_paths.first, encoding: 'UTF-8')
    assert_match(/^title:/, body, 'example post should have frontmatter')
    assert_match(/^published: true$/, body)
  end

  # --- Blank mode --------------------------------------------------

  def test_blank_mode_still_ships_404_page
    run_new('mysite', '--blank')
    assert File.exist?('mysite/content/404.md'),
           'every site needs a 404 page, blank scaffolds included'
  end

  def test_blank_mode_skips_example_post
    run_new('mysite', '--blank')
    # The welcome example post directory should NOT exist.
    refute Dir.exist?('mysite/content/posts/welcome'), 'example post should be skipped in blank mode'
    # But the posts collection's index page DOES still exist — empty
    # is a legitimate state.
    assert File.exist?('mysite/content/posts/index.md')
  end

  def test_blank_mode_uses_terse_home_page
    run_new('mysite', '--blank')
    home = File.read('mysite/content/index.md', encoding: 'UTF-8')
    # The blank variant just says "Welcome." — no tutorial body.
    refute_match(/Where to next/, home, 'blank home should not carry the tutorial body')
    assert_match(/^Welcome\.\s*$/, home, 'blank home should be a single-line welcome')
  end

  def test_blank_mode_uses_terse_about_page
    run_new('mysite', '--blank')
    about = File.read('mysite/content/about.md', encoding: 'UTF-8')
    refute_match(/sits at .\/about\/./, about, 'blank about should not carry the explanatory body')
    assert_match(/^A short bio\.\s*$/, about, 'blank about should be a single-line stub')
  end

  def test_blank_mode_uses_terse_config
    run_new('mysite', '--blank')
    config = File.read('mysite/config/site.yml', encoding: 'UTF-8')
    # The full config has long ─── separator comments; the blank
    # variant doesn't.
    refute_match(/────────/, config, 'blank config should not carry the documentation banners')
    # Yet the config IS still a valid, working file — keys are present.
    assert_match(/^title:/, config)
    assert_match(/^collections:/, config)
    assert_match(/^environments:/, config)
  end

  def test_blank_mode_does_not_emit_dual_files
    # Both `.blank.<ext>.tt` and `.<ext>.tt` exist in the skeleton
    # tree; only ONE should land in the output (no `.blank.` files
    # surviving, no double-write to the same path).
    run_new('mysite', '--blank')
    refute Dir.glob('mysite/**/*.blank.*').any?,
           'no .blank.* sentinel files should survive in the scaffolded site'
  end

  def test_default_mode_uses_full_variants
    # Sanity check the inverse: without --blank, the populated home
    # page DOES carry the tutorial body, and the example post IS
    # present.
    run_new('mysite')
    home = File.read('mysite/content/index.md', encoding: 'UTF-8')
    assert_match(/Where to next/, home)
    assert Dir.exist?('mysite/content/posts/welcome')
  end

  # --- YAML-hostile option values -------------------------------------
  #
  # `--name` / `--description` / `--author` are free text that lands in
  # `config/site.yml` and in frontmatter. Before these values were
  # emitted as YAML scalars, `--name "My Site: A Story"` scaffolded
  # with exit 0 and produced a config Psych couldn't parse — so the
  # scaffold reported success and `bin/build` died on the first run.
  # A `#` was quieter and worse: the value was silently truncated.

  # Every frontmatter-bearing file the scaffold writes, so a regression
  # in one template can't hide behind another passing.
  FRONTMATTER_FILES = [
    'content/index.md',
    'content/about.md',
    'content/posts/welcome/index.md'
  ].freeze

  def assert_scaffold_parses(project = 'mysite')
    YAML.safe_load_file("#{project}/config/site.yml")

    FRONTMATTER_FILES.each do |rel|
      path = "#{project}/#{rel}"
      body = File.read(path, encoding: 'UTF-8')
      match = body.match(Abqari::FRONTMATTER_RE)
      refute_nil match, "#{rel} should have parseable frontmatter"
      YAML.safe_load(match[1], permitted_classes: Abqari::YAML_PERMITTED_CLASSES)
    end
  end

  def test_title_containing_a_colon_produces_parseable_yaml
    assert run_new('mysite', '--name', 'My Site: A Story')
    assert_scaffold_parses
    assert_equal 'My Site: A Story', config_yaml['title']
  end

  def test_description_containing_a_hash_is_not_truncated
    # The silent-failure case: `#` starts a YAML comment, so an
    # unquoted value lost everything after it without any error.
    assert run_new('mysite', '--description', 'Notes # on stuff')
    assert_scaffold_parses
    assert_equal 'Notes # on stuff', config_yaml['description']
  end

  def test_yaml_hostile_values_round_trip_through_every_sink
    assert run_new('mysite',
                   '--name', 'Site: "quoted" & odd',
                   '--description', "Trailing colon: yes # and a hash",
                   '--author', '@handle')
    assert_scaffold_parses

    config = config_yaml
    assert_equal 'Site: "quoted" & odd', config['title']
    assert_equal 'Trailing colon: yes # and a hash', config['description']
    assert_equal '@handle', config['author']

    home = File.read('mysite/content/index.md', encoding: 'UTF-8')
    front = YAML.safe_load(home.match(Abqari::FRONTMATTER_RE)[1])
    assert_equal 'Site: "quoted" & odd', front['title']
  end

  def test_values_that_yaml_would_coerce_stay_strings
    # `yes` loads back as `true` and `1.0` as a Float unless quoted —
    # a plain quote-the-special-characters filter misses both, because
    # neither string contains a special character.
    assert run_new('mysite', '--name', 'yes', '--description', '1.0', '--author', 'null')
    assert_scaffold_parses

    config = config_yaml
    assert_equal 'yes', config['title']
    assert_equal '1.0', config['description']
    assert_equal 'null', config['author']
  end

  def test_blank_mode_also_quotes_yaml_hostile_values
    # The blank scaffold renders different templates for the same
    # sinks; it needs the same protection.
    assert run_new('mysite', '--blank', '--name', 'My Site: A Story')
    YAML.safe_load_file('mysite/config/site.yml')
    assert_equal 'My Site: A Story', config_yaml['title']

    %w[content/index.md content/about.md].each do |rel|
      body = File.read("mysite/#{rel}", encoding: 'UTF-8')
      YAML.safe_load(body.match(Abqari::FRONTMATTER_RE)[1])
    end
  end

  # --- Argument validation -------------------------------------------
  #
  # `abqari new <projectname>` creates a directory in the CURRENT
  # directory; the argument is a name, not a path. Nothing checked that,
  # so `""` scaffolded into the cwd and `..` / absolute paths wrote ~40
  # files wherever they pointed, overwriting same-named files.

  def test_empty_projectname_is_rejected
    _out, err = capture_io { refute Abqari::CLI::New.run(['', '--skip-bundle']) }
    assert_match(/empty/i, err)
    assert_empty Dir.children('.'), 'nothing should be written into the cwd'
  end

  def test_traversing_projectname_is_rejected
    _out, err = capture_io { refute Abqari::CLI::New.run(['../evil', '--skip-bundle']) }
    assert_match(/looks like a path/, err)
    refute Dir.exist?('../evil')
  end

  def test_absolute_projectname_is_rejected
    _out, err = capture_io { refute Abqari::CLI::New.run(['/tmp/abqari-abs-evil', '--skip-bundle']) }
    assert_match(/looks like a path/, err)
    refute Dir.exist?('/tmp/abqari-abs-evil')
  end

  def test_dot_projectname_is_rejected
    _out, err = capture_io { refute Abqari::CLI::New.run(['.', '--skip-bundle']) }
    assert_match(/not a usable directory name/, err)
  end

  def test_extra_positional_arguments_are_reported
    # An unquoted two-word name silently lost everything after the first
    # word — the user got a site called "my" and no indication why.
    _out, err = capture_io { Abqari::CLI::New.run(%w[my blog site --skip-bundle]) }
    assert_match(/Ignoring extra argument/, err)
    assert_match(/Quote the name/, err)
  end

  def test_force_refuses_to_overwrite_an_existing_git_repository
    FileUtils.mkdir_p('someproject/.git')
    File.write('someproject/README.md', 'existing work')

    _out, err = capture_io do
      refute Abqari::CLI::New.run(['someproject', '--force', '--skip-bundle'])
    end

    assert_match(/\.git directory/, err)
    assert_equal 'existing work', File.read('someproject/README.md'),
                 '--force must not clobber an unrelated repository'
  end

  def test_target_that_is_a_file_is_reported_cleanly
    File.write('notadir', 'x')
    _out, err = capture_io { refute Abqari::CLI::New.run(['notadir', '--skip-bundle']) }
    assert_match(/is a file, not a directory/, err)
  end

  # --- Flag errors ----------------------------------------------------

  def test_unknown_flag_reports_without_a_backtrace
    # `OptionParser#parse` raises on an unknown flag and nothing caught
    # it, so a one-character typo met the user with a six-frame trace.
    _out, err = capture_io { refute Abqari::CLI.run(%w[new --bloank mysite]) }

    assert_match(/invalid option/, err)
    refute_match(/\.rb:\d+:in/, err, 'no backtrace frames should reach the user')
    assert_match(/--help/, err, 'and it should point at the help')
  end

  # --- Encoding -------------------------------------------------------

  def test_non_ascii_name_works_when_argv_arrives_as_binary
    # Under a C/POSIX locale (Docker, cron, `env -i`) Ruby tags ARGV as
    # US-ASCII/BINARY. Rendering a UTF-8 template against it raised
    # Encoding::CompatibilityError PART WAY THROUGH scaffolding, leaving
    # a half-written directory that then blocked a corrected retry.
    binary_name = 'café'.dup.force_encoding(Encoding::ASCII_8BIT)

    capture_io { assert Abqari::CLI.run([('new'), binary_name, '--skip-bundle']) }

    assert Dir.exist?('café')
    assert_equal 'Café', config_yaml('café')['title']
  end

  # --- Blank mode + fonts ---------------------------------------------

  def test_blank_mode_still_scaffolds_fonts_for_a_font_dependent_theme
    # Blank mode emitted no fonts section while next-steps still told
    # the user to run bin/fetch-fonts — which then reported "No fonts
    # configured", and magazine silently fell back to system serifs.
    run_new('mysite', '--blank', '--theme', 'magazine')

    fonts = config_yaml['fonts']
    refute_nil fonts, 'magazine needs its webfonts declared even in blank mode'
    assert_includes fonts.map { |f| f['family'] }, 'Playfair Display'
  end

  def test_blank_mode_omits_fonts_for_a_system_font_theme
    run_new('mysite', '--blank', '--theme', 'minimal')
    assert_nil config_yaml['fonts'], 'minimal uses system fonts — nothing to declare'
  end

  def test_ordinary_values_are_not_gratuitously_quoted
    # The quoting is Psych's, so it only fires when YAML needs it —
    # a plain scaffold should still read as plain YAML.
    run_new('mysite', '--name', 'My Site', '--author', 'Ada Lovelace')
    config = File.read('mysite/config/site.yml', encoding: 'UTF-8')
    assert_match(/^title: My Site$/, config)
    assert_match(/^author: Ada Lovelace$/, config)
    assert_match(/^locale: en$/, config)
    assert_match(/^theme: minimal$/, config)
  end
end
