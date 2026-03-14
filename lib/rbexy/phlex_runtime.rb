require "phlex"
require "phlex-rails"

module Rbexy
  # A Phlex::HTML subclass that serves as the execution context for compiled
  # .rbx templates when Rbexy.configuration.render_target == :phlex.
  #
  # Instead of ActionView's @output_buffer, compiled Phlex-target code calls
  # Phlex element methods directly (div, span, etc.) and renders component
  # instances via render().
  class PhlexRuntime < Phlex::HTML
    include Phlex::Rails::Helpers

    # Allow the runtime to carry Rails view context helpers (link_to, image_tag, etc.)
    attr_reader :view_context

    # Called by PhlexCompiler-generated code for inline expressions: {expr}
    #
    #   Array / Enumerable → render each item recursively
    #   Phlex::SGML        → render() (structural, shared buffer)
    #   SafeObject         → raw()
    #   nil / false / ""  → silent no-op
    #   anything else     → plain(value.to_s) CGI-escaped
    def __rbx_expr_out(value)
      case value
      when Array, Enumerable
        value.each { |v| __rbx_expr_out(v) }
      when Phlex::SGML
        render(value)
      when Phlex::SGML::SafeObject
        raw(value)
      when nil, false, ""
        nil
      else
        plain(value.to_s)
      end
    end

    def initialize(view_context: nil, assigns: {})
      @view_context = view_context
      assigns.each { |k, v| instance_variable_set("@#{k}", v) }
    end

    def view_template(&block)
      instance_eval(&block)
    end

    # Delegate unknown method calls to the Rails view_context if present,
    # mirroring how Rbexy::Component delegates via method_missing.
    def method_missing(meth, *args, **kwargs, &block)
      if view_context&.respond_to?(meth, true)
        view_context.send(meth, *args, **kwargs, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_all)
      view_context&.respond_to?(method_name, include_all) || super
    end
  end
end
