require 'spec_helper'

RSpec.describe SearchIndices::SearchServer do
  def schema_config
    schema = double("schema config")
    schema.stub(:elasticsearch_mappings).and_return({})
    schema.stub(:elasticsearch_settings).and_return({})
    schema
  end

  it "returns_an_index" do
    search_server = described_class.new("http://l", schema_config, ["mainstream_test", "page-traffic_test"], 'govuk_test', ["mainstream_test"], SearchConfig.new)
    index = search_server.index("mainstream_test")
    assert index.is_a?(SearchIndices::Index)
    assert_equal "mainstream_test", index.index_name
  end

  it "returns_an_index_for_govuk_index" do
    search_server = described_class.new("http://l", schema_config, ["mainstream_test", "page-traffic_test"], 'govuk_test', ["mainstream_test"], SearchConfig.new)
    index = search_server.index("govuk_test")
    assert index.is_a?(SearchIndices::Index)
    assert_equal "govuk_test", index.index_name
  end

  it "raises_an_error_for_unknown_index" do
    search_server = described_class.new("http://l", schema_config, ["mainstream_test", "page-traffic_test"], 'govuk_test', ["mainstream_test"], SearchConfig.new)
    assert_raises SearchIndices::NoSuchIndex do
      search_server.index("z")
    end
  end

  it "can_get_multi_index" do
    search_server = described_class.new("http://l", schema_config, ["mainstream_test", "page-traffic_test"], 'govuk_test', ["mainstream_test"], SearchConfig.new)
    index = search_server.index_for_search(%w{mainstream_test page-traffic_test})
    assert index.is_a?(LegacyClient::IndexForSearch)
    assert_equal ["mainstream_test", "page-traffic_test"], index.index_names
  end

  it "raises_an_error_for_unknown_index_in_multi_index" do
    search_server = described_class.new("http://l", schema_config, ["mainstream_test", "page-traffic_test"], 'govuk_test', ["mainstream_test"], SearchConfig.new)
    assert_raises SearchIndices::NoSuchIndex do
      search_server.index_for_search(%w{mainstream_test unknown})
    end
  end
end
