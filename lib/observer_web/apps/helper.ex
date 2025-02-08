defmodule ObserverWeb.Apps.Helper do
  @moduledoc """
  Helper functions and JSON encoders.

  ## References:
   * https://github.com/shinyscorpion/wobserver
  """

  alias Jason.Encoder

  # coveralls-ignore-start
  defimpl Encoder, for: PID do
    @doc """
    JSON encodes a `PID`.

    Uses `inspect/1` to turn the `pid` into a String and passes the `options` to `Encoder.BitString.encode/1`.
    """
    @spec encode(pid :: pid, options :: Jason.Encode.opts()) :: any()
    def encode(pid, options) do
      pid
      |> inspect
      |> Encoder.BitString.encode(options)
    end
  end

  defimpl Encoder, for: Port do
    @doc """
    JSON encodes a `Port`.

    Uses `inspect/1` to turn the `port` into a String and passes the `options` to `Encoder.BitString.encode/1`.
    """
    @spec encode(port :: port, options :: Jason.Encode.opts()) :: any()
    def encode(port, options) do
      port
      |> inspect
      |> Encoder.BitString.encode(options)
    end
  end

  defimpl Encoder, for: Reference do
    @doc """
    JSON encodes a `Reference`.

    Uses `inspect/1` to turn the `reference` into a String and passes the `options` to `Encoder.BitString.encode/1`.
    """
    @spec encode(reference :: reference, options :: Jason.Encode.opts()) :: any()
    def encode(reference, options) do
      reference
      |> inspect
      |> Encoder.BitString.encode(options)
    end
  end

  # coveralls-ignore-stop

  @doc """
  Formats function information as readable string.

  Only name will be return if only `name` is given.

  ## Examples
  iex> alias ObserverWeb.Apps.Helper
  ...> assert "Elixir.Logger.log/2" == Helper.format_function({Logger, :log, 2})
  ...> assert "format_function" == Helper.format_function(:format_function)
  ...> assert nil == Helper.format_function(nil)

  """
  @spec format_function(nil | {atom, atom, integer} | atom) :: String.t() | nil
  def format_function(nil), do: nil
  def format_function({module, name, arity}), do: "#{module}.#{name}/#{arity}"
  def format_function(name), do: "#{name}"

  @doc """
  Parallel map implemented with `Task`.

  Maps the `function` over the `enum` using `Task.async/1` and `Task.await/1`.
  """
  @spec parallel_map(enum :: list, function :: fun) :: list
  def parallel_map(enum, function) do
    enum
    |> Enum.map(&Task.async(fn -> function.(&1) end))
    |> Enum.map(&Task.await/1)
  end
end
