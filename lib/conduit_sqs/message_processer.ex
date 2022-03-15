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

  def process(broker, name, messages, [fifo_processing: true] = opts) do
    messages
    |> Enum.reduce_while([], fn message, acc ->
      case process_message(broker, name, message) do
        {:ack, message} ->
          {:cont,
           acc ++ [%{id: get_header(message, "message_id"), receipt_handle: get_header(message, "receipt_handle")}]}

        # if we are in a fifo queue, we should stop the reduction
        # at this point to avoid processing the next messages
        {:nack, _} ->
          {:halt, acc}
      end
    end)
    |> sqs().ack_messages(hd(messages).source, opts)
  end

  def process(broker, name, messages, opts) do
    messages
    |> Enum.reduce([], fn message, acc ->
      case process_message(broker, name, message) do
        {:ack, message} ->
          acc ++ [%{id: get_header(message, "message_id"), receipt_handle: get_header(message, "receipt_handle")}]

        {:nack, _message} ->
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
end
