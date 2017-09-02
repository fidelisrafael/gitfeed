# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/LineLength

module GitFeed
  module CLI
    # This module contains helpers related to output in console, this includes
    # formatted and colorized feedback(success/error) messages
    module OutputHelpers
      module_function

      def format_username(username)
        username.bold.underline.colorize(:blue)
      end

      def print_counter(current, total, color = :light_blue)
        return nil unless verbose?

        print "\r[COUNTER] #{current}/#{total}".bold.colorize(color)
      end

      def line_marker(character = '-', width = 100)
        character.to_s * width
      end

      def section(section_name, message_color = :green, synchronize = false, &block)
        return _section(section_name, message_color, &block) unless synchronize

        MUTEX.synchronize { _section(section_name, message_color, &block) }
      end

      def _section(section_name, message_color = :green, &block)
        puts if verbose? # new line
        puts line_marker.colorize(message_color).bold if verbose?

        info "[START] #{section_name}".colorize(message_color).bold

        exec_time = with_execution_time(&block)

        info "[END] Executed #{section_name} in #{exec_time.round(2)} ms".colorize(message_color).bold
        puts line_marker.colorize(message_color).bold if verbose?
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

      def error(message, force = false)
        return nil if !log_errors? && !force

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
end
