# frozen_string_literal: true

# rubocop:disable Metrics/LineLength
# rubocop:disable Metrics/MethodLength
# rubocop:disable Style/CaseEquality
# rubocop:disable Style/Documentation
# rubocop:disable Style/ClassCheck
# rubocop:disable Style/ClassVars

# source: https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/web/action.rb
module GitFeed
  module WebServer
    class WebAction
      RACK_SESSION = 'rack.session'.freeze
      VIEWS_FOLDER = 'views'.freeze

      attr_accessor :env, :block, :type

      def request
        @request ||= ::Rack::Request.new(env)
      end

      def halt(res)
        throw :halt, res
      end

      def redirect(location)
        throw :halt, [302, { 'Location' => "#{request.base_url}#{location}" }, []]
      end

      def params
        indifferent_hash = Hash.new { |hash, key| hash[key.to_s] if Symbol === key }

        indifferent_hash.merge! request.params
        route_params.each { |k, v| indifferent_hash[k.to_s] = v }

        indifferent_hash
      end

      def route_params
        env[WebRouter::ROUTE_PARAMS]
      end

      def session
        env[RACK_SESSION]
      end

      def erb(content, options = {})
        if content.kind_of? Symbol
          unless respond_to?(:"_erb_#{content}")
            src = ERB.new(File.read("#{VIEWS_FOLDER}/#{content}.erb")).src
            WebAction.class_eval("def _erb_#{content}\n#{src}\n end")
          end
        end

        if @_erb
          _erb(content, options[:locals])
        else
          @_erb = true
          content = _erb(content, options[:locals])

          _render { content }
        end
      end

      def render(engine, content, options = {})
        raise 'Only erb templates are supported' if engine != :erb

        erb(content, options)
      end

      def json(payload, status = 200)
        [
          status,
          {
            'Content-Type' => 'application/json',
            'Cache-Control' => 'no-cache'
          },
          [JSON.generate(payload)]
        ]
      end

      def initialize(env, block)
        @_erb = false
        @env = env
        @block = block
        @@files ||= {}
      end

      private

      def _erb(file, locals)
        locals.each { |k, v| define_singleton_method(k) { v } } if locals

        if file.kind_of?(String)
          ERB.new(file).result(binding)
        else
          send(:"_erb_#{file}")
        end
      end
    end
  end
end
