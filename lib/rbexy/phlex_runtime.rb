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
    # Include ALL phlex-rails helper adapters (mirrors PhlexComponent).
    Phlex::Rails::Helpers.constants.each do |helper_name|
      mod = Phlex::Rails::Helpers.const_get(helper_name)
      include mod if mod.is_a?(Module)
    end

    # Called by PhlexCompiler-generated code for inline expressions: {expr}
    #
    #   render(<Comp />) already wrote to buffer → returns nil → no-op here
    #   Array/Enumerable    → each element rendered recursively
    #   Phlex::SafeObject   → raw()
    #   nil / false / ""   → silent no-op (safe for &&, ||, ternary)
    #   anything else      → plain(value.to_s) CGI-escaped
    def __rbx_expr_out(value)
      case value
      when nil, false, ""
        nil
      when Array, Enumerable
        value.each { |v| __rbx_expr_out(v) }
      when Phlex::SGML
        render(value)
      when Phlex::SGML::SafeObject
        raw(value)
      else
        plain(value.to_s)
      end
    end

    # Return nil from render() so that {cond && <Comp />} doesn't double-render.
    # The actual rendering is a side-effect on the buffer, not the return value.
    def render(renderable = nil, &block)
      super
      nil
    end

    def initialize(assigns: {})
      assigns.each { |k, v| instance_variable_set("@#{k}", v) }
    end

    def view_template(&block)
      instance_eval(&block)
    end

    # Explicit escape hatch for trusted HTML strings (mirrors PhlexComponent#safe).
    # WARNING: never pass user-supplied input to safe() — bypasses XSS protection.
    def safe(html_string)
      Phlex::SGML::SafeValue.new(html_string.to_s)
    end

    # Rails view_context is accessed via phlex-rails' context[:rails_view_context]
    # which is set automatically during render_in. We no longer carry our own
    # @view_context ivar or method_missing delegation — phlex-rails' SGML#method_missing
    # provides better error hints ("Try including Phlex::Rails::Helpers::LinkTo").
  end
end
