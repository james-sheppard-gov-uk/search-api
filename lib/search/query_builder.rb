require_relative "best_bets_checker"
require_relative "escaping"

require_relative "query_components/base_component"
require_relative "query_components/booster"
require_relative "query_components/sort"
require_relative "query_components/popularity"
require_relative "query_components/best_bets"
require_relative "query_components/filter"
require_relative "query_components/highlight"
require_relative "query_components/aggregates"
require_relative "query_components/core_query"
require_relative "query_components/text_query"

module Search
  # Builds a query for a search across all GOV.UK indices
  class QueryBuilder
    include Search::QueryHelpers

    attr_reader :search_params

    def initialize(search_params:, content_index_names:, metasearch_index:)
      @search_params = search_params
      @content_index_names = content_index_names
      @metasearch_index = metasearch_index
    end

    def payload
      hash_without_blank_values(
        from: search_params.start,
        size: search_params.count,
        fields: fields.uniq,
        query: query,
        filter: filter,
        sort: sort,
        aggs: aggregates,
        highlight: highlight,
        explain: search_params.debug[:explain],
      )
    end

    # `title`, `description` always needed to potentially populate virtual
    # fields. If not explicitly requested they will not be sent to the user.
    # The same applies to all `*_content_ids` in order to be able to expand
    # their corresponding fields without having to request both fields
    # explicitly.
    def fields
      search_params.return_fields +
        %w[title description organisation_content_ids topic_content_ids
           mainstream_browse_page_content_ids]
    end

    def query
      return more_like_this_query_hash unless search_params.similar_to.nil?
      return { match_all: {} } if search_params.query.nil?

      core_query = QueryComponents::CoreQuery.new(search_params)

      best_bets.wrap(
        popularity_boost.wrap(
          format_boost.wrap(
            if search_params.enable_new_weighting?
              new_weighting_query
            elsif search_params.quoted_search_phrase?
              core_query.quoted_phrase_query
            else
              {
                bool: {
                  must: [core_query.optional_id_code_query].compact,
                  should: [
                    core_query.match_phrase("title"),
                    core_query.match_phrase("acronym"),
                    core_query.match_phrase("description"),
                    core_query.match_phrase("indexable_content"),
                    core_query.match_all_terms(%w(title acronym description indexable_content)),
                    core_query.match_bigrams(%w(title acronym description indexable_content)),
                    core_query.minimum_should_match("_all")
                  ],
                }
              }
            end
          )
        )
      )
    end

    def filter
      QueryComponents::Filter.new(search_params).payload
    end

  private

    attr_reader :content_index_names
    attr_reader :metasearch_index

    def best_bets
      QueryComponents::BestBets.new(metasearch_index: metasearch_index, search_params: search_params)
    end

    def popularity_boost
      QueryComponents::Popularity.new(search_params)
    end

    def format_boost
      QueryComponents::Booster.new(search_params)
    end

    def sort
      QueryComponents::Sort.new(search_params).payload
    end

    def aggregates
      QueryComponents::Aggregates.new(search_params).payload
    end

    def highlight
      QueryComponents::Highlight.new(search_params).payload
    end

    def hash_without_blank_values(hash)
      Hash[hash.reject { |_key, value|
        [nil, [], {}].include?(value)
      }]
    end

    def new_weighting_query
      QueryComponents::TextQuery.new(search_params).payload
    end

    # More like this is a separate function for returning similar documents,
    # but it's included in the main search API.
    # All other parameters are ignored if "similar_to" is present.
    def more_like_this_query_hash
      docs = content_index_names.reduce([]) do |documents, index_name|
        documents << {
          _type: 'edition',
          _id: search_params.similar_to,
          _index: index_name
        }
      end

      {
        more_like_this: { docs: docs }
      }
    end
  end
end
