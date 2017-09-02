# frozen_string_literal: true

# rubocop:disable Metrics/LineLength
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength

require_relative 'router'
require_relative 'web_action'

# source: https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/web/application.rb
module GitFeed
  module WebServer
    # Simple `Rack` HTTP application
    class BaseApplication
      extend WebRouter

      def call(env)
        action = self.class.match(env)

        return [404, { Rack::CONTENT_LENGTH => '0' }, []] unless action

        resp = catch(:halt) do
          app = self
          self.class.run_befores(app, action)
          begin
            resp = action.instance_exec env, &action.block
          ensure
            self.class.run_afters(app, action)
          end

          resp
        end

        resp =  case resp
                when Array
                  resp
                else
                  headers = {
                    'Content-Type' => 'text/html',
                    'Cache-Control' => 'no-cache',
                    'Content-Language' => action.locale
                  }

                  [200, headers, [resp]]
                end

        resp[1] = resp[1].dup

        resp[1][Rack::CONTENT_LENGTH] = resp[2].inject(0) { |l, p| l + p.bytesize }.to_s

        resp[2] = [] if %w[HEAD OPTIONS].member?(env[Rack::REQUEST_METHOD])

        resp
      end

      def self.helpers(mod = nil, &block)
        if block_given?
          WebAction.class_eval(&block)
        else
          WebAction.send(:include, mod)
        end
      end

      def self.before(path = nil, &block)
        befores << [path && Regexp.new("\\A#{path.gsub('*', '.*')}\\z"), block]
      end

      def self.after(path = nil, &block)
        afters << [path && Regexp.new("\\A#{path.gsub('*', '.*')}\\z"), block]
      end

      def self.run_befores(app, action)
        run_hooks(befores, app, action)
      end

      def self.run_afters(app, action)
        run_hooks(afters, app, action)
      end

      def self.run_hooks(hooks, app, action)
        hooks.select { |p, _| !p || p =~ action.env[WebRouter::PATH_INFO] }
             .each { |_, b| action.instance_exec(action.env, app, &b) }
      end

      def self.befores
        @befores ||= []
      end

      def self.afters
        @afters ||= []
      end
    end
  end
end
