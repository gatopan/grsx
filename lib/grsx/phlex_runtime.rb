# frozen_string_literal: true

module Grsx
  # A Phlex::HTML subclass that serves as the execution context for compiled
  # .rsx templates in standalone (non-component) rendering.
  #
  # Compiled code calls Phlex element methods directly (div, span, etc.)
  # and renders component instances via render().
  class PhlexRuntime < Phlex::HTML
    include RsxDSL

    def initialize(assigns: {})
      assigns.each { |k, v| instance_variable_set("@#{k}", v) }
    end

    def view_template(&block)
      instance_eval(&block)
    end
  end
end
