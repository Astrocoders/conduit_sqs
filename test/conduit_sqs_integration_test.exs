defmodule ConduitSQSIntegrationTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  alias Conduit.Message

  defmodule TestSubscriber do
    use Conduit.Subscriber

    def process(%Conduit.Message{body: body} = message, _) do
      if String.starts_with?(body, "ack") do
        Conduit.Message.ack(message)
      else
        Conduit.Message.nack(message)
      end
    end

    def on_acked(messages_receipts) do
      send(ConduitSQSIntegrationTest, {:acked, messages_receipts})
    end

    def on_nacked(message) do
      send(ConduitSQSIntegrationTest, {:nacked, message})
    end
  end

  defmodule Broker do
    use Conduit.Broker, otp_app: :conduit_sqs

    defp fifo_queue_url, do: Application.get_env(:conduit_sqs, :fifo_queue_url)
    defp standard_queue_url, do: Application.get_env(:conduit_sqs, :standard_queue_url)

    configure do
      queue fifo_queue_url()
      queue standard_queue_url()
    end

    pipeline :out_tracking do
      plug Conduit.Plug.LogOutgoing
    end

    pipeline :in_tracking do
      plug Conduit.Plug.LogIncoming
    end

    outgoing do
      pipe_through [:out_tracking]

      publish :sub_fifo,
        to: fifo_queue_url(),
        message_group_id: "test-group-id"

      publish :sub_standard,
        to: standard_queue_url()
    end

    incoming ConduitSQSIntegrationTest do
      pipe_through [:in_tracking]

      subscribe :sub_fifo, TestSubscriber,
        from: fifo_queue_url(),
        fifo_processing: true,
        acked_handler: &TestSubscriber.on_acked/1,
        nacked_handler: &TestSubscriber.on_nacked/1

      subscribe :sub_standard, TestSubscriber,
        from: standard_queue_url(),
        fifo_processing: false,
        acked_handler: &TestSubscriber.on_acked/1,
        nacked_handler: &TestSubscriber.on_nacked/1
    end
  end

  setup do
    {:ok, _pid} = Broker.start_link()

    :ok
  end

  @tag :capture_log
  @tag :integration_test
  test "publishes messages, and consumes in a standard queue" do
    Process.register(self(), __MODULE__)

    {:ok, _} = publish_message("ack 1", :sub_standard)
    {:ok, _} = publish_message("ack 2", :sub_standard)
    {:ok, _} = publish_message("ack 3", :sub_standard)
    {:ok, _} = publish_message("nack 1", :sub_standard)
    {:ok, _} = publish_message("ack 4", :sub_standard)
    {:ok, _} = publish_message("ack 5", :sub_standard)
    {:ok, _} = publish_message("ack 6", :sub_standard)

    assert_receive {:acked, %Conduit.Message{body: "ack 1"}}, 5000
    assert_receive {:acked, %Conduit.Message{body: "ack 2"}}, 5000
    assert_receive {:acked, %Conduit.Message{body: "ack 3"}}, 5000
    assert_receive {:nacked, %Conduit.Message{body: "nack 1"}}, 5000
    assert_receive {:acked, %Conduit.Message{body: "ack 4"}}, 5000
    assert_receive {:acked, %Conduit.Message{body: "ack 5"}}, 5000
    assert_receive {:acked, %Conduit.Message{body: "ack 6"}}, 5000
  end

  @tag :capture_log
  @tag :integration_test
  test "publishes messages, and consumes in a fifo queue" do
    Process.register(self(), __MODULE__)

    {:ok, _} = publish_message("ack 1", :sub_fifo)
    {:ok, _} = publish_message("ack 2", :sub_fifo)
    {:ok, _} = publish_message("ack 3", :sub_fifo)
    {:ok, _} = publish_message("nack 1", :sub_fifo)
    {:ok, _} = publish_message("ack 4", :sub_fifo)
    {:ok, _} = publish_message("ack 5", :sub_fifo)
    {:ok, _} = publish_message("ack 6", :sub_fifo)

    assert_receive {:acked, %Conduit.Message{body: "ack 1"}}, 5000
    assert_receive {:acked, %Conduit.Message{body: "ack 2"}}, 5000
    assert_receive {:acked, %Conduit.Message{body: "ack 3"}}, 5000
    assert_receive {:nacked, %Conduit.Message{body: "nack 1"}}, 5000
    refute_receive {:acked, %Conduit.Message{body: "ack 4"}}, 5000
    refute_receive {:acked, %Conduit.Message{body: "ack 5"}}, 5000
    refute_receive {:acked, %Conduit.Message{body: "ack 6"}}, 5000
  end

  defp publish_message(body, name) do
    message = Message.put_body(%Message{}, body)

    opts =
      case name do
        :sub_standard -> []
        :sub_fifo -> [message_deduplication_id: :crypto.strong_rand_bytes(8) |> Base.encode64()]
      end

    Broker.publish(message, name, opts)
  end
end
