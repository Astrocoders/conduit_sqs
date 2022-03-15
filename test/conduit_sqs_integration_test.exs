defmodule ConduitSQSIntegrationTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  alias Conduit.Message

  defmodule TestSubscriber do
    use Conduit.Subscriber

    def process(message, _) do
      send(ConduitSQSIntegrationTest, {:process, message})
      message
    end
  end

  defmodule Broker do
    use Conduit.Broker, otp_app: :conduit_sqs

    configure do
      queue "subscription.fifo", fifo_queue: true
    end

    pipeline :out_tracking do
      plug Conduit.Plug.LogOutgoing
    end

    pipeline :in_tracking do
      plug Conduit.Plug.LogIncoming
    end

    outgoing do
      pipe_through [:out_tracking]

      publish :sub, to: "subscription.fifo", message_group_id: "test-group-id"
    end

    incoming ConduitSQSIntegrationTest do
      pipe_through [:in_tracking]

      subscribe :sub, TestSubscriber, from: "subscription.fifo", fifo_processing: true
    end
  end

  @tag :capture_log
  @tag :integration_test
  test "creates queue, publishes messages, and consumes them" do
    Process.register(self(), __MODULE__)
    {:ok, _pid} = Broker.start_link()

    message = Message.put_body(%Message{}, "hi")

    mdid = :crypto.strong_rand_bytes(8) |> Base.encode64()

    {:ok,
     %Conduit.Message{
       private: %{
         aws_sqs_response: %{
           message_id: message_id
         }
       }
     }} = Broker.publish(message, :sub, message_deduplication_id: mdid)

    assert is_binary(message_id)

    assert_receive {:process, consumed_message}, 5000

    assert consumed_message.body == "hi"

    {:messages, messages} = :erlang.process_info(self(), :messages)

    for {:process, message} <- messages do
      assert message.body == "hi"
    end
  end
end
