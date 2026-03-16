# frozen_string_literal: true

require "phlex"
require "phlex-rails"

module Grsx
  # Shared DSL methods included by both PhlexComponent and PhlexRuntime.
  #
  # These methods form the bridge between Grsx's compiled .rsx output and
  # Phlex's rendering API: expression output, HTML safety, transparent
  # partial rendering, and automatic Rails helper inclusion.
  #
  # ── Design rationale ──────────────────────────────────────────────
  #
  # ERB, Slim, and Haml run compiled code directly on the ActionView
  # context, so `render`, `yield`, and helpers "just work".  GRSX
  # compiles into a Phlex boundary, where `render` is Phlex's render
  # and `self` is the component — not the view context.
  #
  # This module bridges the gap:
  #   • render(String) → delegates to view_context.render (like ERB)
  #   • render(Phlex)  → delegates to Phlex's render (components)
  #   • method_missing → view_context delegation (helpers)
  #   • safe()         → trusted HTML bypass
  #
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

    # ── Expression output ───────────────────────────────────────────
    #
    # Handles all { ruby_expr } in compiled templates:
    #
    #   render(<Comp />)      already wrote to buffer → returns nil → no-op
    #   Array/Enumerable      → each element rendered recursively
    #   Phlex::SafeObject     → raw()  (trusted HTML, no escaping)
    #   nil / false / ""      → silent no-op (safe for && and || patterns)
    #   anything else         → plain(value.to_s)  (CGI auto-escaped, XSS-safe)
    #
    def __rsx_expr_out(value)
      case value
      when nil, false, ""
        nil  # {condition && <Foo />}: falsy short-circuit
      when Array, Enumerable
        # {@items.map { |i| <Item /> }}: map returns [nil,...] after render→nil
        value.each { |v| __rsx_expr_out(v) }
      when Phlex::SGML
        # Safety net: component passed directly (e.g. {MyComp.new})
        render(value)
      when Phlex::SGML::SafeObject
        raw(value)
      else
        plain(value.to_s)
      end
    end

    # ── Transparent render ──────────────────────────────────────────
    #
    # Lesson from ERB/Slim/Haml: render('shared/flash') should render
    # a Rails partial, not output the string literal "shared/flash".
    #
    # Phlex's native render treats Strings as plain text.  We intercept
    # String arguments and delegate through Phlex::Rails::Partial, which
    # calls view_context.render under the hood.  This makes RSX behave
    # like ERB for partial rendering:
    #
    #   {render 'shared/flash'}                   ← just works
    #   {render 'shared/card', title: 'Hello'}    ← with locals
    #   {render partial: 'shared/card'}           ← keyword form
    #   {render MyComponent.new}                  ← Phlex components still work
    #
    def render(renderable = nil, *args, **kwargs, &block)
      case renderable
      when String
        # Partial path — delegate to Rails view context, just like ERB.
        # Uses raw() because Rails' render already handles escaping.
        if rendering? && (vc = view_context)
          raw vc.render(renderable, *args, **kwargs, &block)
        end
        nil
      when nil
        # nil renderable with keyword args → Rails render(partial: ...) form
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

    # ── Component resolution ────────────────────────────────────────
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
    #
    #   __resolve_rsx_const("Section")   → UI::SectionComponent or UI::Section
    #   __resolve_rsx_const("UI::Badge") → UI::BadgeComponent or UI::Badge
    #
    def __resolve_rsx_const(name)
      # 1. Try with Component suffix (top-level)
      klass = "#{name}Component".safe_constantize
      return klass if klass

      # 2. Try bare name (top-level)
      klass = name.safe_constantize
      return klass if klass

      # 3. Search configured component namespaces
      namespaces = Grsx.configuration.element_resolver.component_namespaces.values.flatten.uniq
      namespaces.each do |ns|
        klass = "#{ns}::#{name}Component".safe_constantize
        return klass if klass

        klass = "#{ns}::#{name}".safe_constantize
        return klass if klass
      end

      # 4. Fallback: directly consult the RsxAutoloader registry.
      #    safe_constantize doesn't trigger the autoloader's const_missing
      #    hooks, and after dev-mode code reloads the module objects in the
      #    registry become stale (Zeitwerk recreates modules). We match by
      #    module NAME to survive reloads.
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

    # Search the RsxAutoloader registry by module name (string comparison)
    # rather than module identity. After loading the .rsx file, resolve by
    # full name string (safe_constantize) — NOT through the stale registry
    # module, which Zeitwerk may have recycled during a code reload.
    def __rsx_autoload_try(const_name, parent_name = nil)
      target_sym = const_name.to_sym
      Grsx::Rails::RsxAutoloader.registry.each do |(mod, sym), path|
        next unless sym == target_sym
        next if parent_name && mod.name != parent_name

        # Load the .rsx file (compiles + evals at TOPLEVEL_BINDING)
        Grsx::Rails::RsxAutoloader.load_rsx(path)

        # Resolve by fully-qualified name string against the CURRENT
        # module hierarchy, not the stale registry module object.
        full_name = mod.name ? "#{mod.name}::#{const_name}" : const_name.to_s
        klass = full_name.safe_constantize
        return klass if klass
      end
      nil
    end

    # ── View-context helper fallback ──────────────────────────────────
    #
    # ERB, Slim, and Haml run on the ActionView context, so every helper
    # (Devise's devise_mapping, Turbo's turbo_frame_tag, etc.) is available
    # without opt-in.  Phlex intentionally omits this for purity.
    #
    # GRSX restores ERB-like ergonomics: when a method isn't found on the
    # component, we delegate to the view context (helpers).  This makes
    # gem-injected helpers (Devise, Turbo, Avo, Flipper, etc.) transparent.
    #
    # Only activates during rendering — outside a request, raises normally.
    #
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

    # ── Trusted HTML bypass ─────────────────────────────────────────
    #
    # Explicit escape hatch for trusted HTML strings.
    #
    # WARNING: never pass user-supplied input to safe() — it bypasses all
    # XSS protection.  Only use for strings you have produced or sanitized
    # yourself (e.g. helper output, pre-built JSON, etc.).
    def safe(html_string)
      Phlex::SGML::SafeValue.new(html_string.to_s)
    end
  end
end
