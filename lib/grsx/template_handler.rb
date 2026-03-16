# frozen_string_literal: true

module Grsx
  # ActionView template handler for .rsx files.
  #
  # Registers .rsx as a first-class view template type in Rails, just like
  # ERB, Haml, or Slim.  Rails automatically discovers and renders .rsx
  # files from app/views/:
  #
  #   app/views/posts/index.html.rsx
  #   app/views/posts/_sidebar.rsx
  #   app/views/layouts/application.html.rsx
  #
  # .rsx files are Ruby with <Tag> extensions.  Controller instance
  # variables are forwarded as @ivars and all Rails helpers are available
  # through automatic view-context delegation.
  #
  # ── Architecture note ───────────────────────────────────────────────
  #
  # ERB, Slim, and Haml compile templates into Ruby code that writes
  # directly to @output_buffer.  GRSX takes a different path: it creates
  # a Phlex::HTML subclass (PhlexRuntime) and calls render_in.  This
  # gives us Phlex's XSS-safe buffer and component DSL, but it means
  # yield, render, and helpers need explicit bridging — see PhlexRuntime
  # and RsxDSL for the bridging code.
  #
  class TemplateHandler
    # ── ActionView handler protocol ─────────────────────────────────

    def self.call(template, source = nil)
      new.call(template, source)
    end

    # Compiles .rsx source into a Ruby string that ActionView wraps in
    # a method body:  def _template_xyz(local_assigns, output_buffer, &block)
    def call(template, source = nil)
      source ||= template.source
      compiled = Grsx.compile(source, source_map: true)

      preamble  = annotation_preamble(template)
      postamble = annotation_postamble(template)

      <<~RUBY
        # ── Assign forwarding ───────────────────────────────────────
        __grsx_assigns = local_assigns.transform_keys(&:to_s)
        if respond_to?(:assigns, true)
          (assigns || {}).each { |k, v| __grsx_assigns[k.to_s] = v }
        end

        # ── Layout block capture ────────────────────────────────────
        # ActionView passes the layout body as &block to this method.
        # We wrap it in a lambda that defers `yield` to render time,
        # avoiding the ArgumentError that Proc.new raises during
        # Rails' template validation step (which calls without a block).
        #
        # Pattern inspired by how ERB/Slim natively use `yield` — but
        # since GRSX crosses into a Phlex boundary, we capture here
        # and provide `layout_content` / `yield_content` on PhlexRuntime.
        __grsx_layout_block = lambda { |*args| yield(*args) if block_given? }

        # ── Runtime instantiation ───────────────────────────────────
        __grsx_runtime = Class.new(Grsx::PhlexRuntime) {
          define_method(:view_template) { #{compiled} }
        }.new(assigns: __grsx_assigns, layout_block: __grsx_layout_block)

        #{preamble}__grsx_runtime.render_in(self, &nil)#{postamble}
      RUBY
    end

    # Declares that GRSX does not (yet) support ActionView streaming.
    # Implementing the interface signals to Rails that GRSX is a
    # well-behaved handler — Slim and Haml both declare this.
    def supports_streaming?
      false
    end

    # Let Rails handle encoding — we don't need to parse encoding
    # comments ourselves.
    def handles_encoding?
      false
    end

    # Map compile-time error locations back to .rsx source lines using
    # the GRSX source map.  Called by ActionView::Template#translate_location
    # to power Rails' ErrorHighlight integration.
    #
    # Without this, error highlights point at compiled Ruby lines that
    # don't correspond to anything in the .rsx file.
    def translate_location(spot, backtrace_location, source)
      return nil unless source

      # The source map embeds  # rsx:N  comments on each generated line.
      # Find the generated line in the compiled output and extract the
      # original RSX line number.
      compiled_line = backtrace_location.lineno
      source_lines = source.lines

      # Search for a  # rsx:N  marker near the error line
      source_lines.each_with_index do |line, idx|
        next unless idx + 1 == compiled_line
        if line =~ /# rsx:(\d+)/
          rsx_line = $1.to_i
          spot[:first_lineno] = rsx_line
          spot[:last_lineno]  = rsx_line
          return spot
        end
      end

      nil
    rescue
      nil
    end

    private

    # ── Template annotations ──────────────────────────────────────
    # When ActionView.annotate_rendered_view_with_filenames is enabled,
    # ERB, Slim, and Haml all wrap their output in HTML comments that
    # identify the source file.  We do the same.

    def annotation_preamble(template)
      return "" unless annotate?(template)
      %("<!-- BEGIN #{template.short_identifier} -->\n".html_safe + )
    end

    def annotation_postamble(template)
      return "" unless annotate?(template)
      %( + "\n<!-- END #{template.short_identifier} -->".html_safe)
    end

    def annotate?(template)
      return false unless defined?(ActionView::Base)
      ActionView::Base.annotate_rendered_view_with_filenames &&
        template.respond_to?(:format) && template.format == :html
    end
  end
end
