# frozen_string_literal: true

require_relative 'base_application'

require_relative '../cli'

module GitFeed
  module WebServer
    # Simple `Rack` HTTP application
    class Application < BaseApplication
      post '/api/v1/users/:username/generate' do
        username = params[:username]
        force_refresh = params[:_force] == 'true'

        CLI.run!(username, false, force_refresh)

        json(ok: true)
      end
    end
  end
end
