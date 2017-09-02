# frozen_string_literal: true

require 'timeout'
require_relative 'base_application'

require_relative '../cli'

module GitFeed
  module WebServer
    # Simple `Rack` HTTP application
    class Application < BaseApplication
      MAX_TIMEOUT = 180 # 3 minutes

      post '/api/v1/users/:username/generate' do
        username = params[:username]
        force_refresh = params[:_force] == 'true'
        verbose = params[:_vvv] == 'true'

        if username.nil? || username.empty?
          # Bad Request
          return json({ error: true, reason: 'empty username' }, 400)
        end

        Timeout.timeout(MAX_TIMEOUT) do
          # TODO: Don't allow to set `verbose` in production
          # (must always be false)
          CLI.run!(username, verbose, force_refresh)
        end

        json(ok: true)
      end
    end
  end
end
