# Core dependencie
require_relative 'utils'

# Standard lib dependencies
require 'json'
require 'fileutils'
require 'timeout'

# External dependencies
require 'pry'
require 'thread/pool'

# Support Dependencies
require_relative 'support/string'
require_relative 'support/truffle_hog'

Thread.abort_on_exception = true

module GitFeed
  module API
    # Add as class methods
    extend GitFeed::Utils

    # Configuration constants
    THREADS_NUMBER = 20
    GITHUB_FOLLOWING_USERS_ENDPOINT = 'https://api.github.com/users/%{username}/following?page=%{page}&per_page=%{per_page}'.freeze
    BLOG_PAGES_DEST_DIRNAME = 'blog-pages'.freeze

    module_function

    def fetch_following_users(username, page, per_page, auth_token = nil)
      endpoint = GITHUB_FOLLOWING_USERS_ENDPOINT % { username: username, page: page, per_page: per_page }

      get(endpoint, github_http_headers(auth_token))
    end

    def get_following_user_data(username, page, per_page, auth_token = nil)
      filename = File.join(username, 'following_pages', "page_#{"%02d" % page}_per_page_#{per_page}.json")

      return get_json_file_data(filename) if has_cached_data?(filename)

      response = fetch_following_users(username, page, per_page, auth_token)
      body = JSON.parse(response.body)

      save_file(filename, body)

      return body
    end

    def fetch_all_following_users_pages(username, per_page, auth_token = nil)
      first_page_response = fetch_following_users(username, 1, per_page, auth_token)

      link_header = first_page_response['Link']
      links = link_header.split(', ')
      last_page = ((links.last || '').match(/\bpage=(\d+)\b/)[1] || 1).to_i

      pool = thread_pool(THREADS_NUMBER)

      1.upto(last_page).each_with_index do |page, index|
        pool.process do
          print_counter index.next, last_page

          get_following_user_data(username, page, per_page, auth_token)
        end
      end

      pool.shutdown

      return true
    end

    def fetch_user(endpoint, auth_token = nil)
      get(endpoint, github_http_headers(auth_token))
    end

    def get_user_data(username, endpoint, auth_token = nil)
      filename = File.join('github_users', "#{username}.json")

      return get_json_file_data(filename) if has_cached_data?(filename)

      response = fetch_user(endpoint, auth_token)
      body = JSON.parse(response.body)

      save_file(filename, body)

      return body
    end

    def extract_rss_from_blog_page(page)
      page_content = File.read(page)

      return [] if page_content.nil? || page_content.empty?

      TruffleHog.parse_feed_urls(page_content).flatten
    end

    def extract_rss_from_blog_pages(blogs_urls)
      blogs_urls.flat_map.each_with_index do |page, index|
        begin
          print_counter index.next, blogs_urls.size

          extract_rss_from_blog_page(page)
        rescue => e
          puts if log_errors? # new line

          error "Something went wrong while reading the file \"#{page}\". Skipping..."
          error "Message: #{e.message}"
        end
      end.compact
    end

    def fetch_each_following_user(following_list, auth_token = nil, num_threads = THREADS_NUMBER)
      pool = thread_pool(num_threads)

      following_list.each_with_index do |user, index|
        pool.process do
          print_counter index.next, following_list.size

          get_user_data(user['login'], user['url'], auth_token)

          begin
          rescue Exception => e
            puts if log_errors? # new line

            error "Error downloading \"#{user}\" data on Github API"
            error e.message
          end
       end
      end

      pool.shutdown

      return true
    end

    def fetch_each_blog_page(blogs_list, num_threads = THREADS_NUMBER, dest_dir = BLOG_PAGES_DEST_DIRNAME, retries = 3)
      pool = thread_pool(num_threads)

      blogs_list.each_with_index do |url, index|
        pool.process do
          print_counter index.next, blogs_list.size

          fetch_blog_page(url, dest_dir)
        end
      end

      pool.shutdown

      return true
    end

    def fetch_blog_page(url, dest_dir = BLOG_PAGES_DEST_DIRNAME, retries = 1)
      filename = File.join(dest_dir, "#{normalize_filename(url)}.html")

      return nil if file_exists?(filename)

      begin
        page_url = normalize_uri(url)

        page_html = get(page_url).body
        save_file(filename, page_html, false)

      rescue Exception => e
        puts if log_errors?

        error "[Retry: {#{retries}}] Error in #{url} | #{e.message}"

        # Save the file with no content to avoid hiting this same URL if
        # the error persisted between all retries attemps
        # save_file(filename, e.message, false) if retries.zero?

        # Try again
        fetch_blog_page(url, dest_dir, retries - 1) if retries > 0
      end
    end
  end
end
