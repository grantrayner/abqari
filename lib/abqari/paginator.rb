# frozen_string_literal: true

module Abqari
  class Paginator
    attr_reader :posts, :page, :total_pages, :base_url

    def initialize(posts:, page:, total_pages:, base_url:)
      @posts = posts
      @page = page
      @total_pages = total_pages
      @base_url = base_url.sub(%r{/?\z}, '/')
    end

    def first?
      page == 1
    end

    def last?
      page == total_pages
    end

    def prev_url
      return nil if first?
      return base_url if page == 2

      "#{base_url}page/#{page - 1}/"
    end

    def next_url
      return nil if last?

      "#{base_url}page/#{page + 1}/"
    end
  end
end
