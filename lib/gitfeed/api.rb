require_relative 'utils'

# Core dependencies
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
    THREADS_NUMBER = 10
    GITHUB_FOLLOWING_USERS_ENDPOINT = "https://api.github.com/users/%{username}/following?page=%{page}&per_page=%{per_page}"
    BLOG_PAGES_DEST_DIRNAME = File.join(Utils::DATA_DIRECTORY, 'blog-pages')
    INVALID_URL_PAGE_CONTENT = '[GIT_FEED_INVALID_PAGE_CONTENT]'

    module_function

    def fetch_following_user(username, page, per_page, auth_token = nil)
      endpoint = GITHUB_FOLLOWING_USERS_ENDPOINT % { username: username, page: page, per_page: per_page }

      get_github_data(endpoint, auth_token)
    end

    def fetch_all_following_users(username, per_page, auth_token = nil)
      page = 1
      data = [fetch_following_user(username, page, per_page, auth_token)] # first page

      # if there's no data in first page, theres no more data to be scrapped
      return [] if data.empty?

      loop do
        print "\r#{page}"

        response = fetch_following_user(username, page = page + 1, per_page, auth_token)

        break if response.nil? || response.empty?

        data << response
      end

      data.flatten
    end

    def fetch_each_following_user(following_list, auth_token = nil, num_threads = THREADS_NUMBER)
      pool = thread_pool(num_threads)
      users_data = []

      following_list.each_with_index do |user, index|
        pool.process do
          print_counter index.next, following_list.size

          begin
            users_data << get_github_data(user['url'], auth_token)
          rescue Exception => e
            puts
            error "Error download #{user} data on Github"
            error e.message
          end

        end
      end

      pool.shutdown

      return users_data
    end

    def fetch_each_blog_page(blogs_list, num_threads = THREADS_NUMBER, dest_dir = BLOG_PAGES_DEST_DIRNAME, retries = 3)
      pool = thread_pool(num_threads)

      FileUtils.mkdir_p(dest_dir)

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
      filename = File.expand_path(File.join(dest_dir, "#{normalize_url(url)}.html"), ROOT_DIR)

      return nil if file_exists?(filename)

      begin
        page_url = normalize_uri(url)

        page_html = get(page_url)
        save_file(filename, page_html, false)

      rescue Exception => e
        puts

        error "[Retry: {#{retries}} Error in #{url} | #{e.message}"

        # Save the file with no content to avoid hiting this same URL if
        # the error persisted between all retries attemps
        save_file(filename, INVALID_URL_PAGE_CONTENT, false) if retries.zero?

        # Try again
        fetch_blog_page(url, dest_dir, retries - 1) if retries > 0
      end
    end
  end
end