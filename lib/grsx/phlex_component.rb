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
  # co-located .rsx file or inline via `template <<~RSX`. GRSX compiles
  # the RSX into a real view_template method — no eval at render time.
  #
  #   class CardComponent < Grsx::PhlexComponent
  #     props :title
  #     slots :header, :footer
  #   end
  #
  class PhlexComponent < Phlex::HTML
    include RsxDSL

    # ── Named slots ──────────────────────────────────────────────

    class << self
      # Declare named content slots.
      #
      #   slots :header, :footer
      #
      def slots(*names)
        names.each do |name|
          define_method(:"with_#{name}") do |&block|
            @_slots ||= {}
            @_slots[name] = block
            self
          end

          define_method(:"has_#{name}?") do
            (@_slots ||= {}).key?(name)
          end
        end
      end

      # ── Props macro ──────────────────────────────────────────────

      # Declare typed props with optional defaults — auto-generates initialize.
      #
      #   props :title, :body, size: :md, disabled: false
      #
      def props(*required_names, **defaults)
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

        attr_reader(*all_names)

        params = required_names.map { |n| "#{n}:" }
        defaults.each { |k, v| params << "#{k}: #{v.inspect}" }
        assignments = all_names.map { |n| "  @#{n} = #{n}" }

        class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          def initialize(#{params.join(", ")})
          #{assignments.join("\n")}
          end
        RUBY
      end

      attr_reader :_declared_props

      # ── Inline template macros ───────────────────────────────────

      # Compile an inline template string at class-definition time.
      #
      #   template <<~RSX
      #     <span class={@color}>{@label}</span>
      #   RSX
      #
      def template(source)
        compiled = Grsx.compile(source)
        @_compiled_template_code = compiled
        define_view_template(compiled)
      end

      # Define an inline sub-component with props and an RSX template.
      #
      #   Badge = component(:label, color: :blue) do
      #     <<~RSX
      #       <span class={@color}>{@label}</span>
      #     RSX
      #   end
      #
      def component(*required_names, **defaults, &block)
        rsx_source = block.call

        klass = Class.new(Grsx::PhlexComponent)
        klass.instance_variable_set(:@_rsx_template_path, nil)

        klass.props(*required_names, **defaults) if required_names.any? || defaults.any?
        klass.template(rsx_source)
        klass
      end
    end

    # Render a named slot. Falls back silently if no content was provided.
    def slot(name)
      block = (@_slots ||= {})[name]
      instance_exec(&block) if block
      nil
    end

    # ── Template loading ───────────────────────────────────────────

    class << self
      TEMPLATE_CACHE = {}
      MTIME_CACHE = {}
      CACHE_MONITOR = Monitor.new
      DESCENDANTS = Set.new
      private_constant :TEMPLATE_CACHE, :MTIME_CACHE, :CACHE_MONITOR, :DESCENDANTS

      def inherited(subclass)
        defining_file = caller_locations(1, 10)
          .find { |loc| loc.path != __FILE__ && !loc.path.end_with?("phlex_component.rb") }
          &.path
        subclass.instance_variable_set(:@_rsx_source_rb, defining_file)

        super
        DESCENDANTS << subclass
        subclass.defer_rsx_template
      end

      def defer_rsx_template
        source = @_rsx_source_rb
        return if source&.end_with?(".rsx")

        path = rsx_template_path
        return unless path && File.exist?(path)

        @_rsx_template_path = path
        @_rsx_compiled = false

        define_method(:view_template) do
          unless self.class.instance_variable_get(:@_rsx_compiled)
            self.class.send(:compile_and_install_template!, path)
          end
          view_template
        end
      end

      def load_rsx_template
        path = rsx_template_path
        return unless path && File.exist?(path)

        compile_and_install_template!(path)
        @_rsx_template_path = path
      end

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

      def rsx_template_path
        return @_rsx_template_path if defined?(@_rsx_template_path)

        source = @_rsx_source_rb
        return nil unless source
        return nil if source.end_with?(".rsx")

        base = File.basename(source, ".rb")
        dir  = File.dirname(source)
        candidate = File.join(dir, "#{base}.rsx")
        candidate if File.exist?(candidate)
      end

      def all_descendants
        DESCENDANTS.to_a
      end

      def compiled_template_code
        return @_compiled_template_code if @_compiled_template_code

        path = @_rsx_template_path || rsx_template_path
        return nil unless path
        compile_template(path)
      end

      private

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

        code = Grsx.compile(content)

        CACHE_MONITOR.synchronize do
          TEMPLATE_CACHE[cache_key] = code
        end
        code
      end

      def define_view_template(compiled_code)
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
