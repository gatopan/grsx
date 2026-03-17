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
    #
    # ── Line-number fidelity ─────────────────────────────────────────
    #
    # ActionView compiles this handler output via:
    #   module_eval(source, identifier, 0)
    #
    # The compiled RSX code is eval'd via class_eval with the .rsx file
    # path as the source identifier. This makes Ruby's backtraces point
    # directly to the correct line in the .rsx template file:
    #
    #   class_eval(body, "path/to/template.rsx", 0)
    #
    # `def view_template` sits at line 0, so the compiled body starts
    # at line 1 — matching RSX line 1. Each compiled line maps to its
    # corresponding RSX source line.
    #
    def call(template, source = nil)
      source ||= template.source
      compiled = Grsx.compile(source)
      identifier = template.respond_to?(:identifier) ? template.identifier : "(rsx)"

      preamble  = annotation_preamble(template)
      postamble = annotation_postamble(template)

      <<~RUBY
        __grsx_assigns = local_assigns.transform_keys(&:to_s)
        if respond_to?(:assigns, true)
          (assigns || {}).each { |k, v| __grsx_assigns[k.to_s] = v }
        end
        __grsx_layout_block = lambda { |*args| yield(*args) if block_given? }
        __grsx_compiled = <<~'__GRSX__'
        #{compiled}
        __GRSX__
        __grsx_runtime = Class.new(Grsx::PhlexRuntime) {
          define_method(:view_template) { instance_eval(__grsx_compiled, #{identifier.inspect}, 1) }
        }.new(assigns: __grsx_assigns, layout_block: __grsx_layout_block)
        #{preamble}__grsx_runtime.render_in(self, &nil)#{postamble}
      RUBY
    end

    # Declares that GRSX does not (yet) support ActionView streaming.
    def supports_streaming?
      false
    end

    # Let Rails handle encoding.
    def handles_encoding?
      false
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
