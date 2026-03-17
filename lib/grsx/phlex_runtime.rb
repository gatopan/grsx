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

  end
end
