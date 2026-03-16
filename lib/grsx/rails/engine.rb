# frozen_string_literal: true

module Grsx
  module Rails
    class Engine < ::Rails::Engine
      # ── 1. RSX single-file autoloader ─────────────────────────────
      # Scan autoload paths for .rsx files without .rb counterparts
      # and register const_missing hooks so constant lookup triggers
      # preprocessing + eval.
      initializer "grsx.rsx_autoloader", after: :setup_main_autoloader do |app|
        require "grsx/rails/rsx_autoloader"
        Grsx::Rails::RsxAutoloader.register_autoloads(app)
      end

      # ── 2. Dev-mode hot-reload ────────────────────────────────────
      # Hot-reload .rsx templates for PhlexComponent subclasses on
      # every request via a lightweight Rack middleware.
      initializer "grsx.phlex_reloader" do |app|
        dev_mode = if app.config.respond_to?(:enable_reloading)
          app.config.enable_reloading
        else
          !app.config.cache_classes
        end

        if dev_mode
          require "grsx/rails/phlex_reloader"
          app.middleware.use Grsx::Rails::PhlexReloader

          # Soft-clear the loaded-files cache on code reload so .rsx
          # files are re-evaluated from disk. Preserves the registry
          # and const_missing hooks — they don't hold class references.
          app.reloader.before_class_unload do
            require "grsx/rails/rsx_autoloader"
            Grsx::Rails::RsxAutoloader.soft_clear
          end
        end
      end

      # ── 3. ActionView template handler ────────────────────────────
      # Register .rsx as a view template type so Rails discovers
      # app/views/**/*.rsx files (like ERB, Haml, Slim).
      initializer "grsx.template_handler" do
        ActiveSupport.on_load(:action_view) do
          require "grsx/template_handler"
          ActionView::Template.register_template_handler(:rsx, Grsx::TemplateHandler.new)
        end
      end
    end
  end
end
