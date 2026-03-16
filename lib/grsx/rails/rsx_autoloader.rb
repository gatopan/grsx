# frozen_string_literal: true

require "monitor"

module Grsx
  module Rails
    # Makes .rsx a first-class Ruby source extension.
    #
    # Single-file components — class definition + RSX template in one file:
    #
    #   # app/components/ui/status_card.rsx
    #   class UI::StatusCard < UI::Base
    #     props :title, :badge_text, :badge_color, description: nil
    #
    #     def view_template
    #       <Section title={@title}>
    #         div(class: "text-center p-3") do
    #           <Badge text={@badge_text} color={@badge_color} />
    #         end
    #       </Section>
    #     end
    #   end
    #
    # ## How it works
    #
    # 1. At boot, scans autoload paths for .rsx files without .rb counterparts.
    # 2. Registers a const_missing hook on parent modules (e.g. UI, Customer).
    # 3. When a missing constant is accessed, the hook checks our registry,
    #    preprocesses the .rsx file, and evals the Ruby result.
    # 4. In dev mode, code reload clears the registry for fresh lookup.
    #
    module RsxAutoloader
      @loaded   = {}
      @mtimes   = {}  # { path => Time } — tracks file modification times
      @registry = {} # { [Module, :ConstName] => "/abs/path/to/file.rsx" }
      @hooked   = {} # modules that already have const_missing
      @monitor  = Monitor.new

      class << self
        attr_reader :registry

        # Load a .rsx file: Prism-based compilation.
        #
        # Uses ExtendedParser (Strategy B): Prism's AST locates method
        # bodies, compiles only those containing RSX tags.
        #
        # In dev mode, checks file mtime and re-loads if changed.
        def load_rsx(path)
          path = path.to_s
          @monitor.synchronize do
            current_mtime = File.mtime(path)
            if @loaded[path]
              # Already loaded — skip unless the file has been modified
              return false if @mtimes[path] == current_mtime
              # File changed on disk — force re-load
              @loaded.delete(path)
            end
            @mtimes[path] = current_mtime
          end

          source = File.read(path)
          processed = Grsx::ExtendedParser.new(source).compile
          eval(processed, TOPLEVEL_BINDING, path, 1) # rubocop:disable Security/Eval
          @monitor.synchronize { @loaded[path] = true }
          true
        end

        # Forget a path (dev-mode reload).
        def unload(path)
          @monitor.synchronize { @loaded.delete(path.to_s) }
        end

        # Clear everything (full code reload).
        def clear
          @monitor.synchronize do
            @loaded.clear
            @mtimes.clear
            @registry.clear
            @hooked.clear
          end
        end

        # Clear only the loaded-files cache so .rsx files are re-evaluated
        # on next const_missing, but preserve the registry and hooks.
        # Use this for dev-mode reloads where the file paths haven't changed.
        def soft_clear
          @monitor.synchronize { @loaded.clear }
        end

        # Re-check all loaded single-file .rsx files for mtime changes.
        # Called by PhlexReloader middleware on each dev request.
        def reload_changed
          paths_to_reload = @monitor.synchronize do
            @loaded.keys.select do |path|
              File.exist?(path) && File.mtime(path) != @mtimes[path]
            end
          end

          paths_to_reload.each do |path|
            load_rsx(path)
          rescue => e
            warn "[GRSX] Failed to reload #{path}: #{e.message}"
          end
        end

        # Scan autoload paths and register .rsx-only files.
        def register_autoloads(app)
          app.config.after_initialize do
            paths = app.config.autoload_paths.map(&:to_s)

            paths.each do |root|
              next unless File.directory?(root)
              scan_directory(root, root)
            end
          end
        end

        # Called from const_missing hooks to check if we have an .rsx
        # file for the missing constant.
        def resolve(mod, const_name)
          key  = [mod, const_name.to_sym]
          path = @registry[key]
          return nil unless path

          load_rsx(path)

          # The eval should have defined the constant.
          if mod.const_defined?(const_name, false)
            mod.const_get(const_name, false)
          else
            nil
          end
        end

        private

        def scan_directory(dir, root)
          Dir.children(dir).sort.each do |entry|
            full_path = File.join(dir, entry)

            if File.directory?(full_path)
              scan_directory(full_path, root)
            elsif entry.end_with?(".rsx")
              rb_counterpart = full_path.sub(/\.rsx\z/, ".rb")
              next if File.exist?(rb_counterpart) # .rb takes precedence

              register_constant(full_path, root)
            end
          end
        end

        def register_constant(path, root)
          relative = path.delete_prefix(root).delete_prefix("/").delete_suffix(".rsx")
          parts = relative.split("/")
          const_name = parts.pop.camelize.to_sym

          # Navigate to parent module, triggering Zeitwerk if needed
          parent = parts.inject(Object) do |mod, segment|
            mod_name = segment.camelize.to_sym
            if mod.const_defined?(mod_name, false)
              mod.const_get(mod_name, false)
            elsif mod.autoload?(mod_name)
              mod.const_get(mod_name) # trigger Zeitwerk
            else
              mod.const_set(mod_name, Module.new)
            end
          end

          # Don't register if already defined (loaded by Zeitwerk)
          return if parent.const_defined?(const_name, false)

          # Register in our lookup table
          @registry[[parent, const_name]] = path

          # Install const_missing hook on the parent module (once)
          install_const_missing(parent)
        rescue => e
          warn "[GRSX] Failed to register #{path}: #{e.message}"
        end

        # Install a const_missing hook on a module so that accessing
        # an undefined constant triggers .rsx loading from our registry.
        def install_const_missing(mod)
          return if @hooked[mod]
          @hooked[mod] = true

          mod.singleton_class.prepend(Module.new do
            define_method(:const_missing) do |name|
              result = Grsx::Rails::RsxAutoloader.resolve(self, name)
              return result if result

              super(name)
            end
          end)
        end
      end
    end
  end
end
