# frozen_string_literal: true

# rubocop:disable Metrics/MethodLength
# rubocop:disable Style/RegexpLiteral

require 'nokogiri'

# source: https://github.com/pauldix/truffle-hog/blob/master/lib/truffle-hog.rb
module TruffleHog
  VERSION = '0.0.3'.freeze

  RSS_TYPES = [
    'application/rss+xml',
    'application/atom+xml',
    'application/rdf+xml',
    'application/rss',
    'application/atom',
    'application/rdf',
    'text/rss+xml',
    'text/atom+xml',
    'text/rdf+xml',
    'text/rss',
    'text/atom',
    'text/rdf'
  ].freeze

  RSS_TAGS = %w(a link).freeze

  def self.parse_feed_urls(html)
    RSS_TYPES.map do |rss_type|
      scan_for_tag_with_regexp(html, rss_type)
      # TODO: Consider
      # Nokogiri is very slow comparated with naive approach of Regexp
      # scan_for_tag_with_nokogiri(html, rss_type)
    end.flatten
  end

  def self.scan_for_tag_with_nokogiri(html, type)
    nokogiri_html = Nokogiri::HTML(html)

    RSS_TAGS.map {|tag| scan_with_nogokiri(nokogiri_html, tag, type) }.reduce(:+)
  end

  def self.scan_for_tag_with_regexp(html, type)
    RSS_TAGS.map {|tag| scan_with_regexp(html, tag, type) }.reduce(:+)
  end

  def self.scan_with_nogokiri(html, tag, type)
    parsed_html = html.is_a?(Nokogiri::HTML::Document) ? html : Nokogiri::HTML(html)

    parsed_html.css("#{tag}[type='#{type}']").map do |tag|
      tag[:href]
    end
  end

  def self.scan_with_regexp(html, tag, type)
    tags = html.scan(/(<#{tag}.*?>)/).flatten
    feed_tags = collect(tags, type)

    feed_tags.map do |inner_tag|
      matches = inner_tag.match(/.*href=['"](.*?)['"].*/)

      matches.nil? ? nil : matches[1]
    end.compact
  end

  def self.collect(tags, type)
    tags.collect { |t| t if feed?(t, type) }.compact
  end

  def self.feed?(html, type)
    html.match?(/.*type=['"]#{Regexp.escape(type)}['"].*/)
  end
end
