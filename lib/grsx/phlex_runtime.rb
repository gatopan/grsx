# frozen_string_literal: true

module Grsx
  # Phlex::HTML subclass that serves as the execution context for compiled
  # .rsx view templates (non-component rendering).
  #
  # ── Architecture ──────────────────────────────────────────────────
  #
  # In ERB/Slim/Haml, compiled template code runs directly on the
  # ActionView::Base instance — `self` IS the view context.  In GRSX,
  # compiled code runs inside this PhlexRuntime, which gives us Phlex's
  # XSS-safe buffer and element DSL but places us one boundary away
  # from the view context.
  #
  # This class bridges that gap:
  #
  #   yield          → layout_content / yield_content
  #   render 'path'  → transparent partial delegation (via RsxDSL)
  #   any_helper     → method_missing → view_context delegation
  #
  class PhlexRuntime < Phlex::HTML
    include RsxDSL

    def initialize(assigns: {}, layout_block: nil)
      assigns.each { |k, v| instance_variable_set("@#{k}", v) }
      @__layout_block = layout_block
    end

    def view_template(&block)
      instance_eval(&block)
    end

    # ── Layout content ────────────────────────────────────────────
    #
    # Replaces `yield` / `yield(:head)` in RSX layout templates.
    #
    # In ERB layouts, `<%= yield %>` inserts the view body and
    # `<%= yield :head %>` inserts a named content_for block.
    #
    # Since GRSX crosses a Phlex boundary, we can't use Ruby's yield
    # directly.  Instead, the template handler captures the layout
    # block as a lambda and we call it here.
    #
    # Available as both `layout_content` and `yield_content` — use
    # whichever reads better in your layout:
    #
    #   {safe(layout_content)}       # insert the view body
    #   {safe(yield_content(:head))} # insert a content_for block
    #
    def layout_content(*args)
      @__layout_block&.call(*args)
    end

    alias_method :yield_content, :layout_content

    # ── Doctype helper ────────────────────────────────────────────
    # Phlex::HTML exposes doctype but only from within view_template.
    # This is a no-op override to ensure doctype is available.
    # (Phlex::HTML already defines it, but we document it here for
    # discoverability.)

    # ── Bootstrap grid helpers ────────────────────────────────────
    # Mirrors UI::Base so RSX view templates have the same DSL
    # as component .rsx files.

    def row(**attrs, &)
      css = class_names("row", attrs.delete(:class))
      div(class: css, **attrs, &)
    end

    def col(size = 12, **attrs, &)
      css = class_names("col-lg-#{size} mb-4", attrs.delete(:class))
      div(class: css, **attrs, &)
    end

    # ── Bootstrap icon helper ─────────────────────────────────────

    def icon(name, **attrs)
      css = class_names("bi bi-#{name}", attrs.delete(:class))
      i(class: css, **attrs)
    end

    private

    # ── View context delegation ───────────────────────────────────
    #
    # Delegates unknown method calls to the Rails view context.
    #
    # ERB/Slim/Haml don't need this because `self` IS the view context.
    # Phlex-Rails requires explicit helper module includes (strict).
    # GRSX takes the pragmatic middle ground: auto-delegate everything.
    #
    # This means set_meta_tags, recaptcha_tags, devise helpers, and
    # any gem-provided view helper work in RSX without configuration.
    #
    def method_missing(name, *, **, &block)
      if rendering? && (vc = context[:rails_view_context]) && vc.respond_to?(name)
        vc.send(name, *, **, &block)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      (rendering? && (vc = context[:rails_view_context]) && vc.respond_to?(name)) || super
    end

    def class_names(*names)
      names.compact.reject { |n| n.respond_to?(:empty?) && n.empty? }.join(" ")
    end
  end
end
