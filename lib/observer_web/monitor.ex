defmodule ObserverWeb.Monitor do
  @moduledoc """
  This module will provide process monitor abstraction
  """

  alias ObserverWeb.Monitor.Process

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Starts monitoring a process's memory usage
  """
  @spec start_process_monitor(pid :: pid()) :: :ok
  def start_process_monitor(pid), do: Process.start_process_monitor(pid)

  @doc """
  Stops monitoring a process's memory usage
  """
  @spec stop_process_monitor(pid :: pid()) :: :ok
  def stop_process_monitor(pid), do: Process.stop_process_monitor(pid)

  @doc """
  Checks if memory monitoring is enabled for a process
  """
  @spec process_enabled?(pid :: pid()) :: boolean()
  def process_enabled?(pid), do: Process.enabled?(pid)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
