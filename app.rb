%w[ lib ].each do |path|
  $:.unshift path unless $:.include?(path)
end

require "sinatra"
require "multi_json"
require "json"
require "csv"
require "statsd"

require "document"
require "elasticsearch_wrapper"
require "null_backend"

require_relative "config"
require_relative "helpers"
require_relative "backends"

class Rummager < Sinatra::Application
  def self.statsd
    @@statsd ||= Statsd.new("localhost").tap do |c|
      c.namespace = ENV["GOVUK_STATSD_PREFIX"].to_s
    end
  end

  def available_backends
    @available_backends ||= Backends.new(settings, logger)
  end

  def backend
    name = params["backend"] || "primary"
    available_backends[name.to_sym] || halt(404)
  end

  def primary_search
    available_backends[:primary]
  end

  def secondary_search
    available_backends[:secondary]
  end

  def backends_for_sitemap
    [
      available_backends[:mainstream],
      available_backends[:detailed],
      available_backends[:government]
    ]
  end

  def text_error(content)
    halt 403, {"Content-Type" => "text/plain"}, content
  end

  helpers do
    include Helpers
  end

  before do
    content_type :json
  end

  get "/search.?:format?" do
    @query = params["q"].to_s.gsub(/[\u{0}-\u{1f}]/, "").strip

    if @query == ""
      expires 3600, :public
      halt 404
    end

    expires 3600, :public if @query.length < 20

    results = primary_search.search(@query, params["format_filter"])
    secondary_results = secondary_search.search(@query)

    logger.info "Found #{secondary_results.count} secondary results"

    @secondary_results = secondary_results.take(5)
    @more_secondary_results = secondary_results.length > 5
    @results = results.take(50 - @secondary_results.length)
    @total_results = @results.length + @secondary_results.length

    MultiJson.encode((@results + @secondary_results).map { |r| r.to_hash.merge(
      highlight: r.highlight,
      presentation_format: r.presentation_format,
      humanized_format: r.humanized_format
    ) })
  end

  get "/:backend/search.?:format?" do
    query = params["q"].to_s.gsub(/[\u{0}-\u{1f}]/, "").strip

    results = backend.search(query, params["format_filter"])

    MultiJson.encode(results.map { |r| r.to_hash.merge(
      highlight: r.highlight,
      presentation_format: r.presentation_format,
      humanized_format: r.humanized_format
    )})
  end

  get "/:backend/advanced_search.?:format?" do
    results = backend.advanced_search(params)
    MultiJson.encode({
      total: results[:total],
      results: results[:results].map { |r| r.to_hash.merge(
        highlight: r.highlight,
        presentation_format: r.presentation_format,
        humanized_format: r.humanized_format
      )}
    })
  end

  get "/?:backend?/preload-autocomplete" do
    # Eventually this is likely to be a list of commonly searched for terms
    # so searching for those is really fast. For the beta, this is just a list
    # of all terms.
    expires 86400, :public
    results = backend.autocomplete_cache rescue []
    MultiJson.encode(results.map { |r| r.to_hash })
  end

  get "/?:backend?/autocomplete" do
    query = params["q"]

    unless query
      expires 86400, :public
      return "[]"
    end

    expires 3600, :public if query.length < 5

    results = backend.complete(query, params["format_filter"]) rescue []
    MultiJson.encode(results.map { |r| r.to_hash.merge(
      presentation_format: r.presentation_format,
      humanized_format: r.humanized_format
    ) })
  end

  get "/sitemap.xml" do
    content_type :xml
    expires 86400, :public
    # Site maps can have up to 50,000 links in them.
    # We use one for / so we can have up to 49,999 others.
    # bes = settings.backends.keys.map { |key| available_backends[key] }
    documents = backends_for_sitemap.flat_map do |be|
      be.all_documents(limit: 49_999)
    end
    builder do |xml|
      xml.instruct!
      xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
        xml.url do
          xml.loc "#{base_url}#{"/"}"
        end
        documents.each do |document|
          unless [settings.inside_government_link, settings.recommended_format].include?(document.format)
            xml.url do
              url = document.link
              url = "#{base_url}#{url}" if url =~ /^\//
              xml.loc url
            end
          end
        end
      end
    end
  end

  post "/?:backend?/documents" do
    request.body.rewind
    documents = [MultiJson.decode(request.body.read)].flatten.map { |hash|
      backend.document_from_hash(hash)
    }

    simple_json_result(backend.add(documents))
  end

  post "/?:backend?/commit" do
    simple_json_result(backend.commit)
  end

  get "/?:backend?/documents/*" do
    document = backend.get(params["splat"].first)
    halt 404 unless document

    MultiJson.encode document.to_hash
  end

  delete "/?:backend?/documents/*" do
    simple_json_result(backend.delete(params["splat"].first))
  end

  post "/?:backend?/documents/*" do
    unless request.form_data?
      halt(
        415,
        {"Content-Type" => "text/plain"},
        "Amendments require application/x-www-form-urlencoded data"
      )
    end
    document = backend.get(params["splat"].first)
    halt 404 unless document
    text_error "Cannot change document links" if request.POST.include? "link"

    # Note: this expects application/x-www-form-urlencoded data, not JSON
    request.POST.each_pair do |key, value|
      if document.has_field?(key)
        document.set key, value
      else
        text_error "Unrecognised field '#{key}'"
      end
    end
    simple_json_result(backend.add([document]))
  end

  delete "/?:backend?/documents" do
    if params["delete_all"]
      action = backend.delete_all
    else
      action = backend.delete(params["link"])
    end
    simple_json_result(action)
  end
end
