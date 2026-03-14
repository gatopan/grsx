require "phlex"
require "phlex-rails"
require "digest"

module Rbexy
  # Base class for JSX-backed Phlex components.
  #
  # Define your props in initialize, write your template in a co-located .rbx
  # file. Rbexy compiles the .rbx into a real view_template method — no eval
  # at render time.
  #
  # ## Basic usage
  #
  #   # app/components/card_component.rb
  #   class CardComponent < Rbexy::PhlexComponent
  #     def initialize(title:)
  #       @title = title
  #     end
  #   end
  #
  #   # app/components/card_component.rbx
  #   <article class="card">
  #     <h2>{@title}</h2>
  #     {content}
  #   </article>
  #
  # ## Named slots
  #
  #   class CardComponent < Rbexy::PhlexComponent
  #     slots :header, :footer
  #   end
  #
  #   # card_component.rbx
  #   <article>
  #     <header>{slot(:header)}</header>
  #     <main>{content}</main>
  #     <footer>{slot(:footer)}</footer>
  #   </article>
  #
  #   # Usage
  #   card = CardComponent.new
  #   card.with_slot(:header) { render LogoComponent.new }
  #   render card
  #
  class PhlexComponent < Phlex::HTML
    include Phlex::Rails::Helpers

    # --- Named slots ---

    class << self
      # Declare named content slots on the component.
      #
      #   class CardComponent < Rbexy::PhlexComponent
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
      #   class CardComponent < Rbexy::PhlexComponent
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
        defaults.each do |key, val|
          if val.is_a?(Array) || val.is_a?(Hash)
            raise ArgumentError,
              "#{name}.props :#{key} has a mutable default (#{val.inspect}). " \
              "Use nil as the default and set the value in initialize instead:\n" \
              "  props :#{key}\n" \
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
    end

    # Render a named slot. Falls back silently if no slot content was provided.
    # Used in .rbx templates as {slot(:header)}.
    def slot(name)
      block = (@_slots ||= {})[name]
      instance_exec(&block) if block
      nil
    end

    # --- Default children slot ---

    # {content} in a .rbx template compiles to `yield` — Phlex 2.x style.
    # This method is a no-op; the compiler special-cases the `content` identifier.
    # Kept for documentation and as a fallback.
    def content
      yield
    end

    # --- Expression output ---

    # Handles all { ruby_expr } in compiled templates:
    #
    #   render(<Comp />) already wrote to buffer → returns nil → no-op here
    #   Array/Enumerable    → each element rendered recursively
    #   Phlex::SafeObject   → raw()  (trusted HTML, no escaping)
    #   nil / false / ""   → silent no-op (safe for && and || patterns)
    #   anything else       → plain(value.to_s)  (CGI auto-escaped, XSS-safe)
    def __rbx_expr_out(value)
      case value
      when nil, false, ""
        nil  # {condition && <Foo />}: falsy short-circuit
      when Array, Enumerable
        # {@items.map { |i| <Item /> }}: map returns [nil,nil,...] after render→nil
        value.each { |v| __rbx_expr_out(v) }
      when Phlex::SGML
        # Safety net: if a user passes a component directly (e.g. {MyComp.new})
        # render it normally. Our render override returns nil so this branch is
        # only hit in direct-instance-passing scenarios, not {cond && <Comp />}.
        render(value)
      when Phlex::SGML::SafeObject
        raw(value)
      else
        plain(value.to_s)
      end
    end

    # Explicit escape hatch for trusted HTML strings.
    #
    # By default, every { expression } is CGI-escaped via plain(). Use safe()
    # when you have a string that is already HTML and must not be escaped:
    #
    #   {safe(@html_body)}            # raw inject
    #   {@items.map { safe(i.html) }} # safe inside map
    #
    # WARNING: never pass user-supplied input to safe() — it bypasses all XSS
    # protection. Only use for strings you have produced or sanitized yourself.
    def safe(html_string)
      Phlex::SGML::SafeValue.new(html_string.to_s)
    end

    # Override Phlex's render to always return nil.
    #
    # Phlex::SGML#render returns the component instance, which would cause
    # __rbx_expr_out to see a Phlex::SGML and call render() a second time
    # (double-render bug). Returning nil short-circuits that:
    #
    #   {true && <Button />}  → true && render(ButtonComponent.new)  → nil
    #                            __rbx_expr_out(nil) → no-op ✓
    #
    #   {@items.map { |i| <Item /> }} → map returns [nil, nil, nil]
    #                            __rbx_expr_out([nil, nil, nil]) → no-op ✓
    def render(renderable = nil, &block)
      super
      nil
    end

    # Raised when a .rbx template fails to compile (syntax or parse error).
    # Provides the source file path and the underlying error message so
    # developers see their .rbx line rather than a rbexy internal backtrace.
    class TemplateCompileError < StandardError
      attr_reader :template_path

      def initialize(message, template_path:)
        @template_path = template_path
        super(message)
      end
    end

    # --- Template loading ---

    class << self
      # Template cache: { path => { mtime: Time, code: String } }
      TEMPLATE_CACHE = {}
      private_constant :TEMPLATE_CACHE

      def inherited(subclass)
        # Capture the caller's file path BEFORE calling super so the stack
        # frame is still fresh. This is more reliable than source_location
        # because it works even when the subclass has no custom initialize.
        defining_file = caller_locations(1, 10)
          .find { |loc| loc.path != __FILE__ && !loc.path.end_with?("phlex_component.rb") }
          &.path
        subclass.instance_variable_set(:@_rbx_source_rb, defining_file)

        super
        subclass.load_rbx_template
      end

      # Locate, compile, and define view_template from the co-located .rbx file.
      # Called once when the subclass is first defined.
      def load_rbx_template
        path = rbx_template_path
        return unless path && File.exist?(path)

        compiled = compile_template(path)
        define_view_template(compiled)
        @_rbx_template_path = path
      end

      # Recompile and redefine view_template if the .rbx file has changed.
      # Called by Rbexy::Rails::PhlexReloader on each dev request.
      def reload_rbx_template_if_changed
        path = @_rbx_template_path
        return unless path

        mtime = File.mtime(path)
        cached = TEMPLATE_CACHE[path]
        return if cached && cached[:mtime] == mtime

        compiled = compile_template(path)
        define_view_template(compiled)
      end

      # Return the path to the .rbx file for this component (nil if not found).
      def rbx_template_path
        @_rbx_template_path if defined?(@_rbx_template_path)

        source = @_rbx_source_rb
        return nil unless source

        base = File.basename(source, ".rb")
        dir  = File.dirname(source)
        candidate = File.join(dir, "#{base}.rbx")
        candidate if File.exist?(candidate)
      end

      # All known PhlexComponent subclasses, for the dev-mode reloader.
      def all_descendants
        ObjectSpace.each_object(Class).select { |c| c < self }
      end

      # Returns the Phlex DSL Ruby code that was compiled from the .rbx template.
      # Useful for debugging, introspection, and writing specs that verify
      # what the compiler generates:
      #
      #   puts MyCard.compiled_template_code
      #   # ⇒ div(class: "card") do
      #   #      plain(@title)
      #   #    end
      def compiled_template_code
        path = @_rbx_template_path || rbx_template_path
        return nil unless path
        compile_template(path)
      end

      private

      def compile_template(path)
        content = File.read(path)

        # Cache by content hash, not mtime. mtime is fragile in Docker/rsync
        # deployments where COPY or rsync can reset timestamps to build time
        # without changing content — or vice versa, touch the file without
        # changing content, causing pointless recompilation.
        #
        # SHA256 is deterministic and correct. We truncate to 16 hex chars
        # (64 bits of collision resistance) which is more than sufficient for
        # a per-process in-memory cache keyed by full path.
        hash = Digest::SHA256.hexdigest(content)[0, 16]
        cache_key = "#{path}:#{hash}"

        return TEMPLATE_CACHE[cache_key] if TEMPLATE_CACHE.key?(cache_key)

        template = Rbexy::Template.new(content, path)

        begin
          code = Rbexy.phlex_compile(template)
        rescue Rbexy::Lexer::SyntaxError, Rbexy::Parser::ParseError => e
          raise TemplateCompileError.new(
            "#{File.basename(path)}: #{e.message}",
            template_path: path
          )
        end

        TEMPLATE_CACHE[cache_key] = code
        code
      end

      def define_view_template(compiled_code)
        # Pass the .rbx file path and line 1 to class_eval so that Ruby's
        # backtraces point directly to the template file when errors occur.
        #
        # Before: view_template defined at phlex_component.rb:233 (useless)
        # After:  error at card_component.rbx:5:in 'view_template'
        #
        # @_rbx_template_path is set by load_rbx_template before we get here.
        source_file = @_rbx_template_path || __FILE__
        class_eval(<<~RUBY, source_file, 1)
          def view_template
            #{compiled_code}
          end
        RUBY
      end
    end
  end
end
