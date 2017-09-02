# frozen_string_literal: true

# rubocop:disable Metrics/LineLength

# Standard lib dependencies
require 'base64'
require 'fileutils'
require 'json'
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

    def github_http_headers(auth_user = nil, auth_token = nil)
      return {} if auth_token.nil? || auth_token.empty?

      { 'Authorization' => "Basic #{Base64.strict_encode64("#{auth_user}:#{auth_token}")}" }
    end

    def github_config
      file = File.join(ROOT_DIR, '.github-config')

      File.exist?(file) ? JSON.parse(File.read(file)) : {}
    end

    def current_api_key_token_for_github
      github_config['token']
    end

    def current_api_key_username_for_github
      github_config['username']
    end

    def get_github_data(url, auth_user = nil, auth_token = nil)
      response = get(url, github_http_headers(auth_user, auth_token)).body

      JSON.parse(response)
    end

    def file_exists?(filename)
      File.exist?(File.join(DATA_DIRECTORY, filename))
    end

    def data_in_cache?(filename, force_refresh = false, min_bytes_size = 1000)
      return false if force_refresh

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

    # Parse 'Link:' header from Github response and obtain the last page
    # to iterate and download each one from the first to last page
    def last_page_from_link_header(link_response)
      return 0 if link_response.nil? || link_response.empty?

      links = link_response.split(', ')

      ((links.last || '').match(/\bpage=(\d+)\b/)[1] || 1).to_i
    end
  end
end
