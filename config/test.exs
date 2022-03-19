import Config

config :conduit_sqs,
  fifo_queue_url: System.get_env("FIFO_QUEUE_URL"),
  standard_queue_url: System.get_env("STANDARD_QUEUE_URL")

config :conduit, ConduitSQSTest,
  access_key_id: System.get_env("ACCESS_KEY_ID"),
  secret_access_key: System.get_env("SECRET_ACCESS_KEY")

config :conduit_sqs, ConduitSQSIntegrationTest.Broker,
  access_key_id: System.get_env("ACCESS_KEY_ID"),
  secret_access_key: System.get_env("SECRET_ACCESS_KEY"),
  adapter: ConduitSQS

config :exvcr,
  vcr_cassette_library_dir: "test/fixture/vcr_cassettes",
  custom_cassette_library_dir: "test/fixture/custom_cassettes",
  filter_sensitive_data: [
    [pattern: System.get_env("ACCESS_KEY_ID"), placeholder: "ACCESS_KEY_ID"],
    [pattern: System.get_env("SECRET_ACCESS_KEY"), placeholder: "SECRET_ACCESS_KEY"]
  ],
  filter_url_params: false,
  filter_request_headers: ["Authorization", "x-amz-date"],
  response_headers_blacklist: []
