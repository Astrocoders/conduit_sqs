defmodule ConduitSQS.MessageProcessor do
  @moduledoc """
  Processes a message batch and acks successful messages
  """
  import Injex
  alias Conduit.Message
  import Conduit.Message
  inject :sqs, ConduitSQS.SQS

  @doc """
  Processes messages and acks successful messages
  """
  @spec process(Conduit.Adapter.broker(), atom, [Conduit.Message.t()], Keyword.t()) :: {:ok, term} | {:error, term}
  def process(broker, name, messages, opts) do
    fifo_processing = opts[:fifo_processing] || false

    run_messages_processing(broker, name, messages, opts, fifo_processing)
  end

  defp run_messages_processing(broker, name, messages, opts, true) do
    messages
    |> Enum.reduce_while([], fn message, acc ->
      case process_message(broker, name, message) do
        {:ack, message} ->
          ack_handler(message, opts)

          {:cont,
           acc ++ [%{id: get_header(message, "message_id"), receipt_handle: get_header(message, "receipt_handle")}]}

        # if we are in a fifo queue, we should stop the reduction
        # at this point to avoid processing the next messages
        {:nack, message} ->
          nack_handler(message, opts)

          {:halt, acc}
      end
    end)
    |> sqs().ack_messages(hd(messages).source, opts)
  end

  defp run_messages_processing(broker, name, messages, opts, false) do
    messages
    |> Enum.reduce([], fn message, acc ->
      case process_message(broker, name, message) do
        {:ack, message} ->
          ack_handler(message, opts)

          acc ++ [%{id: get_header(message, "message_id"), receipt_handle: get_header(message, "receipt_handle")}]

        {:nack, message} ->
          nack_handler(message, opts)

          acc
      end
    end)
    |> sqs().ack_messages(hd(messages).source, opts)
  end

  defp process_message(broker, name, message) do
    case broker.receives(name, message) do
      %Message{status: :ack} = msg ->
        {:ack, msg}

      %Message{status: :nack} = msg ->
        {:nack, msg}
    end
  rescue
    _ex ->
      {:nack, message}
  end

  defp ack_handler(%Conduit.Message{} = message, opts),
    do: maybe_call_handler(:acked_handler, message, opts)

  defp nack_handler(%Conduit.Message{} = message, opts), do: maybe_call_handler(:nacked_handler, message, opts)

  defp maybe_call_handler(type, argument, opts) do
    case opts[type] do
      handler when is_function(handler, 1) ->
        handler.(argument)

        {:ok, argument}

      _ ->
        {:ok, argument}
    end
  end
end
