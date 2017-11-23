# frozen_string_literal: true

# Core dependencies
require_relative 'api'
require_relative 'utils'
require_relative 'cli/output_helpers'
require_relative 'cli/commands'

# Support Dependencies
require_relative 'support/string'
require_relative 'support/truffle_hog'

# rubocop:disable Metrics/LineLength
# rubocop:disable Metrics/AbcSize

module GitFeed
  # Main module to serve as entry point for users. This module is build on
  # top of `GitFeed::API` and lives to be more informative as possible for users
  # through log messages and outputs in each step of processing.
  module CLI
    # Add as class methods
    extend GitFeed::Utils
    extend GitFeed::CLI::OutputHelpers
    extend GitFeed::CLI::Commands

    module_function

    def run!(username, verbose = true, force_refresh = false, per_page = 100)
      unless username
        error "You must supply the username as second parameter. Eg: `#{$PROGRAM_NAME} fidelisrafael`", true
        return
      end

      @verbose = verbose
      options = prepare_options(username, force_refresh)

      section 'GitFeed' do
        start!(username, per_page, github_config_api_user, github_config_api_token, options)
      end
    end

    def start!(username, per_page, auth_user, auth_token, options)
      # Real stuff happening
      # Frist step: Download all following pages of given username
      following_users = fetch_each_following_users_pages(username, per_page, auth_user, auth_token, options)
      # After download all users of each page download above
      users = fetch_each_user_data(following_users, auth_user, auth_token, options)

      # With all users followed by `username` downloaded we can obtain their blog url
      blogs_urls = users.map { |user| user['blog'] }.compact.reject(&:empty?).uniq
      save_file(options[:blogs_list_filename], blogs_urls)

      # Now, we concurrently download each given URL in `blogs_urls` array
      fetch_each_blog_page(blogs_urls)

      # Obtain all pages already downloaded in file system for urls
      blogs_pages = blogs_urls.map do |url|
        filename = File.join(options[:blogs_page_dir], "#{normalize_filename(url)}.html")

        File.exist?(filename) ? filename : nil
      end.compact.uniq

      # And finally: Generates a JSON file with all found RSS and Atom feeds in
      # all urls found in users that `username` follows in Github.
      generate_rss_feed_json(blogs_pages, options[:blogs_rss_feeds_filename])
    end

    def prepare_options(username, force_refresh)
      options = { force_refresh: force_refresh }

      options[:blogs_list_filename] = File.join(username, 'following_users_blogs.json')
      options[:blogs_rss_feeds_filename] = File.join(username, 'rss_feeds.json')
      options[:blogs_page_dir] = File.join(Utils::DATA_DIRECTORY, API::BLOG_PAGES_DEST_DIRNAME)

      options
    end
  end
end
