module Rbexy
  module Rails
    # Rack middleware that hot-reloads .rbx templates for all known
    # PhlexComponent subclasses on every request in development.
    #
    # Installed automatically by the Rbexy Rails engine when
    # config.cache_classes / config.enable_reloading indicates dev mode.
    #
    # You can also install it manually:
    #
    #   # config/application.rb
    #   config.middleware.use Rbexy::Rails::PhlexReloader
    #
    class PhlexReloader
      def initialize(app)
        @app = app
      end

      def call(env)
        Rbexy::PhlexComponent.all_descendants.each(&:reload_rbx_template_if_changed)
        @app.call(env)
      end
    end
  end
end
