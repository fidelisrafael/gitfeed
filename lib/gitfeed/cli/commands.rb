# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/LineLength
# rubocop:disable Metrics/MethodLength
# rubocop:disable Style/RescueModifier

module GitFeed
  module CLI
    # Base feedly collection name
    FEEDLY_COLLECTION_NAME = 'GitFeed.io'.freeze

    # This module basically contains all commands on top of `GitFeed::API` with error
    # handling and formatted output when the verbose mode is activated.
    module Commands
      def fetch_each_following_users_pages(username, per_page, auth_user = nil, auth_token = nil, options = {})
        following_users = []
        fusername = format_username(username)

        section 'Download following users pages' do
          info "Ok, lets start grabbing all pages of following users for #{fusername}\n"

          # Download all following users pages to be iterate in next step
          # (or just skip if is already in file system)
          API.fetch_each_following_users_pages(username, per_page, auth_user, auth_token, options) do |error, _result, current, total|
            print_counter current.next, total

            if error
              puts if log_errors?

              error "Error downloading page \"#{page}\""
              error "Message #{error.message}"
            end
          end

          puts if verbose?

          following_pages = File.join(Utils::DATA_DIRECTORY, username, 'following_pages', '*')
          following_users = parse_json_directory(following_pages)

          info '[OK] downloaded'
          info "Total of #{following_users.size.to_s.underline} users followed by #{fusername}"
        end

        following_users
      end

      def fetch_each_user_data(following_users, auth_user = nil, auth_token = nil, options = {})
        users = []

        section 'Download users pages' do
          info 'Downloading the list of users. This can take a while...'

          API.fetch_each_user_data(following_users, auth_user, auth_token, options) do |error, _result, current, total, user|
            print_counter current.next, total

            if error
              puts if log_errors? # new line

              error "Error downloading username \"#{user['login']}\" data on Github API"
              error "Message: #{error.message}"
            end
          end

          puts if verbose?

          users = following_users.flat_map do |user|
            get_json_file_data(File.join('github_users', "#{user['login']}.json"))
          end.compact

          info "[OK] All users downloaded. Total of #{users.size.to_s.underline} users\n"
        end

        users
      end

      def fetch_each_blog_page(blogs_urls)
        section 'Blogs links' do
          info 'Now, we will download the main page of each blog url found in following users'
          info 'This can take a few minutes...'

          API.fetch_each_blog_page(blogs_urls, API::BLOG_PAGES_DEST_DIRNAME) do |error, _result, currrent, total, blog_url|
            print_counter currrent.next, total

            if error
              puts if log_errors?

              error "Error fetching url \"#{blog_url}\" | #{error.message}"
            end
          end

          puts
          info "[OK] Blog pages downloaded. Total #{blogs_urls.size.to_s.underline.bold}"
        end
      end

      def extract_each_rss_from_blog_pages(blogs_pages)
        API.extract_each_rss_from_blog_pages(blogs_pages) do |error, results, current, total, page|
          print_counter current.next, total

          if error
            puts if log_errors? # new line

            error "Something went wrong while reading the file \"#{page}\""
            error "Message: #{error.message}"
          end

          results
        end
      end

      def generate_rss_feed_json(blogs_pages, dest_filename)
        section 'RSS File Generation' do
          info 'Searching RSS feed link in downloaded blogs pages'

          blogs_feeds = extract_each_rss_from_blog_pages(blogs_pages)
          save_file(dest_filename, blogs_feeds)

          total_scanned = blogs_pages.size
          total_found = blogs_feeds.size
          percent_success = (((total_found * 100) / total_scanned).round(2) rescue 0)

          puts if verbose?

          info "[OK] Saved. Extracted a total of #{total_found.to_s.underline.colorize(:yellow)} RSS feed links from #{total_scanned.to_s.underline.colorize(:pink)} pages"
          info "This mean that the percentage of success was: #{"#{percent_success}%".to_s.underline.bold.colorize(:green)}"
        end
      end

      def register_rss_in_feedly_api(feed_filename, auth_token)
        section 'Feedly Import' do
          pool = Thread.pool(5)
          username = File.dirname(feed_filename)
          client = Feedlr::Client.new(oauth_access_token: auth_token)
          feeds = get_json_file_data(feed_filename).map { |f| "feed/#{f}" }

          feeds.each_with_index do |feed, index|
            pool.process do
              print_counter index.next, feeds.size

              feed_data = {
                id: feed,
                categories: [
                  { label: "#{FEEDLY_COLLECTION_NAME}:#{username}" }
                ]
              }

              begin
                client.add_subscription(feed_data)
              rescue => e
                error e.message
              end
            end
          end

          puts

          pool.shutdown
        end
      end

      def verbose?
        @verbose == true
      end
    end
  end
end
