# frozen_string_literal: true

# rubocop:disable Metrics/LineLength
# rubocop:disable Style/FormatStringToken
# rubocop:disable Style/FormatString
# rubocop:disable Style/MethodLength

# Core dependencies
require_relative 'utils'

# Standard lib dependencies
require 'json'

# External dependencies
require 'pry'
require 'thread/pool'

# Support Dependencies
require_relative 'support/string'
require_relative 'support/truffle_hog'

Thread.abort_on_exception = true

module GitFeed
  # This module holds all needed methods to perform standartized and core actions in GitFeed, such
  # as downloading and saving data, dealing with cache and multi threading.
  module API
    # Add as class methods
    extend GitFeed::Utils

    # Configuration constants
    # Number of default threads when performing concurrently tasks
    THREADS_NUMBER = 10
    # Github base api URL(scheme + host)
    GITHUB_API_URL = 'https://api.github.com'.freeze
    # Endoint to obtain following users in Github
    GITHUB_FOLLOWING_USERS_ENDPOINT = "#{GITHUB_API_URL}/users/%{username}/following?page=%{page}&per_page=%{per_page}".freeze
    # Where to save the data downloaded as subdirectory in data/ root directory.
    BLOG_PAGES_DEST_DIRNAME = 'blog-pages'.freeze

    module_function

    # Github Following Pages stuff
    def get_following_page(username, page, per_page, auth_user = nil, auth_token = nil)
      endpoint = GITHUB_FOLLOWING_USERS_ENDPOINT % { username: username, page: page, per_page: per_page }

      get(endpoint, github_http_headers(auth_user, auth_token))
    end

    # rubocop:disable Metrics/ParameterLists
    def fetch_following_page(username, page, per_page, auth_user = nil, auth_token = nil, options = {})
      filename = File.join(username, 'following_pages', "page_#{'%02d' % page}_per_page_#{per_page}.json")

      return get_json_file_data(filename) if data_in_cache?(filename, options[:force_refresh])

      response = get_following_page(username, page, per_page, auth_user, auth_token)
      body = JSON.parse(response.body)

      save_file(filename, body)

      body
    end
    # rubocop:enable Metrics/ParameterLists

    def fetch_each_following_users_pages(username, per_page, auth_user = nil, auth_token = nil, options = {})
      pool = Thread.pool(options[:num_threads] || THREADS_NUMBER)
      first_page_response = get_following_page(username, 1, per_page, auth_user, auth_token)

      return nil if first_page_response.is_a?(Net::HTTPForbidden) # Rate Limit Error

      last_page = last_page_from_link_header(first_page_response['Link'])

      1.upto(last_page).each_with_index do |page, index|
        pool.process do
          begin
            result = fetch_following_page(username, page, per_page, auth_user, auth_token, options)

            yield [nil, result, index, last_page] if block_given?
          rescue => error
            yield [error, nil, index, last_page] if block_given?
          end
        end
      end

      pool.shutdown
    end

    # Gihutb User related

    def fetch_user_data(username, endpoint, auth_user = nil, auth_token = nil, options = {})
      filename = File.join('github_users', "#{username}.json")

      return get_json_file_data(filename) if data_in_cache?(filename, options[:force_refresh])

      body = get_github_data(endpoint, auth_user, auth_token)

      save_file(filename, body)

      body
    end

    def fetch_each_user_data(users_list, auth_user = nil, auth_token = nil, options = {})
      pool = Thread.pool(options[:num_threads] || THREADS_NUMBER)

      users_list.each_with_index do |user, index|
        pool.process do
          begin
            user_data = fetch_user_data(user['login'], user['url'], auth_user, auth_token, options)

            yield [nil, user_data, index, users_list.size, user] if block_given?
          rescue => error
            yield [error, nil, index, users_list.size, user] if block_given?
          end
        end
      end

      pool.shutdown
    end

    # Generic Blog Pages related stuff

    def fetch_blog_page(url, dest_dir = BLOG_PAGES_DEST_DIRNAME, retries = 1)
      filename = File.join(dest_dir, "#{normalize_filename(url)}.html")

      return get_file_data(filename) if file_exists?(filename)

      begin
        page_url = normalize_uri(url)
        response = get(page_url).body

        save_file(filename, response, false)

        response
      rescue => error
        # Try again
        return fetch_blog_page(url, dest_dir, retries - 1) if retries > 0

        raise error
      end
    end

    def fetch_each_blog_page(blogs_urls, dest_dir = BLOG_PAGES_DEST_DIRNAME, num_threads = THREADS_NUMBER, max_retries = 1)
      pool = Thread.pool(num_threads)
      total = blogs_urls.size

      blogs_urls.each_with_index do |url, index|
        pool.process do
          begin
            result = fetch_blog_page(url, dest_dir, max_retries)

            yield [nil, result, index, total, url] if block_given?
          rescue => error
            yield [error, nil, index, total, url] if block_given?
          end
        end
      end

      pool.shutdown
    end

    def extract_rss_from_blog_page(page)
      page_content = File.read(page)

      return [] if page_content.nil? || page_content.empty?

      TruffleHog.parse_feed_urls(page_content).flatten
    end

    def extract_each_rss_from_blog_pages(blogs_pages)
      blogs_pages.flat_map.each_with_index do |page, index|
        begin
          result = extract_rss_from_blog_page(page)

          yield [nil, result, index, blogs_pages.size, page] if block_given?
        rescue => error
          yield [error, nil, index, blogs_pages.size, page] if block_given?
        end
      end.compact
    end
  end
end
