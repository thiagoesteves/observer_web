defmodule ObserverWeb.TracerFixtures do
  @moduledoc """
  This module will handle the tracer fixture
  """

  alias ObserverWeb.TracerFixtures.Callee

  def testing_fun(_arg1) do
    :ok
  end

  def testing_adding_fun(arg1, arg2) do
    arg1 + arg2
  end

  def testing_caller_fun(arg1, arg2) do
    testing_adding_fun(arg1, arg2)
  end

  def testing_exception_fun(arg) do
    1 / arg
  end

  # Calls into a different module on purpose: global call tracing (`:dbg.tp/4`, what
  # ObserverWeb.Tracer.Server uses) only sees calls that go through a module's export table, not
  # same-module calls (those compile to a local jump). A nested trace test needs a real
  # cross-module call to be observable at all.
  def testing_nested_fun(arg1, arg2) do
    Callee.add(arg1, arg2)
  end
end

defmodule ObserverWeb.TracerFixtures.Callee do
  @moduledoc false

  def add(arg1, arg2), do: arg1 + arg2
end
