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
      threads_number: 10
    }

    # Same constants that may be modified
    DEFAULT_GITHUB_TOKEN = 'ec445fd93d4aaab608ce34d14230f187ef0691dd'

    def run!(username, options = {})
      options = DEFAULT_OPTIONS.merge(options)

      username || raise('You must supply the username as second parameter. Eg: `ruby github.rb fidelisrafael`')
      formatted_username = username.bold.underline.colorize(:green)

      following_basic_filename = "#{username}_following_basic.json"
      following_details_filename = "#{username}_following_users.json"
      blogs_list_filename = "#{username}_following_users_blogs.json"

      info "Ok, lets start grabing the data for user #{formatted_username}\n\n"

      users = nil

      # No need to hit Github API
      if has_cached_data?(following_details_filename)
        users = get_json_file_data(following_details_filename)

        command = "FORCE_REFRESH=true ruby #{$0} #{ARGV.join(' ')}".colorize(:yellow)
        info "Looks like you've runned the script in past, so we will use cached information"
        info "If you want to recreate the data, run the script as: `#{command}`\n\n"

        info "All users followed by #{formatted_username} cached. Total of #{users.size.to_s.underline} users"
      else
        info "Downloading the list of users which #{formatted_username} follows"
        # Only hit Github API in first attempt
        following_users = get_json_file_data(following_basic_filename) || fetch_all_following_users(username, 100, DEFAULT_GITHUB_TOKEN)

        puts

        info "[OK] downloaded.\n\n"

        # Update current file with data
        save_file(following_basic_filename, following_users)

        info "All users followed by #{formatted_username} downloaded. Total of #{following_users.size.to_s.underline} users"
        info "Now, we will get the site url of each followed user..."
        info "We will scrap with the total number of #{options[:threads_number].to_s.underline.bold.colorize(:yellow)} threads.\n\n"

        users_data = API.fetch_each_following_user(following_users, DEFAULT_GITHUB_TOKEN)

        puts "\n"

        info "[OK] downloaded.\n"

        save_file(following_details_filename, users_data)
      end

      info "Generating the file with all links....\n"

      users = get_json_file_data(following_details_filename)

      blogs_urls = users.map {|d| d['blog'] }.reject(&:empty?)

      info "There a total of #{blogs_urls.size.to_s.underline.bold} blogs in users followed by user #{formatted_username}"

      save_file(blogs_list_filename, blogs_urls)
      info "[OK] File generated. See #{blogs_list_filename}\n\n"

      info "Starting RSS Feed URL search for each url..."

      API.fetch_each_blog_page(blogs_urls, options[:threads_number] * 2)

      all_blogs_page = Dir.glob(File.join(API::BLOG_PAGES_DEST_DIRNAME, '*'))
      blogs_feeds = {}
      user_blogs_pages = blogs_urls.map(&method(:normalize_url_for_filename))

      all_blogs_page.each do |page|
        normalized_page = normalize_url_for_filename(File.basename(page).sub(File.extname(page), ''))

        next unless user_blogs_pages.member?(normalized_page)

        begin
          page_content = File.read(page)

          next if page_content.nil? || page_content.empty?

          blogs_feeds[page] = TruffleHog.parse_feed_urls(page_content)
        rescue => e
          if log_errors?
            puts

            error "Something went wrong while reading the page \"#{page}\". Skipping..."
            error "Message: #{e.message}"
          end

          next
        end
      end

      save_file("#{username}_rss_feeds.json", blogs_feeds)

      total_scanned = user_blogs_pages.size
      total_found = blogs_feeds.values.flatten.size
      percent_success = ((total_found * 100)/total_scanned).round(2) rescue 0

      puts

      info "[OK] Saved. Extracted a total of #{total_found.to_s.underline.colorize(:yellow)} RSS feed links from #{total_scanned.to_s.underline.colorize(:pink)} pages"
      info "This mean that the percentage of success was: #{"#{percent_success}%".to_s.underline.bold.colorize(:green)}"
    end
  end
end