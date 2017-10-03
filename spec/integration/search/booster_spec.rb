require 'spec_helper'

RSpec.describe 'BoosterTest' do
  it "service_manual_formats_are_weighted_down" do
    commit_document("mainstream_test",
      "title" => "Agile is good",
      "link" => "/agile-is-good",
      "format" => "service_manual_guide",
    )

    commit_document("mainstream_test",
      "title" => "Being agile is good",
      "link" => "/being-agile-is-good",
      "format" => "service_manual_topic",
    )

    commit_document("mainstream_test",
      "title" => "Can we be agile?",
      "link" => "/can-we-be-agile",
    )

    get "/search?q=agile"

    expect(result_titles).to eq(["Can we be agile?", "Agile is good", "Being agile is good"])
  end

  def result_titles
    parsed_response['results'].map do |result|
      result['title']
    end
  end
end
