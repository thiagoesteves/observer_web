defmodule ObserverWeb.Tracer.Tool.Event do
  @moduledoc """
  Fallback event, used for any raw `:dbg` trace message a Tool doesn't need to
  handle specifically.
  """

  defstruct event: nil
end

defmodule ObserverWeb.Tracer.Tool.EventCall do
  @moduledoc """
  A `:call` trace event.
  """

  @type t :: %__MODULE__{
          mod: module(),
          fun: atom(),
          arity: non_neg_integer(),
          pid: pid(),
          message: list() | nil,
          ts: :erlang.timestamp()
        }

  defstruct mod: nil, fun: nil, arity: nil, pid: nil, message: nil, ts: nil
end

defmodule ObserverWeb.Tracer.Tool.EventReturnFrom do
  @moduledoc """
  A `:return_from` trace event (requires `return_trace()` in the match spec).
  """

  @type t :: %__MODULE__{
          mod: module(),
          fun: atom(),
          arity: non_neg_integer(),
          pid: pid(),
          return_value: term(),
          ts: :erlang.timestamp()
        }

  defstruct mod: nil, fun: nil, arity: nil, pid: nil, return_value: nil, ts: nil
end

defmodule ObserverWeb.Tracer.Tool.EventReturnTo do
  @moduledoc """
  A `:return_to` trace event (requires the `:return_to` trace flag).
  """

  defstruct mod: nil, fun: nil, arity: nil, pid: nil, ts: nil
end

defmodule ObserverWeb.Tracer.Tool.EventIn do
  @moduledoc """
  A scheduler `:in` event (requires the `:running` trace flag).
  """

  defstruct mod: nil, fun: nil, arity: nil, pid: nil, ts: nil
end

defmodule ObserverWeb.Tracer.Tool.EventOut do
  @moduledoc """
  A scheduler `:out` event (requires the `:running` trace flag).
  """

  defstruct mod: nil, fun: nil, arity: nil, pid: nil, ts: nil
end
