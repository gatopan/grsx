# frozen_string_literal: true

require "phlex"
require "phlex-rails"

module Grsx
  # Shared DSL methods included by both PhlexComponent and PhlexRuntime.
  #
  # These methods form the glue between Grsx's compiled .rsx output and
  # Phlex's rendering API: expression output, HTML safety, render
  # nil-return, and Rails helper inclusion.
  module RsxDSL
    def self.included(base)
      # Include ALL phlex-rails helper adapters so link_to, form_with,
      # image_tag, url_for, etc. just work in every .rsx template without
      # per-component opt-in.
      #
      # EXCLUDED: Rails form helpers whose method names collide with Phlex's
      # HTML element methods: Select, TextArea, Label, Object. Including
      # them overrides the HTML tag methods (e.g. `select` becomes the Rails
      # form helper instead of emitting a <select> tag).
      #
      # The form helpers remain available via their _tag variants:
      # select_tag, text_area_tag, label_tag, etc.
      #
      # Some helpers (e.g. Routes) reference `Rails.application` at define
      # time, which raises NameError outside a Rails boot. We rescue and
      # skip — those helpers are unavailable in non-Rails contexts anyway.
      excluded = %i[Select TextArea Label Object].to_set

      Phlex::Rails::Helpers.constants.each do |helper_name|
        next if excluded.include?(helper_name)

        begin
          mod = Phlex::Rails::Helpers.const_get(helper_name)
          base.include mod if mod.is_a?(Module)
        rescue NameError
          # Skip helpers that require Rails to be fully initialized
        end
      end
    end

    # Handles all { ruby_expr } in compiled templates:
    #
    #   render(<Comp />) already wrote to buffer → returns nil → no-op here
    #   Array/Enumerable    → each element rendered recursively
    #   Phlex::SafeObject   → raw()  (trusted HTML, no escaping)
    #   nil / false / ""   → silent no-op (safe for && and || patterns)
    #   anything else       → plain(value.to_s)  (CGI auto-escaped, XSS-safe)
    def __rsx_expr_out(value)
      case value
      when nil, false, ""
        nil  # {condition && <Foo />}: falsy short-circuit
      when Array, Enumerable
        # {@items.map { |i| <Item /> }}: map returns [nil,nil,...] after render→nil
        value.each { |v| __rsx_expr_out(v) }
      when Phlex::SGML
        # Safety net: if a user passes a component directly (e.g. {MyComp.new})
        # render it normally.
        render(value)
      when Phlex::SGML::SafeObject
        raw(value)
      else
        plain(value.to_s)
      end
    end

    # Explicit escape hatch for trusted HTML strings.
    #
    # WARNING: never pass user-supplied input to safe() — it bypasses all XSS
    # protection. Only use for strings you have produced or sanitized yourself.
    def safe(html_string)
      Phlex::SGML::SafeValue.new(html_string.to_s)
    end

    # Override Phlex's render to always return nil.
    #
    # Phlex::SGML#render returns the component instance, which would cause
    # __rsx_expr_out to see a Phlex::SGML and call render() a second time
    # (double-render bug). Returning nil short-circuits that.
    def render(renderable = nil, &block)
      super
      nil
    end
  end
end
