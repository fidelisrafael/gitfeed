# frozen_string_literal: true

require_relative 'api'
require_relative 'utils'
require_relative 'cli/output_helpers'
require_relative 'cli/commands'

# Support Dependencies
require_relative 'support/string'
require_relative 'support/truffle_hog'

# rubocop:disable Metrics/LineLength
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength

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

    def run!(username, verbose = true, per_page = 100)
      @verbose = verbose

      section 'GitFeed' do
        unless username
          error("You must supply the username as second parameter. Eg: `#{$PROGRAM_NAME} fidelisrafael`")
          exit
        end

        # Variables
        auth_token = current_api_key_token_for_github
        blogs_list_filename = File.join(username, 'following_users_blogs.json')
        blogs_rss_feeds_filename = File.join(username, 'rss_feeds.json')
        blogs_page_dir = File.join(Utils::DATA_DIRECTORY, API::BLOG_PAGES_DEST_DIRNAME)

        # Real stuff happening
        # Frist step: Download all following pages of given username
        following_users = fetch_each_following_users_pages(username, per_page, auth_token)
        # After download all users of each page download above
        users = fetch_each_user_data(following_users, auth_token)

        # With all users followed by `username` downloaded we can obtain their blog url
        blogs_urls = users.map { |user| user['blog'] }.reject(&:empty?)
        save_file(blogs_list_filename, blogs_urls)

        # Now, we concurrently download each given URL in `blogs_urls` array
        fetch_each_blog_page(blogs_urls)
        blogs_page = Dir.glob(File.join(blogs_page_dir, '*.html'))

        # And finally: Generates a JSON file with all found RSS and Atom feeds in
        # all urls found in users that `username` follows in Github.
        generate_rss_feed_json(blogs_page, blogs_rss_feeds_filename)
      end
    end
  end
end
