# frozen_string_literal: true

require "phlex"
require "phlex-rails"

module Grsx
  # Shared DSL methods included by both PhlexComponent and PhlexRuntime.
  #
  # Bridges the gap between compiled RSX code and Phlex's rendering API:
  #
  #   • __rsx_expr_out    → expression output (XSS-safe)
  #   • render(String)    → delegates to view_context.render (partials)
  #   • render(Phlex)     → delegates to Phlex's render (components)
  #   • __resolve_rsx_const → runtime component class resolution
  #   • method_missing    → view_context delegation (helpers)
  #   • safe()            → trusted HTML bypass
  #
  module RsxDSL
    def self.included(base)
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

    # ── Expression output ────────────────────────────────────────

    def __rsx_expr_out(value)
      case value
      when nil, false, ""
        nil
      when Array, Enumerable
        value.each { |v| __rsx_expr_out(v) }
      when Phlex::SGML
        render(value)
      when Phlex::SGML::SafeObject
        raw(value)
      else
        plain(value.to_s)
      end
    end

    # ── Transparent render ───────────────────────────────────────

    def render(renderable = nil, *args, **kwargs, &block)
      case renderable
      when String
        if rendering? && (vc = view_context)
          raw vc.render(renderable, *args, **kwargs, &block)
        end
        nil
      when nil
        if !block && kwargs.any? && rendering? && (vc = view_context)
          raw vc.render(**kwargs, &block)
          nil
        else
          super()
          nil
        end
      else
        super(renderable, &block)
        nil
      end
    end

    # ── Component resolution ─────────────────────────────────────
    #
    # Runtime component class resolver — called by compiled RSX code.
    #
    # Searches for the component class using multiple strategies:
    #   1. TagNameComponent (Rails convention)
    #   2. Bare TagName
    #   3. NS::TagNameComponent for each configured namespace
    #   4. NS::TagName for each configured namespace
    #
    # Dots in tag names map to Ruby namespaces: <UI.Badge /> → UI::Badge

    def __resolve_rsx_const(name)
      # 1. Try with Component suffix (top-level)
      klass = "#{name}Component".safe_constantize
      return klass if klass

      # 2. Try bare name (top-level)
      klass = name.safe_constantize
      return klass if klass

      # 3. Search configured component namespaces
      namespaces = Grsx.resolver.component_namespaces.values.flatten.uniq
      namespaces.each do |ns|
        klass = "#{ns}::#{name}Component".safe_constantize
        return klass if klass

        klass = "#{ns}::#{name}".safe_constantize
        return klass if klass
      end

      # 4. Fallback: consult the RsxAutoloader registry.
      if defined?(Grsx::Rails::RsxAutoloader)
        klass = __rsx_autoload_try(name)
        return klass if klass

        namespaces.each do |ns|
          klass = __rsx_autoload_try("#{name}Component", ns)
          return klass if klass

          klass = __rsx_autoload_try(name, ns)
          return klass if klass
        end
      end

      raise NameError, "GRSX: cannot resolve component <#{name.gsub('::', '.')} />. " \
        "Searched: #{name}Component, #{name}" \
        "#{namespaces.map { |ns| ", #{ns}::#{name}Component, #{ns}::#{name}" }.join}"
    end

    # Search the RsxAutoloader registry by module name (string comparison).
    def __rsx_autoload_try(const_name, parent_name = nil)
      target_sym = const_name.to_sym
      Grsx::Rails::RsxAutoloader.registry.each do |(mod, sym), path|
        next unless sym == target_sym
        next if parent_name && mod.name != parent_name

        Grsx::Rails::RsxAutoloader.load_rsx(path)

        full_name = mod.name ? "#{mod.name}::#{const_name}" : const_name.to_s
        klass = full_name.safe_constantize
        return klass if klass
      end
      nil
    end

    # ── View-context helper fallback ─────────────────────────────

    def method_missing(name, ...)
      if rendering? && (vc = view_context) && vc.respond_to?(name)
        vc.send(name, ...)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      (rendering? && (vc = view_context) && vc.respond_to?(name, include_private)) || super
    end

    # ── Trusted HTML bypass ──────────────────────────────────────

    def safe(html_string)
      Phlex::SGML::SafeValue.new(html_string.to_s)
    end
  end
end
