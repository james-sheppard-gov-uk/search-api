require 'spec_helper'

RSpec.describe "HMRC manual publishing" do
  before do
    bunny_mock = BunnyMock.new
    @channel = bunny_mock.start.channel

    consumer = GovukMessageQueueConsumer::Consumer.new(
      queue_name: "hmrc_manuals.test",
      processor: GovukIndex::PublishingEventProcessor.new,
      rabbitmq_connection: bunny_mock
    )

    @queue = @channel.queue("hmrc_manuals.test")
    consumer.run
  end

  it "indexes an HMRC manual" do
    random_example = generate_random_example(
      schema: "hmrc_manual",
      payload: { document_type: "hmrc_manual" },
      details: {
        change_notes: [
          {
            change_note: "Some description of change",
            title: "Name of manual section",
            published_at: "2017-06-21T10:48:34+00:00",
            base_path: "/some/section/base/path",
            section_id: "some_manual_section_id"
          }
        ]
      },
      regenerate_if: ->(example) { example["publishing_app"] == "smartanswers" }
    )

    allow(GovukIndex::MigratedFormats).to receive(:indexable_formats).and_return(["hmrc_manual"])

    @queue.publish(random_example.to_json, content_type: "application/json")

    expected_document = {
       "link" => random_example["base_path"],
       "latest_change_note" => "Some description of change in Name of manual section",
     }
    expect_document_is_in_rummager(expected_document, index: "govuk_test", type: "hmrc_manual")
  end
end
