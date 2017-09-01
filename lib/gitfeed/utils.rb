# encoding: UTF-8

# rubocop:disable Metrics/LineLength
# rubocop:disable Layout/SpaceInsideBlockBraces

require 'open-uri'
require 'timeout'

module GitFeed
  # Module with helpers methods to download all lyrics
  module Utils
    HTTP_REQUES_TIMEOUT = 15 # 15 seconds

    ROOT_DIR = File.expand_path('../..', File.dirname(__FILE__))
    DATA_DIRECTORY = File.join(ROOT_DIR, 'data')

    MUTEX = Mutex.new

    def get(url, headers = {}, timeout = HTTP_REQUES_TIMEOUT)
      ::Timeout::timeout(timeout) do
        open(url, headers).read
      end
    end

    def get_github_data(url, auth_token = nil)
      JSON.parse(get(url, github_http_headers(auth_token)))
    end

    def github_http_headers(auth_token)
      auth_token.nil? ? {} : { "Authorization" => "bearer #{auth_token}" }
    end

    def has_cached_data?(filename, min_bytes_size = 1000)
      return false if ENV['FORCE_REFRESH'] == 'true'

      file_exists?(filename) && File.size(File.join(DATA_DIRECTORY, filename)) > min_bytes_size
    end

    def save_file(filename, data, json = true, open_mode = 'wb')
      full_filename = File.join(DATA_DIRECTORY, filename)

      FileUtils.mkdir_p(File.dirname(full_filename))

      File.open(full_filename, open_mode) do |file|
        file.write(json ? JSON.pretty_generate(data) : data)
      end
    end

    def file_exists?(filename)
      File.exist?(File.join(DATA_DIRECTORY, filename))
    end

    def get_json_file_data(filename)
      return nil unless file_exists?(filename)

      JSON.parse(File.read(File.join(DATA_DIRECTORY, filename)))
    end

    def thread_pool(num_threads)
      Thread.pool(num_threads)
    end

    def normalize_uri(uri)
      (uri =~ /^(https?|ftp|file):/) ? uri : "http://#{uri}"
    end

    def normalize_url_for_filename(url)
      url.gsub(/(\/|\.|:)/, '-').downcase
    end

    def print_counter(current, total)
      return nil unless verbose?

      print "\r[COUNTER] #{current}/#{total}".colorize(:yellow)
    end

    def with_execution_time(&block)
      start_time = Time.now
      yield block if block_given?

      (Time.now - start_time)
    end

    def line_marker(character = '-', width = 100)
      character.to_s * width
    end

    def section(section_name, synchronize = false, message_color = :blue, &block)
      return _section(section_name, message_color, &block) unless synchronize

      MUTEX.synchronize { _section(section_name, message_color, &block) }
    end

    def _section(section_name, message_color = :blue, &block)
      puts # new line
      puts line_marker.colorize(message_color).bold
      info "[START] #{section_name}".colorize(message_color).bold

      exec_time = with_execution_time(&block)

      puts # new line

      info "[END] Executed #{section_name} in #{exec_time.round(2)} ms".colorize(message_color).bold
      puts line_marker.colorize(message_color).bold
      puts # new line
    end

    private :_section

    def info(message)
      return nil unless verbose?

      puts "[INFO] #{message}"
    end

    def log_errors?
      return false unless verbose?

      ENV['LOG_ERRORS'].nil? || ENV['LOG_ERRORS'] == 'true'
    end

    def error(message)
      return nil unless log_errors?

      puts "[ERROR] #{message}".bold.colorize(:red)
    end

    def verbose?
      true # just to allow configuration for now
    end

    def silent?
      !verbose?
    end
  end
end
