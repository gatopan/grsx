# frozen_string_literal: true

module Grsx
  module Rails
    # Rack middleware that hot-reloads .rsx templates for all known
    # PhlexComponent subclasses on every request in development.
    #
    # Installed automatically by the Grsx Rails engine when
    # config.cache_classes / config.enable_reloading indicates dev mode.
    #
    # You can also install it manually:
    #
    #   # config/application.rb
    #   config.middleware.use Grsx::Rails::PhlexReloader
    #
    class PhlexReloader
      def initialize(app)
        @app = app
      end

      def call(env)
        Grsx::PhlexComponent.all_descendants.each(&:reload_rsx_template_if_changed)
        @app.call(env)
      end
    end
  end
end
