require "test_helper"
require "json"
require "set"
require "unified_search_builder"
require "search_parameter_parser"

class UnifiedSearcherBuilderTest < ShouldaUnitTestCase

  # Set BASE_FILTERS if needed to add some default filters to search.
  BASE_FILTERS = nil

  def stub_zero_best_bets
    @metasearch_index = stub("metasearch index")
    @metasearch_index.stubs(:raw_search).returns({
      "hits" => {"hits" => [], "total" => 0}
    })
    @metasearch_index.stubs(:analyzed_best_bet_query).returns("cheese")
  end

  def bb_doc(query, type, best_bets, worst_bets)
    {
      "_index" => "metasearch-2014-05-14t17:27:17z-bc245536-f1c1-4f95-83e4-596199b81f0a",
      "_type" => "best_bet",
      "_id" => "#{query}-#{type}",
      "_score" => 1.0,
      "fields" => {
        "details" => JSON.generate({
          best_bets: best_bets.map do |link, position|
            {link: link, position: position}
          end,
          worst_bets: worst_bets.map do |link|
            {link: link}
          end,
        })
      }
    }
  end

  def setup_best_bets(best_bets, worst_bets)
    @metasearch_index = stub("metasearch index")
    @metasearch_index.stubs(:raw_search).returns({
      "hits" => {"hits" => [
        bb_doc("cheese", "exact", best_bets, worst_bets)
      ], "total" => 1}
    })
    @metasearch_index.expects(:analyzed_best_bet_query).returns("cheese")
  end

  def query_options(options={})
    {
      start: 0,
      count: 20,
      query: "cheese",
      order: nil,
      filters: {},
      fields: nil,
      facets: nil,
      debug: {},
    }.merge(options)
  end

  def text_filter(field_name, values)
    SearchParameterParser::TextFieldFilter.new(field_name, values)
  end

  def date_filter(field_name, values)
    SearchParameterParser::DateFieldFilter.new(
      field_name,
      values,
    )
  end

  def make_search_builder(options={})
    UnifiedSearchBuilder.new(
      query_options(options),
      @metasearch_index,
    )
  end

  def setup_best_bets_query(best_bets, worst_bets)
    setup_best_bets([], [])
    @builder_without_best_bets = make_search_builder
    @query_without_best_bets = @builder_without_best_bets.payload[:query]
    setup_best_bets(best_bets, worst_bets)
    @builder = make_search_builder
  end

  def with_base_filters(filter)
    if BASE_FILTERS
      {
        "and" => [
          filter,
          BASE_FILTERS
        ]
      }
    else
      filter
    end
  end

  context "unfiltered search" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder
    end

    should "have correct 'from' parameter in payload" do
      assert_equal(
        0,
        @builder.payload[:from]
      )
    end

    should "have correct 'size' parameter in payload" do
      assert_equal(
        20,
        @builder.payload[:size]
      )
    end

    should "only contain default filters in payload" do
      assert_equal(
        BASE_FILTERS,
        @builder.payload[:filter]
      )
    end

    should "not have facets in payload" do
      assert_does_not_contain(
        @builder.payload.keys, :facets
      )
    end

  end

  context "search with one filter" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        filters: [ text_filter("organisations", ["hm-magic"]) ]
      )
    end

    should "have filter in payload" do
      assert_contains(
        @builder.payload.keys, :filter
      )
    end

    should "append correct filter to base filters" do
      assert_equal(
        @builder.filters_hash, with_base_filters({"terms" => {"organisations" => ["hm-magic"]}})
      )
    end

    should "not have facets in payload" do
      assert_does_not_contain(
        @builder.payload.keys, :facets
      )
    end
  end

  context "search with a filter with multiple options" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        filters: [ text_filter("organisations", ["hm-magic", "hmrc"]) ],
      )
    end

    should "have filter in payload" do
      assert_contains(
        @builder.payload.keys, :filter
      )
    end

    should "have correct filter" do
      assert_equal(
        @builder.filters_hash,
        with_base_filters({"terms" => {"organisations" => ["hm-magic", "hmrc"]}})
      )
    end

    should "not have facets in payload" do
      assert_does_not_contain(
        @builder.payload.keys, :facets
      )
    end
  end

  context "search with multiple filters" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        filters: [
          text_filter("organisations", ["hm-magic", "hmrc"]),
          text_filter("section", ["levitation"]),
        ],
      )
    end

    should "have filter in payload" do
      assert_contains(
        @builder.payload.keys, :filter
      )
    end

    should "have correct filter" do
      assert_equal(
        @builder.filters_hash,
        {:and => [
          {"terms" => {"organisations" => ["hm-magic", "hmrc"]}},
          {"terms" => {"section" => ["levitation"]}},
          BASE_FILTERS,
        ].compact}
      )
    end

    should "not have facets in payload" do
      assert_does_not_contain(
        @builder.payload.keys, :facets
      )
    end
  end

  context "search with ascending sort" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        order: ["public_timestamp", "asc"],
      )
    end

    should "have sort in payload" do
      assert_contains(
        @builder.payload.keys, :sort
      )
    end

    should "only contain default filters in payload" do
      assert_equal(
        BASE_FILTERS,
        @builder.payload[:filter]
      )
    end

    should "not have facets in payload" do
      assert_does_not_contain(
        @builder.payload.keys, :facets
      )
    end

    should "put documents without a timestamp at the bottom" do
      assert_equal(
        [{"public_timestamp" => {order: "asc", missing: "_last"}}],
        @builder.sort_list
      )
    end
  end

  context "search with descending sort" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        order: ["public_timestamp", "desc"],
      )
    end

    should "have sort in payload" do
      assert_contains(
        @builder.payload.keys, :sort
      )
    end

    should "only contain default filters in payload" do
      assert_equal(
        BASE_FILTERS,
        @builder.payload[:filter]
      )
    end

    should "not have facets in payload" do
      assert_does_not_contain(
        @builder.payload.keys, :facets
      )
    end

    should "put documents without a timestamp at the bottom" do
      assert_equal(
        [{"public_timestamp" => {order: "desc", missing: "_last"}}],
        @builder.sort_list
      )
    end
  end

  context "search with explicit return fields" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        return_fields: ['title'],
      )
    end

    should "have correct fields in payload" do
      assert_equal(
        ['title'],
        @builder.payload[:fields]
      )
    end
  end

  context "search with facet" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        facets: {"organisations" => {requested: 10, scope: :exclude_field_filter}},
      )
    end

    should "only contain default filters in payload" do
      assert_equal(
        BASE_FILTERS,
        @builder.payload[:filter]
      )
    end

    should "have correct facet in payload" do
      assert_equal(
        {
          "organisations" => {
            terms: {
              field: "organisations",
              order: "count",
              size: 100000,
            },
          },
        },
        @builder.payload[:facets])
    end
  end

  context "search with facet and filter on same field" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        filters: [ text_filter("organisations", ["hm-magic"]) ],
        facets: {"organisations" => {requested: 10, scope: :exclude_field_filter}},
      )
    end

    should "have correct filter" do
      assert_equal(
        @builder.filters_hash, with_base_filters({"terms" => {"organisations" => ["hm-magic"]}})
      )
    end

    should "have correct facet in payload" do
      assert_equal(
        {
          "organisations" => {
            terms: {
              field: "organisations",
              order: "count",
              size: 100000,
            },
          },
        },
        @builder.payload[:facets])
    end
  end

  context "search with facet and filter on same field, and scope set to all_filters" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        filters: [ text_filter("organisations", ["hm-magic"]) ],
        facets: {"organisations" => {requested: 10, scope: :all_filters}},
      )
    end

    should "have correct filter" do
      assert_equal(
        @builder.filters_hash, with_base_filters({"terms" => {"organisations" => ["hm-magic"]}})
      )
    end

    should "have correct facet in payload" do
      assert_equal(
        {
          "organisations" => {
            terms: {
              field: "organisations",
              order: "count",
              size: 100000,
            },
            facet_filter: with_base_filters({
              "terms" => {"organisations" => ["hm-magic"]}
            }),
          },
        },
        @builder.payload[:facets])
    end
  end

  context "search with facet and filter on different field" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        filters: [ text_filter("section", "levitation") ],
        facets: {"organisations" => {requested: 10, scope: :exclude_field_filter}},
      )
    end

    should "have correct filter" do
      assert_equal(
        @builder.filters_hash, with_base_filters({"terms" => {"section" => ["levitation"]}})
      )
    end

    should "have facet with facet_filter in payload" do
      assert_equal(
        {
          "organisations" => {
            terms: {
              field: "organisations",
              order: "count",
              size: 100000,
            },
            facet_filter: with_base_filters({
              "terms" => {"section" => ["levitation"]}
            }),
          },
        },
        @builder.payload[:facets])
    end
  end

  context "search with a single best bet url" do
    setup do
      setup_best_bets_query([["/foo", 1]], [])
    end

    should "have correct query in payload" do
      assert_equal(
        {
          bool: {
            should: [
              @query_without_best_bets,
              {
                function_score: {
                  query: {
                    ids: { values: ["/foo"] },
                  },
                  boost_factor: 1000000,
                }
              }
            ]
          }
        },
        @builder.payload[:query])
    end
  end

  context "search with two best bet urls" do
    setup do
      setup_best_bets_query([["/foo", 1], ["/bar", 2]], [])
    end

    should "have correct query in payload" do
      assert_equal(
        {
          bool: {
            should: [
              @query_without_best_bets,
              {
                function_score: {
                  query: { ids: { values: ["/foo"] }, },
                  boost_factor: 2000000,
                }
              },
              {
                function_score: {
                  query: { ids: { values: ["/bar"] }, },
                  boost_factor: 1000000,
                }
              }
            ]
          }
        },
        @builder.payload[:query])
    end
  end

  context "search with a worst bet" do
    setup do
      setup_best_bets_query([], ["/foo"])
    end

    should "have correct query in payload" do
      assert_equal(
        {
          bool: {
            should: [
              @query_without_best_bets,
            ],
            must_not: [
              { ids: { values: ["/foo"] } }
            ],
          }
        },
        @builder.payload[:query])
    end
  end

  context "search with debug disabling use of best bets" do
    setup do
      # No need to set up best bets query.
      @builder = make_search_builder(
        debug: {disable_best_bets: true}
      )
    end

    should "have not have a bool query in payload" do
      assert @builder.payload[:query].keys != [:bool]
    end
  end

  context "search with debug disabling use of popularity" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        debug: {disable_popularity: true}
      )
    end

    should "have not have a function_score clause to add popularity in payload" do
      query = @builder.payload[:query]
      refute_match(/popularity/, query.to_s)
      assert_equal(
        query[:indices][:query][:function_score][:query].keys,
        [:function_score]
      )
    end
  end

  context "search with debug explain" do
    setup do
      stub_zero_best_bets
      @builder = make_search_builder(
        debug: {explain: true},
      )
    end

    should "have not have a custom_score clause to add popularity in payload" do
      assert @builder.payload[:explain] == true
    end
  end

  context "search with debug disabling use of synonyms" do
    setup do
      stub_zero_best_bets
      @builder_with_synonyms = make_search_builder
      @builder_without_synonyms = make_search_builder(debug: {disable_synonyms: true})
    end

    should "not mention the query_default analyzer" do
      query_with_synonyms = @builder_with_synonyms.payload[:query]
      query_without_synonyms = @builder_without_synonyms.payload[:query]
      refute_match(/query_default/, query_without_synonyms.to_s)
      assert_match(/query_default/, query_with_synonyms.to_s)
    end
  end
end
