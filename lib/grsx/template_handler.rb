# frozen_string_literal: true

module Grsx
  # ActionView template handler for .rsx files.
  #
  # Registers .rsx as a first-class view template type in Rails — just like
  # ERB, Haml, or Slim. After registration, Rails automatically discovers
  # and renders .rsx files from app/views/:
  #
  #   app/views/posts/index.html.rsx
  #   app/views/posts/_sidebar.rsx
  #   app/views/layouts/application.html.rsx
  #
  # Controller instance variables are forwarded as @ivars in the template,
  # and all Phlex::Rails helpers (link_to, form_with, etc.) are available
  # through the view context.
  #
  class TemplateHandler
    def call(template, source = nil)
      source ||= template.source
      compiled = Grsx.compile(Grsx::Template.new(source, template.identifier))

      # This Ruby string is eval'd by Rails inside the ActionView context.
      # We create a one-off PhlexRuntime subclass with the compiled RSX as
      # view_template, forward controller assigns + partial locals, and
      # render through Phlex's pipeline with the view context for helpers.
      <<~RUBY
        __grsx_assigns = local_assigns.transform_keys(&:to_s)
        if respond_to?(:assigns, true)
          (assigns || {}).each { |k, v| __grsx_assigns[k.to_s] = v }
        end

        __grsx_runtime = Class.new(Grsx::PhlexRuntime) {
          define_method(:view_template) { #{compiled} }
        }.new(assigns: __grsx_assigns)

        __grsx_runtime.render_in(self, &nil)
      RUBY
    end
  end
end
