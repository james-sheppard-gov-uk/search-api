require 'spec_helper'

RSpec.describe Indexer::CompareEnumerator do
  it "when_matching_keys_exist" do
    data_left = { '_root_id' => 'abc', '_root_type' => 'stuff', 'custom' => 'data_left' }
    data_right = { '_root_id' => 'abc', '_root_type' => 'stuff', 'custom' => 'data_right' }

    stub_scroll_enumerator(left_request: [data_left], right_request: [data_right])

    results = described_class.new('index_a', 'index_b').to_a
    assert_equal results, [[data_left, data_right]]
  end

  it "when_key_only_exists_in_left_index" do
    data = { '_root_id' => 'abc', '_root_type' => 'stuff', 'custom' => 'data_left' }

    stub_scroll_enumerator(left_request: [data], right_request: [])

    results = described_class.new('index_a', 'index_b').to_a
    assert_equal results, [[data, described_class::NO_VALUE]]
  end


  it "when_key_only_exists_in_right_index" do
    data = { '_root_id' => 'abc', '_root_type' => 'stuff', 'custom' => 'data_right' }

    stub_scroll_enumerator(left_request: [], right_request: [data])

    results = described_class.new('index_a', 'index_b').to_a
    assert_equal results, [[described_class::NO_VALUE, data]]
  end

  it "with_matching_ids_but_different_types" do
    data_left = { '_root_id' => 'abc', '_root_type' => 'stuff', 'custom' => 'data_left' }
    data_right = { '_root_id' => 'abc', '_root_type' => 'other_stuff', 'custom' => 'data_right' }

    stub_scroll_enumerator(left_request: [data_left], right_request: [data_right])

    results = described_class.new('index_a', 'index_b').to_a
    assert_equal results, [
      [described_class::NO_VALUE, data_right],
      [data_left, described_class::NO_VALUE],
    ]
  end

  it "with_different_ids" do
    data_left = { '_root_id' => 'abc', '_root_type' => 'stuff', 'custom' => 'data_left' }
    data_right = { '_root_id' => 'def', '_root_type' => 'stuff', 'custom' => 'data_right' }

    stub_scroll_enumerator(left_request: [data_left], right_request: [data_right])

    results = described_class.new('index_a', 'index_b').to_a
    assert_equal results, [
      [data_left, described_class::NO_VALUE],
      [described_class::NO_VALUE, data_right],
    ]
  end

  it "correct_aligns_records_with_matching_keys" do
    key1 = { '_root_id' => 'abc', '_root_type' => 'stuff' }
    key2 = { '_root_id' => 'def', '_root_type' => 'stuff' }
    key3 = { '_root_id' => 'ghi', '_root_type' => 'stuff' }
    key4 = { '_root_id' => 'jkl', '_root_type' => 'stuff' }
    key5 = { '_root_id' => 'mno', '_root_type' => 'stuff' }

    stub_scroll_enumerator(left_request: [key1, key3, key5], right_request: [key2, key3, key4, key5])

    results = described_class.new('index_a', 'index_b').to_a
    assert_equal results, [
      [key1, described_class::NO_VALUE],
      [described_class::NO_VALUE, key2],
      [key3, key3],
      [described_class::NO_VALUE, key4],
      [key5, key5],
    ]
  end

  it "scroll_enumerator_mappings" do
    data = { '_id' => 'abc', '_type' => 'stuff', '_source' => { 'custom' => 'data' } }
    stub_client_for_scroll_enumerator(return_values: [[data], []])

    enum = described_class.new('index_a', 'index_b').get_enum('index_name')

    assert_equal enum.to_a, [
      { '_root_id' => 'abc', '_root_type' => 'stuff', 'custom' => 'data' }
    ]
  end

  it "scroll_enumerator_mappings_when_filter_is_passed_in" do
    data = { '_id' => 'abc', '_type' => 'stuff', '_source' => { 'custom' => 'data' } }
    search_body = { query: 'custom_filter', sort: 'by_stuff' }

    stub_client_for_scroll_enumerator(return_values: [[data], []], search_body: search_body)

    enum = described_class.new('index_a', 'index_b').get_enum('index_name', search_body)

    assert_equal enum.to_a, [
      { '_root_id' => 'abc', '_root_type' => 'stuff', 'custom' => 'data' }
    ]
  end

  it "scroll_enumerator_mappings_without_sorting" do
    data = { '_id' => 'abc', '_type' => 'stuff', '_source' => { 'custom' => 'data' } }
    search_body = { query: 'custom_filter' }

    stub_client_for_scroll_enumerator(return_values: [[data], []], search_body: search_body.merge(sort: described_class::DEFAULT_SORT))

    enum = described_class.new('index_a', 'index_b').get_enum('index_name', search_body)

    assert_equal enum.to_a, [
      { '_root_id' => 'abc', '_root_type' => 'stuff', 'custom' => 'data' }
    ]
  end

private

  def commit_document(*args)
    IntegrationTest.new(nil).commit_document(*args)
  end

  def stub_scroll_enumerator(left_request:, right_request:)
    allow(ScrollEnumerator).to receive(:new).and_return(
      left_request.to_enum,
      right_request.to_enum,
    )
  end

  def stub_client_for_scroll_enumerator(return_values:, search_body: nil, search_type: "query_then_fetch")
    client = double(:client)
    allow(Services).to receive(:elasticsearch).and_return(client)

    expect(client).to receive(:search).with(
      hash_including(
        index: 'index_name',
        search_type: search_type,
        body: search_body || {
          query: described_class::DEFAULT_QUERY,
          sort: described_class::DEFAULT_SORT,
        }
      )
    ).and_return(
      { '_scroll_id' => 'scroll_ID_0', 'hits' => { 'total' => 1, 'hits' => return_values[0] } }
    )


    return_values[1..-1].each_with_index do |return_value, i|
      expect(client).to receive(:scroll).with(
        scroll_id: "scroll_ID_#{i}", scroll: "1m"
      ).and_return(
        { '_scroll_id' => "scroll_ID_#{i + 1}", 'hits' => { 'hits' => return_value } }
      )
    end
  end
end
