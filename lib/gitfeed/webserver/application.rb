# frozen_string_literal: true

require 'timeout'
require_relative 'base_application'

require_relative '../cli'

module GitFeed
  module WebServer
    # Simple `Rack` HTTP application
    class Application < BaseApplication
      MAX_TIMEOUT = 60 # 60 seconds

      post '/api/v1/users/:username/generate' do
        username = params[:username]
        force_refresh = params[:_force] == 'true'

        if username.nil? || username.empty?
          return json({ error: true, reason: 'empty username' }, 400)
        end

        Timeout.timeout(MAX_TIMEOUT) do
          CLI.run!(username, false, force_refresh)
        end

        json(ok: true)
      end
    end
  end
end
