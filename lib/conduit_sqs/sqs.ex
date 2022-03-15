defmodule ConduitSQS.SQS do
  @moduledoc """
  Interface between ConduitSQS and SQS
  """
  require Logger
  alias ExAws.SQS, as: Client
  alias Conduit.Message
  alias ConduitSQS.SQS.Options

  @type topology :: Conduit.Adapter.topology()
  @type opts :: Keyword.t()
  @type queue :: binary
  @type max_number_of_messages :: pos_integer
  @type subscriber_opts :: Keyword.t()
  @type publish_opts :: Keyword.t()
  @type adapter_opts :: Keyword.t()
  @type delete_message_item :: %{
          id: binary,
          receipt_handle: binary
        }

  @doc """
  Converts a Conduit message to an SQS message and publishes it
  """
  @spec publish(Conduit.Message.t(), adapter_opts, publish_opts) :: {:ok, Conduit.Message.t()} | {:error, term()}
  def publish(%Message{body: body} = message, config, opts) do
    request_opts = Keyword.merge(config, request_opts(opts))

    case message.destination
         |> Client.send_message(body, Options.from(message, opts))
         |> ExAws.request(request_opts) do
      {:ok, result} ->
        {:ok, message |> Conduit.Message.put_private(:aws_sqs_response, result |> get_in([:body]))}

      error ->
        error
    end
  end

  @doc """
  Retrieves the specified number of messages from the queue and converts them to
  Conduit messages
  """
  @spec get_messages(queue, max_number_of_messages, subscriber_opts, adapter_opts) :: [Conduit.Message.t()]
  def get_messages(queue, max_number_of_messages, subscriber_opts, adapter_opts) do
    sub_opts = build_subscriber_opts(max_number_of_messages, subscriber_opts)

    request_opts =
      adapter_opts
      |> Keyword.merge(request_opts(subscriber_opts))
      |> Keyword.merge(max_attempts: :infinity)

    queue
    |> Client.receive_message(sub_opts)
    |> ExAws.request!(request_opts)
    |> get_in([:body])
    |> __MODULE__.Message.to_conduit_messages(queue)
  end

  defp build_subscriber_opts(max_number_of_messages, subscriber_opts) do
    subscriber_opts
    |> Keyword.put(:max_number_of_messages, max_number_of_messages)
    |> Keyword.put_new(:attribute_names, :all)
    |> Keyword.put_new(:message_attribute_names, :all)
    |> Keyword.put_new(:fifo_processing, false)
    |> Keyword.delete(:nacked_handler)
    |> Keyword.delete(:acked_handler)
  end

  @doc """
  Removes messages that have been processed from the SQS queue
  """
  @spec ack_messages([delete_message_item], queue :: binary, opts :: Keyword.t()) :: {:ok, term} | {:error, term}
  def ack_messages(delete_message_items, queue, opts),
    do: queue |> Client.delete_message_batch(delete_message_items) |> ExAws.request(opts)

  defp request_opts(opts), do: Keyword.take(opts, [:region, :base_backoff_in_ms, :max_backoff_in_ms, :max_attempts])
end
