# frozen_string_literal: true

require "phlex"
require "phlex-rails"
require "digest"
require "monitor"
require "set"

module Grsx
  # Base class for RSX-powered Phlex components.
  #
  # Declare props with the `props` macro, write your template in a
  # co-located .rsx file. GRSX compiles the .rsx into a real
  # view_template method — no eval at render time.
  #
  # ## Basic usage
  #
  #   # app/components/card_component.rb
  #   class CardComponent < Grsx::PhlexComponent
  #     props :title
  #   end
  #
  #   # app/components/card_component.rsx
  #   <article class="card">
  #     <h2>{@title}</h2>
  #     {content}
  #   </article>
  #
  # ## Named slots
  #
  #   class CardComponent < Grsx::PhlexComponent
  #     slots :header, :footer
  #   end
  #
  #   # card_component.rsx
  #   <article>
  #     <header>{slot(:header)}</header>
  #     <main>{content}</main>
  #     <footer>{slot(:footer)}</footer>
  #   </article>
  #
  class PhlexComponent < Phlex::HTML
    include RsxDSL

    # --- Named slots ---

    class << self
      # Declare named content slots on the component.
      #
      #   class CardComponent < Grsx::PhlexComponent
      #     slots :header, :footer
      #   end
      def slots(*names)
        names.each do |name|
          # Define a setter: component.with_header { ... }
          define_method(:"with_#{name}") do |&block|
            @_slots ||= {}
            @_slots[name] = block
            self
          end

          # Define a predicate: has_header?
          define_method(:"has_#{name}?") do
            (@_slots ||= {}).key?(name)
          end
        end
      end

      # Declare typed props with optional defaults — auto-generates initialize.
      #
      #   class CardComponent < Grsx::PhlexComponent
      #     props :title, :body, size: :md, disabled: false
      #   end
      #
      # This is exactly equivalent to:
      #
      #   def initialize(title:, body:, size: :md, disabled: false)
      #     @title    = title
      #     @body     = body
      #     @size     = size
      #     @disabled = disabled
      #   end
      #
      # You can still override initialize manually when you need logic
      # beyond simple ivar assignment.
      def props(*required_names, **defaults)
        # Guard against mutable default values ([], {}) — they would be
        # shared across every instance of the component, causing subtle
        # cross-request state contamination. Fail loudly at class-definition
        # time with guidance on the idiomatic fix.
        #
        # Frozen defaults ([].freeze, {}.freeze) are safe — they raise on
        # mutation, so sharing across instances cannot cause contamination.
        defaults.each do |key, val|
          if (val.is_a?(Array) || val.is_a?(Hash)) && !val.frozen?
            raise ArgumentError,
              "#{name}.props :#{key} has a mutable default (#{val.inspect}). " \
              "Use a frozen default or nil:\n" \
              "  props #{key}: [].freeze          # frozen, safe to share\n" \
              "  # or\n" \
              "  props :#{key}                    # required, caller provides\n" \
              "  # or manual initialize:\n" \
              "  def initialize(#{key}: nil)\n" \
              "    @#{key} = #{key} || #{val.inspect}\n" \
              "  end"
          end
        end

        @_declared_props = { required: required_names.map(&:to_sym), defaults: defaults }

        all_names = required_names.map(&:to_sym) + defaults.keys.map(&:to_sym)

        # Generate attr_readers so callers can inspect prop values after render.
        # Templates use @ivar directly; attr_reader makes the same data available
        # to parent components or test code.
        attr_reader(*all_names)

        # Build initialize parameter list
        params = required_names.map { |n| "#{n}:" }
        defaults.each { |k, v| params << "#{k}: #{v.inspect}" }

        # Build ivar assignment lines
        assignments = all_names.map { |n| "  @#{n} = #{n}" }

        class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          def initialize(#{params.join(", ")})
          #{assignments.join("\n")}
          end
        RUBY
      end

      # Returns the declared props, or nil if none were declared.
      attr_reader :_declared_props

      # Compile an inline template string at class-definition time.
      # Eliminates the need for a separate .rsx file for simple components.
      #
      #   class BadgeComponent < Grsx::PhlexComponent
      #     props :label, color: :blue
      #
      #     template <<~RSX
      #       <span class={@color}>{@label}</span>
      #     RSX
      #   end
      #
      def template(source)
        compiled = Grsx.compile(source)
        @_compiled_template_code = compiled
        define_view_template(compiled)
      end

      # Define an inline sub-component with props and an RSX template.
      # Returns a PhlexComponent subclass — assign it to a constant for
      # tag resolution:
      #
      #   class CardComponent < Grsx::PhlexComponent
      #     Badge = component(:label, color: :blue) do
      #       <<~RSX
      #         <span class={@color}>{@label}</span>
      #       RSX
      #     end
      #   end
      #
      # The block must return an RSX source string. Props use the same
      # signature as the `props` macro (required symbols + keyword defaults).
      def component(*required_names, **defaults, &block)
        rsx_source = block.call

        klass = Class.new(Grsx::PhlexComponent)
        # Prevent the inherited hook from looking for a co-located .rsx file
        klass.instance_variable_set(:@_rsx_template_path, nil)

        klass.props(*required_names, **defaults) if required_names.any? || defaults.any?
        klass.template(rsx_source)
        klass
      end
    end

    # Render a named slot. Falls back silently if no slot content was provided.
    # Used in .rsx templates as {slot(:header)}.
    def slot(name)
      block = (@_slots ||= {})[name]
      instance_exec(&block) if block
      nil
    end

    # --- Expression output, safe(), render override ---
    # See RsxDSL module for __rsx_expr_out, safe, and render nil-return.

    # --- Template loading ---

    class << self
      # Template cache: { "path:content_hash" => compiled_code_string }
      TEMPLATE_CACHE = {}
      # Mtime cache: { path => Time } — tracks file modification times for
      # the dev-mode reloader without conflicting with the content-hash cache.
      MTIME_CACHE = {}
      # Monitor for thread-safe cache access (Puma runs multiple threads).
      CACHE_MONITOR = Monitor.new
      # Explicit descendant tracking — avoids ObjectSpace.each_object heap
      # scan on every dev request. Populated by the inherited hook below.
      DESCENDANTS = Set.new
      private_constant :TEMPLATE_CACHE, :MTIME_CACHE, :CACHE_MONITOR, :DESCENDANTS

      def inherited(subclass)
        # Capture the caller's file path BEFORE calling super so the stack
        # frame is still fresh. This is more reliable than source_location
        # because it works even when the subclass has no custom initialize.
        defining_file = caller_locations(1, 10)
          .find { |loc| loc.path != __FILE__ && !loc.path.end_with?("phlex_component.rb") }
          &.path
        subclass.instance_variable_set(:@_rsx_source_rb, defining_file)

        super
        DESCENDANTS << subclass
        subclass.defer_rsx_template
      end

      # Mark this class as having a co-located .rsx template, but defer
      # compilation until first render. This ensures that Grsx.configuration
      # (set by Rails initializers) is fully available at compile time.
      #
      # A stub view_template is defined that compiles and redefines itself
      # on first invocation — zero overhead after first render.
      #
      # In single-file mode (source IS .rsx), view_template was already
      # compiled by the preprocessor during require — nothing to defer.
      def defer_rsx_template
        # Single-file .rsx: the preprocessor already compiled <Tag> syntax
        # into the view_template method body when the file was loaded.
        # No sidecar to find, no deferred compilation needed.
        source = @_rsx_source_rb
        return if source&.end_with?(".rsx")

        path = rsx_template_path
        return unless path && File.exist?(path)

        @_rsx_template_path = path
        @_rsx_compiled = false

        # Define a stub that compiles on first call, then replaces itself.
        define_method(:view_template) do
          # Compile once, thread-safely, then redefine for all future calls.
          unless self.class.instance_variable_get(:@_rsx_compiled)
            self.class.send(:compile_and_install_template!, path)
          end
          # Re-dispatch to the now-compiled method.
          view_template
        end
      end

      # Eagerly compile the co-located .rsx template. Use this when you
      # know the resolver configuration is already available (e.g. in specs
      # or after Rails initialization).
      def load_rsx_template
        path = rsx_template_path
        return unless path && File.exist?(path)

        compile_and_install_template!(path)
        @_rsx_template_path = path
      end

      # Recompile and redefine view_template if the .rsx file has changed.
      # Called by Grsx::Rails::PhlexReloader on each dev request.
      def reload_rsx_template_if_changed
        path = @_rsx_template_path
        return unless path

        mtime = File.mtime(path)
        CACHE_MONITOR.synchronize do
          return if MTIME_CACHE[path] == mtime
          MTIME_CACHE[path] = mtime
        end

        compiled = compile_template(path)
        define_view_template(compiled)
      end

      # Return the path to the co-located .rsx template file (nil if not found).
      #
      # In single-file mode (source IS .rsx), returns nil — the template
      # is already compiled into the class, no sidecar to load.
      def rsx_template_path
        return @_rsx_template_path if defined?(@_rsx_template_path)

        source = @_rsx_source_rb
        return nil unless source

        # Single-file .rsx: no sidecar needed
        return nil if source.end_with?(".rsx")

        base = File.basename(source, ".rb")
        dir  = File.dirname(source)
        candidate = File.join(dir, "#{base}.rsx")
        candidate if File.exist?(candidate)
      end

      # All known PhlexComponent subclasses, for the dev-mode reloader.
      # Uses explicit tracking via inherited hook instead of ObjectSpace scan.
      def all_descendants
        DESCENDANTS.to_a
      end

      # Returns the Phlex DSL Ruby code that was compiled from the .rsx template.
      # Useful for debugging, introspection, and writing specs that verify
      # what the compiler generates:
      #
      #   puts MyCard.compiled_template_code
      #   # ⇒ div(class: "card") do
      #   #      plain(@title)
      #   #    end
      def compiled_template_code
        # For inline templates (defined via `template <<~RSX`), return
        # the stored compiled code directly.
        return @_compiled_template_code if @_compiled_template_code

        # For file-based templates, compile from the .rsx file.
        path = @_rsx_template_path || rsx_template_path
        return nil unless path
        compile_template(path)
      end

      private

      # Thread-safe compile-and-install. Compiles the .rsx template and
      # redefines view_template with the compiled code. Idempotent —
      # concurrent threads will wait on the monitor rather than double-compile.
      def compile_and_install_template!(path)
        CACHE_MONITOR.synchronize do
          return if @_rsx_compiled

          compiled = compile_template(path)
          define_view_template(compiled)
          @_rsx_compiled = true
        end
      end

      def compile_template(path)
        content = File.read(path)

        hash = Digest::SHA256.hexdigest(content)[0, 16]
        cache_key = "#{path}:#{hash}"

        CACHE_MONITOR.synchronize do
          return TEMPLATE_CACHE[cache_key] if TEMPLATE_CACHE.key?(cache_key)
        end

        code = Grsx.compile(content, source_map: true)

        CACHE_MONITOR.synchronize do
          TEMPLATE_CACHE[cache_key] = code
        end
        code
      end

      def define_view_template(compiled_code)
        # Pass the .rsx file path and line 1 to class_eval so that Ruby's
        # backtraces point directly to the template file when errors occur.
        #
        # Before: view_template defined at phlex_component.rb:233 (useless)
        # After:  error at card_component.rsx:5:in 'view_template'
        #
        # @_rsx_template_path is set by load_rsx_template before we get here.
        source_file = @_rsx_template_path || __FILE__
        class_eval(<<~RUBY, source_file, 1)
          def view_template
            #{compiled_code}
          end
        RUBY
      end
    end
  end
end
