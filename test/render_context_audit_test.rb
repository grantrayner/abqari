# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

# Audit guard for RenderContext's template-visible state.
#
# RenderContext templates receive the full binding via `get_binding`,
# so every instance variable on the context is one `<%= @whatever %>`
# typo away from being a real reference. The contract documented in
# `lib/abqari/render_context.rb` is:
#
#   - `@page` and `@site` are template-public (exposed via attr_reader).
#   - Every other ivar must use the `@_`-prefix convention so it's
#     visibly "internal" and easy to grep for.
#
# This audit constructs a RenderContext, exercises the paths that
# populate ivars (notably `render_layout` chaining via `@_yielded_content`),
# then inspects `instance_variables` and fails if any ivar is neither
# in `TEMPLATE_PUBLIC_IVARS` nor `@_`-prefixed.
#
# Adding a new public ivar requires updating `TEMPLATE_PUBLIC_IVARS`
# (and docs/security.md, since the template-accessible surface is
# part of the trust model). Adding a new internal ivar just requires
# the `@_` prefix.
class RenderContextIvarAuditTest < Minitest::Test
  def test_render_context_only_exposes_public_ivars_after_layout_chain
    site = TestHelpers.built_site
    page = site.posts.first

    ctx = Abqari::RenderContext.new(page, site)

    # Render a real layout chain to make sure every code path that
    # writes an ivar fires at least once. The fixture's `post` layout
    # extends `application`, so `@_yielded_content` gets populated
    # during the inner render.
    ctx.render_layout('post')

    public_set = Abqari::RenderContext::TEMPLATE_PUBLIC_IVARS.to_set
    leaks = ctx.instance_variables.reject do |ivar|
      public_set.include?(ivar) || ivar.to_s.start_with?('@_')
    end

    assert leaks.empty?, <<~MSG
      RenderContext exposed instance variable(s) that are neither
      template-public nor `@_`-prefixed:

        #{leaks.sort.join(', ')}

      Every ivar on RenderContext is reachable from any ERB partial
      via `<%= @whatever %>`, since templates run against the
      context's binding. To keep the template-visible surface narrow:

      - If the ivar IS intended for template access, add it to
        `RenderContext::TEMPLATE_PUBLIC_IVARS` and expose it via
        `attr_reader` (and update docs/security.md).
      - Otherwise rename it with a leading underscore
        (`@_my_internal_state`) — Ruby's convention for "private,
        keep out" — which this audit accepts.
    MSG
  end

  def test_render_context_initialiser_alone_produces_no_internal_ivars
    site = TestHelpers.built_site
    page = site.posts.first
    ctx  = Abqari::RenderContext.new(page, site)

    leaks = ctx.instance_variables - Abqari::RenderContext::TEMPLATE_PUBLIC_IVARS
    assert leaks.empty?,
           "fresh RenderContext should have only TEMPLATE_PUBLIC_IVARS, got: #{leaks.inspect}"
  end
end
