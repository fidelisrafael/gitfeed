require_relative 'api'
require_relative 'utils'

# Support Dependencies
require_relative 'support/string'
require_relative 'support/truffle_hog'

module GitFeed
  module CLI
    # Add as class methods
    extend GitFeed::Utils

    module_function

    DEFAULT_OPTIONS = {
      verbose: true,
      log_errors: true,
      threads_number: 10,
      sites_threads_number: 20,
      per_page: 100
    }

    def run!(username, options = {})
      section 'GitFeed' do
        _run!(username, options)
      end
    end

    def format_username(username)
      username.bold.underline.colorize(:green)
    end

    def fetch_all_following_users_pages(username, auth_token, options = {})
      following_users = []

      section 'Download following users pages' do
        info "Ok, lets start grabbing all pages of following users for #{format_username(username)}\n\n"

        # Download all following users pages to be iterate in next step
        # (or just skip if is already in file system)
        API.fetch_all_following_users_pages(username, options[:per_page], auth_token)

        following_pages = File.join(Utils::DATA_DIRECTORY, username, 'following_pages', '*')
        following_users = parse_json_directory(following_pages)

        info "[OK] downloaded"
        info "Total of #{following_users.size.to_s.underline} users followed by #{format_username(username)}"
      end

      return following_users
    end

    def fetch_each_following_user(username, following_users_pages, auth_token, options = {})
      users = []

      section 'Download users pages' do
        info "Downloading the list of users which #{format_username(username)} follows. This can take a while..."

        API.fetch_each_following_user(following_users_pages, auth_token)

        users = following_users_pages.flat_map do |user|
          get_json_file_data(File.join('github_users', "#{user['login']}.json"))
        end.compact

        info "[OK] All users followed by #{format_username(username)} downloaded. Total of #{users.size.to_s.underline} users\n\n"
      end

      return users
    end

    def fetch_each_blog_page(username, filename, users, options = {})
      section 'Blogs links' do
        info "Generating the file with all links....\n"

        blogs_urls = users.map {|d| d['blog'] }.reject(&:empty?)

        save_file(filename, blogs_urls)

        info "[OK] There a total of #{blogs_urls.size.to_s.underline.bold} blogs in users followed by user #{format_username(username)}"
        info "[OK] File generated. See #{filename.underline}\n\n"

        info "Now, we will download the main page of each blog url found in #{format_username(username)} following users"
        info "This can take a few minutes..."

        API.fetch_each_blog_page(blogs_urls, options[:sites_threads_number])
      end
    end

    def generate_filtered_rss_blogs(username, filename, options = {})
      section 'RSS File Generation' do
        info "Starting RSS Feed URL search for each url..."

        all_blogs_page = Dir.glob(File.join(Utils::DATA_DIRECTORY, API::BLOG_PAGES_DEST_DIRNAME, '*'))
        blogs_feeds = API.extract_rss_from_blog_pages(all_blogs_page)

        save_file(filename, blogs_feeds.flatten)

        total_scanned = all_blogs_page.size
        total_found = blogs_feeds.flatten.size
        percent_success = ((total_found * 100)/total_scanned).round(2) rescue 0

        info "[OK] Saved. Extracted a total of #{total_found.to_s.underline.colorize(:yellow)} RSS feed links from #{total_scanned.to_s.underline.colorize(:pink)} pages"
        info "This mean that the percentage of success was: #{"#{percent_success}%".to_s.underline.bold.colorize(:green)}"
      end
    end

    def _run!(username, options)
      username || raise("You must supply the username as second parameter. Eg: `#{$0} fidelisrafael`")

      options = DEFAULT_OPTIONS.merge(options)
      blogs_list_filename = File.join(username, 'following_users_blogs.json')
      blogs_rss_feeds_filename = File.join(username, 'rss_feeds.json')

      following_users = fetch_all_following_users_pages(username, current_api_key_token_for_github, options)
      users = fetch_each_following_user(username, following_users, current_api_key_token_for_github, options)

      fetch_each_blog_page(username, blogs_list_filename, users, options)
      generate_filtered_rss_blogs(username, blogs_rss_feeds_filename, options)
    end
  end
end