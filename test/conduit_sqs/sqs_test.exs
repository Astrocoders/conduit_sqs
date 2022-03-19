defmodule ConduitSQS.SQSTest do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  alias ConduitSQS.SQS
  alias Conduit.Message
  import Conduit.Message

  setup do
    opts = Application.get_env(:conduit, ConduitSQSTest)
    {:ok, %{opts: opts}}
  end

  describe "publish/3" do
    test "publish the message with all of its attributes and headers", %{opts: config} do
      standard_queue_url = Application.get_env(:conduit_sqs, :standard_queue_url)

      message =
        %Message{}
        |> put_header("attempts", 1)
        |> put_header("ignore", true)
        |> put_header("message_group_id", "22")
        |> put_created_by("test")
        |> put_correlation_id("1")
        |> put_body("hi")
        |> put_destination(standard_queue_url)

      use_cassette "publish" do
        assert {:ok,
                %Conduit.Message{
                  private: %{
                    aws_sqs_response: %{
                      md5_of_message_attributes: "da0504e68243d743924e90454985a7b3",
                      md5_of_message_body: "49f68a5c8493ec2c0bf489821c21fc3b",
                      message_id: _,
                      request_id: _
                    }
                  }
                }} = SQS.publish(message, config, [])
      end
    end
  end

  describe "get_messages/4" do
    test "returns a list of messages with attributes mapped to conduit attributes and headers", %{opts: config} do
      use_cassette "receive" do
        fifo_queue_url = Application.get_env(:conduit_sqs, :fifo_queue_url)

        assert [
                 %Message{
                   body: "hi",
                   correlation_id: "1",
                   created_by: "test",
                   headers: %{
                     "approximate_first_receive_timestamp" => _,
                     "approximate_receive_count" => _,
                     "attempts" => 1,
                     "ignore" => true,
                     "md5_of_body" => _,
                     "message_id" => _,
                     "receipt_handle" => _,
                     "request_id" => _,
                     "sender_id" => _,
                     "sent_timestamp" => _
                   },
                   source: ^fifo_queue_url
                 }
               ] = SQS.get_messages(fifo_queue_url, 10, [], config)
      end
    end
  end
end
