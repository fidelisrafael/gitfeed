# frozen_string_literal: true

# rubocop:disable Metrics/LineLength

require 'open-uri'
require 'net/http'
require 'openssl'
require 'timeout'

module GitFeed
  # This module contains all helpers methods to deal with HTTP requests and
  # data handling(such saving, reading from cache, etc) and formatting output
  module Utils
    # Maximum timeout for HTTP requests
    HTTP_REQUES_TIMEOUT = 15 # 15 seconds
    # The main root folder of application
    ROOT_DIR = File.expand_path('../..', File.dirname(__FILE__))
    # The directory where ALL data is saved
    DATA_DIRECTORY = File.join(ROOT_DIR, 'data')

    # :nodoc:
    MUTEX = Mutex.new

    def with_execution_time(&block)
      start_time = Time.now

      yield block if block_given?

      (Time.now - start_time)
    end

    def get(url, headers = {}, timeout = HTTP_REQUES_TIMEOUT)
      ::Timeout.timeout(timeout) do
        get_request(url, headers)
      end
    end

    def create_http_client(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      http
    end

    def send_get_request(uri, headers = {})
      http = create_http_client(uri)
      request = Net::HTTP::Get.new(uri.request_uri, headers)

      http.request(request)
    end

    def get_request(url, headers)
      uri = URI(normalize_uri(url))
      response = send_get_request(uri, headers)

      if response['Location']
        new_url = URI(response['Location'])
        # Handle the case when server replies with "Location" header as relative path, eg:
        # Location: /blog
        if new_url.host.nil?
          new_url = "#{new_url.scheme || uri.scheme}://#{uri.host}/#{new_url}"
        end

        return get_request(new_url.to_s, headers)
      end

      response
    end

    def github_http_headers(auth_token)
      auth_token.nil? ? {} : { 'Authorization' => "bearer #{auth_token}" }
    end

    def current_api_key_token_for_github
      file = File.join(ROOT_DIR, '.github-api-key')

      File.exist?(file) ? File.read(file).chop : ''
    end

    def get_github_data(url, auth_token = nil)
      response = get(url, github_http_headers(auth_token)).body

      JSON.parse(response)
    end

    def file_exists?(filename)
      File.exist?(File.join(DATA_DIRECTORY, filename))
    end

    def data_in_cache?(filename, min_bytes_size = 1000)
      return false if ENV['FORCE_REFRESH'] == 'true'

      file_exists?(filename) && File.size(File.join(DATA_DIRECTORY, filename)) > min_bytes_size
    end

    def get_file_data(filename)
      return nil unless file_exists?(filename)

      File.read(File.join(DATA_DIRECTORY, filename))
    end

    def get_json_file_data(filename)
      return nil unless file_exists?(filename)

      JSON.parse(get_file_data(filename))
    end

    def parse_json_directory(glob_pattern)
      files = Dir.glob(glob_pattern).sort

      files.flat_map do |file|
        JSON.parse(File.read(file))
      end
    end

    def save_file(filename, data, json = true, open_mode = 'wb')
      full_filename = File.join(DATA_DIRECTORY, filename)

      FileUtils.mkdir_p(File.dirname(full_filename))

      File.open(full_filename, open_mode) do |file|
        file.write(json ? JSON.pretty_generate(data) : data)
      end
    end

    def normalize_uri(uri)
      uri =~ /^(https?|ftp|file):/ ? uri : "http://#{uri}"
    end

    # Removes any non-word character
    def normalize_filename(filename)
      filename.to_s.gsub(/\W+/, '-').downcase
    end
  end
end
